class_name UiFactory
extends RefCounted

signal theme_applied

var text_color: Color
var muted_color: Color
var green_color: Color
var green_dark_color: Color
var border_color: Color
var surface_color: Color
var surface_2_color: Color
var crystal_white_color: Color
var overlay_text_color: Color
var danger_color: Color
var warning_color: Color
var console_bg_color: Color
var console_text_color: Color
var background_modulate_color: Color
var font_scale := 1.18
var font_size_percent := 100

var _theme: Dictionary = {}
var _colors: Dictionary = {}
var _textures: Dictionary = {}
var _panel_textures: Dictionary = {}
var _texture_cache: Dictionary = {}
var _tracked_labels: Array = []
var _tracked_panels: Array = []
var _tracked_buttons: Array = []
var _tracked_toggles: Array = []
var _tracked_options: Array = []
var _tracked_inputs: Array = []
var _tracked_backgrounds: Array[CanvasItem] = []
var _tracked_sliders: Array[HSlider] = []
var _created_since_prune := 0

func _init(theme_or_text: Variant = {}, muted := Color("527384"), green := Color("16866f"), green_dark := Color("c5f1dfde"), border := Color("a8e8e8e8"), surface := Color("e9fbfbd4"), surface_2 := Color("d8f4f3dc"), crystal := Color("f7ffffdf")) -> void:
	if theme_or_text is Dictionary:
		apply_theme(theme_or_text)
	else:
		apply_theme(_legacy_snapshot(theme_or_text, muted, green, green_dark, border, surface, surface_2, crystal))

func apply_theme(snapshot: Dictionary) -> void:
	var previous_palette := _theme.duplicate(false)
	var next_palette := snapshot.duplicate(false)
	previous_palette.erase("font_size_percent")
	next_palette.erase("font_size_percent")
	var fonts_only := not _theme.is_empty() and previous_palette == next_palette and font_size_percent != int(snapshot.get("font_size_percent", 100))
	_theme = snapshot.duplicate(true)
	_colors = snapshot.get("colors", {}) if snapshot.get("colors", {}) is Dictionary else {}
	_textures = snapshot.get("button_textures", {}) if snapshot.get("button_textures", {}) is Dictionary else {}
	_panel_textures = snapshot.get("panel_textures", {}) if snapshot.get("panel_textures", {}) is Dictionary else {}
	font_scale = float(snapshot.get("font_scale", 1.18))
	font_size_percent = clampi(int(snapshot.get("font_size_percent", 100)), 100, 200)
	text_color = color("text", Color("12384a"))
	muted_color = color("muted", Color("527384"))
	green_color = color("accent", Color("16866f"))
	green_dark_color = color("accent_soft", Color("c5f1dfde"))
	border_color = color("border", Color("a8e8e8e8"))
	surface_color = color("surface", Color("e9fbfbd4"))
	surface_2_color = color("surface2", Color("d8f4f3dc"))
	crystal_white_color = color("crystal", Color("f7ffffdf"))
	overlay_text_color = color("overlay_text", Color("efffff"))
	danger_color = color("danger", Color("c84d68"))
	warning_color = color("warning", Color("b87918"))
	console_bg_color = color("console_bg", Color("102a35e8"))
	console_text_color = color("console_text", Color("d9fff3"))
	background_modulate_color = color("background_modulate", Color.WHITE)
	if fonts_only:
		_resize_tracked_fonts()
	else:
		_retheme_tracked()
	theme_applied.emit()

func theme_id() -> String:
	return str(_theme.get("id", "blue_healing"))

func color(role: String, fallback := Color.WHITE) -> Color:
	var raw: Variant = _colors.get(role, fallback)
	return Color(str(raw)) if raw is String else raw if raw is Color else fallback

