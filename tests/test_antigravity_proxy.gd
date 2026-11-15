extends SceneTree

const ServiceScript = preload("res://scripts/modules/antigravity/antigravity_proxy_service.gd")
const PanelScript = preload("res://scripts/ui/antigravity_proxy_panel.gd")
const CoordinatorScript = preload("res://scripts/app/antigravity_proxy_coordinator.gd")
var failures := 0

class FakeConfig extends RefCounted:
	func mixed_port() -> int:
		return 39001

class FakeControl extends RefCounted:
	var online := false

class FakeService extends ServiceScript:
	func _init() -> void:
		accounts.free()
		accounts = FakeAccounts.new()
	var calls: Array = []
	var installed := false
	func _call_helper(action: String) -> Dictionary:
		calls.append(action)
		if action == "inspect":
			return {"ok": true, "installed": installed, "intact": installed, "running": false, "proxy_port": 39001}
		installed = action != "disable"
		return {"ok": true, "message": "fixture result"}

class FakeAccounts extends "res://scripts/modules/antigravity/antigravity_accounts.gd":
	var requests: Array = []
	func run(action: String, id: String, _executable: String) -> Dictionary:
		requests.append([action, id])
		if action == "launch":
			selected = id
		return {"ok": true, "logged_in": action == "quota", "models": [], "message": "fixture account opened"}

func _init() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	if not value:
		printerr("FAIL: " + message)
		failures += 1

