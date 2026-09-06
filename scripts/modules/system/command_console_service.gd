class_name CommandConsoleService
extends Node

## 内置命令行执行服务
## 在独立进程中运行 PowerShell/CMD，并通过临时日志增量回传 stdout/stderr。

signal output_appended(text: String)
signal state_changed(running: bool, message: String)
signal finished(exit_code: int, stopped: bool)

const ProxyConfigScript = preload("res://scripts/modules/proxy/proxy_config.gd")
const SETTINGS_PATH := "user://terminal_settings.cfg"

var proxy_config
var process_id := -1
var _working_directory := ""
var _output_path := ""
var _script_paths: Array[String] = []
var _output_offset := 0
var _poll_accumulator := 0.0
var _stopped_by_user := false
var _exit_detected_msec := 0

const OUTPUT_POLL_INTERVAL_SEC := 0.08
const MAX_READ_BYTES_PER_POLL := 131072

func bind_config(config) -> void:
	proxy_config = config

func _ensure_config() -> void:
	if proxy_config == null:
		proxy_config = ProxyConfigScript.new()
func initialize() -> void:
	_ensure_console_dir()
	_load_working_directory()

func working_directory() -> String:
	if _working_directory.is_empty():
		_working_directory = default_working_directory()
	return _working_directory

func default_working_directory() -> String:
	var candidate := OS.get_environment("USERPROFILE") if OS.get_name() == "Windows" else OS.get_environment("HOME")
	if not candidate.is_empty() and DirAccess.dir_exists_absolute(candidate):
		return candidate
	return ProjectSettings.globalize_path("user://")

func set_working_directory(path: String) -> Dictionary:
	if is_running():
		return {"ok": false, "message": "请先停止当前命令，再修改运行目录。"}
	var normalized := path.strip_edges().replace("\\", "/").trim_suffix("/")
	if normalized.is_empty() or not DirAccess.dir_exists_absolute(normalized):
		return {"ok": false, "message": "所选目录不存在或无法访问。"}
	_working_directory = normalized
	_save_working_directory()
	return {"ok": true, "message": "运行目录已更新。", "path": _working_directory}

func reset_working_directory() -> Dictionary:
	return set_working_directory(default_working_directory())

func is_running() -> bool:
	return process_id > 0 and OS.is_process_running(process_id)

func run_command(shell_name: String, command: String) -> bool:
	if is_running():
		output_appended.emit("\n[系统] 已有命令正在运行，请先停止。\n")
		return false
	var cleaned := command.strip_edges()
	if cleaned.is_empty():
		output_appended.emit("\n[系统] 请输入要运行的命令。\n")
		return false
	_ensure_console_dir()
	_cleanup_files()
	_output_offset = 0
	_poll_accumulator = 0.0
	_stopped_by_user = false
	_exit_detected_msec = 0
	var token := str(Time.get_ticks_usec())
	_output_path = console_dir().path_join("output_%s.log" % token)
	var launch: Dictionary = _prepare_launch(shell_name.to_lower(), cleaned, token, working_directory())
	if not bool(launch.get("ok", false)):
		output_appended.emit("\n[系统] %s\n" % str(launch.get("message", "无法创建命令。")))
		return false
	var executable := str(launch.get("executable", ""))
	var args: PackedStringArray = launch.get("args", PackedStringArray())
	process_id = OS.create_process(executable, args, false)
	if process_id <= 0:
		process_id = -1
		output_appended.emit("\n[系统] 无法启动 %s。\n" % shell_name)
		_cleanup_files()
		return false
	state_changed.emit(true, "%s · PID %d" % [_display_shell(shell_name), process_id])
	return true

func stop() -> void:
	if process_id <= 0:
		return
	_stopped_by_user = true
	if OS.get_name() == "Windows":
		var task_output: Array = []
		OS.execute("taskkill", PackedStringArray(["/PID", str(process_id), "/T", "/F"]), task_output, true, false)
	else:
		OS.kill(process_id)

func _process(delta: float) -> void:
	if process_id <= 0:
		return
	var running := OS.is_process_running(process_id)
	_poll_accumulator += delta
	if _poll_accumulator >= OUTPUT_POLL_INTERVAL_SEC:
		_poll_accumulator = 0.0
		_poll_output(not running)
	if running:
		_exit_detected_msec = 0
		return
	if _exit_detected_msec == 0:
		_exit_detected_msec = Time.get_ticks_msec()
		return
	if Time.get_ticks_msec() - _exit_detected_msec < 180:
		return
	if _has_unread_output():
		return
	_finish_process()
