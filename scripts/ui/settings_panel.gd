class_name SettingsPanel
extends Node

signal system_proxy_intent_changed(enabled: bool)
signal ports_apply_requested(mixed_port: int, controller_port: int)
signal port_random_requested(kind: String)
signal core_restart_requested
signal core_update_requested
signal ui_theme_requested(theme_id: String)
signal log_message(message: String)

const SURFACE := Color("e9fbfbd4")
const SURFACE_2 := Color("d8f4f3dc")
const BORDER := Color("a8e8e8e8")
const TEXT := Color("12384a")
const MUTED := Color("527384")
const GREEN := Color("16866f")
const GREEN_DARK := Color("c5f1dfde")
const YELLOW := Color("b87918")
const RED := Color("c84d68")

var ui: UiFactory
var proxy_config
var _system_proxy_enabled := false
var proxy_toggle: CheckButton
var mixed_port_spin: SpinBox
var controller_port_spin: SpinBox
var system_proxy_hint_label: Label
var port_message_label: Label
var desktop_pet_toggle: CheckButton
var autostart_toggle: CheckButton
var core_status_label: Label
var core_download_button: Button
var core_progress: ProgressBar
var core_progress_label: Label
var theme_selector: OptionButton
var theme_description_label: Label
var theme_message_label: Label
func setup(factory: UiFactory, config, system_proxy_enabled: bool) -> void:
	ui = factory
	proxy_config = config
	_system_proxy_enabled = system_proxy_enabled

func build() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 14)
	page.add_child(_build_appearance_card())
	page.add_child(_build_core_card())
	page.add_child(_build_behavior_card())
	return page

func pet_control() -> CheckButton:
	return desktop_pet_toggle

func autostart_control() -> CheckButton:
	return autostart_toggle

