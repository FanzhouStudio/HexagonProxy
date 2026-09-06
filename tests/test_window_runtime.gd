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
		_fail("图形窗口测试运行在 headless 模式", 2)
		return
	if root.mode not in [Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN] or not root.borderless:
		_fail("主窗口没有进入无边框全屏模式", 3)
		return

	var f11 := InputEventKey.new()
	f11.keycode = KEY_F11
	f11.pressed = true
	scene.window_mode_controller._unhandled_key_input(f11)
	await process_frame
	if root.mode not in [Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN]:
		_fail("F11 仍然改变了全屏状态", 4)
		return
	scene.app_shell.window_action_requested.emit("minimize")
	await process_frame
	await create_timer(0.08).timeout
	if root.mode != Window.MODE_MINIMIZED:
		_fail("右上角最小化没有进入最小化状态", 5)
		return
	scene.window_mode_controller.set_fullscreen(true)
	await process_frame

	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	scene.window_mode_controller._unhandled_key_input(escape)
	await process_frame
	if not is_instance_valid(scene.resident.close_prompt):
		_fail("ESC 没有打开退出确认", 6)
		return
	scene.window_mode_controller._unhandled_key_input(escape)
	await process_frame
	if is_instance_valid(scene.resident.close_prompt):
		_fail("第二次 ESC 没有关闭退出确认", 7)
		return

	scene.app_shell.show_page("nodes")
	var names: Array = []
	for index in 60:
		names.append("刷新节点-%02d" % index)
	var payload := {"proxies": {"六角选择": {"type": "Selector", "now": names[0], "all": names}}}
	scene.nodes_panel.handle_api_result("proxies", true, payload)
	var deadline := Time.get_ticks_msec() + 3000
	while scene.nodes_panel.node_grid.get_child_count() < names.size() and Time.get_ticks_msec() < deadline:
		await process_frame
	for frame in 30:
		scene.nodes_panel.handle_api_result("proxies", true, payload)
		scene.nodes_panel.handle_api_result("delay:%s" % names[frame % names.size()], true, {"delay": 80 + frame})
		await process_frame
		if frame % 3 == 0 and _viewport_is_black(root):
			_fail("节点周期刷新期间出现整帧黑屏", 8)
			return

	print("PASS: 默认无边框全屏 · F11 禁用 · 顶栏最小化 · ESC 退出确认 · 刷新无黑帧")
	scene.queue_free()
	await process_frame
	quit(0)

func _viewport_is_black(viewport: Viewport) -> bool:
	var image := viewport.get_texture().get_image()
	if image == null or image.get_width() <= 0 or image.get_height() <= 0:
		return true
	var width := image.get_width()
	var height := image.get_height()
	var points := [
		Vector2i(int(width * 0.08), int(height * 0.12)),
		Vector2i(int(width * 0.35), int(height * 0.16)),
		Vector2i(int(width * 0.50), int(height * 0.45))
	]
	var brightest := 0.0
	for point in points:
		var color := image.get_pixel(point.x, point.y)
		brightest = maxf(brightest, maxf(color.r, maxf(color.g, color.b)))
	return brightest < 0.08

func _fail(message: String, code: int) -> void:
	printerr("FAIL: %s" % message)
	quit(code)
