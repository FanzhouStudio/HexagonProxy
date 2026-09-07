class_name CodexProfileCoordinator
extends Node

var service
var panel: CodexAccountsPanel
var _active := false
var _working := false
var _usage_timer: Timer
var _last_attempt: Dictionary = {}
var _refresh_cursor := 0
const USAGE_REFRESH_SECONDS := 300

func setup(profile_service, accounts_panel: CodexAccountsPanel) -> void:
	service = profile_service
	panel = accounts_panel
	panel.create_profile_requested.connect(_on_create_requested)
	panel.switch_profile_requested.connect(_on_switch_requested)
	panel.forget_profile_requested.connect(_on_forget_requested)
	panel.refresh_requested.connect(_on_refresh_requested)
	panel.launch_requested.connect(_on_launch_requested)
	panel.import_requested.connect(_on_import_requested)
	panel.capture_requested.connect(_on_capture_requested)
	panel.capture_to_requested.connect(_on_capture_to_requested)
	panel.usage_requested.connect(_on_usage_requested)
	panel.recover_requested.connect(_on_recover_requested)
	panel.authorize_requested.connect(_on_authorize_requested)

func _on_authorize_requested(display_name: String) -> void:
	if _begin("正在打开官方授权页面，请在浏览器完成登录（最多等待 3 分钟）…"):
		var result: Dictionary = await service.authorize_profile(display_name)
		if bool(result.get("ok", false)):
			result["message"] = "授权已独立保存，可从列表切换；当前账号未改变。"
		await _finish(result)

func start() -> void:
	_active = true
	_usage_timer = Timer.new()
	_usage_timer.wait_time = 5
	_usage_timer.timeout.connect(_auto_refresh_usage)
	add_child(_usage_timer)
	_usage_timer.start()
	_on_refresh_requested()

func shutdown() -> void:
	_active = false
	if is_instance_valid(_usage_timer):
		_usage_timer.stop()

func _auto_refresh_usage() -> void:
	if not _active or _working or service.is_busy():
		return
	var accounts: Array = service.profiles()
	if accounts.is_empty():
		return
	var now := int(Time.get_unix_time_from_system())
	for offset in range(accounts.size()):
		var index := (_refresh_cursor + offset) % accounts.size()
		var account: Dictionary = accounts[index]
		var id := str(account.get("id", ""))
		if not bool(account.get("login_present", false)) or str(account.get("auth_kind", "")) == "api":
			continue
		if now - int(_last_attempt.get(id, 0)) < USAGE_REFRESH_SECONDS:
			continue
		_refresh_cursor = (index + 1) % accounts.size()
		_last_attempt[id] = now
		_working = true
		panel.set_busy(true)
		await service.refresh_usage(id)
		_working = false
		if _active:
			panel.render(service.view_state(), service.profiles())
			panel.set_busy(false)
		return

func _begin(message: String) -> bool:
	if not _active or _working:
		return false
	_working = true
	panel.set_busy(true)
	panel.show_message(message, true)
	return true

func _finish(result: Dictionary, refresh: bool = true) -> void:
	if not _active:
		_working = false
		return
	if refresh:
		await service.refresh_status()
	_working = false
	if not _active:
		return
	panel.render(service.view_state(), service.profiles())
	panel.set_busy(false)
	panel.show_message(str(result.get("message", "")), bool(result.get("ok", false)))

func _on_create_requested(display_name: String) -> void:
	if _begin("正在创建账号配置…"):
		var result: Dictionary = await service.create_profile(display_name)
		if _active and bool(result.get("ok", false)):
			panel.clear_profile_name()
		await _finish(result, false)

func _on_switch_requested(profile_id: String) -> void:
	if _begin("正在保存当前账号并切换 Codex…"):
		_last_attempt.erase(profile_id)
		await _finish(await service.switch_profile(profile_id))

func _on_forget_requested(profile_id: String) -> void:
	if _begin("正在移除账号入口…"):
		await _finish(service.forget_profile(profile_id), false)

func _on_refresh_requested() -> void:
	if _begin("正在检测 Codex…"):
		var state: Dictionary = await service.refresh_status()
		await _finish({"ok": bool(state.get("ok", false)), "message": str(state.get("message", "状态已刷新。"))}, false)

func _on_launch_requested() -> void:
	if _begin("正在启动 Codex…"):
		await _finish(await service.launch_selected())

func _on_import_requested(path: String, display_name: String) -> void:
	if _begin("正在导入登录文件…"):
		var result: Dictionary = await service.import_profile(path, display_name)
		if _active and bool(result.get("ok", false)):
			panel.clear_profile_name()
		await _finish(result, false)

func _on_capture_requested(display_name: String) -> void:
	if _begin("正在保存当前登录…"):
		var result: Dictionary = await service.capture_current(display_name)
		if bool(result.get("ok", false)):
			await service.refresh_usage(str(result["profile_id"]))
		await _finish(result)

func _on_capture_to_requested(profile_id: String) -> void:
	if _begin("正在将当前登录保存到指定账号…"):
		var result: Dictionary = await service.capture_current("", profile_id)
		if bool(result.get("ok", false)):
			await service.refresh_usage(str(result["profile_id"]))
		await _finish(result)

func _on_usage_requested(profile_id: String) -> void:
	if _begin("正在查询账号额度…"):
		_last_attempt[profile_id] = int(Time.get_unix_time_from_system())
		await _finish(await service.refresh_usage(profile_id), false)

func _on_recover_requested() -> void:
	if _begin("正在恢复中断前的账号…"):
		await _finish(await service.recover_interrupted_switch())
