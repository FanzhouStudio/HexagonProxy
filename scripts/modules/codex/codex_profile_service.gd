class_name CodexProfileService
extends Node

signal event_logged(message: String)

const HELPER_SOURCE := "res://scripts/windows_codex_profile_helper.ps1"
const INDEX_VERSION := 1
const DEFAULT_PROFILE_ID := "default"

var _profiles: Array = []
var _selected_id := DEFAULT_PROFILE_ID
var _installed := false
var _running := false
var _busy := false

func initialize() -> void:
	DirAccess.make_dir_recursive_absolute(_runtime_dir())
	DirAccess.make_dir_recursive_absolute(_managed_root())
	_install_helper()
	_load_index()
	refresh_status()

func dispose() -> void:
	pass

func profiles() -> Array:
	var result: Array = []
	for profile in _profiles:
		if profile is Dictionary:
			var item: Dictionary = (profile as Dictionary).duplicate(true)
			item["selected"] = str(item.get("id", "")) == _selected_id
			item["login_present"] = _login_present(item)
			result.append(item)
	return result

func selected_id() -> String:
	return _selected_id

func is_installed() -> bool:
	return _installed

func is_running() -> bool:
	return _running

func is_busy() -> bool:
	return _busy

func refresh_status() -> Dictionary:
	_ensure_helper()
	var result := _call_helper("inspect", "", "")
	if bool(result.get("ok", false)):
		_installed = bool(result.get("installed", false))
		_running = bool(result.get("running", false))
	return {
		"installed": _installed,
		"running": _running,
		"selected_id": _selected_id
	}

func create_profile(display_name: String) -> Dictionary:
	var name := display_name.strip_edges()
	if name.is_empty():
		return _failure("请先输入账号备注。")
	if name.length() > 40:
		name = name.left(40)
	var profile_id := _new_profile_id()
	var root := _managed_root().path_join(profile_id)
	var codex_home := root.path_join("codex")
	var electron_data := root.path_join("electron")
	var error := DirAccess.make_dir_recursive_absolute(codex_home)
	if error != OK:
		return _failure("无法创建 Codex 账号目录。")
	DirAccess.make_dir_recursive_absolute(electron_data)
	_profiles.append({
		"id": profile_id,
		"name": name,
		"codex_home": codex_home,
		"electron_data": electron_data,
		"created_at": Time.get_datetime_string_from_system(false, true)
	})
	_save_index()
	event_logged.emit("已创建 Codex 账号配置“%s”。首次切换后请按 Codex 官方流程登录。" % name)
	return {
		"ok": true,
		"profile_id": profile_id,
		"message": "账号配置已创建。切换后完成一次登录即可。"
	}

func switch_profile(profile_id: String) -> Dictionary:
	if _busy:
		return _failure("Codex 账号正在切换，请稍后再试。")
	var profile := _find_profile(profile_id)
	if profile.is_empty():
		return _failure("没有找到这个 Codex 账号配置。")
	if OS.get_name() != "Windows":
		return _failure("Codex 桌面账号切换目前仅支持 Windows。")
	_busy = true
	var result := _call_helper(
		"switch",
		str(profile.get("codex_home", "")),
		str(profile.get("electron_data", ""))
	)
	_busy = false
	if bool(result.get("ok", false)):
		_selected_id = profile_id
		_running = true
		_save_index()
		var message := "已切换并启动 Codex：%s" % str(profile.get("name", "Codex"))
		event_logged.emit(message)
		result["message"] = message
		return result
	result["message"] = _message_for_code(str(result.get("message_code", "")))
	return result

func launch_selected() -> Dictionary:
	if _busy:
		return _failure("Codex 正在处理中。")
	var profile := _find_profile(_selected_id)
	if profile.is_empty():
		profile = _find_profile(DEFAULT_PROFILE_ID)
	_busy = true
	var result := _call_helper(
		"launch",
		str(profile.get("codex_home", "")),
		str(profile.get("electron_data", ""))
	)
	_busy = false
	if bool(result.get("ok", false)):
		_running = true
		result["message"] = "Codex 已启动。"
		return result
	result["message"] = _message_for_code(str(result.get("message_code", "")))
	return result

func forget_profile(profile_id: String) -> Dictionary:
	if profile_id == DEFAULT_PROFILE_ID:
		return _failure("默认账号配置不能移除。")
	if profile_id == _selected_id and _running:
		return _failure("请先切换到其他账号，再移除当前正在使用的配置。")
	var index := -1
	for i in range(_profiles.size()):
		var item: Dictionary = _profiles[i] as Dictionary
		if str(item.get("id", "")) == profile_id:
			index = i
			break
	if index < 0:
		return _failure("没有找到这个账号配置。")
	var name := str((_profiles[index] as Dictionary).get("name", "Codex"))
	_profiles.remove_at(index)
	if _selected_id == profile_id:
		_selected_id = DEFAULT_PROFILE_ID
	_save_index()
	event_logged.emit("已从 HexagonProxy 列表移除 Codex 配置“%s”，本地 profile 数据未删除。" % name)
	return {
		"ok": true,
		"message": "已从列表移除；本地登录与历史数据仍保留在原目录。"
	}