func _build_appearance_card() -> PanelContainer:
	var card := ui.panel(SURFACE, BORDER, 20)
	card.custom_minimum_size.y = 150
	var content_margin := ui.margin(22, 16, 22, 16)
	card.add_child(content_margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	content_margin.add_child(column)
	column.add_child(ui.label("界面与阅读", 18, TEXT))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	column.add_child(row)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(words)
	words.add_child(ui.label("色系主题", 14, TEXT))
	theme_description_label = ui.label("海蓝治愈 · 明亮柔和的水蓝色系", 11, MUTED)
	words.add_child(theme_description_label)
	theme_selector = OptionButton.new()
	theme_selector.custom_minimum_size = Vector2(210, 42)
	ui.apply_crystal_option_theme(theme_selector)
	theme_selector.item_selected.connect(_on_theme_selected)
	row.add_child(theme_selector)
	theme_message_label = ui.label("按钮、卡片与输入框使用纹理底图 · 文字自动适配明暗主题", 10, MUTED)
	column.add_child(theme_message_label)
	return card

func _build_core_card() -> PanelContainer:
	var card := ui.panel(SURFACE, BORDER, 20)
	card.custom_minimum_size.y = 230
	var content_margin := ui.margin(22, 18, 22, 18)
	card.add_child(content_margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	content_margin.add_child(column)
	column.add_child(ui.label("Mihomo 内核", 18, TEXT))
	core_status_label = ui.label("已安装" if proxy_config.has_core() else "尚未安装", 13, GREEN if proxy_config.has_core() else YELLOW)
	column.add_child(core_status_label)
	var core_path_label := ui.label(proxy_config.core_path(), 11, MUTED)
	core_path_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(core_path_label)
	var core_row := HBoxContainer.new()
	core_row.add_theme_constant_override("separation", 10)
	column.add_child(core_row)
	core_download_button = ui.button("检查并下载最新内核", GREEN_DARK, GREEN)
	core_download_button.pressed.connect(_request_core_update)
	core_row.add_child(core_download_button)
	var restart := ui.button("重启内核", SURFACE_2, TEXT)
	restart.pressed.connect(func() -> void: core_restart_requested.emit())
	core_row.add_child(restart)
	core_progress = ProgressBar.new()
	core_progress.min_value = 0
	core_progress.max_value = 100
	core_progress.value = 0
	core_progress.show_percentage = false
	core_progress.custom_minimum_size.y = 8
	core_progress.visible = false
	column.add_child(core_progress)
	core_progress_label = ui.label("", 11, MUTED)
	column.add_child(core_progress_label)
	return card

func _build_behavior_card() -> PanelContainer:
	var card := ui.panel(SURFACE, BORDER, 20)
	card.custom_minimum_size.y = 360
	var content_margin := ui.margin(22, 18, 22, 18)
	card.add_child(content_margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	content_margin.add_child(column)
	column.add_child(ui.label("连接设置", 18, TEXT))
	var proxy_row := HBoxContainer.new()
	column.add_child(proxy_row)
	var proxy_words := VBoxContainer.new()
	proxy_words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	proxy_row.add_child(proxy_words)
	proxy_words.add_child(ui.label("Windows 系统代理", 14, TEXT))
	system_proxy_hint_label = ui.label("127.0.0.1:%d · 退出时自动关闭" % proxy_config.mixed_port(), 11, MUTED)
	proxy_words.add_child(system_proxy_hint_label)
	proxy_toggle = CheckButton.new()
	proxy_toggle.text = "启用"
	ui.apply_crystal_toggle_theme(proxy_toggle)
	proxy_toggle.set_pressed_no_signal(_system_proxy_enabled)
	proxy_toggle.toggled.connect(_on_system_proxy_toggled)
	proxy_row.add_child(proxy_toggle)
	var port_row := HBoxContainer.new()
	port_row.add_theme_constant_override("separation", 8)
	column.add_child(port_row)
	var port_label := ui.label("本地混合端口", 13, TEXT)
	port_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	port_row.add_child(port_label)
	mixed_port_spin = _create_port_spin(proxy_config.mixed_port())
	port_row.add_child(mixed_port_spin)
	var random_mixed := ui.small_choice_button("随机")
	random_mixed.pressed.connect(func() -> void: port_random_requested.emit("mixed"))
	port_row.add_child(random_mixed)
	var api_row := HBoxContainer.new()
	api_row.add_theme_constant_override("separation", 8)
	column.add_child(api_row)
	var api_label := ui.label("本地控制接口", 13, TEXT)
	api_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	api_row.add_child(api_label)
	api_row.add_child(ui.label("127.0.0.1 :", 12, MUTED))
	controller_port_spin = _create_port_spin(proxy_config.controller_port())
	api_row.add_child(controller_port_spin)
	var random_controller := ui.small_choice_button("随机")
	random_controller.pressed.connect(func() -> void: port_random_requested.emit("controller"))
	api_row.add_child(random_controller)
	var save_ports := ui.small_choice_button("保存端口")
	save_ports.pressed.connect(_request_ports_apply)
	api_row.add_child(save_ports)
	port_message_label = ui.label("修改端口后，下次启动代理时生效。", 10, MUTED)
	column.add_child(port_message_label)
	var tray_row := HBoxContainer.new()
	column.add_child(tray_row)
	var tray_words := VBoxContainer.new()
	tray_words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tray_row.add_child(tray_words)
	tray_words.add_child(ui.label("关闭主窗口", 13, TEXT))
	tray_words.add_child(ui.label("点击 X 时选择最小化到托盘或直接退出", 10, MUTED))
	tray_row.add_child(ui.label("每次询问", 12, GREEN))
	var pet_row := HBoxContainer.new()
	column.add_child(pet_row)
	var pet_words := VBoxContainer.new()
	pet_words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pet_row.add_child(pet_words)
	pet_words.add_child(ui.label("桌面宠物", 13, TEXT))
	pet_words.add_child(ui.label("透明置顶 · 可拖动 · 右键隐藏", 10, MUTED))
	desktop_pet_toggle = CheckButton.new()
	desktop_pet_toggle.text = "显示"
	ui.apply_crystal_toggle_theme(desktop_pet_toggle)
	pet_row.add_child(desktop_pet_toggle)
	var startup_row := HBoxContainer.new()
	column.add_child(startup_row)
	var startup_words := VBoxContainer.new()
	startup_words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	startup_row.add_child(startup_words)
	startup_words.add_child(ui.label("开机自启", 13, TEXT))
	startup_words.add_child(ui.label("登录 Windows 后从托盘启动", 10, MUTED))
	autostart_toggle = CheckButton.new()
	autostart_toggle.text = "启用"
	ui.apply_crystal_toggle_theme(autostart_toggle)
	startup_row.add_child(autostart_toggle)
	return card

func _create_port_spin(value: int) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = 1024
	spin.max_value = 65535
	spin.step = 1
	spin.rounded = true
	spin.value = value
	spin.custom_minimum_size = Vector2(128, 42)
	ui.apply_spinbox_theme(spin, 13)
	return spin

func set_theme_catalog(items: Array, current_id: String) -> void:
	if not is_instance_valid(theme_selector):
		return
	theme_selector.clear()
	var selected_index := 0
	for index in items.size():
		var item: Dictionary = items[index]
		theme_selector.add_item(str(item.get("name", item.get("id", "主题"))))
		theme_selector.set_item_metadata(index, str(item.get("id", "")))
		theme_selector.set_item_tooltip(index, str(item.get("description", "")))
		if str(item.get("id", "")) == current_id:
			selected_index = index
	if theme_selector.item_count > 0:
		theme_selector.select(selected_index)

func set_theme_state(snapshot: Dictionary) -> void:
	if is_instance_valid(theme_description_label):
		theme_description_label.text = "%s · %s" % [str(snapshot.get("name", "界面主题")), str(snapshot.get("description", ""))]
	if is_instance_valid(theme_selector):
		var target_id := str(snapshot.get("id", ""))
		for index in theme_selector.item_count:
			if str(theme_selector.get_item_metadata(index)) == target_id:
				theme_selector.select(index)
				break

func show_theme_message(message: String, success: bool) -> void:
	if is_instance_valid(theme_message_label):
		theme_message_label.text = message
		theme_message_label.add_theme_color_override("font_color", ui.green_color if success else ui.danger_color)

func _on_theme_selected(index: int) -> void:
	if is_instance_valid(theme_selector) and index >= 0 and index < theme_selector.item_count:
		ui_theme_requested.emit(str(theme_selector.get_item_metadata(index)))

func _request_ports_apply() -> void:
	if not is_instance_valid(mixed_port_spin) or not is_instance_valid(controller_port_spin):
		return
	ports_apply_requested.emit(int(mixed_port_spin.value), int(controller_port_spin.value))

func set_port_values(mixed_port: int, controller_port: int) -> void:
	if is_instance_valid(mixed_port_spin):
		mixed_port_spin.set_value_no_signal(mixed_port)
	if is_instance_valid(controller_port_spin):
		controller_port_spin.set_value_no_signal(controller_port)
	if is_instance_valid(system_proxy_hint_label):
		system_proxy_hint_label.text = "127.0.0.1:%d · 退出时自动关闭" % mixed_port

func show_port_message(message: String, success: bool) -> void:
	if is_instance_valid(port_message_label):
		port_message_label.text = message
		port_message_label.add_theme_color_override("font_color", ui.green_color if success else ui.danger_color)
	log_message.emit(message)

func _on_system_proxy_toggled(enabled: bool) -> void:
	system_proxy_intent_changed.emit(enabled)

func reject_system_proxy_enable(message: String) -> void:
	set_system_proxy_state(false)
	log_message.emit(message)

func set_system_proxy_state(enabled: bool) -> void:
	_system_proxy_enabled = enabled
	if is_instance_valid(proxy_toggle):
		proxy_toggle.set_pressed_no_signal(enabled)

func set_system_proxy_busy(busy: bool) -> void:
	if is_instance_valid(proxy_toggle):
		proxy_toggle.disabled = busy
		proxy_toggle.text = "处理中…" if busy else "启用"

func _request_core_update() -> void:
	core_update_requested.emit()

func show_core_update_blocked(message: String) -> void:
	set_core_update_progress(-1.0, message)
	log_message.emit("为避免替换正在运行的文件，内核更新已取消。")

func set_core_update_progress(progress: float, message: String) -> void:
	if not is_instance_valid(core_progress):
		return
	core_progress.visible = progress >= 0.0 and progress < 1.0
	core_progress.value = maxf(progress, 0.0) * 100.0
	core_progress_label.text = message
	core_progress_label.add_theme_color_override("font_color", ui.danger_color if progress < 0.0 else ui.green_color if progress >= 1.0 else ui.muted_color)
	core_download_button.disabled = progress >= 0.0 and progress < 1.0
	if progress >= 1.0:
		core_status_label.text = "已安装"
		core_status_label.add_theme_color_override("font_color", ui.green_color)
