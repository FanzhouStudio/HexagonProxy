extends SceneTree

const ProxyConfigScript = preload("res://scripts/modules/proxy/proxy_config.gd")
const PortConflictServiceScript = preload("res://scripts/modules/system/port_conflict_service.gd")

var _listener_pid := -1

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	if OS.get_name() != "Windows":
		print("PASS: 非 Windows 跳过端口进程释放实测")
		quit(0)
		return
	var config = ProxyConfigScript.new()
	config.ensure_directories()
	var port: int = int(config.random_available_port())
	if port < 0:
		_fail("无法取得测试端口", 2)
		return
	_listener_pid = _start_listener(port)
	if _listener_pid <= 0:
		_fail("无法启动端口占用测试进程", 3)
		return
	await create_timer(0.8).timeout
	var service = PortConflictServiceScript.new()
	root.add_child(service)
	service.bind_config(config)
	service.initialize()
	var info: Dictionary = service.inspect_port(port)
	if not bool(info.get("ok", false)) or not bool(info.get("occupied", false)):
		_fail("没有识别测试端口占用：%s" % info.get("message", ""), 4)
		return
	var processes: Array = info.get("processes", [])
	if processes.is_empty():
		_fail("端口占用结果缺少进程信息", 5)
		return
	var pids := PackedInt32Array()
	var found_listener := false
	for process in processes:
		if process is Dictionary:
			var pid := int(process.get("pid", -1))
			if pid > 0:
				pids.append(pid)
			if pid == _listener_pid:
				found_listener = true
	if not found_listener:
		_fail("识别到的 PID 与测试监听进程不一致", 6)
		return
	var released: Dictionary = service.release_port(port, pids)
	if not bool(released.get("ok", false)) or not bool(released.get("released", false)):
		_fail("端口释放失败：%s" % released.get("message", ""), 7)
		return
	await create_timer(0.25).timeout
	if OS.is_process_running(_listener_pid):
		_fail("占用进程仍在运行", 8)
		return
	_listener_pid = -1
	if not config.is_port_available(port):
		_fail("进程结束后端口仍不可用", 9)
		return
	if not service.is_protected_process("svchost", 12345):
		_fail("系统关键进程没有被保护", 10)
		return
	if not service.is_protected_process("anything", OS.get_process_id()):
		_fail("HexagonProxy 当前进程没有被保护", 11)
		return
	service.queue_free()
	print("PASS: 端口占用诊断、PID 确认、安全保护与进程释放")
	quit(0)

func _start_listener(port: int) -> int:
	var script := "$l=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,%d);$l.Start();while($true){Start-Sleep 1}" % port
	var encoded := Marshalls.raw_to_base64(script.to_utf16_buffer())
	return OS.create_process("powershell.exe", PackedStringArray([
		"-NoLogo", "-NoProfile", "-NonInteractive", "-EncodedCommand", encoded
	]), false)

func _fail(message: String, code: int) -> void:
	if _listener_pid > 0 and OS.is_process_running(_listener_pid):
		OS.kill(_listener_pid)
	_listener_pid = -1
	printerr("FAIL: %s" % message)
	quit(code)
