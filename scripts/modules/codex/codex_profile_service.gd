class_name CodexProfileService
extends Node

signal event_logged(message: String)

const HELPER_SOURCE := "res://scripts/windows_codex_profile_helper.ps1"
const INDEX_VERSION := 4
const DEFAULT_PROFILE_ID := "default"
const StoreScript = preload("res://scripts/modules/codex/codex_account_store.gd")

var account_store = StoreScript.new()
var _selected_id := DEFAULT_PROFILE_ID
var _installed := false
var _running := false
var _busy := false
var _load_error := ""
var _state: Dictionary = {}
var _storage_root := ""
var _storage_index := ""
var _worker: Thread
var _disposed := false
var _active_override := ""

# Tests and portable integrations can isolate storage without touching real accounts.
func configure_storage(managed_root: String, index_path: String) -> void:
	_storage_root = managed_root
	_storage_index = index_path

func initialize() -> void:
	if account_store.get_parent() == null:
		add_child(account_store)
	DirAccess.make_dir_recursive_absolute(_managed_root())
	_install_helper()
	_load_index()

func dispose() -> void:
	_disposed = true
	if _worker and _worker.is_started():
		_worker.wait_to_finish()
	_worker = null

func _exit_tree() -> void:
	dispose()

func profiles() -> Array:
	var result: Array = []
	for raw in account_store.all():
		var item: Dictionary = raw.duplicate(true)
		var usage_identity: Dictionary = item.get("usage_identity", {})
		if not _same_identity(item, usage_identity):
			item["usage"] = {}
		item["selected"] = str(item.get("id", "")) == _selected_id
		if item["selected"] and bool(_state.get("account", {}).get("login_present", false)) and not _same_identity(item, _state.get("account", {})):
			item["usage"] = {}
			item["usage_error"] = "当前登录已变化，此栏是旧账号备份。请先保存新登录。"
		if item["selected"] and _same_identity(item, _state.get("account", {})):
			item.merge(_state.get("account", {}), true)
		else:
			item["login_present"] = FileAccess.file_exists(str(item.get("snapshot_path", "")).path_join("auth.json"))
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

func view_state() -> Dictionary:
	var state := _state.duplicate(true)
	state["identity_mismatch"] = bool(_state.get("account", {}).get("login_present", false)) and not _same_identity(account_store.find(_selected_id), _state.get("account", {}))
	state.merge({"installed": _installed, "running": _running, "selected_id": _selected_id, "busy": _busy}, true)
	if not _load_error.is_empty():
		state["message"] = _load_error
	return state

func refresh_status() -> Dictionary:
	if _busy or _disposed:
		return view_state()
	_busy = true
	var result := await _call_helper("inspect")
	_busy = false
	if bool(result.get("ok", false)):
		_state = result
		_installed = bool(result.get("installed", false))
		_running = bool(result.get("running", false))
		var info: Dictionary = result.get("account", {})
		# Observing an external login must never change a saved account's identity.
		if _same_identity(account_store.find(_selected_id), info):
			account_store.update(_selected_id, info)
	else:
		_state["ok"] = false
		_state["message"] = result.get("message", "状态检测失败。")
	return view_state()

func create_profile(display_name: String) -> Dictionary:
	if not _can_mutate():
		return _failure(_blocked_message())
	var label := display_name.strip_edges().left(40)
	if label.is_empty():
		return _failure("请先输入账号备注。")
	_busy = true
	var profile := _new_profile(label)
	var result := await _call_helper("prepare", {"CodexHome": profile["snapshot_path"]})
	_busy = false
	if not bool(result.get("ok", false)):
		return result
	account_store.add(profile)
	if not _save_index():
		account_store.remove(str(profile["id"]))
		return _failure("账号索引保存失败，未添加到列表。")
	return {"ok": true, "profile_id": profile["id"], "message": "账号配置已创建。切换后请在 Codex 中完成官方登录。"}

