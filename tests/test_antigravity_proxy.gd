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
	check(panel.quota_view.text.contains("剩余 0%"), "zero quota is displayed as a real exhausted balance")
	panel.show_quota({"ok": false, "message": "接口未返回额度"})
	check(panel.quota_view.text.contains("额度未知") and not panel.quota_view.text.contains("剩余 0%"), "unknown quota is never rendered as exhausted")
	check(panel.launch_button.disabled and panel.disable_button.disabled and not panel.enable_button.disabled, "uninstalled controls reflect actual state")
	var previous_count := service.calls.size()
	await coordinator._on_action_requested("enable")
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
