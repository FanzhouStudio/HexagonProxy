class_name AntigravityProxyPanel
extends Node

signal executable_selected(path: String)
signal action_requested(action: String)
signal refresh_requested
signal account_add_requested(account_name: String)
signal account_action_requested(action: String, id: String)
signal account_remove_requested(id: String)
signal account_default_requested(id: String)

const ConfirmationPromptScript = preload("res://scripts/ui/confirmation_prompt.gd")

var ui: UiFactory
var status_label: Label
var endpoint_label: Label
var path_edit: LineEdit
var choose_button: Button
var enable_button: Button
var disable_button: Button
var launch_button: Button
var refresh_button: Button
var message_label: Label
var exe_dialog: FileDialog
var _state: Dictionary = {}
var _busy := false
var account_name: LineEdit
var account_add: Button
var quota_view: Label
var quota_heading: Label
var quota_rows: VBoxContainer
var quota_bars: Array[ProgressBar] = []
var account_message: Label
var account_list: VBoxContainer
var account_buttons: Array[Button] = []
var _selected_account := "default"
var _prompt_host: Control
var _page_scroll: ScrollContainer
var _account_snapshot: Dictionary = {}
var _quota_snapshot: Dictionary = {}
var _quota_account := ""
var _quota_cached := false
var _quota_row_views: Array = []

func setup(factory: UiFactory, prompt_host: Control = null) -> void:
	ui = factory
	_prompt_host = prompt_host

func build() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 20)
	var heading := ui.label("账号与连接", 24, ui.text_color)
	page.add_child(heading)
	page.add_child(ui.label("共享原有项目与对话，单独保存账号登录与额度，为 Antigravity 配置网络连接。", 13, ui.muted_color))
	var sections := HBoxContainer.new()
	sections.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sections.add_theme_constant_override("separation", 20)
	page.add_child(sections)
	var card := ui.panel(Color("e9fbfbd4"), Color("a8e8e8e8"), 20)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sections.add_child(card)
	var margin := ui.margin(22, 18, 22, 18)
	card.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	margin.add_child(column)
	column.add_child(ui.label("网络连接", 18, ui.text_color))
	var description := ui.label("让 Antigravity 和语言服务使用 HexagonProxy，无需开启 TUN。请先连接代理，再退出 Antigravity 并启用。", 12, ui.muted_color)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(description)
	status_label = ui.label("正在检测 Antigravity…", 14, ui.muted_color)
	column.add_child(status_label)
	endpoint_label = ui.label("", 12, ui.muted_color)
	column.add_child(endpoint_label)
	column.add_child(ui.label("应用程序", 12, ui.muted_color))
	var path_row := VBoxContainer.new()
	path_row.add_theme_constant_override("separation", 10)
	column.add_child(path_row)
	path_edit = LineEdit.new()
	path_edit.editable = false
	path_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	path_edit.custom_minimum_size.y = 42
	ui.apply_line_edit_theme(path_edit, 12)
	path_row.add_child(path_edit)
	choose_button = ui.small_choice_button("选择程序")
	choose_button.pressed.connect(func() -> void: exe_dialog.popup_centered_ratio(0.7))
	path_row.add_child(choose_button)
	var actions := HFlowContainer.new()
	actions.add_theme_constant_override("h_separation", 10)
	actions.add_theme_constant_override("v_separation", 10)
	column.add_child(actions)
	enable_button = _action_button("启用 / 同步端口", "enable", actions)
	launch_button = _action_button("通过代理启动", "launch", actions)
	disable_button = _action_button("卸载并恢复", "disable", actions)
	refresh_button = ui.small_choice_button("刷新状态")
	refresh_button.pressed.connect(func() -> void: refresh_requested.emit())
	actions.add_child(refresh_button)
	message_label = ui.label("启用时会备份程序目录中的同名文件，卸载时恢复。Antigravity 更新后，可在此重新启用。", 11, ui.muted_color)
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(message_label)
	var note := ui.label("使用 antigravity-proxy v2.4 · Windows x64。代理未连接时，已启用的 Antigravity 可能无法访问外网；可在此卸载恢复。", 11, ui.muted_color)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(note)
	exe_dialog = FileDialog.new()
	exe_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	exe_dialog.access = FileDialog.ACCESS_FILESYSTEM
	exe_dialog.filters = PackedStringArray(["*.exe ; Antigravity 程序"])
	exe_dialog.use_native_dialog = true
	exe_dialog.file_selected.connect(func(path: String) -> void: executable_selected.emit(path))
	page.add_child(exe_dialog)
	var accounts_card := ui.panel(ui.surface_color, ui.border_color, 8)
	accounts_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sections.add_child(accounts_card)
	var accounts_margin := ui.margin(22, 18, 22, 18)
	accounts_card.add_child(accounts_margin)
	var accounts_column := VBoxContainer.new()
	accounts_column.add_theme_constant_override("separation", 18)
	accounts_margin.add_child(accounts_column)
	_build_accounts(accounts_column)
	var scroll := ScrollContainer.new()
	_page_scroll = scroll
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(page)
	if not is_instance_valid(_prompt_host):
		_prompt_host = scroll
	return scroll

