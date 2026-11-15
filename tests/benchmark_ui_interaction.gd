extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene: Control = load("res://main.tscn").instantiate()
	root.add_child(scene)
	await create_timer(1.5).timeout
	root.size = Vector2i(1600, 900)
	root.content_scale_size = Vector2i(1920, 1080)
	scene.antigravity_proxy_coordinator.shutdown()
	scene.codex_profile_coordinator.shutdown()
	var panel = scene.app_shell.antigravity_proxy_panel
	var models: Array = []
	for index in 18:
		models.append({"name": "Gemini Model %d High" % index, "remaining": 75})
	var state := {"selected_account": "fixture", "default_account": "fixture", "accounts": [{"id": "default", "name": "原有账号"}, {"id": "fixture", "name": "工作账号", "logged_in": true}], "quota_snapshots": {"fixture": {"ok": true, "models": models}}}
	scene.app_shell.show_page("antigravity")
	panel.render(state)
	await process_frame
	var render_times: Array = []
	for index in 20:
		var start := Time.get_ticks_usec()
		panel.render(state)
		render_times.append((Time.get_ticks_usec() - start) / 1000.0)
		await process_frame
	var navigation: Array = []
	for index in 30:
		var start := Time.get_ticks_usec()
		scene.app_shell.show_page(["dashboard", "settings", "antigravity"][index % 3])
		navigation.append((Time.get_ticks_usec() - start) / 1000.0)
		await process_frame
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
	var fonts: Array = []
	for index in 8:
		var start := Time.get_ticks_usec()
		scene.ui_theme_service.set_font_size_percent(150 if index % 2 == 0 else 160)
		fonts.append((Time.get_ticks_usec() - start) / 1000.0)
		await process_frame
	var result := {"account_refresh_median_ms": _median(render_times), "navigation_median_ms": _median(navigation), "font_update_median_ms": _median(fonts), "labels_tracked": scene.ui._tracked_labels.size(), "draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)}
	print(JSON.stringify(result))
	var output := OS.get_environment("HEXAGON_BENCHMARK_OUTPUT")
	if not output.is_empty():
		var file := FileAccess.open(output, FileAccess.WRITE)
		file.store_string(JSON.stringify(result))
	scene._quit_application()
	quit(0)

func _median(values: Array) -> float:
	values.sort()
	return float(values[values.size() / 2])
