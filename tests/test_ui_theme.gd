extends SceneTree

const ThemeServiceScript = preload("res://scripts/modules/ui/ui_theme_service.gd")
const UiFactoryScript = preload("res://scripts/ui/ui_factory.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var service = ThemeServiceScript.new()
	root.add_child(service)
	service.initialize()
	service.set_theme("blue_healing")
	var ui = UiFactoryScript.new(service.snapshot())
	var label := ui.label("主题文字", 13, Color("12384a"))
	var panel := ui.panel(Color("e9fbfbd4"), Color("a8e8e8e8"), 16)
	var dynamic_panel := ui.panel(ui.surface_color, ui.border_color, 16)
	var button := ui.small_choice_button("操作")
	var primary := ui.small_choice_button("添加账号")
	ui.primary_button(primary)
	var option := OptionButton.new()
	ui.apply_crystal_option_theme(option)
	var input := LineEdit.new()
	ui.apply_line_edit_theme(input)
	var console := RichTextLabel.new()
	ui.apply_console_theme(console)
	var toggle := CheckButton.new()
	ui.apply_crystal_toggle_theme(toggle)
	var background := ColorRect.new()
	ui.apply_background_theme(background)
	for id in ["midnight", "blue_healing", "qq_warm", "midnight"]:
		service.set_theme(id)
		ui.apply_theme(service.snapshot())
		assert(ui.theme_id() == id)
		for box in [panel.get_theme_stylebox("panel"), dynamic_panel.get_theme_stylebox("panel"), button.get_theme_stylebox("normal"), option.get_theme_stylebox("normal"), input.get_theme_stylebox("normal"), console.get_theme_stylebox("normal")]:
			assert(box is StyleBoxFlat and box.shadow_size == 0, "Redesigned themes must not restore water textures or shadows")
		assert(label.get_theme_color("font_color") == ui.text_color, "Legacy labels retain semantic colors across theme changes")
		assert(label.get_theme_constant("shadow_offset_y") == 1 and label.get_theme_constant("outline_size") == 1, "Text depth stays subtle and consistent after theme changes")
		assert(ui.axolotl_texture().resource_path == "res://assets/ui/axolotl_mark.svg", "Mascot artwork never depends on the theme")
		assert(panel.get_theme_stylebox("panel").bg_color == ui.surface_color)
		assert(dynamic_panel.get_theme_stylebox("panel").bg_color == ui.surface_color)
		assert(input.get_theme_stylebox("normal").bg_color == ui.color("input"))
		assert(console.get_theme_color("default_color") == ui.console_text_color)
		for state in ["font_color", "font_pressed_color", "font_hover_color", "font_focus_color"]:
			assert(primary.get_theme_color(state) == ui.color("primary_text"), "Primary actions need readable text in every interaction state")
		var primary_luminance := ui.color("primary_text").srgb_to_linear().get_luminance()
		var accent_luminance: float = ui.green_color.srgb_to_linear().get_luminance()
		assert((maxf(primary_luminance, accent_luminance) + 0.05) / (minf(primary_luminance, accent_luminance) + 0.05) > 4.5, "Primary actions need at least 4.5:1 contrast")
		if id == "qq_warm":
			assert(background.material == null, "Switching to a solid theme clears the gradient")
		else:
			assert(background.material is ShaderMaterial and not background.is_processing(), "Gradient background stays static")
			var corners: Array = service.snapshot().background_gradient
			assert(background.material.get_shader_parameter("top_left") == Color(corners[0]))
			assert(background.material.get_shader_parameter("bottom_right") == Color(corners[3]))
			assert(toggle.has_theme_icon_override("checked") and toggle.has_theme_icon_override("unchecked"))
			for corner in corners:
				var base := Color(corner).blend(ui.surface_color)
				var luminances := [base.srgb_to_linear().get_luminance(), ui.text_color.srgb_to_linear().get_luminance()]
				var contrast := (maxf(luminances[0], luminances[1]) + 0.05) / (minf(luminances[0], luminances[1]) + 0.05)
				assert(contrast > 7.0, "%s %s main text contrast %.2f must exceed 7:1" % [id, corner, contrast])
	var second = ThemeServiceScript.new()
	root.add_child(second)
	second.initialize()
	assert(second.current_theme_id() == "midnight", "Existing theme identifiers remain persistent")
	for node in [label, panel, dynamic_panel, button, primary, option, input, console, toggle, background]:
		node.free()
	service.free()
	second.free()
	print("PASS: flat QQ themes, static gradients, semantic colors, contrast, primary states and persistence")
	quit(0)
