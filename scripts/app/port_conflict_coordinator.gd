class_name PortConflictCoordinator
extends Node

## 端口冲突协调器
## 负责设置页意图、占用诊断、确认与释放结果路由。

var port_conflict_service
var settings_panel
var mihomo_control
var _active := false
var _port_task_busy := false
var _port_thread: Thread


func setup(service, settings, control) -> void:
	port_conflict_service = service
	settings_panel = settings
	mihomo_control = control
	settings_panel.port_release_requested.connect(_on_port_release_requested)
	settings_panel.port_release_confirmed.connect(_on_port_release_confirmed)

func start() -> void:
	_active = true

func shutdown() -> void:
	_active = false
	if _port_thread and _port_thread.is_alive():
		_port_thread.wait_to_finish()
	_port_thread = null

func _on_port_release_requested(_kind: String, port: int) -> void:
	if not _active:
		return
	if _ports_locked():
		settings_panel.show_port_message("请先断开代理，再释放端口占用。", false)
		return
	if _port_task_busy:
		settings_panel.show_port_message("端口检测正在进行，请稍候。", false)
		return
	_port_task_busy = true
	settings_panel.show_port_message("正在检测端口 %d…" % port, true)
	_check_port_async(port)

func _check_port_async(port: int) -> void:
	_port_thread = Thread.new()
	_port_thread.start(func():
		var result: Dictionary = port_conflict_service.inspect_port(port)
		call_deferred("_finish_port_check", result, port)
	)

func _finish_port_check(result: Dictionary, port: int) -> void:
	_port_task_busy = false
	if not _active:
		return
	if not bool(result.get("ok", false)):
		settings_panel.show_port_message(str(result.get("message", "端口检测失败。")), false)
		return
	if not bool(result.get("occupied", false)):
		settings_panel.show_port_message("端口 %d 当前可用，无需释放。" % port, true)
		return
	var processes: Array = result.get("processes", [])
	if processes.is_empty():
		settings_panel.show_port_message("端口 %d 已占用，但无法识别占用进程。" % port, false)
		return
	for process in processes:
		if process is Dictionary and bool(process.get("protected", false)):
			settings_panel.show_port_message(
				"端口 %d 被受保护进程 %s (PID %d) 占用，已拒绝自动结束。" % [
					port, str(process.get("name", "Unknown")), int(process.get("pid", -1))
				], false)
			return
	settings_panel.show_port_release_confirmation(port, processes)

func _on_port_release_confirmed(port: int, pids: PackedInt32Array) -> void:
	if not _active:
		return
	if _ports_locked():
		settings_panel.show_port_message("代理状态已变化，请先断开代理再操作。", false)
		return
	if _port_task_busy:
		settings_panel.show_port_message("端口操作正在进行，请稍候。", false)
		return
	_port_task_busy = true
	settings_panel.show_port_message("正在释放端口 %d…" % port, true)
	_release_port_async(port, pids)

func _release_port_async(port: int, pids: PackedInt32Array) -> void:
	_port_thread = Thread.new()
	_port_thread.start(func():
		var result: Dictionary = port_conflict_service.release_port(port, pids)
		call_deferred("_finish_port_release", result)
	)

func _finish_port_release(result: Dictionary) -> void:
	_port_task_busy = false
	if not _active:
		return
	settings_panel.show_port_message(
		str(result.get("message", "端口释放失败。")),
		bool(result.get("ok", false)) and bool(result.get("released", false))
	)

func _ports_locked() -> bool:
	return bool(mihomo_control.online) or bool(mihomo_control.starting) or int(mihomo_control.core_pid) > 0
