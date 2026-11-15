class_name AntigravityProxyPanel
extends Node

signal executable_selected(path: String)
signal action_requested(action: String)
signal refresh_requested
signal account_add_requested(account_name: String)
signal account_action_requested(action: String, id: String)

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
var account_message: Label
var account_list: VBoxContainer
var account_buttons: Array[Button] = []
var _selected_account := "default"

func setup(factory: UiFactory) -> void:
	ui = factory

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
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(page)
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
	for item in state.get("accounts", []):
		var id := str(item.get("id", ""))
		var card := ui.panel(ui.surface_2_color, ui.border_color, 7)
		account_list.add_child(card)
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		card.add_child(row)
		var title := ui.label(str(item.get("name", "账号")), 14, ui.text_color)
		title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(title)
		var status := str(item.get("email", ""))
		if status.is_empty():
			status = "原有账号 · 使用原登录" if id == "default" else "待登录 · 点击登录后在官方窗口完成授权"
		elif not item.get("logged_in", false):
			status += " · 上次识别的账号"
		if item.get("logged_in", false):
			status += " · 已识别登录"
		if id == _selected_account:
			status += " · 最近打开"
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
		var snapshot: Dictionary = state.get("quota_snapshots", {}).get(id, {})
		if not snapshot.is_empty():
			var summaries := PackedStringArray()
			for model in snapshot.get("models", []):
				summaries.append("%s · 剩余 %s%%" % [model.get("name", "模型"), model.get("remaining", "未知")])
			var quota := ui.label("上次查询：" + " / ".join(summaries), 11, ui.muted_color)
			quota.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			row.add_child(quota)

func _show_cached_quota() -> void:
	var snapshot: Dictionary = _state.get("quota_snapshots", {}).get(selected_account(), {})
	if snapshot.is_empty():
		quota_view.text = "额度未知，打开并登录此配置后点击刷新。"
	else:
		show_quota(snapshot, selected_account())
		quota_view.text = "上次查询缓存（可能已变化）\n" + quota_view.text

func show_quota(result: Dictionary, id := "") -> void:
	for account in _state.get("accounts", []):
		if str(account.get("id", "")) == id:
			quota_heading.text = str(account.get("name", "账号")) + " · 额度详情"
			break
	if not result.get("ok", false):
		quota_view.text = "额度未知：" + str(result.get("message", "读取失败"))
		return
	var lines := PackedStringArray()
	if not str(result.get("email", "")).is_empty():
		lines.append(str(result.email))
	for model in result.get("models", []):
		lines.append("%s：剩余 %s%% · 重置 %s" % [model.get("name", "模型"), model.get("remaining", "未知"), model.get("reset", "未知")])
	lines.append("查询时间（UTC）：%s" % result.get("checked_at", "未知"))
	quota_view.text = "\n".join(lines)

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
	_build_account_rows(state)
	_show_cached_quota()
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