func import_profile(path: String, display_name: String = "") -> Dictionary:
	return await _import_or_capture("import", path, display_name)

func authorize_profile(display_name: String = "") -> Dictionary:
	return await _import_or_capture("login", "", display_name)

func _same_identity(left: Dictionary, right: Dictionary) -> bool:
	var a := str(left.get("account_id", ""))
	var b := str(right.get("account_id", ""))
	if not a.is_empty() and not b.is_empty():
		var left_email := str(left.get("email", "")).to_lower()
		var right_email := str(right.get("email", "")).to_lower()
		return a == b and (left_email.is_empty() or right_email.is_empty() or left_email == right_email)
	a = str(left.get("email", "")).to_lower()
	b = str(right.get("email", "")).to_lower()
	return not a.is_empty() and a == b

func capture_current(display_name: String = "", target_id: String = "") -> Dictionary:
	if not _can_mutate():
		return _failure(_blocked_message())
	_busy = true
	# Capture into a fresh directory first; no existing login can be overwritten.
	var captured := _new_profile(display_name.strip_edges().left(40))
	var result := await _call_helper("capture", {"CodexHome": captured["snapshot_path"]})
	_busy = false
	if not bool(result.get("ok", false)):
		return result
	var info: Dictionary = result.get("account", {})
	var target: Dictionary = account_store.find(target_id).duplicate(true)
	if not target_id.is_empty() and target.is_empty():
		return _failure("目标账号不存在，登录已保存在独立备份目录。")
	if target_id.is_empty():
		for item in account_store.all():
			if _same_identity(item, info):
				target = item.duplicate(true)
				break
	# Explicitly filling an empty row is allowed; replacing a different saved
	# identity is not. The old snapshot is always retained, including on save errors.
	if not target.is_empty() and FileAccess.file_exists(str(target.get("snapshot_path", "")).path_join("auth.json")) and not _same_identity(target, info):
		return _failure("该栏已保存另一个账号，请选择空账号栏或使用顶部“保存为独立账号”。原账号未覆盖。")
	var previous: Array = account_store.all()
	var old_selected := _selected_id
	if target.is_empty():
		target = captured.duplicate(true)
	else:
		target["snapshot_path"] = captured["snapshot_path"]
	target.merge(info, true)
	if not _same_identity(target.get("usage_identity", {}), info):
		target["usage"] = {}
		target["usage_error"] = ""
		target["usage_identity"] = {}
	if not display_name.strip_edges().is_empty():
		target["name"] = display_name.strip_edges().left(40)
	if str(target.get("name", "")).is_empty():
		target["name"] = str(info.get("email", "已保存账号"))
	var id := str(target["id"])
	if account_store.find(id).is_empty():
		account_store.add(target)
	else:
		account_store.update(id, target)
	_selected_id = id
	if not _save_index():
		account_store.load_accounts(previous)
		_selected_id = old_selected
		return _failure("账号索引保存失败；原账号未覆盖，新登录仍保留在独立目录。")
	_state["account"] = info
	return {"ok": true, "profile_id": id, "message": "当前登录已保存到“%s”，其他账号保持不变。" % str(target["name"])}

