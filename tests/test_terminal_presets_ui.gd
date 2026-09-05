extends SceneTree

var captured_create: Array = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene: Control = load("res://main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var panel = scene.terminal_panel
	panel.set_presets([{
		"id": "preset-1",
		"name": "查看端口",
		"shell": "cmd",
		"command": "netstat -ano"
	}])
	await process_frame
	if panel.preset_box.get_child_count() != 1:
		_fail("常用命令快捷栏没有生成按钮", 2)
		return
	var item = panel.preset_box.get_child(0)
	var fill_button: Button = item.get_child(0)
	fill_button.pressed.emit()
	if panel.shell_selector.selected != 1 or panel.command_input.text != "netstat -ano":
		_fail("点击常用命令没有把 Shell 和真实命令填入输入栏", 3)
		return

	panel.preset_create_requested.connect(func(name: String, shell_name: String, command: String) -> void:
		captured_create.append({"name": name, "shell": shell_name, "command": command})
	)
	panel.command_input.text = "Get-Date"
	panel.shell_selector.select(0)
	panel.open_create_preset()
	if panel.preset_command_edit.text != "Get-Date" or panel.preset_shell_selector.selected != 0:
		_fail("添加常用命令没有预填当前输入内容", 4)
		return
	panel.preset_name_edit.text = "查看时间"
	panel._submit_preset_dialog()
	if captured_create.size() != 1:
		_fail("添加常用命令没有发出保存意图", 5)
		return
	var created: Dictionary = captured_create[0]
	if str(created.get("name", "")) != "查看时间" or str(created.get("shell", "")) != "powershell" or str(created.get("command", "")) != "Get-Date":
		_fail("常用命令保存意图内容不正确", 6)
		return

	scene.queue_free()
	await process_frame
	print("PASS: 常用命令快捷填入、Shell 同步与新增预填")
	quit(0)

func _fail(message: String, code: int) -> void:
	printerr("FAIL: %s" % message)
	quit(code)
