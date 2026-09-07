class_name CodexAccountsPanel
extends Node

signal create_profile_requested(display_name: String)
signal switch_profile_requested(profile_id: String)
signal forget_profile_requested(profile_id: String)
signal refresh_requested
signal launch_requested
signal import_requested(path: String, display_name: String)
signal capture_requested(display_name: String)
signal capture_to_requested(profile_id: String)
signal usage_requested(profile_id: String)
signal recover_requested
signal authorize_requested(display_name: String)

const SURFACE := Color("e9fbfbd4")
const SURFACE_2 := Color("d8f4f3dc")
const BORDER := Color("a8e8e8e8")
const TEXT := Color("12384a")
const MUTED := Color("527384")
const GREEN := Color("16866f")
const YELLOW := Color("b87918")
const ConfirmationPromptScript = preload("res://scripts/ui/confirmation_prompt.gd")

var ui: UiFactory
var _prompt_host: Control
var _running := false
var _installed := false
var _busy := false
var _selected_id := "default"
var status_label: Label
var message_label: Label
var profile_name_edit: LineEdit
var profile_list: VBoxContainer
var create_button: Button
var refresh_button: Button
var launch_button: Button
var import_button: Button
var capture_button: Button
var authorize_button: Button
var recover_button: Button
var _file_dialog: FileDialog
var _row_actions: Array[Button] = []
var _reset_labels: Array[Label] = []
var _countdown_elapsed := 0.0

func _process(delta: float) -> void:
	_countdown_elapsed += delta
	if _countdown_elapsed < 30:
		return
	_countdown_elapsed = 0
	for label in _reset_labels:
		if is_instance_valid(label):
			label.text = _reset_text(int(label.get_meta("reset", 0)))

func setup(factory: UiFactory, prompt_host: Control = null) -> void:
	ui = factory
	_prompt_host = prompt_host

func build() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 14)
	page.add_child(_build_header_card())
	page.add_child(_build_profiles_card())
	return page

func render(state: Dictionary, profiles: Array) -> void:
	_running = bool(state.get("running", false))
	_selected_id = str(state.get("selected_id", "default"))
	var installed := bool(state.get("installed", false))
	_installed = installed
	if is_instance_valid(recover_button):
		recover_button.visible = bool(state.get("recovery_required", false))
	if is_instance_valid(status_label):
		if not installed:
			status_label.text = "未检测到 Codex Windows 桌面版"
			status_label.add_theme_color_override("font_color", ui.danger_color)
		elif _running:
			status_label.text = "Codex 正在运行 · 当前配置：%s" % _selected_name(profiles)
			if bool(state.get("identity_mismatch", false)):
				status_label.text = "检测到登录账号已变化 · 请保存为独立账号，或保存到指定空账号栏"
			status_label.add_theme_color_override("font_color", ui.green_color)
		else:
			status_label.text = "Codex 已安装 · 当前配置：%s" % _selected_name(profiles)
			status_label.add_theme_color_override("font_color", ui.muted_color)
	if is_instance_valid(create_button):
		create_button.disabled = _busy
	if is_instance_valid(launch_button):
		launch_button.disabled = not installed or _running
	_rebuild_profiles(profiles)
	_update_buttons()

func show_message(message: String, success: bool) -> void:
	if is_instance_valid(message_label):
		message_label.text = message
		message_label.add_theme_color_override(
			"font_color",
			ui.green_color if success else ui.danger_color
		)

func clear_profile_name() -> void:
	if is_instance_valid(profile_name_edit):
		profile_name_edit.clear()

func set_busy(busy: bool) -> void:
	_busy = busy
	_update_buttons()

func _update_buttons() -> void:
	for button in [create_button, refresh_button, import_button, capture_button, recover_button, authorize_button]:
		if is_instance_valid(button):
			button.disabled = _busy
	if is_instance_valid(profile_name_edit):
		profile_name_edit.editable = not _busy
	if is_instance_valid(launch_button):
		launch_button.disabled = _busy or _running or not _installed
	for button in _row_actions:
		if is_instance_valid(button):
			button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			button.custom_minimum_size.y = 40
			button.disabled = _busy or bool(button.get_meta("unavailable", false))