func _import_or_capture(action: String, path: String, display_name: String) -> Dictionary:
	if not _can_mutate():
		return _failure(_blocked_message())
	_busy = true
	var label := display_name.strip_edges().left(40)
	var profile: Dictionary = account_store.find(_selected_id).duplicate(true) if action == "capture" else _new_profile(label)
	var previous := profile.duplicate(true)
	var arguments := {"CodexHome": profile["snapshot_path"]}
	if action == "import":
		arguments["ImportPath"] = path
	var result := await _call_helper(action, arguments)
	_busy = false
	if not bool(result.get("ok", false)):
		return result
	var info: Dictionary = result.get("account", {})
	profile.merge(info, true)
	if not label.is_empty():
		profile["name"] = label
	elif action != "capture":
		profile["name"] = str(info.get("email", ""))
		if str(profile["name"]).is_empty():
			profile["name"] = "已保存账号" if action == "capture" else "导入账号"
	if action == "capture":
		account_store.update(_selected_id, profile)
	else:
		account_store.add(profile)
	if not _save_index():
		if action == "capture":
			account_store.update(_selected_id, previous)
		else:
			account_store.remove(str(profile["id"]))
		return _failure("账号索引保存失败；登录文件仍保留在新建的账号目录。")
	return {"ok": true, "profile_id": profile["id"], "message": "账号已保存，可从列表切换。" if action == "capture" else "登录文件已导入，可从列表切换。"}

func switch_profile(profile_id: String) -> Dictionary:
	if not _can_mutate():
		return _failure(_blocked_message())
	var inspection := await refresh_status()
	if not bool(inspection.get("ok", false)):
		return _failure("无法确认当前登录身份，暂未切换；请先刷新状态。")
	var live_info: Dictionary = inspection.get("account", {})
	if bool(live_info.get("login_present", false)) and not _same_identity(account_store.find(_selected_id), live_info):
		var saved := await capture_current()
		if not bool(saved.get("ok", false)):
			return saved
	if profile_id == _selected_id and _same_identity(account_store.find(profile_id), live_info):
		return await launch_selected()
	var target: Dictionary = account_store.find(profile_id)
	if target.is_empty():
		return _failure("账号不存在。")
	_busy = true
	# The helper commits this index only after auth/config and launch succeed.
	var pending := _index_path() + ".pending-%d-%d" % [Time.get_ticks_usec(), randi()]
	if not _write_index(pending, profile_id):
		_busy = false
		return _failure("无法保存切换计划，当前账号未改变。")
	var result := await _call_helper("switch", {
		"CodexHome": target["snapshot_path"],
		"CurrentSnapshot": profile_path(_selected_id),
		"IndexPath": _index_path(), "PendingIndex": pending, "ExpectedProfileId": _selected_id
	})
	_busy = false
	if FileAccess.file_exists(pending):
		DirAccess.remove_absolute(pending)
	if str(result.get("message_code", "")) == "state_changed":
		_load_index()
	if result.has("running"):
		_running = bool(result["running"])
	if bool(result.get("ok", false)):
		_selected_id = profile_id
		_state["account"] = {}
		result["message"] = "已切换并启动 Codex：%s" % str(target.get("name", ""))
		event_logged.emit(str(result["message"]))
	return result

func recover_interrupted_switch() -> Dictionary:
	if _busy or _disposed:
		return _failure("Codex 正在处理中。")
	_busy = true
	var result := await _call_helper("recover")
	_busy = false
	if bool(result.get("ok", false)):
		result["message"] = "已恢复中断前的认证与配置。"
	return result

func launch_selected() -> Dictionary:
	if not _can_mutate():
		return _failure(_blocked_message())
	_busy = true
	var result := await _call_helper("launch")
	_busy = false
	if bool(result.get("ok", false)):
		_running = true
		result["message"] = "Codex 已启动。"
	return result

