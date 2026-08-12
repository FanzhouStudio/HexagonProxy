class_name DesktopPet
extends Node

signal main_requested
signal hidden_by_user

const PET_WINDOW_SIZE := Vector2i(300, 230)
const GREEN := Color("70e1aa")
const YELLOW := Color("f4cd6b")
const RED := Color("ef7484")
const MUTED := Color("8791aa")

var pet_window: Window
var pet_texture: TextureRect
var node_label: Label
var delay_label: Label
var latency_bar: ProgressBar
var _pet_base_y := 58.0
var _animation_time := 0.0

func create_pet(initial_position: Vector2i, initially_visible: bool) -> void:
	if is_instance_valid(pet_window):
		set_pet_visible(initially_visible)
		return
	pet_window = Window.new()
	pet_window.title = "六角恐龙"
	pet_window.size = PET_WINDOW_SIZE
	pet_window.transparent = true
	pet_window.transparent_bg = true
	pet_window.borderless = true
	pet_window.always_on_top = true
	pet_window.unresizable = true
	pet_window.visible = false
	pet_window.force_native = true
	pet_window.close_requested.connect(_hide_from_user)
	add_child(pet_window)
	_build_pet_contents()
	if initial_position.x > -10000:
		pet_window.position = _clamp_to_screen(initial_position)
	else:
		pet_window.position = _default_position()
	set_pet_visible(initially_visible)

func set_pet_visible(value: bool) -> void:
	if not is_instance_valid(pet_window):
		return
	pet_window.visible = value
	if value:
		pet_window.position = _clamp_to_screen(pet_window.position)

func is_pet_visible() -> bool:
	return is_instance_valid(pet_window) and pet_window.visible

func get_pet_position() -> Vector2i:
	return pet_window.position if is_instance_valid(pet_window) else Vector2i(-10000, -10000)

func set_node_status(node_name: String, delay_ms: int, online: bool) -> void:
	if not is_instance_valid(node_label):
		return
	if not online:
		node_label.text = "六角恐龙正在休息"
		node_label.tooltip_text = ""
		delay_label.text = "离线"
		latency_bar.value = 0
		_set_bar_color(MUTED)
		return
	var display_name := node_name if not node_name.is_empty() else "等待选择节点"
	node_label.text = display_name
	node_label.tooltip_text = display_name
	if delay_ms <= 0:
		delay_label.text = "测速中"
		latency_bar.value = 22
		_set_bar_color(MUTED)
		return
	delay_label.text = "%d ms" % delay_ms
	latency_bar.value = clampf(110.0 - float(delay_ms) / 4.5, 5.0, 100.0)
	_set_bar_color(GREEN if delay_ms < 200 else YELLOW if delay_ms < 500 else RED)

func _build_pet_contents() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.gui_input.connect(_on_pet_input)
	pet_window.add_child(root)

	var status_shadow := Panel.new()
	status_shadow.position = Vector2(14, 12)
	status_shadow.size = Vector2(272, 50)
	status_shadow.add_theme_stylebox_override("panel", _style(Color(0, 0, 0, 0.32), Color.TRANSPARENT, 18, 0))
	root.add_child(status_shadow)
	var status := PanelContainer.new()
	status.position = Vector2(10, 8)
	status.size = Vector2(272, 50)
	status.add_theme_stylebox_override("panel", _style(Color("111729e6"), Color("506f9178"), 18, 1))
	root.add_child(status)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 7)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 7)
	status.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	margin.add_child(column)
	var title_row := HBoxContainer.new()
	column.add_child(title_row)
	node_label = Label.new()
	node_label.text = "六角恐龙正在休息"
	node_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	node_label.add_theme_font_size_override("font_size", 12)
	node_label.add_theme_color_override("font_color", Color.WHITE)
	title_row.add_child(node_label)
	delay_label = Label.new()
	delay_label.text = "离线"
	delay_label.add_theme_font_size_override("font_size", 11)
	delay_label.add_theme_color_override("font_color", MUTED)
	title_row.add_child(delay_label)
	latency_bar = ProgressBar.new()
	latency_bar.custom_minimum_size.y = 7
	latency_bar.show_percentage = false
	latency_bar.min_value = 0
	latency_bar.max_value = 100
	latency_bar.value = 0
	latency_bar.add_theme_stylebox_override("background", _style(Color("2430473a"), Color.TRANSPARENT, 4, 0))
	column.add_child(latency_bar)
	_set_bar_color(MUTED)

	pet_texture = TextureRect.new()
	pet_texture.texture = _axolotl_texture()
	pet_texture.position = Vector2(42, _pet_base_y)
	pet_texture.size = Vector2(216, 150)
	pet_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pet_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pet_texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pet_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(pet_texture)

	var hint := Label.new()
	hint.text = "拖动移动 · 右键隐藏 · 双击打开"
	hint.position = Vector2(42, 207)
	hint.size = Vector2(216, 18)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Color("a9aebfd0"))
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hint)

func _on_pet_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed:
		return
	if event.button_index == MOUSE_BUTTON_RIGHT:
		_hide_from_user()
	elif event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
		main_requested.emit()
	elif event.button_index == MOUSE_BUTTON_LEFT:
		pet_window.start_drag()

func _hide_from_user() -> void:
	set_pet_visible(false)
	hidden_by_user.emit()

func _process(delta: float) -> void:
	if not is_pet_visible() or not is_instance_valid(pet_texture):
		return
	_animation_time += delta
	pet_texture.position.y = _pet_base_y + sin(_animation_time * 2.4) * 3.0

func _set_bar_color(color: Color) -> void:
	if not is_instance_valid(latency_bar):
		return
	latency_bar.add_theme_stylebox_override("fill", _style(color, color.lightened(0.15), 4, 1))
	delay_label.add_theme_color_override("font_color", color)

func _default_position() -> Vector2i:
	var screen := DisplayServer.get_primary_screen()
	var usable := DisplayServer.screen_get_usable_rect(screen)
	return usable.position + usable.size - PET_WINDOW_SIZE - Vector2i(26, 26)

func _clamp_to_screen(value: Vector2i) -> Vector2i:
	var screen := DisplayServer.get_screen_from_rect(Rect2i(value, PET_WINDOW_SIZE))
	if screen < 0:
		screen = DisplayServer.get_primary_screen()
	var usable := DisplayServer.screen_get_usable_rect(screen)
	return Vector2i(
		clampi(value.x, usable.position.x, usable.end.x - PET_WINDOW_SIZE.x),
		clampi(value.y, usable.position.y, usable.end.y - PET_WINDOW_SIZE.y)
	)

func _axolotl_texture() -> AtlasTexture:
	var texture := AtlasTexture.new()
	texture.atlas = load("res://assets/axolotl.png")
	texture.region = Rect2(24, 44, 112, 72)
	return texture

func _style(fill: Color, border: Color, radius: int, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	return style