func _build_accounts(column: VBoxContainer) -> void:
	column.add_child(ui.label("账号管理", 18, ui.text_color))
	var hint := ui.label("添加后完成官方登录，之后直接点击“切换”。各账号共享项目和对话；首次升级会备份旧数据，并请求关闭待迁移的窗口。", 12, ui.muted_color)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(hint)
	var row := HBoxContainer.new()
	column.add_child(row)
	account_name = LineEdit.new()
	account_name.placeholder_text = "账号备注（可选），例如工作号"
	account_name.max_length = 60
	account_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ui.apply_line_edit_theme(account_name, 12)
	row.add_child(account_name)
	account_add = ui.small_choice_button("添加账号并登录")
	ui.primary_button(account_add)
	account_add.pressed.connect(func() -> void: account_add_requested.emit(account_name.text))
	account_name.text_submitted.connect(func(_value: String) -> void: account_add_requested.emit(account_name.text))
	row.add_child(account_add)
	account_message = ui.label("", 12, ui.muted_color)
	account_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(account_message)
	column.add_child(HSeparator.new())
	column.add_child(ui.label("已保存账号", 14, ui.text_color))
	account_list = VBoxContainer.new()
	account_list.add_theme_constant_override("separation", 12)
	column.add_child(account_list)
	column.add_child(HSeparator.new())
	quota_heading = ui.label("额度详情", 14, ui.text_color)
	column.add_child(quota_heading)
	quota_view = ui.label("额度未知。打开并登录所选配置后可刷新；未运行或接口不兼容时会显示原因。", 12, ui.muted_color)
	quota_view.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(quota_view)
	var quota_scroll := ScrollContainer.new()
	quota_scroll.custom_minimum_size.y = 320
	quota_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(quota_scroll)
	quota_rows = VBoxContainer.new()
	quota_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quota_rows.add_theme_constant_override("separation", 10)
	quota_scroll.add_child(quota_rows)
	ui.theme_applied.connect(_refresh_quota_styles)

func selected_account() -> String:
	return _selected_account

func show_account_message(message: String, success: bool) -> void:
	account_message.text = message
	ui.update_label_color(account_message, ui.green_color if success else ui.danger_color)

func _build_account_rows(state: Dictionary) -> void:
	for child in account_list.get_children():
		account_list.remove_child(child)
		child.queue_free()
	account_buttons.clear()
	_selected_account = str(state.get("selected_account", "default"))
	var default_id := str(state.get("default_account", "default"))
	for item in state.get("accounts", []):
		var id := str(item.get("id", ""))
		var card := ui.panel(ui.surface_2_color, ui.border_color, 7)
		account_list.add_child(card)
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		card.add_child(row)
		var title := ui.label(str(item.get("name", "账号")) + (" · 默认" if id == default_id else ""), 14, ui.text_color)
		title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(title)
		var status := str(item.get("email", ""))
		if status.is_empty():
			status = "原有账号 · 使用原登录" if id == "default" else "待登录 · 点击登录后在官方窗口完成授权"
		elif not item.get("logged_in", false):
			status += " · 上次识别的账号"
		if item.get("logged_in", false):
			status += " · 曾识别登录（历史记录）"
		if id == _selected_account:
			status += " · 最近打开"
		var session: Dictionary = state.get("account_sessions", {}).get(id, {})
		if session.has("editor_running"):
			status += " · 窗口运行中" if session.editor_running else " · 窗口未运行"
		elif session.get("discovery", "") == "process_access_denied":
			status += " · 权限不足，运行状态未知"
		var detail := ui.label(status, 11, ui.muted_color)
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(detail)
		var actions := HFlowContainer.new()
		actions.add_theme_constant_override("h_separation", 8)
		row.add_child(actions)
		var switch_button := ui.small_choice_button("切换" if id == "default" or item.get("logged_in", false) else "登录 / 切换")
		ui.primary_button(switch_button)
		switch_button.set_meta("account_id", id)
		switch_button.set_meta("account_action", "launch")
		switch_button.pressed.connect(func() -> void: account_action_requested.emit("launch", id))
		actions.add_child(switch_button)
		account_buttons.append(switch_button)
		var refresh := ui.small_choice_button("刷新登录与额度")
		refresh.pressed.connect(func() -> void: account_action_requested.emit("quota", id))
		actions.add_child(refresh)
		account_buttons.append(refresh)
		if id != default_id:
			var default_button := ui.small_choice_button("设为默认")
			default_button.set_meta("account_id", id)
			default_button.set_meta("account_action", "set_default")
			default_button.pressed.connect(func() -> void: account_default_requested.emit(id))
			actions.add_child(default_button)
			account_buttons.append(default_button)
			var remove_button := ui.small_choice_button("删除", ui.danger_color)
			remove_button.tooltip_text = "删除账号入口，保留本地登录备份、项目和对话"
			remove_button.set_meta("account_id", id)
			remove_button.set_meta("account_action", "remove")
			remove_button.pressed.connect(func() -> void: _request_remove(id, str(item.get("name", "账号"))))
			actions.add_child(remove_button)
			account_buttons.append(remove_button)
		var snapshot: Dictionary = state.get("quota_snapshots", {}).get(id, {})
		if not snapshot.is_empty():
			var view_button := ui.small_choice_button("查看额度 · %d 个模型" % snapshot.get("models", []).size())
			view_button.pressed.connect(func() -> void:
				show_quota(_state.get("quota_snapshots", {}).get(id, {}), id, true)
				call_deferred("reveal_quota")
			)
			actions.add_child(view_button)
			account_buttons.append(view_button)

