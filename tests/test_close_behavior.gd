extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var main: Control = load("res://main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var resident = main.resident
	resident.request_close()
	await process_frame
	if not is_instance_valid(resident.close_prompt) or resident.close_prompt.name != "ClosePrompt":
		_fail("点击 X 没有显示关闭选择框", 2)
		return
	resident.request_close()
	await process_frame
	var prompt_count := 0
	for child in main.get_children():
		if child.name == "ClosePrompt":
			prompt_count += 1
	if prompt_count != 1:
		_fail("重复关闭请求创建了多个选择框", 3)
		return
	resident._dismiss_close_prompt()
	await process_frame
	if is_instance_valid(resident.close_prompt):
		_fail("取消后关闭选择框仍然存在", 4)
		return
	resident._show_close_prompt()
	await process_frame
	resident._hide_main_to_tray()
	await process_frame
	if not resident.window_visibility.is_hidden():
		_fail("最小化到托盘状态没有生效", 5)
		return
	resident.show_main_window()
	await process_frame
	if resident.window_visibility.is_hidden():
		_fail("从托盘恢复主窗口状态失败", 6)
		return
	main._quit_application()
	print("PASS: ResidentController 关闭选择、托盘隐藏与窗口恢复")
	quit(0)

func _fail(message: String, code: int) -> void:
	printerr("FAIL: %s" % message)
	quit(code)
