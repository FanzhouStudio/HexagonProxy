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
	scene.app_shell.show_page("antigravity")
	var models: Array = []
	for index in 18:
		models.append({"name": ["Gemini · High", "Claude Sonnet · Medium", "GPT-OSS · Medium"][index % 3], "remaining": [100, 75, 20, 0][index % 4], "reset": "2026-11-16T08:00:00Z"})
	var snapshot := {"ok": true, "models": models, "checked_at": "2026-11-16T01:00:00Z"}
	var panel = scene.app_shell.antigravity_proxy_panel
	for theme in ["midnight", "blue_healing"]:
		scene.settings_panel.ui_theme_requested.emit(theme)
		panel.render({"current_port": 7890, "default_account": "preview", "selected_account": "preview", "accounts": [{"id": "default", "name": "原有账号"}, {"id": "preview", "name": "工作账号", "email": "work@example.invalid", "logged_in": true}], "quota_snapshots": {"preview": snapshot}})
		panel.set_busy(false)
		await process_frame
		await process_frame
		panel.reveal_quota()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/quota-%s.png" % theme)
	scene._quit_application()
	quit(0)
