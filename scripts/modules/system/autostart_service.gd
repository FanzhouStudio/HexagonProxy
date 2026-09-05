class_name AutostartService
extends Node

## Windows 开机启动服务
## 使用 Startup 目录中的 VBS 隐藏启动应用

signal status_changed(enabled: bool)
signal busy_changed(busy: bool)
signal event_logged(message: String)

var enabled := false
var busy := false

func initialize() -> void:
	refresh_state()

func refresh_state() -> void:
	enabled = OS.get_name() == "Windows" and FileAccess.file_exists(autostart_path())
	status_changed.emit(enabled)

func set_enabled(value: bool) -> void:
	if OS.get_name() != "Windows":
		event_logged.emit("开机自启当前仅支持 Windows。")
		return
	if busy:
		return
	busy = true
	busy_changed.emit(true)
	var code := _write_state(value)
	enabled = code == OK and value
	status_changed.emit(enabled)
	busy = false
	busy_changed.emit(false)
	if code == OK:
		event_logged.emit("开机自启已%s。" % ("开启" if value else "关闭"))
	else:
		event_logged.emit("开机自启设置失败（%s）。" % error_string(code))

func enable() -> void:
	set_enabled(true)

func disable() -> void:
	set_enabled(false)

func toggle() -> void:
	set_enabled(not enabled)

func is_enabled() -> bool:
	return enabled

func autostart_path() -> String:
	return OS.get_environment("APPDATA").path_join("Microsoft/Windows/Start Menu/Programs/Startup/HexagonProxy.vbs")

func autostart_command() -> String:
	var executable := OS.get_executable_path()
	if OS.has_feature("editor"):
		var project_dir := ProjectSettings.globalize_path("res://").trim_suffix("/").trim_suffix("\\")
		return "\"%s\" --path \"%s\" -- --tray-start" % [executable, project_dir]
	return "\"%s\" -- --tray-start" % executable
func migrate_legacy_registration() -> void:
	if OS.get_name() != "Windows":
		return
	for value_name in ["六角代理", "HexagonProxy"]:
		OS.create_process("reg.exe", PackedStringArray([
			"delete", "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run",
			"/v", value_name, "/f"
		]), false)

func _write_state(value: bool) -> int:
	if value:
		DirAccess.make_dir_recursive_absolute(autostart_path().get_base_dir())
		var file := FileAccess.open(autostart_path(), FileAccess.WRITE)
		if file == null:
			return FileAccess.get_open_error()
		var command := autostart_command().replace("\"", "\"\"")
		file.store_string("Set shell = CreateObject(\"WScript.Shell\")\r\nshell.Run \"%s\", 0, False\r\n" % command)
		file.close()
		return OK
	if FileAccess.file_exists(autostart_path()):
		return DirAccess.remove_absolute(autostart_path())
	return OK
