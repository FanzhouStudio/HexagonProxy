class_name AntigravityProxyService
extends Node

signal event_logged(message: String)

const HELPER_SOURCE := "res://scripts/windows_antigravity_proxy_helper.ps1"
const PAYLOAD_SOURCE := "res://third_party/antigravity-proxy"
const SETTINGS_PATH := "user://antigravity_proxy.cfg"
const PAYLOAD_FILES := ["version.dll", "config.template.json", "LICENSE.txt", "AUTHORS.txt"]

var proxy_config
var _exe_path := ""
var _state: Dictionary = {}
var _busy := false
var _disposed := false
var _runtime_override := ""
var _settings_override := ""
var accounts = preload("res://scripts/modules/antigravity/antigravity_accounts.gd").new()

func bind_config(config) -> void:
	proxy_config = config

func configure_storage(runtime_path: String, settings_path: String) -> void:
	_runtime_override = runtime_path
	_settings_override = settings_path

func initialize() -> void:
	if accounts.get_parent() == null:
		add_child(accounts)
		accounts.initialize(_runtime_path().path_join("accounts"))
	var settings := ConfigFile.new()
	settings.load(_settings_path())
	_exe_path = str(settings.get_value("antigravity", "executable", _default_executable()))
	if not _install_resources():
		event_logged.emit("Antigravity 代理组件准备失败，请检查运行目录权限。")

func dispose() -> void:
	_disposed = true

func _default_executable() -> String:
	return OS.get_environment("LOCALAPPDATA").path_join("Programs/antigravity/Antigravity.exe")

func _runtime_path() -> String:
	return _runtime_override if not _runtime_override.is_empty() else ProjectSettings.globalize_path("user://runtime/antigravity-proxy")

func _settings_path() -> String:
	return _settings_override if not _settings_override.is_empty() else SETTINGS_PATH

func _install_resources() -> bool:
	if DirAccess.make_dir_recursive_absolute(_runtime_path()) != OK:
		return false
	var resources := {"helper.ps1": HELPER_SOURCE}
	for name in PAYLOAD_FILES:
		resources[name] = PAYLOAD_SOURCE.path_join(name)
	for name in resources:
		var source: String = resources[name]
		var destination := _runtime_path().path_join(name)
		if FileAccess.file_exists(destination) and FileAccess.get_sha256(source) == FileAccess.get_sha256(destination):
			continue
		var input := FileAccess.open(source, FileAccess.READ)
		if input == null:
			return false
		var data := input.get_buffer(input.get_length())
		input.close()
		var output := FileAccess.open(destination + ".tmp", FileAccess.WRITE)
		if output == null:
			return false
		output.store_buffer(data)
		output.close()
		if DirAccess.rename_absolute(destination + ".tmp", destination) != OK:
			return false
	return true

func view_state() -> Dictionary:
	var state := _state.duplicate(true)
	state.merge({"exe_path": _exe_path, "busy": _busy, "current_port": proxy_config.mixed_port() if proxy_config else 7890}, true)
	state["accounts"] = accounts.list()
	state["selected_account"] = accounts.selected
	state["default_account"] = accounts.default_account
	state["quota_snapshots"] = accounts.quotas.duplicate(true)
	state["account_sessions"] = accounts.session_states.duplicate(true)
	return state

func set_executable(path: String) -> Dictionary:
	if _busy or _disposed:
		return _failure("请等待当前操作完成。")
	if bool(_state.get("installed", false)):
		return _failure("请先卸载当前目录中的代理组件，再更换程序路径。")
	if not FileAccess.file_exists(path) or path.get_file().to_lower() not in ["antigravity.exe", "antigravity ide.exe"]:
		return _failure("请选择 Antigravity.exe 或 Antigravity IDE.exe。")
	var settings := ConfigFile.new()
	settings.load(_settings_path())
	settings.set_value("antigravity", "executable", path)
	if settings.save(_settings_path()) != OK:
		return _failure("无法保存 Antigravity 程序路径。")
	_exe_path = path
	_state = {}
	return {"ok": true, "message": "程序路径已保存。"}

