extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var main: Control = load("res://main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.call("_on_main_window_close_requested")
	await process_frame
	var prompt: Variant = main.get("_close_prompt")
	if not is_instance_valid(prompt) or prompt.name != "ClosePrompt":
		printerr("FAIL: 点击 X 没有显示关闭选择框")
		quit(2)
		return
	main.call("_on_main_window_close_requested")
	await process_frame
	var prompt_count := 0
	for child in main.get_children():
		if child.name == "ClosePrompt":
			prompt_count += 1
	if prompt_count != 1:
		printerr("FAIL: 重复关闭请求创建了多个选择框")
		quit(3)
		return
	main.call("_dismiss_close_prompt")
	await process_frame
	if is_instance_valid(main.get("_close_prompt")):
		printerr("FAIL: 取消后关闭选择框仍然存在")
		quit(4)
		return
	main.call("_show_close_prompt")
	await process_frame
	main.call("_hide_main_to_tray")
	await process_frame
	if not bool(main.get("_main_hidden_to_tray")):
		printerr("FAIL: 最小化到托盘状态没有生效")
		quit(5)
		return
	main.call("_show_main_window")
	await process_frame
	if bool(main.get("_main_hidden_to_tray")):
		printerr("FAIL: 从托盘恢复主窗口状态失败")
		quit(6)
		return
	print("PASS: 关闭选择、托盘隐藏与窗口恢复")
	quit(0)
