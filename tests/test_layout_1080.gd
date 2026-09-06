extends SceneTree

const WindowModeControllerScript = preload("res://scripts/app/window_mode_controller.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var viewport_width := int(ProjectSettings.get_setting("display/window/size/viewport_width"))
	var viewport_height := int(ProjectSettings.get_setting("display/window/size/viewport_height"))
	var window_width := int(ProjectSettings.get_setting("display/window/size/window_width_override"))
	var window_height := int(ProjectSettings.get_setting("display/window/size/window_height_override"))
	var min_width := int(ProjectSettings.get_setting("display/window/size/min_width"))
	var min_height := int(ProjectSettings.get_setting("display/window/size/min_height"))
	var borderless := bool(ProjectSettings.get_setting("display/window/size/borderless", false))
	var stretch_mode := str(ProjectSettings.get_setting("display/window/stretch/mode", ""))
	var stretch_aspect := str(ProjectSettings.get_setting("display/window/stretch/aspect", ""))
	var window_controller = WindowModeControllerScript.new()
	if viewport_width != 1920 or viewport_height != 1080:
		_fail("项目设计基准不是 1920x1080", 2)
		return
	if viewport_width * 9 != viewport_height * 16 or window_width * 9 != window_height * 16 or min_width * 9 != min_height * 16:
		_fail("窗口基准/窗口化恢复尺寸/最小窗口没有统一为 16:9", 3)
		return
	if not borderless or stretch_mode != "canvas_items" or stretch_aspect != "expand" or not window_controller.startup_fullscreen_enabled():
		window_controller.free()
		_fail("默认窗口不是无边框全屏自适应模式", 6)
		return
	window_controller.free()

	var scene: Control = load("res://main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	await create_timer(0.1).timeout
	var shell = scene.app_shell
	var page_host: Control = shell.page_host
	var shell_rect: Rect2 = scene.get_global_rect()
	for action_id in ["minimize", "close", "exit"]:
		var button: Button = shell.window_action_buttons.get(action_id)
		if not is_instance_valid(button) or not shell_rect.encloses(button.get_global_rect()):
			_fail("右上角窗口按钮 %s 超出 1920x1080 可视区域" % action_id, 7)
			return
	for page_name in ["dashboard", "nodes", "subscription", "routing", "terminal", "codex", "settings"]:
		shell.show_page(page_name)
		await process_frame
		var page: Control = shell.pages[page_name]
		var minimum := page.get_combined_minimum_size()
		if minimum.x > page_host.size.x + 1.0 or minimum.y > page_host.size.y + 1.0:
			_fail("页面 %s 最小尺寸 %s 超出可用区域 %s" % [page_name, minimum, page_host.size], 4)
			return

	shell.show_page("settings")
	await process_frame
	var release_buttons: Array[Node] = shell.pages["settings"].find_children("*", "Button", true, false)
	var release_count := 0
	for node in release_buttons:
		var button := node as Button
		if button != null and button.text == "释放占用":
			release_count += 1
			if not page_host.get_global_rect().encloses(button.get_global_rect()):
				_fail("端口释放按钮超出设置页可视区域", 8)
				return
	if release_count != 2:
		_fail("设置页没有同时提供混合端口与控制端口释放入口", 9)
		return

	shell.show_page("terminal")
	await process_frame
	var host_bottom: float = page_host.get_global_rect().end.y
	var input_bottom: float = scene.terminal_panel.command_input.get_global_rect().end.y
	var run_bottom: float = scene.terminal_panel.run_button.get_global_rect().end.y
	if input_bottom > host_bottom + 1.0 or run_bottom > host_bottom + 1.0:
		_fail("终端输入区域仍被页面底部裁剪", 5)
		return

	scene._quit_application()
	print("PASS: 1920x1080 基准、16:9 窗口与页面无裁剪")
	quit(0)

func _fail(message: String, code: int) -> void:
	printerr("FAIL: %s" % message)
	quit(code)