func _build_header_card() -> PanelContainer:
	var card := ui.panel(SURFACE, BORDER, 20)
	card.custom_minimum_size.y = 250
	var margin := ui.margin(22, 18, 22, 18)
	card.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	column.add_child(ui.label("Codex 桌面账号", 18, TEXT))
	var desc := ui.label(
		"保存多个账号的登录与配置，切换时自动备份并重启 Codex。聊天历史、插件和本地文件保留。",
		11,
		MUTED
	)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(desc)
	status_label = ui.label("正在检测 Codex…", 13, MUTED)
	column.add_child(status_label)
	var input_row := HBoxContainer.new()
	input_row.add_theme_constant_override("separation", 10)
	column.add_child(input_row)
	profile_name_edit = LineEdit.new()
	profile_name_edit.placeholder_text = "账号备注，例如：工作号 / 备用号"
	profile_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	profile_name_edit.custom_minimum_size.y = 42
	ui.apply_line_edit_theme(profile_name_edit, 12)
	input_row.add_child(profile_name_edit)
	create_button = ui.small_choice_button("新建账号配置", GREEN)
	create_button.custom_minimum_size.x = 140
	create_button.pressed.connect(_request_create)
	input_row.add_child(create_button)
	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 8)
	column.add_child(action_row)
	authorize_button = ui.small_choice_button("授权添加账号", GREEN)
	authorize_button.pressed.connect(func() -> void: authorize_requested.emit(profile_name_edit.text.strip_edges()))
	action_row.add_child(authorize_button)
	launch_button = ui.small_choice_button("启动当前配置")
	launch_button.pressed.connect(func() -> void: launch_requested.emit())
	action_row.add_child(launch_button)
	refresh_button = ui.small_choice_button("刷新状态")
	refresh_button.pressed.connect(func() -> void: refresh_requested.emit())
	action_row.add_child(refresh_button)
	import_button = ui.small_choice_button("导入 auth.json")
	import_button.pressed.connect(_choose_import_file)
	action_row.add_child(import_button)
	capture_button = ui.small_choice_button("保存为独立账号")
	capture_button.pressed.connect(func() -> void: capture_requested.emit(profile_name_edit.text.strip_edges()))
	action_row.add_child(capture_button)
	recover_button = ui.small_choice_button("恢复中断切换", YELLOW)
	recover_button.visible = false
	recover_button.pressed.connect(func() -> void: recover_requested.emit())
	action_row.add_child(recover_button)
	message_label = ui.label(
		"推荐：授权添加账号，在浏览器完成一次官方登录后自动保存，不影响当前账号。之后可从列表切换。",
		10,
		MUTED
	)
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(message_label)
	return card

func _build_profiles_card() -> PanelContainer:
	var card := ui.panel(SURFACE, BORDER, 20)
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var margin := ui.margin(22, 18, 22, 18)
	card.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	column.add_child(ui.label("账号配置", 18, TEXT))
	var hint := ui.label(
		"登录文件仅保存在本机；额度查询仅发送至 OpenAI 官方服务。显示剩余额度，查询失败会保留上次结果。",
		10,
		MUTED
	)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(hint)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	profile_list = VBoxContainer.new()
	profile_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	profile_list.add_theme_constant_override("separation", 8)
	scroll.add_child(profile_list)
	return card

func _rebuild_profiles(profiles: Array) -> void:
	if not is_instance_valid(profile_list):
		return
	for child in profile_list.get_children():
		profile_list.remove_child(child)
		child.queue_free()
	_row_actions.clear()
	_reset_labels.clear()
	for raw in profiles:
		if raw is Dictionary:
			profile_list.add_child(_profile_row(raw as Dictionary))

