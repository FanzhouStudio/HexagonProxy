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
	scene.antigravity_proxy_coordinator.shutdown()
	var panel = scene.app_shell.antigravity_proxy_panel
	panel.render({"installed": false, "current_port": 7890, "selected_account": "preview", "accounts": [{"id": "default", "name": "默认账号"}, {"id": "preview", "name": "工作账号", "email": "work@example.com", "logged_in": true}]})
	panel.set_busy(false)
	for id in ["blue_healing", "midnight"]:
		scene.settings_panel.ui_theme_requested.emit(id)
		for page in ["settings", "dashboard", "antigravity", "codex", "terminal"]:
			scene.app_shell.show_page(page)
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://build/%s-%s.png" % [id, page])
		scene.app_shell.show_page("antigravity")
		panel._request_remove("preview", "工作账号")
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/%s-dialog.png" % id)
		panel._prompt_host.get_node("AntigravityDeletePrompt").queue_free()
		await process_frame
	scene._quit_application()
	quit(0)
