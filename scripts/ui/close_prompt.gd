class_name ClosePrompt
extends Control

## 主窗口关闭确认浮层
## 只负责展示关闭选项并发出用户意图

signal cancel_requested
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
	card.custom_minimum_size = Vector2(680, 300)
	center.add_child(card)
	var content_margin = ui.margin(30, 26, 30, 24)
	card.add_child(content_margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	content_margin.add_child(column)
	column.add_child(ui.label("退出 HexagonProxy？", 21, TEXT))
	var message = ui.label(
		"如果只是暂时不看主窗口，建议继续在托盘守护网络。\n确认退出后，HexagonProxy 会关闭 Windows 系统代理，并停止由本应用启动的 Mihomo 内核。",
		13,
		MUTED
	)
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(message)
	var warning = ui.label("⚠ 退出会中断当前代理连接。ESC 可快速取消。", 12, ui.warning_color)
	warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(warning)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 10)
	column.add_child(actions)
	_build_actions(actions)

func _build_actions(actions: HBoxContainer) -> void:
	var cancel_button = ui.button("取消", Color("e3f3f3e8"), TEXT)
	cancel_button.custom_minimum_size.x = 82
	cancel_button.pressed.connect(func(): cancel_requested.emit())
	actions.add_child(cancel_button)

	var tray_button = ui.button("继续后台守护", Color("d8f4eee8"), GREEN)
	tray_button.custom_minimum_size.x = 150
	tray_button.add_theme_color_override("font_focus_color", ui.green_color)
	tray_button.pressed.connect(func(): tray_requested.emit())
	actions.add_child(tray_button)

	var exit_button = ui.button("确认退出", Color("ffe3e8ef"), RED)
	exit_button.custom_minimum_size.x = 112
	exit_button.add_theme_color_override("font_color", ui.danger_color)
	exit_button.add_theme_color_override("font_hover_color", ui.danger_color)
	exit_button.add_theme_color_override("font_pressed_color", ui.danger_color)
	exit_button.pressed.connect(func(): exit_requested.emit())
	actions.add_child(exit_button)
	tray_button.grab_focus()
