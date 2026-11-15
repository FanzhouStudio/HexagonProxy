extends Control

signal completed

const MARK = preload("res://assets/ui/axolotl_mark.svg")
var emblem: TextureRect
var wordmark: Label
var caption: Label
var _elapsed := 0.0
var _done := false
var animate := true

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 200
	mouse_filter = Control.MOUSE_FILTER_STOP
	var background := ColorRect.new()
	background.color = Color("49463f")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 16)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(stack)
	var logo_space := Control.new()
	logo_space.custom_minimum_size = Vector2(320, 190)
	logo_space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(logo_space)
	emblem = TextureRect.new()
	emblem.texture = MARK
	emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	emblem.position = Vector2(72, 0)
	emblem.size = Vector2(176, 176)
	emblem.pivot_offset = Vector2(88, 88)
	emblem.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	logo_space.add_child(emblem)
	wordmark = Label.new()
	wordmark.text = "HexagonProxy"
	wordmark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wordmark.add_theme_font_size_override("font_size", 28)
	wordmark.add_theme_color_override("font_color", Color("eee9df"))
	stack.add_child(wordmark)
	caption = Label.new()
	caption.text = "六角恐龙 · 守护每一次连接"
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size", 14)
	caption.add_theme_color_override("font_color", Color("b4afa5"))
	stack.add_child(caption)
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Segoe UI"])
	var intro_theme := Theme.new()
	intro_theme.default_font = font
	theme = intro_theme
	update_frame(0.0)
	set_process(animate)

func update_frame(seconds: float) -> void:
	_elapsed = seconds
	# One short greeting: gentle rise and breath, then reveal the ready UI.
	var rise := clampf(seconds / 0.35, 0.0, 1.0)
	emblem.position.y = lerpf(8.0, 0.0, ease(rise, 0.5)) - sin(seconds * PI * 2.0) * 2.0
	emblem.scale = Vector2.ONE * (1.0 + sin(seconds * PI * 2.0) * 0.018)
	wordmark.modulate.a = rise
	caption.modulate.a = clampf((seconds - 0.12) / 0.3, 0.0, 1.0)
	modulate.a = 1.0 - smoothstep(0.75, 1.1, seconds)

func _process(delta: float) -> void:
	update_frame(_elapsed + delta)
	if _elapsed >= 1.1:
		dismiss()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		dismiss()

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_pressed():
		dismiss()

func dismiss() -> void:
	if _done:
		return
	_done = true
	set_process(false)
	hide()
	completed.emit()
	queue_free()
