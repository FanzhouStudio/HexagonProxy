class_name ProxyCleanup
extends Node

## Mihomo 启动前旧进程清理

var cleanup_pid := -1
var _started_msec := 0

func begin(core_path: String, helper_path: String) -> bool:
	stop()
	if OS.get_name() != "Windows":
		return true
	if not FileAccess.file_exists(helper_path):
		return false
	cleanup_pid = OS.create_process("powershell.exe", PackedStringArray([
		"-NoLogo",
		"-NoProfile",
		"-NonInteractive",
		"-ExecutionPolicy",
		"Bypass",
		"-File",
		helper_path,
		core_path
	]), false)
	_started_msec = Time.get_ticks_msec()
	if cleanup_pid <= 0:
		cleanup_pid = -1
		return false
	return true

func wait_for_completion(timeout_msec := 10000) -> bool:
	if OS.get_name() != "Windows":
		return true
	if cleanup_pid <= 0:
		return false
	while OS.is_process_running(cleanup_pid):
		if Time.get_ticks_msec() - _started_msec > timeout_msec:
			OS.kill(cleanup_pid)
			cleanup_pid = -1
			return false
		await get_tree().create_timer(0.1).timeout
	var exit_code := OS.get_process_exit_code(cleanup_pid)
	cleanup_pid = -1
	return exit_code == 0

func is_running() -> bool:
	return cleanup_pid > 0 and OS.is_process_running(cleanup_pid)

func stop() -> void:
	if cleanup_pid > 0 and OS.is_process_running(cleanup_pid):
		OS.kill(cleanup_pid)
	cleanup_pid = -1