func refresh_usage(profile_id: String) -> Dictionary:
	if not _can_mutate():
		return _failure(_blocked_message())
	if profile_id == _selected_id:
		var inspection := await refresh_status()
		if not bool(inspection.get("ok", false)) or bool(inspection.get("identity_mismatch", false)):
			return _failure("当前登录与此账号栏不一致或无法确认，请先保存当前登录后查询。")
	var profile: Dictionary = account_store.find(profile_id)
	if profile.is_empty():
		return _failure("账号不存在。")
	_busy = true
	# The helper synchronizes current credentials into the durable account record
	# before querying, and rotates only inactive credentials to avoid desktop races.
	var auth_home := profile_path(profile_id)
	var result := await _call_helper("usage", {"CodexHome": auth_home})
	_busy = false
	if bool(result.get("ok", false)):
		var patch: Dictionary = result.get("account", {}).duplicate(true)
		if not _same_identity(profile, patch):
			return _failure("查询返回的账号与该栏不一致，请先保存当前登录到正确账号，再查询额度。")
		patch["usage"] = result.get("usage", {})
		patch["usage_identity"] = result.get("account", {}).duplicate(true)
		patch["usage_error"] = ""
		account_store.update(profile_id, patch)
		if not _save_index():
			return _failure("额度已获取，但缓存保存失败。")
		result["message"] = "额度已更新。"
	else:
		# Preserve the last successful reading and timestamp on request failures.
		account_store.update(profile_id, {"usage_error": result.get("message", "额度查询失败。")})
	return result

func forget_profile(profile_id: String) -> Dictionary:
	if not _can_mutate():
		return _failure(_blocked_message())
	if profile_id == DEFAULT_PROFILE_ID:
		return _failure("默认账号配置不能移除。")
	if profile_id == _selected_id:
		return _failure("请先切换到其他账号，再移除当前配置。")
	var previous: Array = account_store.all()
	if not account_store.remove(profile_id):
		return _failure("账号不存在。")
	if not _save_index():
		account_store.load_accounts(previous)
		return _failure("账号索引保存失败。")
	return {"ok": true, "message": "已移除列表入口；本地登录与配置备份仍保留。"}

func profile_path(profile_id: String) -> String:
	return str(account_store.find(profile_id).get("snapshot_path", ""))

func _new_profile(label: String) -> Dictionary:
	var id := "%d_%d" % [int(Time.get_unix_time_from_system()), randi()]
	return {
		"id": id, "name": label, "snapshot_path": _managed_root().path_join("accounts").path_join(id),
		"created_at": Time.get_datetime_string_from_system(true),
		"usage": {"five_hour": -1, "weekly": -1, "updated_at": ""}
	}

func _load_index() -> void:
	var items: Array = [{"id": DEFAULT_PROFILE_ID, "name": "默认账号", "builtin": true,
		"snapshot_path": _managed_root().path_join("accounts/default")}]
	_selected_id = DEFAULT_PROFILE_ID
	_load_error = ""
	if FileAccess.file_exists(_index_path()):
		var parser := JSON.new()
		var parse_error := parser.parse(FileAccess.get_file_as_string(_index_path()))
		var data: Variant = parser.data if parse_error == OK else null
		if not data is Dictionary or not data.get("accounts", data.get("profiles", [])) is Array:
			_load_error = "账号索引损坏，请先恢复 codex_profiles.json 备份；原文件未覆盖。"
		else:
			_active_override = str(data.get("active_home", ""))
			var seen := {DEFAULT_PROFILE_ID: true}
			for raw in data.get("accounts", data.get("profiles", [])):
				if not raw is Dictionary:
					continue
				var item: Dictionary = raw.duplicate(true)
				var id := str(item.get("id", ""))
				if id.is_empty():
					continue
				# Copy only auth/config from legacy independent homes; retain all originals.
				if str(item.get("snapshot_path", "")).is_empty():
					var legacy_home := str(item.get("codex_home", ""))
					item["snapshot_path"] = _managed_root().path_join("accounts").path_join(id)
					if not legacy_home.is_empty() and id != DEFAULT_PROFILE_ID:
						if not _migrate_snapshot(legacy_home, str(item["snapshot_path"])):
							_load_error = "旧账号备份迁移失败，请检查目录权限；原账号文件未改变。"
						if id == str(data.get("selected_id", "")) and _active_override.is_empty():
							_active_override = legacy_home
				if id == DEFAULT_PROFILE_ID:
					items[0].merge(item, true)
					items[0]["builtin"] = true
				elif not seen.has(id):
					seen[id] = true
					items.append(item)
			var selected := str(data.get("selected_id", DEFAULT_PROFILE_ID))
			if seen.has(selected):
				_selected_id = selected
	account_store.load_accounts(items)