func style(fill: Color, border: Color, radius: int, width: int) -> StyleBoxFlat:
	var result := StyleBoxFlat.new()
	result.bg_color = _resolve_color(fill)
	result.border_color = _resolve_color(border)
	result.set_border_width_all(width)
	result.set_corner_radius_all(radius)
	if bool(_theme.get("flat", false)):
		result.set_corner_radius_all(mini(radius, 7))
	result.content_margin_left = 10
	result.content_margin_right = 10
	result.content_margin_top = 8
	result.content_margin_bottom = 8
	result.shadow_color = Color("17394a35") if theme_id() == "blue_healing" else Color("00000055")
	result.shadow_size = 8
	result.shadow_offset = Vector2(0, 3)
	if bool(_theme.get("flat", false)):
		result.shadow_size = 0
	result.anti_aliasing = true
	return result

func panel(fill: Color, border: Color, radius: int) -> PanelContainer:
	var result := PanelContainer.new()
	result.add_theme_stylebox_override("panel", _panel_style(fill, border, radius))
	var entry := {
		"node": result, "fill": fill, "border": border, "radius": radius,
		"fill_role": _semantic_role(fill), "border_role": _semantic_role(border)
	}
	result.set_meta("ui_panel_entry", entry)
	_tracked_panels.append(entry)
	_track_creation()
	return result

func apply_background_theme(item: CanvasItem) -> void:
	item.modulate = background_modulate_color
	var corners: Array = _theme.get("background_gradient", [])
	if corners.size() == 4:
		var material: ShaderMaterial = item.get_meta("ui_gradient_material") if item.has_meta("ui_gradient_material") else null
		if material == null:
			material = ShaderMaterial.new()
			material.shader = preload("res://assets/ui/soft_gradient.gdshader")
			item.set_meta("ui_gradient_material", material)
		for index in 4:
			material.set_shader_parameter(["top_left", "top_right", "bottom_left", "bottom_right"][index], Color(str(corners[index])))
		item.material = material
	else:
		item.material = null
	if not item in _tracked_backgrounds:
		_tracked_backgrounds.append(item)

func update_panel_style(panel: PanelContainer, fill: Color, border: Color, radius := 16) -> void:
	if not is_instance_valid(panel):
		return
	var entry: Dictionary = panel.get_meta("ui_panel_entry", {})
	if not entry.is_empty():
		if entry.fill == fill and entry.border == border and entry.radius == radius:
			return
		entry["fill"] = fill
		entry["border"] = border
		entry["radius"] = radius
		entry["fill_role"] = _semantic_role(fill)
		entry["border_role"] = _semantic_role(border)
	panel.add_theme_stylebox_override("panel", _panel_style(_resolve_color(fill), _resolve_color(border), radius))

func update_label_color(label_node: Label, color_value: Color) -> void:
	if not is_instance_valid(label_node):
		return
	var entry: Dictionary = label_node.get_meta("ui_label_entry", {})
	if not entry.is_empty():
		if entry.color == color_value:
			return
		entry["color"] = color_value
		entry["role"] = _semantic_role(color_value)
	label_node.add_theme_color_override("font_color", _resolve_color(color_value))
	_apply_text_depth(label_node, _resolve_color(color_value))

func margin(left: int, top: int, right: int, bottom: int) -> MarginContainer:
	var result := MarginContainer.new()
	result.add_theme_constant_override("margin_left", left)
	result.add_theme_constant_override("margin_top", top)
	result.add_theme_constant_override("margin_right", right)
	result.add_theme_constant_override("margin_bottom", bottom)
	return result

func label(text: String, font_size: int, color_value: Color) -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_font_size_override("font_size", _scaled_font(font_size))
	result.add_theme_color_override("font_color", _resolve_color(color_value))
	result.add_theme_color_override("font_disabled_color", muted_color.darkened(0.25))
	_apply_text_depth(result, result.get_theme_color("font_color"))
	var entry := {"node": result, "size": font_size, "color": color_value, "role": _semantic_role(color_value)}
	result.set_meta("ui_label_entry", entry)
	_tracked_labels.append(entry)
	_track_creation()
	return result