func refresh_status() -> Dictionary:
	if _busy or _disposed:
		return view_state()
	_busy = true
	_state = await _call_helper("inspect")
	_busy = false
	return view_state()

func perform(action: String) -> Dictionary:
	if action not in ["enable", "disable", "launch"]:
		return _failure("未知操作。")
	if _busy or _disposed:
		return _failure("请等待当前操作完成。")
	_busy = true
	var result := await _call_helper(action)
	_busy = false
	event_logged.emit(str(result.get("message", "")))
	return result

func _call_helper(action: String) -> Dictionary:
	if OS.get_name() != "Windows":
		return _failure("Antigravity 独立代理目前仅支持 Windows x64。")
	var result_path := _runtime_path().path_join("result-%d-%d.json" % [Time.get_ticks_usec(), randi()])
	var args := PackedStringArray(["-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "RemoteSigned", "-File",
		_runtime_path().path_join("helper.ps1"), "-Action", action, "-ExePath", _exe_path, "-ProxyPort", str(proxy_config.mixed_port() if proxy_config else 7890),
		"-PayloadDirectory", _runtime_path(), "-StateRoot", _runtime_path().path_join("installations"), "-ResultPath", result_path])
	var pid := OS.create_process("powershell.exe", args, false)
	if pid <= 0:
		return _failure("无法启动 Antigravity 代理助手。")
	var deadline := Time.get_ticks_msec() + 30000
	while not FileAccess.file_exists(result_path):
		if _disposed:
			return _failure("应用正在退出，请在下次启动后刷新代理状态。")
		if not OS.is_process_running(pid):
			return _failure("代理助手未返回结果，请检查安装目录权限。")
		if Time.get_ticks_msec() >= deadline:
			# Do not interrupt an in-progress file transaction; it will finish or
			# retain its recovery marker. A later refresh detects the actual state.
			return _failure("代理操作仍未返回，请稍后刷新状态；恢复提示出现时请点击卸载并恢复。")
		await get_tree().create_timer(0.1).timeout
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(result_path).trim_prefix("\ufeff"))
	DirAccess.remove_absolute(result_path)
	if not parsed is Dictionary:
		return _failure("代理助手返回格式异常。")
	var result: Dictionary = parsed
	if result.has("message_code"):
		result["message"] = _message(str(result["message_code"]))
	return result

func _message(code: String) -> String:
	match code:
		"enabled": return "Antigravity 独立代理已启用，使用当前混合端口。下次启动生效。"
		"disabled": return "代理组件已卸载，安装前的文件已恢复。"
		"launched": return "已通过 HexagonProxy 代理启动 Antigravity。"
		"not_installed": return "未找到 Antigravity，请选择程序位置。"
		"invalid_path": return "请选择有效的 Antigravity 主程序。"
		"unsupported_architecture": return "当前代理组件仅支持 Windows x64 版 Antigravity。"
		"running": return "请先完整退出 Antigravity 及其后台进程，再进行此操作。"
		"proxy_unavailable": return "本机混合端口未监听，请先连接 HexagonProxy。"
		"state_invalid", "backup_invalid": return "安装记录或原始备份异常；请保留运行目录中的备份后检查。"
		"files_changed": return "代理文件被其他程序修改，已停止覆盖。请先手动核对 Antigravity 目录中的 version.dll 和 config.json。"
		"payload_invalid": return "代理组件校验失败，请重新安装 HexagonProxy。"
		"recovery_required": return "上次代理安装中断，请先点击“卸载并恢复”。"
		"rollback_failed": return "安装失败且恢复未完成，请保留备份并点击“卸载并恢复”重试。"
		"install_failed": return "代理安装失败，已恢复原始文件。请检查目录权限。"
		"busy": return "另一个实例正在操作 Antigravity，请稍后刷新。"
		"not_enabled": return "请先启用 Antigravity 独立代理。"
	return "代理操作失败，请检查安装目录权限后刷新状态。"

func _failure(message: String) -> Dictionary:
	return {"ok": false, "message": message}