func _profile_row(profile: Dictionary) -> Control:
	var card := ui.panel(SURFACE_2, BORDER, 14)
	card.custom_minimum_size.y = 82
	var margin := ui.margin(14, 10, 14, 10)
	card.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	margin.add_child(row)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(words)
	var name := str(profile.get("name", "Codex 账号"))
	var name_label := ui.label(name, 14, TEXT)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.add_child(name_label)
	var logged_in := bool(profile.get("login_present", false))
	var selected := str(profile.get("id", "")) == _selected_id
	var login_text := "已保存登录" if logged_in else "待登录"
	var state_text := "%s · %s" % [login_text, "当前账号" if selected else "账号备份"]
	var email := str(profile.get("email", ""))
	var plan := str(profile.get("plan", ""))
	if not email.is_empty():
		state_text += " · " + email
	if not plan.is_empty():
		state_text += " · " + plan
	var account_label := ui.label(state_text, 10, GREEN if logged_in else YELLOW)
	account_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.add_child(account_label)
	var usage: Dictionary = profile.get("usage", {})
	var meters := HBoxContainer.new()
	meters.add_theme_constant_override("separation", 24)
	words.add_child(meters)
	meters.add_child(_quota_meter("5 小时", usage.get("five_hour", -1), int(usage.get("five_hour_reset", 0))))
	meters.add_child(_quota_meter("每周", usage.get("weekly", -1), int(usage.get("weekly_reset", 0))))
	if not str(usage.get("updated_at", "")).is_empty():
		words.add_child(ui.label("更新于 " + str(usage["updated_at"]).replace("T", " ").replace("Z", " UTC"), 10, MUTED))
	var usage_error := str(profile.get("usage_error", ""))
	if not usage_error.is_empty():
		var error_label := ui.label(usage_error, 10, YELLOW)
		error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		words.add_child(error_label)
	var action_text := "切换"
	if selected:
		action_text = "运行中" if _running else "启动"
	var action := ui.small_choice_button(action_text)
	action.custom_minimum_size.x = 76
	action.set_meta("unavailable", not _installed or (selected and _running))
	_row_actions.append(action)
	action.pressed.connect(_request_profile_action.bind(profile.duplicate(true)))
	row.add_child(action)
	var usage_button := ui.small_choice_button("查额度")
	usage_button.set_meta("unavailable", not logged_in or str(profile.get("auth_kind", "")) == "api")
	usage_button.pressed.connect(func() -> void: usage_requested.emit(str(profile.get("id", ""))))
	_row_actions.append(usage_button)
	row.add_child(usage_button)
	if not logged_in:
		var save_button := ui.small_choice_button("将当前登录保存到此账号", GREEN)
		save_button.pressed.connect(func() -> void: capture_to_requested.emit(str(profile.get("id", ""))))
		_row_actions.append(save_button)
		row.add_child(save_button)
	if not bool(profile.get("builtin", false)):
		var forget := ui.small_choice_button("移除", ui.danger_color)
		forget.tooltip_text = "只从列表移除，不删除 Codex profile 数据"
		forget.pressed.connect(_request_forget.bind(profile.duplicate(true)))
		forget.set_meta("unavailable", selected)
		_row_actions.append(forget)
		row.add_child(forget)
	return card

func _request_create() -> void:
	if _busy or not is_instance_valid(profile_name_edit):
		return
	create_profile_requested.emit(profile_name_edit.text.strip_edges())

func _request_profile_action(profile: Dictionary) -> void:
	if _busy:
		return
	var profile_id := str(profile.get("id", ""))
	if profile_id == _selected_id:
		launch_requested.emit()
		return
	_show_switch_prompt(profile)

func _show_switch_prompt(profile: Dictionary) -> void:
	if not is_instance_valid(_prompt_host):
		switch_profile_requested.emit(str(profile.get("id", "")))
		return
	var existing := _prompt_host.get_node_or_null("CodexSwitchPrompt")
	if is_instance_valid(existing):
		existing.queue_free()
	var prompt = ConfirmationPromptScript.new()
	prompt.name = "CodexSwitchPrompt"
	_prompt_host.add_child(prompt)
	prompt.setup(
		ui,
		"切换到“%s”？" % str(profile.get("name", "Codex 账号")),
		"将保存当前登录与配置，关闭 Codex，再以目标账号启动。正在执行的本地任务会被中断；切换失败会尝试恢复原账号。",
		"切换并重启",
		false
	)
	prompt.confirmed.connect(
		func() -> void:
			switch_profile_requested.emit(str(profile.get("id", "")))
	)