func _request_remove(id: String, account_title: String) -> void:
	if _busy or id == str(_state.get("default_account", "default")) or not is_instance_valid(_prompt_host):
		return
	var existing := _prompt_host.get_node_or_null("AntigravityDeletePrompt")
	if is_instance_valid(existing):
		return
	var prompt = ConfirmationPromptScript.new()
	prompt.name = "AntigravityDeletePrompt"
	_prompt_host.add_child(prompt)
	prompt.setup(ui, "删除“%s”的账号入口？" % account_title,
		"将从 HexagonProxy 列表移除此账号和额度缓存。保留本地登录数据及备份，不删除共享项目、工作区和对话，也不会关闭正在运行的 Antigravity 窗口。",
		"删除入口", true)
	prompt.confirmed.connect(func() -> void:
		if not _busy:
			account_remove_requested.emit(id)
	)

func _show_cached_quota(id := "") -> void:
	if id.is_empty():
		id = selected_account()
	var snapshot: Dictionary = _state.get("quota_snapshots", {}).get(id, {})
	if snapshot.is_empty():
		_clear_quota_rows()
		_quota_snapshot = {}
		_quota_account = id
		quota_heading.text = "额度详情"
		quota_view.text = "额度未知，打开并登录此配置后点击刷新。"
	else:
		show_quota(snapshot, id, true)

func show_quota(result: Dictionary, id := "", cached := false) -> void:
	if _quota_snapshot == result and _quota_account == id and _quota_cached == cached:
		return
	var models: Array = result.get("models", [])
	var names := models.map(func(model: Dictionary) -> String: return str(model.get("name", "模型")))
	var old_names := _quota_row_views.map(func(view: Dictionary) -> String: return str(view.name.text))
	var rebuild := id != _quota_account or names != old_names
	_quota_snapshot = result.duplicate(true)
	_quota_account = id
	_quota_cached = cached
	for account in _state.get("accounts", []):
		if str(account.get("id", "")) == id:
			quota_heading.text = str(account.get("name", "账号")) + " · 额度详情"
			break
	if not result.get("ok", false):
		_clear_quota_rows()
		quota_view.text = "额度未知：" + str(result.get("message", "读取失败"))
		return
	var lines := PackedStringArray()
	if cached:
		lines.append("上次查询缓存（可能已变化）")
	if not str(result.get("email", "")).is_empty():
		lines.append(str(result.email))
	if rebuild:
		_clear_quota_rows()
	for index in models.size():
		var model: Dictionary = models[index]
		if rebuild:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 12)
			quota_rows.add_child(row)
			var model_name := ui.label(str(model.get("name", "模型")), 12, ui.text_color)
			model_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			model_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			row.add_child(model_name)
			var progress := ProgressBar.new()
			progress.custom_minimum_size = Vector2(110, 12)
			progress.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			progress.show_percentage = false
			row.add_child(progress)
			quota_bars.append(progress)
			var percentage := ui.label("", 12, ui.text_color)
			percentage.custom_minimum_size.x = 170
			percentage.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			row.add_child(percentage)
			_quota_row_views.append({"name": model_name, "bar": progress, "remaining": percentage})
		var raw: Variant = model.get("remaining")
		var known := (raw is int or raw is float) and is_finite(float(raw)) and float(raw) >= 0 and float(raw) <= 100
		var bar: ProgressBar = _quota_row_views[index].bar
		bar.value = float(raw) if known else 0.0
		bar.visible = known
		bar.tooltip_text = "重置时间：%s" % str(model.get("reset", "未知"))
		var remaining: Label = _quota_row_views[index].remaining
		remaining.text = "剩余 %s%%" % str(raw) if known else "额度未知"
		remaining.tooltip_text = bar.tooltip_text
	lines.append("查询时间（UTC）：%s" % result.get("checked_at", "未知"))
	quota_view.text = "\n".join(lines)
	_refresh_quota_styles()