func button(text: String, _fill: Color, color_value: Color) -> Button:
	var result := Button.new()
	result.text = text
	result.custom_minimum_size.y = 46
	result.add_theme_font_size_override("font_size", _scaled_font(13))
	result.add_theme_color_override("font_color", _resolve_color(color_value))
	result.add_theme_color_override("font_hover_color", text_color)
	result.add_theme_color_override("font_pressed_color", text_color)
	result.add_theme_color_override("font_focus_color", text_color)
	_apply_text_depth(result, result.get_theme_color("font_color"))
	_apply_button_textures(result, false)
	_tracked_buttons.append({"node": result, "small": false, "color": color_value, "role": _semantic_role(color_value)})
	_track_creation()
	return result

func small_choice_button(text: String, color_value: Color = Color.TRANSPARENT) -> Button:
	var text_color_value := (text_color if bool(_theme.get("flat", false)) else muted_color) if color_value.a <= 0.001 else color_value
	var result := button(text, surface_2_color, text_color_value)
	result.custom_minimum_size = Vector2(64, 38)
	result.add_theme_font_size_override("font_size", _scaled_font(12))
	result.set_meta("ui_small_button", true)
	_apply_button_textures(result, true)
	return result

func apply_nav_button(button: Button, active: bool) -> void:
	button.set_meta("ui_nav", true)
	button.set_meta("ui_nav_active", active)
	button.add_theme_font_size_override("font_size", _scaled_font(13))
	button.add_theme_color_override("font_color", green_color if active else muted_color)
	button.add_theme_stylebox_override("normal", _texture_style("pressed" if active else "normal", true))
	if bool(_theme.get("flat", false)):
		button.add_theme_color_override("font_color", text_color if active else muted_color)
		button.add_theme_stylebox_override("normal", style(color("nav_active") if active else color("nav"), Color.TRANSPARENT, 6, 0))
		button.add_theme_stylebox_override("hover", style(surface_2_color, Color.TRANSPARENT, 6, 0))
		button.add_theme_stylebox_override("pressed", style(color("nav_active"), Color.TRANSPARENT, 6, 0))

func apply_rail_button(button: Button, active: bool) -> void:
	apply_nav_button(button, active)
	button.set_meta("ui_rail", true)
	button.add_theme_font_size_override("font_size", 22)
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER

func apply_crystal_toggle_theme(toggle: CheckButton) -> void:
	toggle.add_theme_font_size_override("font_size", _scaled_font(13))
	toggle.add_theme_color_override("font_color", text_color)
	toggle.add_theme_color_override("font_hover_color", green_color)
	toggle.add_theme_color_override("font_pressed_color", green_color)
	toggle.add_theme_color_override("font_focus_color", text_color)
	toggle.add_theme_color_override("font_disabled_color", muted_color)
	_apply_text_depth(toggle, text_color)
	var icons: Dictionary = _theme.get("toggle_icons", {})
	for icon_name in ["checked", "checked_disabled", "unchecked", "unchecked_disabled"]:
		var icon_path := str(icons.get("off" if icon_name.begins_with("unchecked") else "on", ""))
		if icon_path.is_empty():
			toggle.remove_theme_icon_override(icon_name)
		else:
			toggle.add_theme_icon_override(icon_name, _load_svg_texture(icon_path))
	if not toggle in _tracked_toggles:
		_tracked_toggles.append(toggle)