func _request_forget(profile: Dictionary) -> void:
	if _busy:
		return
	if not is_instance_valid(_prompt_host):
		forget_profile_requested.emit(str(profile.get("id", "")))
		return
	var existing := _prompt_host.get_node_or_null("CodexForgetPrompt")
	if is_instance_valid(existing):
		existing.queue_free()
	var prompt = ConfirmationPromptScript.new()
	prompt.name = "CodexForgetPrompt"
	_prompt_host.add_child(prompt)
	prompt.setup(
		ui,
		"从列表移除“%s”？" % str(profile.get("name", "Codex 账号")),
		"只会移除 HexagonProxy 中的入口，不会删除该 Codex profile 的登录状态、聊天历史或本地数据。",
		"移除入口",
		true
	)
	prompt.confirmed.connect(
		func() -> void:
			forget_profile_requested.emit(str(profile.get("id", "")))
	)

func _selected_name(profiles: Array) -> String:
	for raw in profiles:
		if raw is Dictionary and str(raw.get("id", "")) == _selected_id:
			return str(raw.get("name", "默认账号"))
	return "默认账号"

func _choose_import_file() -> void:
	if _busy:
		return
	if not is_instance_valid(_file_dialog):
		_file_dialog = FileDialog.new()
		_file_dialog.title = "导入 Codex 登录文件"
		_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_file_dialog.filters = PackedStringArray(["*.json ; Codex 登录文件"])
		_file_dialog.use_native_dialog = true
		add_child(_file_dialog)
		_file_dialog.file_selected.connect(func(path: String) -> void:
			if not _busy:
				import_requested.emit(path, profile_name_edit.text.strip_edges())
		)
	_file_dialog.popup_centered_ratio(0.65)

func _format_remaining(value: Variant) -> String:
	if not (value is int or value is float) or float(value) < 0:
		return "未知"
	return "%d%%" % int(clampf(float(value), 0, 100))

func _quota_meter(title: String, amount: Variant, reset: int) -> Control:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 5)
	var known := (amount is int or amount is float) and float(amount) >= 0
	var tint := GREEN if known and float(amount) > 20 else YELLOW
	column.add_child(ui.label(title + "剩余 " + _format_remaining(amount), 13, tint if known else MUTED))
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(140, 12)
	bar.show_percentage = false
	bar.value = clampf(float(amount), 0, 100) if known else 0
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.1, 0.22, 0.27, 0.45)
	background.set_corner_radius_all(5)
	var fill := StyleBoxFlat.new()
	fill.bg_color = tint
	fill.set_corner_radius_all(5)
	bar.add_theme_stylebox_override("background", background)
	bar.add_theme_stylebox_override("fill", fill)
	column.add_child(bar)
	var recovery := ui.label(_reset_text(reset), 10, MUTED)
	recovery.set_meta("reset", reset)
	_reset_labels.append(recovery)
	recovery.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(recovery)
	return column

func _reset_text(reset: int) -> String:
	if reset <= 0:
		return "恢复时间：未知"
	var seconds := maxi(0, reset - int(Time.get_unix_time_from_system()))
	var local_time := Time.get_datetime_string_from_unix_time(reset + int(Time.get_time_zone_from_system()["bias"]) * 60).replace("T", " ")
	if seconds == 0:
		return "已到恢复时间 · 请刷新额度"
	var minutes := int(ceil(float(seconds) / 60.0))
	var remaining := "%d天 %d小时" % [minutes / 1440, (minutes % 1440) / 60] if minutes >= 1440 else "%d小时 %d分" % [minutes / 60, minutes % 60]
	return "恢复：%s（本地）\n约 %s后" % [local_time, remaining]

func _usage_details(usage: Dictionary) -> String:
	var lines := PackedStringArray()
	var updated := str(usage.get("updated_at", ""))
	if not updated.is_empty():
		lines.append("上次更新（UTC）：" + updated)
	for key in ["five_hour_reset", "weekly_reset"]:
		var reset := int(usage.get(key, 0))
		if reset > 0:
			lines.append(("5 小时重置：" if key == "five_hour_reset" else "每周重置：") + Time.get_datetime_string_from_unix_time(reset) + " UTC")
	return "\n".join(lines)