func _migrate_snapshot(source: String, target: String) -> bool:
	if FileAccess.file_exists(target.path_join("snapshot.json")):
		return true
	if DirAccess.make_dir_recursive_absolute(target) != OK:
		return false
	for name in ["auth.json", "config.toml"]:
		if FileAccess.file_exists(source.path_join(name)):
			if DirAccess.copy_absolute(source.path_join(name), target.path_join(name)) != OK:
				return false
	var marker := FileAccess.open(target.path_join("snapshot.json"), FileAccess.WRITE)
	if marker == null:
		return false
	marker.store_string(JSON.stringify({"version": 1, "auth_present": FileAccess.file_exists(target.path_join("auth.json")),
		"config_present": FileAccess.file_exists(target.path_join("config.toml"))}))
	marker.close()
	return true

func _write_index(path: String, selected: String) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({"version": INDEX_VERSION, "selected_id": selected, "active_home": _active_override, "accounts": account_store.all()}, "  "))
	file.flush()
	var error := file.get_error()
	file.close()
	return error == OK

func _save_index() -> bool:
	if not _load_error.is_empty():
		return false
	var temp := _index_path() + ".tmp"
	if not _write_index(temp, _selected_id):
		return false
	return DirAccess.rename_absolute(temp, _index_path()) == OK

func _can_mutate() -> bool:
	return not _busy and not _disposed and _load_error.is_empty()

func _blocked_message() -> String:
	return _load_error if not _load_error.is_empty() else "Codex 正在处理中，请稍后再试。"

func _active_home() -> String:
	if not _active_override.is_empty():
		return _active_override
	var value := OS.get_environment("CODEX_HOME").strip_edges()
	return value if not value.is_empty() else OS.get_environment("USERPROFILE").path_join(".codex")

func _managed_root() -> String:
	return _storage_root if not _storage_root.is_empty() else OS.get_environment("USERPROFILE").path_join(".codex-profiles/HexagonProxy")

func _index_path() -> String:
	return _storage_index if not _storage_index.is_empty() else ProjectSettings.globalize_path("user://codex_profiles.json")

func _helper_path() -> String:
	return ProjectSettings.globalize_path("user://runtime/windows_codex_profile_helper.ps1")

func _install_helper() -> void:
	DirAccess.make_dir_recursive_absolute(_helper_path().get_base_dir())
	var source := FileAccess.open(HELPER_SOURCE, FileAccess.READ)
	if source == null:
		return
	var target := FileAccess.open(_helper_path(), FileAccess.WRITE)
	if target:
		target.store_buffer(source.get_buffer(source.get_length()))
		target.close()
	source.close()

func _call_helper(action: String, parameters: Dictionary = {}) -> Dictionary:
	if _disposed:
		return _failure("应用正在退出。")
	if OS.get_name() != "Windows":
		return _failure("Codex 账号管理目前仅支持 Windows。")
	if not FileAccess.file_exists(_helper_path()):
		return _failure("Codex 操作助手不可用。")
	var args := PackedStringArray(["-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "RemoteSigned",
		"-File", _helper_path(), "-Action", action, "-ActiveHome", _active_home()])
	for key in parameters:
		args.append("-" + str(key))
		args.append(str(parameters[key]))
	var thread := Thread.new()
	_worker = thread
	var error := thread.start(_execute_helper.bind(args))
	if error != OK:
		return _failure("无法启动 Codex 操作线程。")
	while thread.is_alive():
		await get_tree().process_frame
		if _disposed:
			return _failure("应用正在退出。")
	var result: Dictionary = thread.wait_to_finish()
	_worker = null
	if not bool(result.get("ok", false)) and not result.has("message"):
		result["message"] = _message_for_code(str(result.get("message_code", "")))
	return result