func apply_crystal_option_theme(option: OptionButton) -> void:
	option.add_theme_font_size_override("font_size", _scaled_font(13))
	option.add_theme_color_override("font_color", text_color)
	option.add_theme_color_override("font_hover_color", green_color)
	option.add_theme_color_override("font_pressed_color", green_color)
	option.add_theme_color_override("font_focus_color", text_color)
	_apply_text_depth(option, text_color)
	option.add_theme_stylebox_override("normal", _texture_style("normal", false))
	option.add_theme_stylebox_override("hover", _texture_style("hover", false))
	option.add_theme_stylebox_override("pressed", _texture_style("pressed", false))
	option.add_theme_stylebox_override("focus", _texture_style("hover", false))
	option.add_theme_stylebox_override("disabled", _panel_style(surface_2_color, border_color, 6))
	option.add_theme_color_override("font_disabled_color", muted_color)
	var popup := option.get_popup()
	popup.add_theme_color_override("font_color", text_color)
	popup.add_theme_color_override("font_hover_color", green_color)
	popup.add_theme_color_override("font_accelerator_color", muted_color)
	popup.add_theme_font_size_override("font_size", _scaled_font(12))
	popup.add_theme_stylebox_override("panel", _panel_style(crystal_white_color, border_color, 8))
	popup.add_theme_stylebox_override("hover", _panel_style(surface_2_color, green_color, 8, true))
	if not option in _tracked_options:
		_tracked_options.append(option)

func apply_line_edit_theme(edit: LineEdit, base_size := 12) -> void:
	edit.add_theme_font_size_override("font_size", _scaled_font(base_size))
	edit.add_theme_color_override("font_color", text_color)
	edit.add_theme_color_override("font_placeholder_color", muted_color)
	edit.add_theme_color_override("font_uneditable_color", muted_color)
	edit.add_theme_color_override("caret_color", green_color)
	edit.add_theme_color_override("selection_color", green_dark_color)
	_apply_text_depth(edit, text_color)
	edit.add_theme_stylebox_override("normal", _panel_style(color("input", crystal_white_color), border_color, 10, true))
	edit.add_theme_stylebox_override("focus", _panel_style(color("input", crystal_white_color), green_color, 10, true))
	edit.add_theme_stylebox_override("read_only", _panel_style(surface_2_color, border_color, 7, true))
	_track_input(edit, "line", base_size)

func apply_text_edit_theme(edit: TextEdit, base_size := 12) -> void:
	edit.add_theme_font_size_override("font_size", _scaled_font(base_size))
	edit.add_theme_color_override("font_color", text_color)
	edit.add_theme_color_override("font_placeholder_color", muted_color)
	edit.add_theme_color_override("caret_color", green_color)
	edit.add_theme_color_override("selection_color", green_dark_color)
	_apply_text_depth(edit, text_color)
	edit.add_theme_stylebox_override("normal", _panel_style(color("input", crystal_white_color), border_color, 10, true))
	edit.add_theme_stylebox_override("focus", _panel_style(color("input", crystal_white_color), green_color, 10, true))
	_track_input(edit, "text", base_size)

func apply_console_theme(view: RichTextLabel, base_size := 12) -> void:
	view.add_theme_font_size_override("normal_font_size", _scaled_font(base_size))
	view.add_theme_color_override("default_color", console_text_color)
	_apply_text_depth(view, console_text_color)
	view.add_theme_stylebox_override("normal", _panel_style(console_bg_color, border_color, 10))
	_track_input(view, "console", base_size)

func apply_spinbox_theme(spin: SpinBox, base_size := 13) -> void:
	var line := spin.get_line_edit()
	if is_instance_valid(line):
		apply_line_edit_theme(line, base_size)

func apply_slider_theme(slider: HSlider) -> void:
	for state in ["slider", "grabber_area", "grabber_area_highlight"]:
		var fill := green_color if state != "slider" else green_dark_color
		var track := style(fill, Color.TRANSPARENT, 3, 0)
		track.set_content_margin_all(0)
		track.content_margin_top = 3
		track.content_margin_bottom = 3
		slider.add_theme_stylebox_override(state, track)
	var key := "slider-thumb-" + green_color.to_html()
	if not _texture_cache.has(key):
		var thumb := Image.new()
		thumb.load_svg_from_string('<svg xmlns="http://www.w3.org/2000/svg" width="22" height="22"><circle cx="11" cy="11" r="9" fill="#fff" stroke="#%s" stroke-width="3"/></svg>' % green_color.to_html(false))
		_texture_cache[key] = ImageTexture.create_from_image(thumb)
	for state in ["grabber", "grabber_highlight"]:
		slider.add_theme_icon_override(state, _texture_cache[key])
	if not slider in _tracked_sliders:
		_tracked_sliders.append(slider)

