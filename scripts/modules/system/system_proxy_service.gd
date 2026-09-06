class_name SystemProxyService
extends Node

## Windows 系统代理服务
## 负责代理注册表切换、状态恢复和异步助手进程

signal status_changed(enabled: bool)
signal busy_changed(busy: bool)
signal event_logged(message: String)

const ProxyConfigScript = preload("res://scripts/modules/proxy/proxy_config.gd")
const LocalNetworkCatalogScript = preload("res://scripts/modules/network/local_network_catalog.gd")

var proxy_config
var local_network_catalog = LocalNetworkCatalogScript.new()
var enabled := false
var busy := false
var process_id := -1
var _target := false
var _pending: Variant = null
var _started_msec := 0
var _state_captured := false
var _shutting_down := false

func bind_config(config) -> void:
	proxy_config = config

func _ensure_config() -> void:
	if proxy_config == null:
		proxy_config = ProxyConfigScript.new()

func initialize() -> void:
	DirAccess.make_dir_recursive_absolute(runtime_dir())
	_install_helper()
	_state_captured = FileAccess.file_exists(state_path())
	enabled = _state_captured

func set_enabled(value: bool) -> void:
	_ensure_config()
	if OS.get_name() != "Windows":
		event_logged.emit("当前版本的系统代理开关仅支持 Windows。")
		return
	if busy:
		_pending = value
		return
	if value == enabled:
		status_changed.emit(enabled)
		return
	if not value and not _state_captured:
		enabled = false
		status_changed.emit(false)
		return
	if not FileAccess.file_exists(helper_path()):
		_install_helper()
	busy = true
	_target = value
	busy_changed.emit(true)
	var action := "enable" if value else "disable"
	process_id = OS.create_process("powershell.exe", PackedStringArray([
		"-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
		"-File", helper_path(), action, state_path(),
		"%s:%d" % [proxy_config.controller_host(), proxy_config.mixed_port()],
		local_network_catalog.windows_proxy_override()
	]), false)
	_started_msec = Time.get_ticks_msec()
	if process_id <= 0:
		process_id = -1
		busy = false
		busy_changed.emit(false)
		event_logged.emit("无法启动系统代理设置助手。")
		status_changed.emit(enabled)

func enable() -> void:
	set_enabled(true)
func disable() -> void:
	set_enabled(false)

func toggle() -> void:
	set_enabled(not enabled)

func is_enabled() -> bool:
	return enabled

func _process(_delta: float) -> void:
	if process_id <= 0:
		return
	if OS.is_process_running(process_id):
		if Time.get_ticks_msec() - _started_msec <= 12000:
			return
		OS.kill(process_id)
		_finish(false, true)
		return
	var code := OS.get_process_exit_code(process_id)
	_finish(code == 0, false)

func _finish(success: bool, timed_out: bool) -> void:
	process_id = -1
	busy = false
	if success:
		enabled = _target
		_state_captured = FileAccess.file_exists(state_path())
		event_logged.emit("系统代理已%s。" % ("开启" if enabled else "关闭"))
	else:
		event_logged.emit("系统代理设置%s。" % ("超时，操作已终止" if timed_out else "失败，请检查 Windows 权限"))
	status_changed.emit(enabled)
	busy_changed.emit(false)
	if _pending != null and not _shutting_down:
		var pending := bool(_pending)
		_pending = null
		if pending != enabled:
			set_enabled(pending)

func stop() -> void:
	if _shutting_down:
		return
	_shutting_down = true
	_pending = null
	if process_id > 0 and OS.is_process_running(process_id):
		OS.kill(process_id)
	process_id = -1
	busy = false
	if OS.get_name() == "Windows" and FileAccess.file_exists(state_path()) and FileAccess.file_exists(helper_path()):
		OS.create_process("powershell.exe", PackedStringArray([
			"-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
			"-File", helper_path(), "disable", state_path()
		]), false)
	enabled = false

func runtime_dir() -> String:
	_ensure_config()
	return proxy_config.runtime_dir()
func helper_path() -> String:
	return runtime_dir().path_join("windows_proxy_helper.ps1")

func state_path() -> String:
	return runtime_dir().path_join("windows_proxy_state.json")

func _install_helper() -> void:
	var source := FileAccess.open("res://scripts/windows_proxy_helper.ps1", FileAccess.READ)
	if source == null:
		return
	var target := FileAccess.open(helper_path(), FileAccess.WRITE)
	if target != null:
		target.store_buffer(source.get_buffer(source.get_length()))
		target.close()
	source.close()
