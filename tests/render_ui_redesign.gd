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
	scene.app_shell.show_page("antigravity")
	scene.antigravity_proxy_coordinator.shutdown()
	scene.app_shell.antigravity_proxy_panel.render({"exe_path": "C:/Program Files/Antigravity/Antigravity.exe", "installed": true, "intact": true, "current_port": 7890, "selected_account": "preview", "accounts": [{"id": "default", "name": "默认账号 · 个人"}, {"id": "preview", "name": "工作账号", "email": "work@example.com", "logged_in": true}]})
	scene.app_shell.antigravity_proxy_panel.set_busy(false)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/ui-antigravity.png")
	scene.app_shell.show_page("dashboard")
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/ui-dashboard.png")
	for page in ["settings", "nodes", "codex", "subscription"]:
		scene.app_shell.show_page(page)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/ui-%s.png" % page)
	scene._quit_application()
	quit(0)
