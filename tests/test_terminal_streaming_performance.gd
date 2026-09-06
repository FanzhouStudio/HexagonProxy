extends SceneTree

const CommandConsoleServiceScript = preload("res://scripts/modules/system/command_console_service.gd")
const TerminalCoordinatorScript = preload("res://scripts/app/terminal_coordinator.gd")
const ProxyConfigScript = preload("res://scripts/modules/proxy/proxy_config.gd")

var chunks := PackedStringArray()

class FakeCommandService:
	signal output_appended(text: String)
	signal state_changed(running: bool, message: String)
	signal finished(exit_code: int, stopped: bool)
	var running := false
	func is_running() -> bool: return running
	func working_directory() -> String: return "C:/Temp"
	func run_command(_shell: String, _command: String) -> bool: return true
	func stop() -> void: running = false
	func set_working_directory(path: String) -> Dictionary: return {"ok": true, "path": path, "message": "ok"}
	func reset_working_directory() -> Dictionary: return {"ok": true, "path": "C:/Temp", "message": "ok"}

class FakePresetService:
	signal presets_changed
	func list_presets() -> Array: return []
	func add_preset(_name: String, _shell: String, _command: String) -> Dictionary: return {"ok": true}
	func update_preset(_id: String, _name: String, _shell: String, _command: String) -> Dictionary: return {"ok": true}
	func delete_preset(_id: String) -> Dictionary: return {"ok": true}
class FakePanel:
	signal run_requested(shell_name: String, command: String)
	signal stop_requested
	signal working_directory_selected(path: String)
	signal working_directory_reset_requested
	signal preset_create_requested(name: String, shell_name: String, command: String)
	signal preset_update_requested(id: String, name: String, shell_name: String, command: String)
	signal preset_delete_requested(id: String)
	var append_calls := 0
	var output := ""
	func append_output(text: String) -> void:
		append_calls += 1
		output += text
	func set_working_directory(_path: String) -> void: pass
	func set_presets(_items: Array) -> void: pass
	func set_running(_running: bool, _message: String) -> void: pass
	func show_finished(_exit_code: int, _stopped: bool) -> void: pass

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var service = CommandConsoleServiceScript.new()
	root.add_child(service)
	service.bind_config(ProxyConfigScript.new())
	service.initialize()
	service.output_appended.connect(func(text: String) -> void: chunks.append(text))
	var stream_path := ProjectSettings.globalize_path("user://terminal-streaming-test.log")
	var expected := "a".repeat(131071) + "终端边界" + "z".repeat(200000)
	var file := FileAccess.open(stream_path, FileAccess.WRITE)
	if file == null:
		_fail("无法创建流式输出测试文件", 2)
		return
	file.store_buffer(expected.to_utf8_buffer())
	file.close()
	service._output_path = stream_path
	service._output_offset = 0
	var guard := 0
	while service._has_unread_output() and guard < 16:
		service._poll_output()
		guard += 1
	var actual := "".join(chunks)
	if actual != expected:
		_fail("增量读取在 UTF-8 边界损坏输出", 3)
		return
	if chunks.size() < 2 or chunks[0].length() != 131071:
		_fail("终端输出没有按读取上限分批", 4)
		return
	DirAccess.remove_absolute(stream_path)
	service.queue_free()
	await process_frame
	var fake_service = FakeCommandService.new()
	var fake_presets = FakePresetService.new()
	var fake_panel = FakePanel.new()
	var coordinator = TerminalCoordinatorScript.new()
	root.add_child(coordinator)
	coordinator.setup(fake_service, fake_presets, fake_panel)
	coordinator.start()
	for _index in 50:
		fake_service.output_appended.emit("x")
	await process_frame
	if fake_panel.append_calls != 0:
		_fail("高频输出在批量刷新间隔前就触发 UI 重排", 5)
		return
	await create_timer(0.12).timeout
	if fake_panel.append_calls != 1 or fake_panel.output.length() != 50:
		_fail("高频输出没有合并为单次 UI 刷新", 6)
		return
	coordinator.shutdown()
	coordinator.queue_free()
	await process_frame
	print("PASS: 终端增量读取、UTF-8 边界与批量 UI 刷新")
	quit(0)

func _fail(message: String, code: int) -> void:
	printerr("FAIL: %s" % message)
	quit(code)
