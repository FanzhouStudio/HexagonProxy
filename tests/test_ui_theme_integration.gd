extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene: Control = load("res://main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var shell = scene.app_shell
	var settings = scene.settings_panel
	assert(settings.theme_selector.item_count == 3)
	for id in ["blue_healing", "midnight", "qq_warm", "blue_healing"]:
		settings.ui_theme_requested.emit(id)
		await process_frame
		assert(scene.ui.theme_id() == id)
		assert(shell.window_action_buttons["exit"].get_theme_color("font_color") == scene.ui.danger_color)
		assert(shell.page_title.get_theme_color("font_color") == scene.ui.overlay_text_color, "Page headings stay readable in light themes")
		assert(settings.theme_description_label.get_theme_color("font_color") == scene.ui.muted_color)
		assert(settings.theme_selector.get_theme_stylebox("normal") is StyleBoxFlat)
		assert((shell.aquarium_background.material is ShaderMaterial) == (id != "qq_warm"))
		assert(scene.dashboard_panel.traffic_graph.background == scene.ui.color("graph_bg", scene.ui.crystal_white_color), "Charts cannot retain a previous theme's background")
		assert(scene.dashboard_panel.traffic_graph.accent == scene.ui.green_color)
		for online in [false, true]:
			scene.dashboard_panel.set_status(online, false, "fixture")
			assert(scene.dashboard_panel.pet_texture.modulate == Color.WHITE, "Connection state cannot tint the mascot")
			assert(scene.dashboard_panel.pet_texture.texture.resource_path == "res://assets/ui/axolotl_mark.svg")
		assert(scene.dashboard_panel.pet_speech.get_theme_color("font_color") == scene.ui.text_color)
		assert(scene.dashboard_panel.profile_label.get_theme_color("font_color") == scene.ui.muted_color)
		assert(shell.rail_buttons.settings.get_theme_font_size("font_size") == 22, "Theme switching preserves rail icon sizing")
		for page_name in ["dashboard", "nodes", "subscription", "routing", "terminal", "codex", "antigravity", "settings"]:
			shell.show_page(page_name)
			await process_frame
			var minimum: Vector2 = shell.pages[page_name].get_combined_minimum_size()
			assert(minimum.x <= shell.page_host.size.x + 1 and minimum.y <= shell.page_host.size.y + 1, "Theme switching cannot clip page %s" % page_name)
		var appearance_style: StyleBox = settings._settings_grid.get_child(0).get_theme_stylebox("panel")
		assert(appearance_style is StyleBoxFlat and appearance_style.bg_color == scene.ui.surface_color)
		var nav: Button = shell.nav_buttons.settings
		assert(nav.get_theme_stylebox("normal") is StyleBoxFlat and nav.get_theme_stylebox("normal").bg_color == scene.ui.color("nav_active"))
	scene._quit_application()
	print("PASS: live light/dark theme switching, readable headings, controls and all eight page layouts")
	quit(0)