func _run() -> void:
	var base := ProjectSettings.globalize_path("user://tests-antigravity-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(base)
	var theme = load("res://scripts/modules/ui/ui_theme_service.gd").new()
	root.add_child(theme)
	theme.initialize()
	var factory = load("res://scripts/ui/ui_factory.gd").new(theme.snapshot())
	var service := FakeService.new()
	root.add_child(service)
	service.bind_config(FakeConfig.new())
	service.configure_storage(base.path_join("runtime"), base.path_join("settings.cfg"))
	service.initialize()
	check(service._install_resources(), "bundled resources copied successfully")
	check(FileAccess.get_sha256(base.path_join("runtime/version.dll")) == FileAccess.get_sha256("res://third_party/antigravity-proxy/version.dll"), "bundled native payload materialized intact")
	var path := base.path_join("Antigravity.exe")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("fixture only")
	file.close()
	check(bool(service.set_executable(path).get("ok")), "custom executable saved")
	var reopened := FakeService.new()
	root.add_child(reopened)
	reopened.configure_storage(base.path_join("runtime"), base.path_join("settings.cfg"))
	reopened.initialize()
	check(reopened.view_state()["exe_path"] == path, "executable persists across restart")
	var native := ServiceScript.new()
	root.add_child(native)
	native.bind_config(FakeConfig.new())
	native.configure_storage(base.path_join("native-runtime"), base.path_join("settings.cfg"))
	native.initialize()
	var native_status: Dictionary = await native.refresh_status()
	check(bool(native_status.get("ok")) and not bool(native_status.get("installed", false)), "Godot to Windows helper JSON bridge inspects fixture without launching it")
	native.dispose()
	var panel := PanelScript.new()
	root.add_child(panel)
	panel.setup(factory)
	var page: Control = panel.build()
	root.add_child(page)
	var control := FakeControl.new()
	var coordinator := CoordinatorScript.new()
	root.add_child(coordinator)
	coordinator.setup(service, panel, control)
	coordinator.start()
	await process_frame
	check(panel.account_list.get_child_count() == 1, "original account has its own clickable row")
	var original_row_id := panel.account_list.get_child(0).get_instance_id()
	panel.render(service.view_state())
	check(panel.account_list.get_child(0).get_instance_id() == original_row_id, "Unchanged account refresh reuses row controls")
	var display_state: Dictionary = service.view_state()
	display_state.accounts = [{"id": "default", "name": "默认账号", "logged_in": true, "email": "fixture@example.invalid"}]
	display_state.account_sessions = {"default": {"editor_running": false}}
	panel.render(display_state)
	var labels: Array = panel.account_list.find_children("*", "Label", true, false)
	check(labels.any(func(label: Label) -> bool: return label.text.contains("历史记录") and label.text.contains("窗口未运行")), "Cached login identity cannot imply a live account window")
	display_state.account_sessions = {"default": {"discovery": "process_access_denied"}}
	panel.render(display_state)
	labels = panel.account_list.find_children("*", "Label", true, false)
	check(labels.any(func(label: Label) -> bool: return label.text.contains("运行状态未知")), "Unreadable process state stays unknown")
	await coordinator._add_account("工作号")
	check(panel.account_list.get_child_count() == 2 and panel.selected_account() != "default", "new account is listed and opened immediately")
	check(service.accounts.requests.size() == 1 and service.accounts.requests[0][0] == "launch", "adding an account must actually open login")
	var previous_id: String = panel.selected_account()
	panel.account_buttons[0].pressed.emit()
	await process_frame
	check(service.accounts.requests[-1] == ["launch", "default"], "each row switches directly without a dropdown")
	check(panel.selected_account() == "default" and previous_id != "default", "switching refreshes selected account state")
	await coordinator._poll_login()
	check(coordinator._login_timer.is_stopped(), "automatic login recognition stops polling once identified")
	var remove_buttons: Array[Button] = []
	for button in panel.account_buttons:
		if button.get_meta("account_action", "") == "remove":
			remove_buttons.append(button)
	check(remove_buttons.size() == 1 and str(remove_buttons[0].get_meta("account_id")) == previous_id, "Only a saved custom account offers deletion")
	remove_buttons[0].pressed.emit()
	var prompt := panel._prompt_host.get_node_or_null("AntigravityDeletePrompt")
	check(is_instance_valid(prompt) and service.accounts.exists(previous_id), "Deletion opens a confirmation and leaves the account intact")
	var cancel: Button = prompt.find_children("*", "Button", true, false).filter(func(button: Button) -> bool: return button.text == "取消")[0]
	cancel.pressed.emit()
	await process_frame
	check(service.accounts.exists(previous_id), "Cancelling deletion keeps the account")
	# Delete the most recently opened account with an active login-recognition timer.
	await coordinator._account_action("launch", previous_id)
	service.accounts.quotas[previous_id] = {"ok": true, "models": []}
	panel.render(service.view_state())
	panel.set_busy(true)
	for button in panel.account_buttons:
		check(button.disabled, "All account buttons, including deletion, are disabled while busy")
	panel._request_remove(previous_id, "工作号")
	check(panel._prompt_host.get_node_or_null("AntigravityDeletePrompt") == null, "Busy state cannot open a delete prompt")
	panel.set_busy(false)
	for button in panel.account_buttons:
		if button.get_meta("account_action", "") == "remove":
			button.pressed.emit()
	prompt = panel._prompt_host.get_node_or_null("AntigravityDeletePrompt")
	var confirm: Button = prompt.find_children("*", "Button", true, false).filter(func(button: Button) -> bool: return button.text == "删除入口")[0]
	confirm.pressed.emit()
	await process_frame
	check(not service.accounts.exists(previous_id) and not service.accounts.quotas.has(previous_id), "Confirmation removes the account and quota cache")
	check(panel.account_list.get_child_count() == 1 and panel.selected_account() == "default", "Deleting the selected entry refreshes the list and default selection")
	check(coordinator._pending_login_id.is_empty() and coordinator._login_timer.is_stopped(), "Deleted accounts stop automatic login polling")
	check(panel.quota_heading.text == "额度详情" and panel.quota_view.text.contains("额度未知"), "Deleted account quota details are cleared")
	panel.show_quota({"ok": true, "models": [{"name": "Fixture", "remaining": 0, "reset": "2030-01-01T00:00:00Z"}], "checked_at": "fixture"})
	check(panel.quota_rows.get_child_count() == 1 and panel.quota_bars.size() == 1 and panel.quota_bars[0].value == 0 and panel.quota_bars[0].visible, "zero quota has its own row and a real empty progress bar")
	panel.show_quota({"ok": true, "models": [{"name": "Model A", "remaining": 75}, {"name": "Model B", "remaining": 100}, {"name": "Unknown"}]})
	check(panel.quota_rows.get_child_count() == 3 and panel.quota_bars[0].value == 75 and panel.quota_bars[1].value == 100 and not panel.quota_bars[2].visible, "Each model has a separate row; unknown balances have no fake zero bar")
	var bar_id := panel.quota_bars[0].get_instance_id()
	panel.show_quota({"ok": true, "models": [{"name": "Model A", "remaining": 75}, {"name": "Model B", "remaining": 100}, {"name": "Unknown"}]})
	check(panel.quota_bars[0].get_instance_id() == bar_id, "Identical quota response preserves progress controls and scrolling")
	panel.show_quota({"ok": false, "message": "接口未返回额度"})
	check(panel.quota_view.text.contains("额度未知") and not panel.quota_view.text.contains("剩余 0%"), "unknown quota is never rendered as exhausted")
	check(panel.quota_rows.get_child_count() == 0, "Failed queries clear stale model bars")
	var live_state: Dictionary = service.view_state()
	live_state.quota_snapshots = {"default": {"ok": true, "checked_at": "first", "models": [{"name": "Live model", "remaining": 80}]}}
	panel.render(live_state)
	var live_row := panel.account_list.get_child(0).get_instance_id()
	var live_bar := panel.quota_bars[0].get_instance_id()
	var live_style := panel.quota_bars[0].get_theme_stylebox("fill")
	for tick in 30:
		live_state.quota_snapshots.default.checked_at = str(tick)
		live_state.quota_snapshots.default.models[0].remaining = 80 - tick
		panel.render(live_state)
		check(panel.account_list.get_child(0).get_instance_id() == live_row and panel.quota_bars[0].get_instance_id() == live_bar, "Timestamp and balance updates must not rebuild account cards or model rows")
		check(panel.quota_bars[0].get_theme_stylebox("fill") == live_style, "Balance updates within one color range cannot invalidate progress styles")
	check(panel.quota_bars[0].value == 51, "Changed balances still update the existing bar")
	check(panel.quota_view.text.count("上次查询缓存") == 1, "Repeated refresh cannot accumulate cache captions")
	await coordinator._add_account("新的默认号")
	var preferred: String = panel.selected_account()
	for button in panel.account_buttons:
		if button.get_meta("account_action", "") == "set_default" and button.get_meta("account_id", "") == preferred:
			button.pressed.emit()
			break
	check(service.accounts.default_account == preferred, "Set-default UI saves the preferred custom account")
	panel._request_remove("default", "原有账号")
	prompt = panel._prompt_host.get_node_or_null("AntigravityDeletePrompt")
	check(is_instance_valid(prompt), "Original entry can be deleted after choosing a new default")
	prompt.confirmed.emit()
	prompt.queue_free()
	await process_frame
	check(not service.accounts.exists("default") and panel.account_list.get_child_count() == 1, "Deleting the original entry keeps the new default")
	check(panel.launch_button.disabled and panel.disable_button.disabled and not panel.enable_button.disabled, "uninstalled controls reflect actual state")
	var previous_count := service.calls.size()
	await coordinator._on_action_requested("enable")
	await coordinator._on_action_requested("launch")
	check(service.accounts.requests[-1] == ["launch", preferred], "Proxy launch uses the preferred account instead of resurrecting the original entry")
	check(service.calls.size() == previous_count, "offline enable blocked before helper")
	control.online = true
	await coordinator._on_action_requested("enable")
	check(not panel.launch_button.disabled and not panel.disable_button.disabled and panel.choose_button.disabled, "enabled state unlocks launch and recovery")
	check(not bool(service.set_executable(path).get("ok")), "managed install cannot be orphaned by path changes")
	check(panel.endpoint_label.text.contains("39001"), "UI uses configured mixed port")
	panel.render({"installed": true, "running": true})
	check(panel.enable_button.disabled and panel.disable_button.disabled and panel.launch_button.disabled, "running app cannot be modified")
	panel.render({"installed": true, "running": false, "recovery_required": true})
	check(panel.enable_button.disabled and panel.launch_button.disabled and not panel.disable_button.disabled, "interrupted install offers restore only")
	panel.set_busy(true)
	check(panel.refresh_button.disabled and panel.disable_button.disabled, "busy operations cannot be duplicated")
	panel.set_busy(false)
	control.online = false
	await coordinator._on_action_requested("disable")
	check(not service.installed, "offline uninstall remains available")
	coordinator.shutdown()
	previous_count = service.calls.size()
	await coordinator._on_action_requested("disable")
	check(service.calls.size() == previous_count, "shutdown stops new commands")
	check(not bool((await service.perform("unknown")).get("ok")), "invalid action rejected")
	service.dispose()
	reopened.dispose()
	if failures > 0:
		quit(1)
		return
	print("PASS: Antigravity resources, persistent settings, UI states, offline gates and lifecycle")
	quit(0)
