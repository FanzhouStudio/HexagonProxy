class_name ProxyProcess
extends Node

## Mihomo 进程管理
## 只负责启动、停止、检测进程

signal process_started(pid: int)
signal process_stopped
signal process_crashed

var pid := -1
var _pipes: Array[FileAccess] = []
var _log: FileAccess
var _log_dirty := false
var _last_flush := 0
var _log_elapsed := 0.0
var _status_elapsed := 0.0

func _drain_log() -> void:
	for pipe in _pipes:
		for _chunk in 4:
			var bytes := pipe.get_buffer(4096)
			if bytes.is_empty():
				break
			if _log and _log.get_position() < 2097152:
				_log.store_buffer(bytes)
				_log_dirty = true
	if _log and _log_dirty and Time.get_ticks_msec() - _last_flush >= 250:
		_log.flush()
		_last_flush = Time.get_ticks_msec()
		_log_dirty = false

func _close_log() -> void:
	_drain_log()
	for pipe in _pipes:
		pipe.close()
	_pipes.clear()
	if _log:
		_log.close()
		_log = null
	_log_dirty = false

func launch(executable_path: String, arguments: PackedStringArray = PackedStringArray()) -> bool:
	if pid > 0 and OS.is_process_running(pid):
		return true

	_close_log()
	var child := OS.execute_with_pipe(executable_path, arguments, false)
	pid = int(child.get("pid", -1))
	if pid > 0:
		_pipes.append(child.stdio)
		_pipes.append(child.stderr)
		var directory := ProjectSettings.globalize_path("user://diagnostics")
		DirAccess.make_dir_recursive_absolute(directory)
		var path := directory.path_join("mihomo-current.log")
		var previous := directory.path_join("mihomo-previous.log")
		if FileAccess.file_exists(previous):
			DirAccess.remove_absolute(previous)
		if FileAccess.file_exists(path):
			DirAccess.rename_absolute(path, previous)
		_log = FileAccess.open(path, FileAccess.WRITE)
		if _log:
			_log.store_line("Core started: " + Time.get_datetime_string_from_system())
		process_started.emit(pid)
		return true

	return false

func stop() -> void:
	if pid <= 0:
		return
	OS.kill(pid)
	_close_log()
	pid = -1
	process_stopped.emit()

func is_running() -> bool:
	return pid > 0 and OS.is_process_running(pid)

func _process(_delta: float) -> void:
	if pid <= 0:
		return
	_log_elapsed += _delta
	_status_elapsed += _delta
	if _log_elapsed >= 0.05:
		_log_elapsed = 0.0
		_drain_log()
	if _status_elapsed < 0.25:
		return
	_status_elapsed = 0.0
	if not OS.is_process_running(pid):
		_close_log()
		pid = -1
		process_crashed.emit()
