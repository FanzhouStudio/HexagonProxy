class_name AntigravityProxyCoordinator
extends Node

var service
var panel: AntigravityProxyPanel
var control
var _active := false
var _working := false
var _login_timer: Timer
var _pending_login_id := ""
var _login_checks := 0

func setup(proxy_service, proxy_panel: AntigravityProxyPanel, mihomo_control) -> void:
	service = proxy_service
	panel = proxy_panel
	control = mihomo_control
	panel.executable_selected.connect(_on_executable_selected)
	panel.action_requested.connect(_on_action_requested)
	panel.refresh_requested.connect(_refresh)
	panel.account_add_requested.connect(_add_account)
	panel.account_action_requested.connect(_account_action)

func _add_account(account_name: String) -> void:
	if not _active or _working:
		return
	var result: Dictionary = service.accounts.add(account_name)
	panel.render(service.view_state())
	if result.get("ok", false):
		panel.account_name.clear()
		await _account_action("launch", str(result.id))
	else:
		panel.show_account_message(str(result.get("message", "")), false)

func _account_action(action: String, id: String, quiet := false) -> void:
	if not _active or _working:
		return
	_working = true
	panel.set_busy(true)
	if not quiet:
		panel.show_account_message("正在打开账号登录窗口…" if action == "launch" else "正在刷新此账号登录状态和额度…", true)
	var result: Dictionary = await service.accounts.run(action, id, str(service.view_state().get("exe_path", "")))
	if _active:
		panel.render(service.view_state())
		panel.set_busy(false)
		if not quiet or result.get("logged_in", false):
			panel.show_account_message(str(result.get("message", "")), result.get("ok", false))
		if action == "quota":
			if not quiet or result.get("ok", false):
				panel.show_quota(result, id)
			if result.get("logged_in", false) and id == _pending_login_id:
				_login_timer.stop()
		else:
			panel.quota_view.text = "额度未知，请登录此配置后刷新。"
			if result.get("ok", false):
				_pending_login_id = id
				_login_checks = 0
				_login_timer.start(5.0)
	_working = false

func _poll_login() -> void:
	if not _active or _working:
		return
	_login_checks += 1
	await _account_action("quota", _pending_login_id, true)
	if _login_checks >= 24:
		_login_timer.stop()

func start() -> void:
	_active = true
	_login_timer = Timer.new()
	_login_timer.timeout.connect(_poll_login)
	add_child(_login_timer)
	_refresh()

func shutdown() -> void:
	_active = false
	if is_instance_valid(_login_timer):
		_login_timer.stop()

func _refresh() -> void:
	if not _active or _working:
		return
	_working = true
	panel.set_busy(true)
	var state: Dictionary = await service.refresh_status()
	if _active:
		panel.render(state)
		panel.set_busy(false)
		if not bool(state.get("ok", false)):
			panel.show_message(str(state.get("message", "检测失败，请刷新重试。")), false)
	_working = false

func _on_executable_selected(path: String) -> void:
	if not _active or _working:
		return
	var result: Dictionary = service.set_executable(path)
	panel.show_message(str(result.get("message", "")), bool(result.get("ok", false)))
	if bool(result.get("ok", false)):
		_refresh()

func _on_action_requested(action: String) -> void:
	if not _active or _working:
		return
	if action != "disable" and not bool(control.online):
		panel.show_message("请先在总览中连接代理，再启用或启动 Antigravity。", false)
		return
	_working = true
	panel.set_busy(true)
	panel.show_message("正在处理 Antigravity 代理…", true)
	var result: Dictionary = await service.perform(action)
	var state: Dictionary = await service.refresh_status()
	if _active:
		panel.render(state)
		panel.set_busy(false)
		panel.show_message(str(result.get("message", "")), bool(result.get("ok", false)))
	_working = false
