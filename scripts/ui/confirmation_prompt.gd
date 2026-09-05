class_name ConfirmationPrompt
extends Control

signal confirmed

const TEXT := Color("12384a")
const MUTED := Color("527384")
const GREEN := Color("16866f")
const RED := Color("c84d68")

var ui: UiFactory

func setup(factory: UiFactory, title_text: String, message_text: String, confirm_text := "确认", destructive := false) -> void:
	ui = factory
	z_index = 100
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var veil := ColorRect.new()
	veil.color = Color("0a354552")
	veil.mouse_filter = Control.MOUSE_FILTER_STOP
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(veil)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var card := ui.panel(Color("f6fffff5"), Color("bfffffff"), 20)
	card.custom_minimum_size = Vector2(520, 220)
	center.add_child(card)
	var margin := ui.margin(28, 24, 28, 22)
	card.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)
	column.add_child(ui.label(title_text, 20, TEXT))
	var message := ui.label(message_text, 13, MUTED)
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(message)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 10)
	column.add_child(actions)
	var cancel_button := ui.button("取消", Color("e3f3f3e8"), TEXT)
	cancel_button.custom_minimum_size.x = 92
	cancel_button.add_theme_color_override("font_focus_color", ui.text_color)
	var cancel_shortcut := Shortcut.new()
	var escape_event := InputEventKey.new()
	escape_event.keycode = KEY_ESCAPE
	cancel_shortcut.events = [escape_event]
	cancel_button.shortcut = cancel_shortcut
	cancel_button.pressed.connect(queue_free)
	actions.add_child(cancel_button)
	var accent := RED if destructive else GREEN
	var fill := Color("ffe3e8ef") if destructive else Color("d8f4eee8")
	var confirm_button := ui.button(confirm_text, fill, accent)
	confirm_button.custom_minimum_size.x = 92
	var semantic_accent := ui.danger_color if destructive else ui.green_color
	confirm_button.add_theme_color_override("font_hover_color", semantic_accent)
	confirm_button.add_theme_color_override("font_pressed_color", semantic_accent)
	confirm_button.add_theme_color_override("font_focus_color", semantic_accent)
	confirm_button.pressed.connect(func() -> void:
		confirmed.emit()
		queue_free()
	)
	actions.add_child(confirm_button)
	confirm_button.grab_focus()