func stat_card(parent: Container, title: String, value: String, color_value: Color) -> Label:
	var card := panel(surface_color, border_color, 16)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size.y = 88
	parent.add_child(card)
	var content_margin := margin(13, 10, 13, 10)
	card.add_child(content_margin)
	var column := VBoxContainer.new()
	content_margin.add_child(column)
	column.add_child(label(title, 11, muted_color))
	var value_label := label(value, 18, color_value)
	column.add_child(value_label)
	return value_label

func action_card(title: String, description: String, action: String) -> Array:
	var card := panel(surface_color, border_color, 16)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var content_margin := margin(16, 14, 16, 14)
	card.add_child(content_margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 7)
	content_margin.add_child(column)
	column.add_child(label(title, 14, text_color))
	var desc := label(description, 11, muted_color)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(desc)
	var action_button := small_choice_button(action)
	action_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	column.add_child(action_button)
	return [card, action_button]

func empty_message(text: String) -> Label:
	var result := label(text, 15, muted_color)
	result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	result.custom_minimum_size = Vector2(760, 180)
	return result

func axolotl_texture() -> Texture2D:
	# A single untinted brand asset for every theme and connection state.
	return load("res://assets/ui/axolotl_mark.svg")

func _apply_text_depth(control: Control, foreground: Color) -> void:
	var light_text := foreground.get_luminance() > 0.5
	control.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5) if light_text else Color(1, 1, 1, 0.5))
	control.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.2) if light_text else Color(1, 1, 1, 0.15))
	control.add_theme_constant_override("shadow_offset_x", 0)
	control.add_theme_constant_override("shadow_offset_y", 1)
	control.add_theme_constant_override("shadow_outline_size", 0)
	control.add_theme_constant_override("outline_size", 1)

func _scaled_font(base_size: int) -> int:
	var baseline := maxi(15 if bool(_theme.get("flat", false)) else base_size + 1, int(round(float(base_size) * font_scale)))
	return int(round(float(baseline) * font_size_percent / 100.0))

func primary_button(button: Button) -> void:
	button.set_meta("ui_primary", true)
	_apply_button_textures(button, bool(button.get_meta("ui_small_button", false)))

func _panel_style(fill: Color, border: Color, radius: int, compact := false) -> StyleBox:
	var role := _panel_texture_role(_semantic_role(fill))
	var path := str(_panel_textures.get(role, ""))
	if path.is_empty():
		return style(fill, border, radius, 1)
	var box := StyleBoxTexture.new()
	box.texture = _load_svg_texture(path)
	box.set_meta("source_path", path)
	box.set_meta("ui_panel_role", role)
	var horizontal_edge := 18.0 if compact else 26.0
	var vertical_edge := 10.0 if compact else 26.0
	box.texture_margin_left = horizontal_edge
	box.texture_margin_right = horizontal_edge
	box.texture_margin_top = vertical_edge
	box.texture_margin_bottom = vertical_edge
	box.content_margin_left = 10.0
	box.content_margin_right = 10.0
	box.content_margin_top = 7.0 if compact else 8.0
	box.content_margin_bottom = 7.0 if compact else 8.0
	return box

func _panel_texture_role(role: String) -> String:
	match role:
		"surface": return "surface"
		"surface2", "accent_soft", "nav", "nav_active": return "surface2"
		"crystal": return "crystal"
		"sidebar": return "sidebar"
		"input": return "input"
		"console_bg": return "console"
	return ""

