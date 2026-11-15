extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _native_visible() -> bool:
	var handle := DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE)
	var script := 'param([long]$Handle)\nAdd-Type -TypeDefinition \'using System; using System.Runtime.InteropServices; public static class VisibilityProbe { [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr handle); }\'\n[VisibilityProbe]::IsWindowVisible([IntPtr]$Handle)'
	var path := ProjectSettings.globalize_path("user://probe.ps1")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(script)
	file.close()
	# Do not block the window's message pump while asking Windows whether a
	# queued ShowWindowAsync has completed. A synchronous OS.execute here can
	# itself prevent the visibility transition this test is trying to observe.
	var worker := Thread.new()
	worker.start(func() -> Dictionary:
		var output: Array = []
		var code := OS.execute("powershell.exe", PackedStringArray(["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", path, str(handle)]), output, true)
		return {"code": code, "text": "".join(output)}
	)
	while worker.is_alive():
		await create_timer(0.02).timeout
	var result: Dictionary = worker.wait_to_finish()
	assert(result.code == 0, "Visibility probe failed: " + str(result.text))
	return "True" in str(result.text)

func _expect_visible(expected: bool, message: String) -> void:
	var deadline := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline:
		if await _native_visible() == expected:
			return
		await create_timer(0.1).timeout
	assert(false, message)

func _run() -> void:
	assert(DisplayServer.get_name() != "headless")
	var scene: Control = load("res://main.tscn").instantiate()
	root.add_child(scene)
	await create_timer(1.8).timeout
	var visibility = scene.resident.window_visibility
	assert(visibility.hide_main())
	await create_timer(0.5).timeout
	var bridge_pid: int = visibility._bridge_pid
	assert(bridge_pid > 0)
	await _expect_visible(false, "Prewarmed bridge must actually hide the main window")
	assert(visibility.show_main())
	await create_timer(0.3).timeout
	assert(visibility._bridge_pid == bridge_pid)
	await _expect_visible(true, "Restoring reuses the same helper process")
	for index in 5:
		visibility.hide_main()
		visibility.show_main()
	await create_timer(0.4).timeout
	await _expect_visible(true, "Rapid clicks resolve to the latest desired state")
	assert(visibility.hide_main())
	await create_timer(0.3).timeout
	await _expect_visible(false, "A subsequent hide must still work")
	assert(visibility.show_main())
	await create_timer(0.3).timeout
	visibility.shutdown()
	await process_frame
	assert(not OS.is_process_running(bridge_pid), "Closing the app stops its bridge")
	print("PASS: native hide/restore, helper reuse, rapid click ordering and shutdown")
	scene._quit_application()
	quit(0)
