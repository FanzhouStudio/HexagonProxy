extends SceneTree

const ThemeService = preload("res://scripts/modules/ui/ui_theme_service.gd")
const Factory = preload("res://scripts/ui/ui_factory.gd")

class FailedSave extends ThemeService:
	func _save_selection() -> Error:
		return ERR_FILE_CANT_WRITE

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	# Tests run with isolated APPDATA; never use production preferences.
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://ui_theme.cfg"))
	var service := ThemeService.new()
	root.add_child(service)
	service.initialize()
	assert(service.snapshot().font_size_percent == 150, "The requested preview defaults to 150%")
	assert(not service.set_font_size_percent(99).ok and not service.set_font_size_percent(201).ok)
	service.set_font_size_percent(100)
	var ui := Factory.new(service.snapshot())
	var label := ui.label("字号", 11, ui.text_color)
	var button := ui.small_choice_button("操作")
	var option := OptionButton.new()
	ui.apply_crystal_option_theme(option)
	var input := LineEdit.new()
	ui.apply_line_edit_theme(input)
	var console := RichTextLabel.new()
	ui.apply_console_theme(console)
	var background := ui.panel(ui.surface_color, ui.border_color, 8)
	var label_baseline := label.get_theme_font_size("font_size")
	var input_baseline := input.get_theme_font_size("font_size")
	var background_style_id := background.get_theme_stylebox("panel").get_instance_id()
	var button_style_id := button.get_theme_stylebox("normal").get_instance_id()
	for percent in [150, 200, 100]:
		service.set_font_size_percent(percent)
		ui.apply_theme(service.snapshot())
		assert(label.get_theme_font_size("font_size") == int(round(float(label_baseline) * percent / 100.0)), "100% must preserve the previous rounded font size")
		assert(input.get_theme_font_size("font_size") == int(round(float(input_baseline) * percent / 100.0)))
		assert(button.get_theme_font_size("font_size") == label.get_theme_font_size("font_size"))
		assert(console.get_theme_font_size("normal_font_size") == label.get_theme_font_size("font_size"))
		assert(option.get_popup().get_theme_font_size("font_size") == label.get_theme_font_size("font_size"))
		assert(background.get_theme_stylebox("panel").get_instance_id() == background_style_id and button.get_theme_stylebox("normal").get_instance_id() == button_style_id, "Dragging the font slider cannot rebuild unrelated styles")
	service.set_font_size_percent(200)
	service.set_theme("midnight")
	var reopened := ThemeService.new()
	root.add_child(reopened)
	reopened.initialize()
	assert(reopened.snapshot().font_size_percent == 200 and reopened.current_theme_id() == "midnight", "Font size and theme persist independently")
	var failing := FailedSave.new()
	root.add_child(failing)
	failing.initialize()
	assert(not failing.set_font_size_percent(175).ok and failing.snapshot().font_size_percent == 200, "Save failure keeps the last working size")
	service.set_font_size_percent(150)
	var scene: Control = load("res://main.tscn").instantiate()
	root.add_child(scene)
	root.size = Vector2i(1600, 900)
	root.content_scale_size = Vector2i(1920, 1080)
	await process_frame
	await process_frame
	var settings = scene.settings_panel
	assert(settings.font_size_slider.min_value == 100 and settings.font_size_slider.max_value == 200)
	assert(settings.font_size_slider.value == 150 and settings.font_size_label.text == "150%")
	for percent in [100, 150, 200]:
		settings.font_size_slider.value = percent
		await create_timer(0.15).timeout
		assert(scene.ui.font_size_percent == percent and settings.font_size_label.text == "%d%%" % percent)
		for page_name in ["dashboard", "nodes", "subscription", "routing", "terminal", "linux", "codex", "antigravity", "settings"]:
			scene.app_shell.show_page(page_name)
			await process_frame
			await process_frame
			var minimum: Vector2 = scene.app_shell.pages[page_name].get_combined_minimum_size()
			assert(minimum.x <= scene.app_shell.page_host.size.x + 1 and minimum.y <= scene.app_shell.page_host.size.y + 1, "%d%% must not push page %s outside the viewport" % [percent, page_name])
		if percent == 200:
			var scroll := scene.app_shell.pages.settings as ScrollContainer
			assert(scroll.get_v_scroll_bar().visible, "Large settings text remains reachable by scrolling: content=%s view=%s" % [settings._settings_grid.get_combined_minimum_size(), scroll.size])
			scroll.ensure_control_visible(settings.autostart_toggle)
			await process_frame
			assert(scroll.get_global_rect().encloses(settings.autostart_toggle.get_global_rect()), "Bottom settings controls remain accessible at 200%")
	settings.font_size_slider.value = 150
	settings.font_size_slider.drag_ended.emit(true)
	assert(scene.ui.font_size_percent == 150, "Releasing the slider immediately applies and saves the last value")
	settings.font_size_slider.value = 140
	scene._quit_application()
	var saved := ThemeService.new()
	root.add_child(saved)
	saved.initialize()
	assert(saved.snapshot().font_size_percent == 140, "Exiting immediately after a keyboard adjustment saves the final selection")
	for node in [label, button, option, input, console, background]:
		node.free()
	print("PASS: font baseline, 150%/200% scaling, slider, persistence, rollback, style reuse and all-page layouts")
	quit(0)
