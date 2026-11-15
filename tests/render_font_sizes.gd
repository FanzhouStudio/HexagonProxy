extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene: Control = load("res://main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	root.size = Vector2i(1600, 900)
	root.content_scale_size = Vector2i(1920, 1080)
	await create_timer(1.4).timeout
	scene.settings_panel.ui_theme_requested.emit("blue_healing")
	for percent in [100, 150, 200]:
		scene.ui_theme_service.set_font_size_percent(percent)
		await process_frame
		for page in ["settings", "dashboard", "antigravity", "terminal"]:
			scene.app_shell.show_page(page)
			await process_frame
			await RenderingServer.frame_post_draw
			print("FONT %d PAGE %s minimum=%s host=%s" % [percent, page, scene.app_shell.pages[page].get_combined_minimum_size(), scene.app_shell.page_host.size])
			root.get_texture().get_image().save_png("res://build/font-%d-%s.png" % [percent, page])
	scene.ui_theme_service.set_font_size_percent(150)
	scene.settings_panel.ui_theme_requested.emit("midnight")
	for page in ["settings", "dashboard"]:
		scene.app_shell.show_page(page)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/font-150-dark-%s.png" % page)
	scene._quit_application()
	quit(0)
