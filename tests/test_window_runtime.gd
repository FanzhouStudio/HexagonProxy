extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene: Control = load("res://main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	await create_timer(0.15).timeout
	if DisplayServer.get_name().to_lower() == "headless":
		printerr("FAIL: 图形窗口测试运行在 headless 模式")
		quit(2)
		return
	if root.mode not in [Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN]:
		printerr("FAIL: 主窗口没有进入全屏模式")
		quit(3)
		return
	if not root.borderless:
		printerr("FAIL: 全屏窗口仍有系统边框")
		quit(4)
		return
	scene.window_mode_controller.set_fullscreen(false)
	await process_frame
	await create_timer(0.1).timeout
	if root.mode != Window.MODE_WINDOWED or root.size != Vector2i(1920, 1080) or root.borderless:
		printerr("FAIL: F11 窗口模式不是 1920x1080 普通窗口：%s" % root.size)
		quit(5)
		return
	scene.window_mode_controller.set_fullscreen(true)
	await process_frame
	print("PASS: 默认无边框全屏 · F11 恢复 1920x1080 窗口")
	scene.queue_free()
	await process_frame
	quit(0)
