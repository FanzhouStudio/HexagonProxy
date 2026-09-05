class_name ProxyProcess
extends Node

## Mihomo 进程管理
## 只负责启动、停止、检测进程

signal process_started(pid: int)
signal process_stopped
signal process_crashed

var pid := -1

func launch(executable_path: String, arguments: PackedStringArray = PackedStringArray()) -> bool:
	if pid > 0 and OS.is_process_running(pid):
		return true

	pid = OS.create_process(executable_path, arguments, false)
	if pid > 0:
		process_started.emit(pid)
		return true

	return false

func stop() -> void:
	if pid <= 0:
		return
	OS.kill(pid)
	pid = -1
	process_stopped.emit()

func is_running() -> bool:
	return pid > 0 and OS.is_process_running(pid)

func _process(_delta: float) -> void:
	if pid > 0 and not OS.is_process_running(pid):
		pid = -1
		process_crashed.emit()
