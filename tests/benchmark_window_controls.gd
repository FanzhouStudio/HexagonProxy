extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene: Control = load("res://main.tscn").instantiate()
	root.add_child(scene)
	await create_timer(1.5).timeout
	var samples: Dictionary = {}
	var start := Time.get_ticks_usec()
	scene.window_mode_controller.minimize_window()
	await process_frame
	await process_frame
	samples.minimize_until_two_frames_ms = (Time.get_ticks_usec() - start) / 1000.0
	scene.window_mode_controller.apply_saved_window_mode()
	await create_timer(0.2).timeout
	start = Time.get_ticks_usec()
	scene.app_shell.window_action_requested.emit("exit")
	samples.exit_prompt_handler_ms = (Time.get_ticks_usec() - start) / 1000.0
	scene.resident._dismiss_close_prompt()
	start = Time.get_ticks_usec()
	scene.resident.close_main_window()
	samples.close_to_tray_handler_ms = (Time.get_ticks_usec() - start) / 1000.0
	await create_timer(2.0).timeout
	start = Time.get_ticks_usec()
	scene.resident.show_main_window()
	samples.restore_handler_ms = (Time.get_ticks_usec() - start) / 1000.0
	await create_timer(1.0).timeout
	print(JSON.stringify(samples))
	scene._quit_application()
	quit(0)