func _texture_style(state: String, compact := false) -> StyleBox:
	if bool(_theme.get("flat", false)):
		var fill := surface_2_color
		if state == "hover":
			fill = color("nav_active")
		elif state == "pressed":
			fill = green_dark_color
		var flat := style(fill, border_color, 6, 1)
		flat.content_margin_left = 14
		flat.content_margin_right = 14
		return flat
	var path := str(_textures.get(state, _textures.get("normal", "")))
	var box := StyleBoxTexture.new()
	if not path.is_empty():
		box.texture = _load_svg_texture(path)
		box.set_meta("source_path", path)
	var horizontal_edge := 20.0 if compact else 24.0
	var vertical_edge := 10.0 if compact else 12.0
	box.texture_margin_left = horizontal_edge
	box.texture_margin_right = horizontal_edge
	box.texture_margin_top = vertical_edge
	box.texture_margin_bottom = vertical_edge
	box.content_margin_left = 12.0
	box.content_margin_right = 12.0
	box.content_margin_top = 7.0
	box.content_margin_bottom = 7.0
	return box

func _load_svg_texture(path: String) -> Texture2D:
	if _texture_cache.has(path):
		return _texture_cache[path]
	var resource: Resource = load(path)
	if not resource is Texture2D:
		return null
	var texture := resource as Texture2D
	_texture_cache[path] = texture
	return texture

func _apply_button_textures(button: Button, compact: bool) -> void:
	button.add_theme_stylebox_override("normal", _texture_style("normal", compact))
	button.add_theme_stylebox_override("hover", _texture_style("hover", compact))
	button.add_theme_stylebox_override("pressed", _texture_style("pressed", compact))
	button.add_theme_stylebox_override("focus", _texture_style("hover", compact))
	button.add_theme_stylebox_override("disabled", style(color("disabled", Color("b9cbd1aa")), border_color, 12, 1))
	button.add_theme_color_override("font_disabled_color", muted_color.darkened(0.2))
	if bool(_theme.get("flat", false)) and button.get_meta("ui_primary", false):
		button.add_theme_stylebox_override("normal", style(green_color, green_color, 6, 0))
		button.add_theme_stylebox_override("hover", style(green_color.lightened(0.1), green_color, 6, 0))
		button.add_theme_stylebox_override("pressed", style(green_color.darkened(0.08), green_color, 6, 0))
		button.add_theme_stylebox_override("focus", style(Color.TRANSPARENT, green_color, 6, 2))
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			button.add_theme_color_override(state, color("primary_text", console_bg_color))
		_apply_text_depth(button, color("primary_text", console_bg_color))

func _resolve_color(value: Color) -> Color:
	if value.a <= 0.001:
		return value
	var role := _semantic_role(value)
	return color(role, value) if not role.is_empty() else value

func _semantic_role(value: Color) -> String:
	var legacy := _role_from_color(value)
	if not legacy.is_empty():
		return legacy
	for role in _colors:
		var raw: Variant = _colors[role]
		var candidate: Color = Color(str(raw)) if raw is String else raw if raw is Color else Color.TRANSPARENT
		if candidate.to_html() == value.to_html():
			return str(role)
	return ""

func _role_from_color(value: Color) -> String:
	match value.to_html(false).to_lower():
		"12384a": return "text"
		"527384", "78909a", "72578c": return "muted"
		"16866f", "75cdb4", "7ed8d2", "8ddfc9", "765399", "9e7ac0", "3478b8": return "accent"
		"c5f1df", "c9f4e3", "d4f3e8", "d9f4ee", "e8e2f8": return "accent_soft"
		"a8e8e8", "b5eee0", "d8d3f6", "d7caee", "d1c8ed", "c7ffff", "b4eee1": return "border"
		"e9fbfb", "e8faf5", "f3f4ff", "ecfbf5", "f7f2ff": return "surface"
		"d8f4f3", "e3f3f3": return "surface2"
		"f7ffff", "f8ffff", "faf8ff", "fffaff", "f6ffff", "ecfff8": return "crystal"
		"e6fbf8": return "sidebar"
		"f4ffff": return "nav"
		"efffff": return "overlay_text"
		"c84d68", "a84545": return "danger"
		"b87918": return "warning"
		"102a35", "071c25": return "console_bg"
		"d9fff3": return "console_text"
		"d5e9e8": return "disabled"
	return ""