func _prepare_launch(shell_name: String, command: String, token: String, work_dir: String) -> Dictionary:
	if shell_name == "cmd":
		var body_path := console_dir().path_join("command_%s.cmd" % token)
		var wrapper_path := console_dir().path_join("wrapper_%s.cmd" % token)
		if not _write_text(body_path, "@echo off\r\n%s\r\n" % command):
			return {"ok": false, "message": "无法写入 CMD 临时脚本。"}
		var wrapper := "@echo off\r\nchcp 65001 >nul\r\ncd /d \"%~3\"\r\nif errorlevel 1 exit /b %errorlevel%\r\ncall \"%~1\" > \"%~2\" 2>&1\r\nexit /b %errorlevel%\r\n"
		if not _write_text(wrapper_path, wrapper):
			DirAccess.remove_absolute(body_path)
			return {"ok": false, "message": "无法写入 CMD 启动脚本。"}
		_script_paths = [body_path, wrapper_path]
		return {"ok": true, "executable": "cmd.exe", "args": PackedStringArray(["/D", "/S", "/C", wrapper_path, body_path, _output_path, work_dir])}
	if shell_name != "powershell":
		return {"ok": false, "message": "不支持的命令行类型。"}
	var escaped_output := _output_path.replace("'", "''")
	var escaped_work_dir := work_dir.replace("'", "''")
	var utf8_prelude := "$utf8 = New-Object System.Text.UTF8Encoding($false)\n[Console]::InputEncoding = $utf8\n[Console]::OutputEncoding = $utf8\n$OutputEncoding = $utf8\nchcp.com 65001 > $null\n$env:PYTHONUTF8 = '1'\n$env:PYTHONIOENCODING = 'utf-8'\n"
	var script := "%s$ProgressPreference = 'SilentlyContinue'\n$global:LASTEXITCODE = 0\nSet-Location -LiteralPath '%s'\n& {\n%s\n} *>&1 | Out-File -LiteralPath '%s' -Encoding utf8 -Width 4096\nexit $LASTEXITCODE\n" % [utf8_prelude, escaped_work_dir, command, escaped_output]
	var encoded := Marshalls.raw_to_base64(script.to_utf16_buffer())
	_script_paths.clear()
	return {"ok": true, "executable": "powershell.exe", "args": PackedStringArray(["-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-EncodedCommand", encoded])}
func _poll_output(final_chunk := false) -> void:
	if _output_path.is_empty() or not FileAccess.file_exists(_output_path):
		return
	var file := FileAccess.open(_output_path, FileAccess.READ)
	if file == null:
		return
	var length := file.get_length()
	if length < _output_offset:
		_output_offset = 0
	var available := length - _output_offset
	if available <= 0:
		file.close()
		return
	var read_size := mini(available, MAX_READ_BYTES_PER_POLL)
	file.seek(_output_offset)
	var bytes := file.get_buffer(read_size)
	file.close()
	var safe_size := _utf8_complete_prefix_size(bytes)
	if safe_size <= 0:
		if final_chunk:
			_output_offset += bytes.size()
		return
	if safe_size < bytes.size():
		bytes = bytes.slice(0, safe_size)
	_output_offset += safe_size
	var chunk := bytes.get_string_from_utf8()
	if _output_offset == safe_size and chunk.begins_with(String.chr(0xfeff)):
		chunk = chunk.trim_prefix(String.chr(0xfeff))
	if not chunk.is_empty():
		output_appended.emit(chunk)

func _utf8_complete_prefix_size(bytes: PackedByteArray) -> int:
	var size := bytes.size()
	if size <= 0:
		return 0
	var start := maxi(0, size - 4)
	for index in range(size - 1, start - 1, -1):
		var value := int(bytes[index])
		if (value & 0xc0) == 0x80:
			continue
		var expected := 1
		if value >= 0xc2 and value <= 0xdf:
			expected = 2
		elif value >= 0xe0 and value <= 0xef:
			expected = 3
		elif value >= 0xf0 and value <= 0xf4:
			expected = 4
		return index if size - index < expected else size
	return size

func _has_unread_output() -> bool:
	if _output_path.is_empty() or not FileAccess.file_exists(_output_path):
		return false
	var file := FileAccess.open(_output_path, FileAccess.READ)
	if file == null:
		return false
	var unread := file.get_length() > _output_offset
	file.close()
	return unread

func _finish_process() -> void:
	_poll_output()
	var exit_code := OS.get_process_exit_code(process_id) if process_id > 0 else -1
	var stopped := _stopped_by_user
	process_id = -1
	state_changed.emit(false, "已停止" if stopped else "命令执行完成 · Exit %d" % exit_code)
	finished.emit(exit_code, stopped)
	_cleanup_files()

func console_dir() -> String:
	_ensure_config()
	return proxy_config.runtime_dir().path_join("console")

func _ensure_console_dir() -> void:
	DirAccess.make_dir_recursive_absolute(console_dir())
func _write_text(path: String, content: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(content)
	file.close()
	return true

func _cleanup_scripts() -> void:
	for path in _script_paths:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	_script_paths.clear()

func _cleanup_files() -> void:
	_cleanup_scripts()
	if not _output_path.is_empty() and FileAccess.file_exists(_output_path):
		DirAccess.remove_absolute(_output_path)
	_output_path = ""

func _load_working_directory() -> void:
	_working_directory = default_working_directory()
	var settings := ConfigFile.new()
	if settings.load(SETTINGS_PATH) != OK:
		return
	var saved := str(settings.get_value("terminal", "working_directory", ""))
	if not saved.is_empty() and DirAccess.dir_exists_absolute(saved):
		_working_directory = saved

func _save_working_directory() -> void:
	var settings := ConfigFile.new()
	settings.set_value("terminal", "working_directory", _working_directory)
	settings.save(SETTINGS_PATH)

func _display_shell(shell_name: String) -> String:
	return "CMD" if shell_name.to_lower() == "cmd" else "PowerShell"

func dispose() -> void:
	stop()
	_cleanup_files()
