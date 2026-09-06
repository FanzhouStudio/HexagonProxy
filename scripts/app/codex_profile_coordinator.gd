class_name CodexProfileCoordinator
extends Node

var service
var panel: CodexAccountsPanel
var _active := false

func setup(profile_service, accounts_panel: CodexAccountsPanel) -> void:
	service = profile_service
	panel = accounts_panel
	panel.create_profile_requested.connect(_on_create_requested)
	panel.switch_profile_requested.connect(_on_switch_requested)
	panel.forget_profile_requested.connect(_on_forget_requested)
	panel.refresh_requested.connect(_on_refresh_requested)
	panel.launch_requested.connect(_on_launch_requested)

func start() -> void:
	_active = true
	_refresh_view()

func shutdown() -> void:
	_active = false

func _on_create_requested(display_name: String) -> void:
	if not _active:
		return
	panel.set_busy(true)
	var result: Dictionary = service.create_profile(display_name)
	panel.set_busy(false)
	panel.show_message(
		str(result.get("message", "创建账号配置失败。")),
		bool(result.get("ok", false))
	)
	if bool(result.get("ok", false)):
		panel.clear_profile_name()
	_refresh_view()

func _on_switch_requested(profile_id: String) -> void:
	if not _active:
		return
	panel.set_busy(true)
	var result: Dictionary = service.switch_profile(profile_id)
	panel.set_busy(false)
	panel.show_message(
		str(result.get("message", "切换 Codex 账号失败。")),
		bool(result.get("ok", false))
	)
	_refresh_view()

func _on_forget_requested(profile_id: String) -> void:
	if not _active:
		return
	var result: Dictionary = service.forget_profile(profile_id)
	panel.show_message(
		str(result.get("message", "移除账号配置失败。")),
		bool(result.get("ok", false))
	)
	_refresh_view()

func _on_refresh_requested() -> void:
	if _active:
		_refresh_view()

func _on_launch_requested() -> void:
	if not _active:
		return
	panel.set_busy(true)
	var result: Dictionary = service.launch_selected()
	panel.set_busy(false)
	panel.show_message(
		str(result.get("message", "启动 Codex 失败。")),
		bool(result.get("ok", false))
	)
	_refresh_view()

func _refresh_view() -> void:
	if not _active:
		return
	var state: Dictionary = service.refresh_status()
	panel.render(state, service.profiles())
