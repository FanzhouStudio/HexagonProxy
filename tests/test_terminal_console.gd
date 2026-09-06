extends SceneTree

const CommandConsoleServiceScript = preload("res://scripts/modules/system/command_console_service.gd")
const ProxyConfigScript = preload("res://scripts/modules/proxy/proxy_config.gd")

var service
var output := ""
var finish_events: Array = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	service = CommandConsoleServiceScript.new()
	root.add_child(service)
	service.bind_config(ProxyConfigScript.new())
	service.initialize()
	var work_dir := ProjectSettings.globalize_path("user://terminal-cwd-test")
	DirAccess.make_dir_recursive_absolute(work_dir)
	var cwd_result: Dictionary = service.set_working_directory(work_dir)
	if not bool(cwd_result.get("ok", false)) or service.working_directory() != work_dir.replace("\\", "/"):
		_fail("终端运行目录无法保存", 11)
		return
	var persisted_service = CommandConsoleServiceScript.new()
	root.add_child(persisted_service)
	persisted_service.bind_config(ProxyConfigScript.new())
	persisted_service.initialize()
	if persisted_service.working_directory() != work_dir.replace("\\", "/"):
		_fail("终端运行目录没有持久化", 12)
		return
	persisted_service.queue_free()
	service.output_appended.connect(func(text: String) -> void: output += text)
	service.finished.connect(func(exit_code: int, stopped: bool) -> void:
		finish_events.append({"exit_code": exit_code, "stopped": stopped})
	)

	if not service.run_command("powershell", "Write-Output (Get-Location).Path; Write-Output 'hexagon-ps-test 六角终端'"):
		_fail("PowerShell 命令无法启动", 2)
		return
	if not await _wait_for_finish(5.0):
		_fail("PowerShell 命令执行超时", 3)
		return
	if not output.contains("hexagon-ps-test") or not output.contains("六角终端") or not output.replace("\\", "/").contains(work_dir.replace("\\", "/")):
		_fail("PowerShell 工作目录或 UTF-8 输出不正确；实际输出=%s" % output.replace("\n", "\\n"), 4)
		return

	output = ""
	finish_events.clear()
	var native_utf8 := "& cmd.exe /D /S /C \"chcp 65001 >nul & echo native-utf8-终端-连接安全\""
	if not service.run_command("powershell", native_utf8):
		_fail("PowerShell 原生 UTF-8 子进程无法启动", 13)
		return
	if not await _wait_for_finish(5.0):
		_fail("PowerShell 原生 UTF-8 子进程执行超时", 14)
		return
	if not output.contains("native-utf8-终端-连接安全"):
		_fail("PowerShell 原生进程中文输出乱码；实际输出=%s" % output.replace("\n", "\\n"), 15)
		return

	var node_lookup: Array = []
	if OS.execute("where.exe", PackedStringArray(["node.exe"]), node_lookup, true, false) == 0:
		output = ""
		finish_events.clear()
		if not service.run_command("powershell", "node -e \"console.log('node-native-终端-连接安全')\""):
			_fail("Node UTF-8 子进程无法启动", 16)
			return
		if not await _wait_for_finish(5.0) or not output.contains("node-native-终端-连接安全"):
			_fail("Node 原生 UTF-8 输出乱码；实际输出=%s" % output.replace("\n", "\\n"), 17)
			return

	output = ""
	finish_events.clear()
	if not service.run_command("cmd", "cd & echo hexagon-cmd-test"):
		_fail("CMD 命令无法启动", 5)
		return
	if not await _wait_for_finish(5.0):
		_fail("CMD 命令执行超时", 6)
		return
	if not output.contains("hexagon-cmd-test") or not output.replace("\\", "/").contains(work_dir.replace("\\", "/")):
		_fail("CMD 工作目录或输出不正确", 7)
		return

	output = ""
	finish_events.clear()
	if not service.run_command("powershell", "Start-Sleep -Seconds 10; Write-Output 'should-not-complete'"):
		_fail("长 PowerShell 命令无法启动", 8)
		return
	await create_timer(0.35).timeout
	service.stop()
	if not await _wait_for_finish(5.0):
		_fail("停止命令后进程没有结束", 9)
		return
	if finish_events.is_empty() or not bool(finish_events.back().get("stopped", false)):
		_fail("停止命令没有标记为用户终止", 10)
		return

	service.dispose()
	service.queue_free()
	print("PASS: 内置终端 PowerShell/CMD 输出与停止进程树")
	quit(0)

func _wait_for_finish(timeout_seconds: float) -> bool:
	var started := Time.get_ticks_msec()
	while finish_events.is_empty():
		if Time.get_ticks_msec() - started > int(timeout_seconds * 1000.0):
			return false
		await process_frame
	return true

func _fail(message: String, code: int) -> void:
	printerr("FAIL: %s" % message)
	if service and service.is_running():
		service.stop()
	quit(code)