func _clear_quota_rows() -> void:
	if not is_instance_valid(quota_rows):
		return
	for child in quota_rows.get_children():
		quota_rows.remove_child(child)
		child.queue_free()
	quota_bars.clear()
	_quota_row_views.clear()

func reveal_quota() -> void:
	_page_scroll.ensure_control_visible(quota_rows.get_parent())

func _refresh_quota_styles() -> void:
	for bar in quota_bars:
		if is_instance_valid(bar):
			var accent := ui.danger_color if bar.value <= 10 else ui.warning_color if bar.value <= 30 else ui.green_color
			var signature := "%s/%s/%s" % [ui.surface_2_color.to_html(), ui.border_color.to_html(), accent.to_html()]
			if bar.get_meta("quota_style", "") == signature:
				continue
			bar.set_meta("quota_style", signature)
			bar.add_theme_stylebox_override("background", ui.style(ui.surface_2_color, ui.border_color, 5, 1))
			bar.add_theme_stylebox_override("fill", ui.style(accent, Color.TRANSPARENT, 5, 0))

func _action_button(text: String, action: String, parent: Container) -> Button:
	var button := ui.small_choice_button(text)
	button.pressed.connect(func() -> void: action_requested.emit(action))
	parent.add_child(button)
	return button

func render(state: Dictionary) -> void:
	_state = state.duplicate(true)
	if not is_instance_valid(status_label):
		return
	path_edit.text = str(state.get("exe_path", ""))
	path_edit.tooltip_text = path_edit.text
	var quota_counts: Dictionary = {}
	for id in state.get("quota_snapshots", {}):
		quota_counts[id] = state.quota_snapshots[id].get("models", []).size()
	var accounts_state := {"accounts": state.get("accounts", []), "selected_account": state.get("selected_account", "default"), "default_account": state.get("default_account", "default"), "quota_counts": quota_counts, "account_sessions": state.get("account_sessions", {})}
	var selection_changed: bool = accounts_state.selected_account != _account_snapshot.get("selected_account", "")
	if accounts_state != _account_snapshot:
		_account_snapshot = accounts_state.duplicate(true)
		_build_account_rows(state)
	var display_id := selected_account() if selection_changed else _quota_account
	if not state.get("accounts", []).any(func(item: Dictionary) -> bool: return str(item.get("id", "")) == display_id):
		display_id = selected_account()
	_show_cached_quota(display_id)
	var installed := bool(state.get("installed", false))
	var running := bool(state.get("running", false))
	status_label.text = "独立代理已启用" if installed else "独立代理未启用"
	if installed and not bool(state.get("intact", false)):
		status_label.text = "代理文件缺失或已变化，请重新启用或卸载恢复"
	if bool(state.get("recovery_required", false)):
		status_label.text = "上次操作中断，请卸载并恢复"
	if running:
		status_label.text += " · Antigravity 正在运行"
	endpoint_label.text = "当前代理：SOCKS5 127.0.0.1:%d" % int(state.get("current_port", 7890))
	if installed and int(state.get("proxy_port", 0)) != int(state.get("current_port", 7890)):
		endpoint_label.text += " · 端口已变更，请退出 Antigravity 后同步"
	_update_buttons()

func set_busy(value: bool) -> void:
	_busy = value
	_update_buttons()

func _update_buttons() -> void:
	if not is_instance_valid(enable_button):
		return
	var running := bool(_state.get("running", false))
	var installed := bool(_state.get("installed", false))
	choose_button.disabled = _busy or installed
	enable_button.disabled = _busy or running or bool(_state.get("recovery_required", false))
	disable_button.disabled = _busy or running or not installed
	launch_button.disabled = _busy or running or not installed or bool(_state.get("recovery_required", false))
	refresh_button.disabled = _busy
	account_add.disabled = _busy
	account_name.editable = not _busy
	for button in account_buttons:
		button.disabled = _busy

func show_message(message: String, success: bool) -> void:
	if is_instance_valid(message_label):
		message_label.text = message
		message_label.add_theme_color_override("font_color", ui.green_color if success else ui.danger_color)
