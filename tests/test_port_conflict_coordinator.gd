extends SceneTree

const CoordinatorScript = preload("res://scripts/app/port_conflict_coordinator.gd")

class FakeService:
	var inspect_calls: Array[int] = []
	var release_calls: Array = []
	var next_inspect: Dictionary = {"ok": true, "occupied": false, "message": "free"}
	func inspect_port(port: int) -> Dictionary:
		inspect_calls.append(port)
		return next_inspect.duplicate(true)
	func release_port(port: int, pids: PackedInt32Array) -> Dictionary:
		release_calls.append({"port": port, "pids": pids})
		return {"ok": true, "released": true, "message": "released"}

class FakeSettings:
	signal port_release_requested(kind: String, port: int)
	signal port_release_confirmed(port: int, pids: PackedInt32Array)
	var messages: Array[String] = []
	var confirmations: Array = []
	func show_port_message(message: String, _success: bool) -> void:
		messages.append(message)
	func show_port_release_confirmation(port: int, processes: Array) -> void:
		confirmations.append({"port": port, "processes": processes.duplicate(true)})

class FakeMihomo:
	var online := false
	var starting := false
	var core_pid := -1

func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	var service = FakeService.new()
	var settings = FakeSettings.new()
	var mihomo = FakeMihomo.new()
	var coordinator = CoordinatorScript.new()
	root.add_child(coordinator)
	coordinator.setup(service, settings, mihomo)
	coordinator.start()

	settings.port_release_requested.emit("mixed", 23001)
	if service.inspect_calls != [23001] or settings.messages.is_empty():
		_fail("空闲端口检测没有返回提示", 2)
		return

	service.next_inspect = {
		"ok": true,
		"occupied": true,
		"processes": [{"pid": 3210, "name": "demo", "protected": false}],
		"message": "occupied"
	}
	settings.port_release_requested.emit("controller", 23002)
	if settings.confirmations.size() != 1 or int(settings.confirmations[0].port) != 23002:
		_fail("占用端口没有进入用户确认流程", 3)
		return
	settings.port_release_confirmed.emit(23002, PackedInt32Array([3210]))
	if service.release_calls.size() != 1 or int(service.release_calls[0].port) != 23002:
		_fail("确认后没有调用端口释放服务", 4)
		return
	service.next_inspect = {
		"ok": true,
		"occupied": true,
		"processes": [{"pid": 4, "name": "System", "protected": true}],
		"message": "occupied"
	}
	settings.port_release_requested.emit("mixed", 23003)
	if settings.confirmations.size() != 1 or not settings.messages.back().contains("受保护"):
		_fail("受保护进程没有被协调器拦截", 5)
		return

	mihomo.online = true
	var inspect_before: int = service.inspect_calls.size()
	settings.port_release_requested.emit("mixed", 23004)
	if service.inspect_calls.size() != inspect_before or not settings.messages.back().contains("先断开"):
		_fail("代理运行中仍执行端口释放检测", 6)
		return
	mihomo.online = false

	coordinator.shutdown()
	inspect_before = service.inspect_calls.size()
	var release_before: int = service.release_calls.size()
	settings.port_release_requested.emit("mixed", 23005)
	settings.port_release_confirmed.emit(23002, PackedInt32Array([3210]))
	if service.inspect_calls.size() != inspect_before or service.release_calls.size() != release_before:
		_fail("Coordinator shutdown 后仍响应端口释放事件", 7)
		return
	print("PASS: PortConflictCoordinator 检测、确认、保护与关闭状态路由")
	quit(0)

func _fail(message: String, code: int) -> void:
	printerr("FAIL: %s" % message)
	quit(code)