func _resize_tracked_fonts() -> void:
	for entry in _tracked_labels:
		if is_instance_valid(entry.node):
			entry.node.add_theme_font_size_override("font_size", _scaled_font(int(entry.size)))
	for entry in _tracked_buttons:
		var node = entry.node
		if is_instance_valid(node):
			var base_size := 12 if node.get_meta("ui_small_button", false) and not node.get_meta("ui_nav", false) else 13
			node.add_theme_font_size_override("font_size", 22 if node.get_meta("ui_rail", false) else _scaled_font(base_size))
	for toggle in _tracked_toggles:
		if is_instance_valid(toggle):
			toggle.add_theme_font_size_override("font_size", _scaled_font(13))
	for option in _tracked_options:
		if is_instance_valid(option):
			option.add_theme_font_size_override("font_size", _scaled_font(13))
			option.get_popup().add_theme_font_size_override("font_size", _scaled_font(12))
	for entry in _tracked_inputs:
		if is_instance_valid(entry.node):
			entry.node.add_theme_font_size_override("normal_font_size" if entry.kind == "console" else "font_size", _scaled_font(int(entry.size)))

func _retheme_tracked() -> void:
	_prune_invalid_tracked()
	for item in _tracked_backgrounds:
		if is_instance_valid(item):
			apply_background_theme(item)
	for entry in _tracked_labels:
		var node = entry.get("node")
		if is_instance_valid(node):
			var label_source: Color = entry.get("color", text_color)
			var label_role := str(entry.get("role", ""))
			var label_color := color(label_role, label_source) if not label_role.is_empty() else _resolve_color(label_source)
			node.add_theme_font_size_override("font_size", _scaled_font(int(entry.get("size", 12))))
			node.add_theme_color_override("font_color", label_color)
			_apply_text_depth(node, label_color)
	for entry in _tracked_panels:
		var node = entry.get("node")
		if is_instance_valid(node):
			var fill_source: Color = entry.get("fill", surface_color)
			var border_source: Color = entry.get("border", border_color)
			var fill_role := str(entry.get("fill_role", ""))
			var border_role := str(entry.get("border_role", ""))
			var themed_fill := color(fill_role, fill_source) if not fill_role.is_empty() else _resolve_color(fill_source)
			var themed_border := color(border_role, border_source) if not border_role.is_empty() else _resolve_color(border_source)
			node.add_theme_stylebox_override("panel", _panel_style(themed_fill, themed_border, int(entry.get("radius", 16))))
	for entry in _tracked_buttons:
		var node = entry.get("node")
		if not is_instance_valid(node):
			continue
		var compact := bool(node.get_meta("ui_small_button", false))
		_apply_button_textures(node, compact)
		node.add_theme_font_size_override("font_size", _scaled_font(12 if compact else 13))
		if bool(node.get_meta("ui_rail", false)):
			apply_rail_button(node, bool(node.get_meta("ui_nav_active", false)))
		elif bool(node.get_meta("ui_nav", false)):
			apply_nav_button(node, bool(node.get_meta("ui_nav_active", false)))
		else:
			var button_source: Color = entry.get("color", text_color)
			var button_role := str(entry.get("role", ""))
			var button_color := color(button_role, button_source) if not button_role.is_empty() else _resolve_color(button_source)
			node.add_theme_color_override("font_color", button_color)
			node.add_theme_color_override("font_hover_color", text_color)
			node.add_theme_color_override("font_pressed_color", text_color)
			_apply_text_depth(node, button_color)
			if node.get_meta("ui_primary", false):
				_apply_button_textures(node, compact)
	for toggle in _tracked_toggles:
		if is_instance_valid(toggle):
			apply_crystal_toggle_theme(toggle)
	for slider in _tracked_sliders:
		if is_instance_valid(slider):
			apply_slider_theme(slider)
	for option in _tracked_options:
		if is_instance_valid(option):
			apply_crystal_option_theme(option)
	for entry in _tracked_inputs:
		var node = entry.get("node")
		if not is_instance_valid(node):
			continue
		var kind := str(entry.get("kind", "line"))
		var size := int(entry.get("size", 12))
		if kind == "line":
			apply_line_edit_theme(node, size)
		elif kind == "text":
			apply_text_edit_theme(node, size)
		elif kind == "console":
			apply_console_theme(node, size)

