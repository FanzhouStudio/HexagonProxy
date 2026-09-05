class_name ClosePrompt
extends Control

## 主窗口关闭确认浮层
## 只负责展示关闭选项并发出用户意图

signal tray_requested
signal exit_requested

const TEXT := Color("12384a")
const MUTED := Color("527384")
const GREEN := Color("16866f")
const RED := Color("c84d68")

var ui

func setup(factory) -> void:
	ui = factory
	name = "ClosePrompt"
	z_index = 110
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()

func _build() -> void:
	var veil := ColorRect.new()
	veil.color = Color("0a354566")
	veil.mouse_filter = Control.MOUSE_FILTER_STOP
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(veil)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var card = ui.panel(Color("f6fffff8"), Color("bfffffff"), 22)
	card.custom_minimum_size = Vector2(590, 250)
	center.add_child(card)
	var content_margin = ui.margin(30, 26, 30, 24)
	card.add_child(content_margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	content_margin.add_child(column)
	column.add_child(ui.label("关闭 HexagonProxy", 21, TEXT))
	var message = ui.label(
		"要让 HexagonProxy 继续在后台守护网络吗？\n最小化到托盘后，主窗口和任务栏图标都会收起；直接退出会关闭系统代理并停止本应用启动的内核。",
		13,
		MUTED
	)
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(message)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 10)
	column.add_child(actions)
	_build_actions(actions)

func _build_actions(actions: HBoxContainer) -> void:
	var cancel_button = ui.button("取消", Color("e3f3f3e8"), TEXT)
	cancel_button.custom_minimum_size.x = 82
	cancel_button.pressed.connect(queue_free)
	var cancel_shortcut := Shortcut.new()
	var escape_event := InputEventKey.new()
	escape_event.keycode = KEY_ESCAPE
	cancel_shortcut.events = [escape_event]
	cancel_button.shortcut = cancel_shortcut
	actions.add_child(cancel_button)

	var tray_button = ui.button("最小化到托盘", Color("d8f4eee8"), GREEN)
	tray_button.custom_minimum_size.x = 142
	tray_button.add_theme_color_override("font_focus_color", ui.green_color)
	tray_button.pressed.connect(func(): tray_requested.emit())
	actions.add_child(tray_button)

	var exit_button = ui.button("直接退出", Color("ffe3e8ef"), RED)
	exit_button.custom_minimum_size.x = 104
	exit_button.add_theme_color_override("font_hover_color", ui.danger_color)
	exit_button.add_theme_color_override("font_pressed_color", ui.danger_color)
	exit_button.pressed.connect(func(): exit_requested.emit())
	actions.add_child(exit_button)
	tray_button.grab_focus()
