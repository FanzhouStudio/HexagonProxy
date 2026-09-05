class_name WindowVisibilityController
extends RefCounted

## 主窗口显示/隐藏控制器
## 负责跨平台窗口状态与 Windows 原生隐藏助手

var host: Control
var proxy_config
var hidden := false

func setup(owner: Control, config) -> void:
	host = owner
	proxy_config = config

func is_hidden() -> bool:
	return hidden

func hide_main() -> bool:
	if hidden:
		return true
	if not _set_visible(false):
		return false
	hidden = true
	return true

func show_main() -> bool:
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
	var helper_path := _helper_path()
	if not FileAccess.file_exists(helper_path):
		_install_helper()
	if not FileAccess.file_exists(helper_path):
		return false
	var process_id: int = OS.create_process("powershell.exe", PackedStringArray([
		"-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
		"-File", helper_path, "show" if visible else "hide", str(OS.get_process_id()), "HexagonProxy"
	]), false)
	return process_id > 0

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