func profile_path(profile_id: String) -> String:
	var profile := _find_profile(profile_id)
	if profile.is_empty():
		return ""
	var home := str(profile.get("codex_home", ""))
	return home.get_base_dir() if profile_id != DEFAULT_PROFILE_ID else home

func _load_index() -> void:
	_profiles = [_default_profile()]
	_selected_id = DEFAULT_PROFILE_ID
	if not FileAccess.file_exists(_index_path()):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(_index_path()))
	if not parsed is Dictionary:
		return
	var data: Dictionary = parsed
	var items: Variant = data.get("profiles", [])
	if items is Array:
		for item in items:
			if item is Dictionary and str(item.get("id", "")) != DEFAULT_PROFILE_ID:
				_profiles.append((item as Dictionary).duplicate(true))
	var stored_selected := str(data.get("selected_id", DEFAULT_PROFILE_ID))
	if not _find_profile(stored_selected).is_empty():
		_selected_id = stored_selected

func _save_index() -> void:
	var persisted: Array = []
	for item in _profiles:
		if item is Dictionary and str(item.get("id", "")) != DEFAULT_PROFILE_ID:
			persisted.append((item as Dictionary).duplicate(true))
	var payload := {
		"version": INDEX_VERSION,
		"selected_id": _selected_id,
		"profiles": persisted
	}
	var path := _index_path()
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var temp := path + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(payload, "  "))
	file.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	DirAccess.rename_absolute(temp, path)

func _default_profile() -> Dictionary:
	var home := OS.get_environment("USERPROFILE").path_join(".codex")
	return {
		"id": DEFAULT_PROFILE_ID,
		"name": "默认账号",
		"codex_home": home,
		"electron_data": "",
		"created_at": "",
		"builtin": true
	}

func _find_profile(profile_id: String) -> Dictionary:
	for item in _profiles:
		if item is Dictionary and str(item.get("id", "")) == profile_id:
			return item as Dictionary
	return {}

func _login_present(profile: Dictionary) -> bool:
	var home := str(profile.get("codex_home", ""))
	return not home.is_empty() and FileAccess.file_exists(home.path_join("auth.json"))

func _new_profile_id() -> String:
	return "%d_%d" % [int(Time.get_unix_time_from_system()), randi()]

func _managed_root() -> String:
	return OS.get_environment("USERPROFILE").path_join(".codex-profiles").path_join("HexagonProxy")

func _index_path() -> String:
	return ProjectSettings.globalize_path("user://codex_profiles.json")

func _runtime_dir() -> String:
	return ProjectSettings.globalize_path("user://runtime")

func _helper_path() -> String:
	return _runtime_dir().path_join("windows_codex_profile_helper.ps1")

func _ensure_helper() -> void:
	if not FileAccess.file_exists(_helper_path()):
		_install_helper()
func _install_helper() -> void:
	var source := FileAccess.open(HELPER_SOURCE, FileAccess.READ)
	if source == null:
		return
	var target := FileAccess.open(_helper_path(), FileAccess.WRITE)
	if target != null:
		target.store_buffer(source.get_buffer(source.get_length()))
		target.close()
	source.close()

func _call_helper(action: String, codex_home: String, electron_data: String) -> Dictionary:
	_ensure_helper()
	if not FileAccess.file_exists(_helper_path()):
		return _failure("Codex 启动助手不可用。")
	var args := PackedStringArray([
		"-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
		"-File", _helper_path(), "-Action", action
	])
	if not codex_home.is_empty():
		args.append_array(PackedStringArray(["-CodexHome", codex_home]))
	if not electron_data.is_empty():
		args.append_array(PackedStringArray(["-ElectronUserData", electron_data]))
	var output: Array = []
	var exit_code := OS.execute("powershell.exe", args, output, true, false)
	var text := "\n".join(output).strip_edges()
	if exit_code != 0:
		return _failure("Codex 启动助手执行失败。")
	var parsed = JSON.parse_string(text)
	return parsed as Dictionary if parsed is Dictionary else _failure("Codex 启动助手返回异常。")

func _message_for_code(code: String) -> String:
	match code:
		"not_installed":
			return "未检测到 Codex Windows 桌面版。"
		"stop_failed":
			return "无法完全关闭 Codex，请先手动退出后重试。"
		"launch_failed":
			return "Codex 启动失败；当前安装方式可能不支持独立 profile 启动。"
		"exception":
			return "Codex profile 操作失败，请查看日志或手动重启 Codex。"
	return "Codex 账号操作失败。"

func _failure(message: String) -> Dictionary:
	return {"ok": false, "message": message}
