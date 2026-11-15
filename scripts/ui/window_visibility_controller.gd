class_name WindowVisibilityController
extends RefCounted

## 主窗口显示/隐藏控制器
## 负责跨平台窗口状态与 Windows 原生隐藏助手

var host: Control
var proxy_config
var hidden := false
var _worker: Thread
var _bridge_pid := -1
var _command_path := ""
var _command_sequence := 0

func setup(owner: Control, config) -> void:
	host = owner
	proxy_config = config
	if OS.get_name() == "Windows" and DisplayServer.get_name() != "headless":
		_start_bridge()

func is_hidden() -> bool:
	return hidden

func hide_main() -> bool:
	if hidden:
		return true
	if not _set_visible(false):
		return false
	hidden = true
	OS.low_processor_usage_mode = true
	return true

func show_main() -> bool:
	OS.low_processor_usage_mode = false
	if not _set_visible(true):
		return false
	hidden = false
	if DisplayServer.get_name() != "headless" and OS.get_name() != "Windows":
		host.get_window().grab_focus()
	return true

func _set_visible(visible: bool) -> bool:
	if DisplayServer.get_name() == "headless":
		return true
	if OS.get_name() != "Windows":
		host.get_window().mode = Window.MODE_WINDOWED if visible else Window.MODE_MINIMIZED
		return true
	if _worker and not _worker.is_alive():
		_bridge_pid = int(_worker.wait_to_finish())
		_worker = null
		if _bridge_pid <= 0:
			return false
	if _command_path.is_empty():
		return false
	if _bridge_pid > 0 and not OS.is_process_running(_bridge_pid):
		_start_bridge()
	var file := FileAccess.open(_command_path + ".tmp", FileAccess.WRITE)
	if file == null:
		return false
	_command_sequence += 1
	file.store_string("%d|%s" % [_command_sequence, "show" if visible else "hide"])
	file.close()
	return DirAccess.rename_absolute(_command_path + ".tmp", _command_path) == OK

func _start_bridge() -> void:
	DirAccess.make_dir_recursive_absolute(proxy_config.runtime_dir())
	_install_helper()
	if not FileAccess.file_exists(_helper_path()):
		return
	_command_path = proxy_config.runtime_dir().path_join("window-%d.command" % OS.get_process_id())
	DirAccess.remove_absolute(_command_path)
	var args := PackedStringArray(["-NoLogo", "-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden", "-ExecutionPolicy", "Bypass", "-File", _helper_path(), "-Action", "watch", "-ProcessId", str(OS.get_process_id()), "-WindowTitle", "HexagonProxy", "-CommandPath", _command_path])
	_worker = Thread.new()
	if _worker.start(func() -> int: return OS.create_process("powershell.exe", args, false)) != OK:
		_worker = null
		_command_path = ""

func shutdown() -> void:
	if _worker and _worker.is_started():
		_bridge_pid = int(_worker.wait_to_finish())
	_worker = null
	if _bridge_pid > 0:
		OS.kill(_bridge_pid)
		_bridge_pid = -1
	if not _command_path.is_empty():
		DirAccess.remove_absolute(_command_path)

func _helper_path() -> String:
	return proxy_config.runtime_dir().path_join("windows_window_helper.ps1")

func _install_helper() -> void:
	var source := FileAccess.open("res://scripts/windows_window_helper.ps1", FileAccess.READ)
	if source == null:
		return
	var target := FileAccess.open(_helper_path(), FileAccess.WRITE)
	if target != null:
		target.store_buffer(source.get_buffer(source.get_length()))
		target.close()
	source.close()