func _prune_invalid_tracked() -> void:
	_tracked_labels = _tracked_labels.filter(func(entry): return is_instance_valid(entry.get("node")))
	_tracked_panels = _tracked_panels.filter(func(entry): return is_instance_valid(entry.get("node")))
	_tracked_buttons = _tracked_buttons.filter(func(entry): return is_instance_valid(entry.get("node")))
	_tracked_toggles = _tracked_toggles.filter(func(node): return is_instance_valid(node))
	_tracked_options = _tracked_options.filter(func(node): return is_instance_valid(node))
	_tracked_sliders.assign(_tracked_sliders.filter(func(node): return is_instance_valid(node)))
	_tracked_inputs = _tracked_inputs.filter(func(entry): return is_instance_valid(entry.get("node")))
	var valid_backgrounds: Array[CanvasItem] = []
	for item in _tracked_backgrounds:
		if is_instance_valid(item):
			valid_backgrounds.append(item)
	_tracked_backgrounds = valid_backgrounds

func _track_creation() -> void:
	_created_since_prune += 1
	if _created_since_prune >= 512:
		_created_since_prune = 0
		_prune_invalid_tracked()

func _track_input(node: Control, kind: String, base_size: int) -> void:
	for entry in _tracked_inputs:
		if entry.get("node") == node:
			entry["kind"] = kind
			entry["size"] = base_size
			return
	_tracked_inputs.append({"node": node, "kind": kind, "size": base_size})

func _legacy_snapshot(text: Color, muted: Color, green: Color, green_dark: Color, border: Color, surface: Color, surface_2: Color, crystal: Color) -> Dictionary:
	return {
		"id": "blue_healing",
		"name": "海蓝治愈",
		"font_scale": 1.18,
		"colors": {
			"text": text.to_html(), "muted": muted.to_html(), "accent": green.to_html(), "accent_soft": green_dark.to_html(),
			"border": border.to_html(), "surface": surface.to_html(), "surface2": surface_2.to_html(), "crystal": crystal.to_html(),
			"sidebar": Color("e6fbf8dc").to_html(), "nav": Color("f4ffffa8").to_html(), "nav_active": green_dark.to_html(),
			"overlay_text": Color("efffff").to_html(), "danger": Color("c84d68").to_html(), "warning": Color("b87918").to_html(),
			"success": green.to_html(), "console_bg": Color("102a35e8").to_html(), "console_text": Color("d9fff3").to_html(),
			"input": crystal.to_html(), "disabled": Color("b9cbd1aa").to_html(), "background_modulate": Color.WHITE.to_html()
		},
		"button_textures": {
			"normal": "res://assets/ui/button_blue_normal.svg",
			"hover": "res://assets/ui/button_blue_hover.svg",
			"pressed": "res://assets/ui/button_blue_pressed.svg"
		},
		"panel_textures": {
			"surface": "res://assets/ui/panel_blue_surface.svg", "surface2": "res://assets/ui/panel_blue_surface2.svg",
			"crystal": "res://assets/ui/panel_blue_crystal.svg", "sidebar": "res://assets/ui/panel_blue_sidebar.svg",
			"input": "res://assets/ui/panel_blue_input.svg", "console": "res://assets/ui/panel_blue_console.svg"
		}
	}