func _execute_helper(args: PackedStringArray) -> Dictionary:
	var output: Array = []
	var code := OS.execute("powershell.exe", args, output, true, false)
	if code != 0:
		return _failure("Codex 操作助手执行失败。")
	var parser := JSON.new()
	var parse_error := parser.parse("\n".join(output).strip_edges().trim_prefix("\ufeff"))
	var parsed: Variant = parser.data if parse_error == OK else null
	return parsed if parsed is Dictionary else _failure("Codex 操作助手返回异常。")

func _message_for_code(code: String) -> String:
	match code:
		"auth_refresh_pending": return "授权文件仍保留；当前账号的访问令牌等待 Codex 续期，请在 Codex 中使用后刷新额度。"
		"reauthorization_required": return "授权续期被拒绝，原 auth.json 已保留。请通过“授权添加账号”重新授权，或导入最新登录。"
		"token_refresh_failed": return "授权续期暂时失败，登录文件未删除；请检查网络后重试。"
		"cli_missing": return "未找到 Codex 官方命令行程序，请安装 Codex CLI 或使用导入 auth.json。"
		"login_timeout": return "授权等待超过 3 分钟，请点击授权添加账号重试；当前登录未改变。"
		"login_failed": return "官方登录未完成，请关闭其他登录流程后重试；当前登录未改变。"
		"missing_tokens": return "没有可导入的登录令牌。若使用系统凭据库，请通过 Codex 官方登录生成完整 auth.json 后再导入。"
		"current_auth_unavailable": return "当前登录使用系统凭据库或登录文件不完整，无法可靠备份。请设置 cli_auth_credentials_store = \"file\" 并通过 Codex 官方流程重新登录后再切换。"
		"invalid_auth": return "登录文件无效或超过 4 MB，请选择完整的 Codex auth.json。"
		"invalid_config": return "config.toml 格式异常，尚未修改当前账号。"
		"not_installed": return "未检测到 Codex Windows 桌面版；仍可导入和管理账号。"
		"stop_failed": return "无法完全关闭 Codex，请先手动退出后重试。"
		"backup_failed": return "当前登录备份失败，尚未应用目标账号；请检查备份目录权限。"
		"launch_failed": return "Codex 启动失败，请检查桌面版安装。"
		"switch_rolled_back": return "切换失败，已恢复原账号的认证和配置。"
		"rollback_failed": return "切换失败且自动恢复未完成；请从原账号目录恢复 auth.json 和 config.toml 后再操作。"
		"snapshot_missing": return "目标账号备份不完整，请重新导入或保存登录状态。"
		"unsafe_path": return "账号备份目录与使用中的 Codex 目录冲突，已停止操作。"
		"index_failed": return "账号索引无法保存，切换已取消。"
		"login_expired": return "登录已过期，请在 Codex 中重新登录，或重新导入最新 auth.json。"
		"api_usage_unsupported": return "API Key 账号不提供 ChatGPT 的 5 小时/每周额度。"
		"missing_account_id": return "登录文件缺少账号 ID，无法查询额度。"
		"usage_forbidden": return "额度接口拒绝访问，请检查账号权限和代理网络。"
		"usage_rate_limited": return "额度查询过于频繁，请稍后重试。"
		"usage_failed": return "额度查询失败或超时，请检查代理网络。"
		"usage_invalid": return "额度接口返回格式异常，保留上次成功结果。"
		"busy": return "另一个 HexagonProxy 实例正在操作 Codex，请稍后重试。"
		"state_changed": return "账号已被另一个实例切换，列表已重新加载，请重试。"
		"recovery_required": return "检测到上次切换中断，请先点击“恢复中断切换”。"
	return "Codex 操作失败，请检查目录权限及登录文件。"

func _failure(message: String) -> Dictionary:
	return {"ok": false, "message": message}
