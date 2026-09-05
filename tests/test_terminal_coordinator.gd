extends SceneTree

const TerminalCoordinatorScript = preload("res://scripts/app/terminal_coordinator.gd")

class FakeService:
	signal output_appended(text: String)
	signal state_changed(running: bool, message: String)
	signal finished(exit_code: int, stopped: bool)
	var running := false
	var runs: Array[String] = []
	var stops := 0
	var work_dir := "C:/Users/Test"
	var set_dirs: Array[String] = []
	func is_running() -> bool: return running
	func working_directory() -> String: return work_dir
	func set_working_directory(path: String) -> Dictionary:
		work_dir = path
		set_dirs.append(path)
		return {"ok": true, "message": "运行目录已更新。"}
	func reset_working_directory() -> Dictionary:
		work_dir = "C:/Users/Test"
		return {"ok": true, "message": "运行目录已更新。"}
	func run_command(shell_name: String, command: String) -> bool:
		runs.append(shell_name + ":" + command)
		return true
	func stop() -> void:
		stops += 1
		running = false

class FakePresetService:
	signal presets_changed
	var items: Array = []
	var calls: Array[String] = []
	func list_presets() -> Array: return items.duplicate(true)
	func add_preset(name: String, shell_name: String, command: String) -> Dictionary:
		calls.append("add:%s:%s:%s" % [name, shell_name, command])
		items.append({"id": "p1", "name": name, "shell": shell_name, "command": command})
		presets_changed.emit()
		return {"ok": true, "message": "常用命令已保存。"}
	func update_preset(id: String, name: String, shell_name: String, command: String) -> Dictionary:
		calls.append("update:%s:%s:%s:%s" % [id, name, shell_name, command])
		items = [{"id": id, "name": name, "shell": shell_name, "command": command}]
		presets_changed.emit()
		return {"ok": true, "message": "常用命令已更新。"}
	func delete_preset(id: String) -> Dictionary:
		calls.append("delete:%s" % id)
		items.clear()
		presets_changed.emit()
		return {"ok": true, "message": "常用命令已删除。"}

class FakePanel:
	signal run_requested(shell_name: String, command: String)
	signal stop_requested
	signal working_directory_selected(path: String)
	signal working_directory_reset_requested
	signal preset_create_requested(name: String, shell_name: String, command: String)
	signal preset_update_requested(id: String, name: String, shell_name: String, command: String)
	signal preset_delete_requested(id: String)
	var output := ""
	var running := false
	var status := ""
	var work_dir := ""
	var preset_snapshot: Array = []
	var finished_events: Array = []
	func append_output(text: String) -> void: output += text
	func set_working_directory(path: String) -> void: work_dir = path
	func set_presets(items: Array) -> void: preset_snapshot = items.duplicate(true)
	func set_running(value: bool, message: String) -> void:
		running = value
		status = message
	func show_finished(exit_code: int, stopped: bool) -> void:
		finished_events.append({"exit_code": exit_code, "stopped": stopped})

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var service = FakeService.new()
	var presets = FakePresetService.new()
	var panel = FakePanel.new()
	var coordinator = TerminalCoordinatorScript.new()
	root.add_child(coordinator)
	coordinator.setup(service, presets, panel)
	coordinator.start()
	if panel.work_dir != "C:/Users/Test":
		_fail("终端初始运行目录没有同步到面板", 5)
		return
	panel.working_directory_selected.emit("D:/Work")
	if service.set_dirs != ["D:/Work"] or panel.work_dir != "D:/Work":
		_fail("选择运行目录没有通过协调器保存并回写", 6)
		return
	panel.working_directory_reset_requested.emit()
	if panel.work_dir != "C:/Users/Test":
		_fail("重置运行目录没有回写默认路径", 7)
		return
	panel.preset_create_requested.emit("查看端口", "powershell", "Get-NetTCPConnection")
	if presets.calls != ["add:查看端口:powershell:Get-NetTCPConnection"] or panel.preset_snapshot.size() != 1:
		_fail("常用命令新增或快照刷新失败", 8)
		return
	panel.preset_update_requested.emit("p1", "查看监听", "cmd", "netstat -ano")
	if presets.calls.size() != 2 or str(panel.preset_snapshot[0].get("shell", "")) != "cmd":
		_fail("常用命令编辑没有路由或刷新", 9)
		return
	panel.preset_delete_requested.emit("p1")
	if presets.calls.size() != 3 or not panel.preset_snapshot.is_empty():
		_fail("常用命令删除没有路由或刷新", 10)
		return
	panel.run_requested.emit("powershell", "Get-Date")
	panel.stop_requested.emit()
	if service.runs != ["powershell:Get-Date"] or service.stops != 1:
		_fail("终端运行/停止意图没有路由到 Service", 2)
		return
	service.output_appended.emit("hello")
	service.state_changed.emit(true, "运行中")
	service.finished.emit(0, false)
	if not panel.output.contains("hello") or not panel.output.contains("运行目录已更新") or not panel.running or panel.status != "运行中" or panel.finished_events.size() != 1:
		_fail("终端 Service 状态/输出没有回写到 Panel", 3)
		return
	coordinator.shutdown()
	var run_count: int = service.runs.size()
	var preset_call_count: int = presets.calls.size()
	var output_before: String = panel.output
	panel.run_requested.emit("cmd", "echo no")
	panel.preset_create_requested.emit("忽略", "cmd", "echo ignored")
	service.output_appended.emit("ignored")
	if service.runs.size() != run_count or presets.calls.size() != preset_call_count or panel.output != output_before:
		_fail("TerminalCoordinator 关闭后仍响应事件", 4)
		return
	print("PASS: TerminalCoordinator 运行、停止、输出与关闭保护")
	quit(0)

func _fail(message: String, code: int) -> void:
	printerr("FAIL: %s" % message)
	quit(code)
