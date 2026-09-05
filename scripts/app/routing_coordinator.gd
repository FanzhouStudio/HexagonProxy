class_name RoutingCoordinator
extends Node

## 应用分流协调器
## 负责 UI 意图、规则快照与运行中自动重启，不让 Panel 直接访问 Service。

var routing_service
var routing_panel
var mihomo_control
var _active := false

func setup(service, panel, control) -> void:
	routing_service = service
	routing_panel = panel
	mihomo_control = control
	routing_panel.application_add_requested.connect(_on_application_add_requested)
	routing_panel.master_enabled_changed.connect(_on_master_enabled_changed)
	routing_panel.rule_target_changed.connect(_on_rule_target_changed)
	routing_panel.rule_enabled_changed.connect(_on_rule_enabled_changed)
	routing_panel.rule_delete_requested.connect(_on_rule_delete_requested)
	routing_service.rules_changed.connect(_refresh_snapshot)
	routing_service.restart_requested.connect(_on_restart_requested)

func start() -> void:
	if _active:
		return
	_active = true
	_refresh_snapshot()

func shutdown() -> void:
	_active = false
func _on_application_add_requested(path: String) -> void:
	if not _active:
		return
	var result: Dictionary = routing_service.add_application(path)
	if not bool(result.get("ok", false)):
		routing_panel.show_message(str(result.get("message", "无法添加应用。")), false)

func _on_master_enabled_changed(enabled: bool) -> void:
	if _active:
		routing_service.set_enabled(enabled)

func _on_rule_target_changed(rule_id: String, target: String) -> void:
	if _active:
		routing_service.set_rule_target(rule_id, target)

func _on_rule_enabled_changed(rule_id: String, enabled: bool) -> void:
	if _active:
		routing_service.set_rule_enabled(rule_id, enabled)

func _on_rule_delete_requested(rule_id: String) -> void:
	if _active:
		routing_service.delete_rule(rule_id)

func _refresh_snapshot() -> void:
	if _active:
		routing_panel.set_snapshot(routing_service.snapshot())

func _on_restart_requested() -> void:
	if not _active:
		return
	if bool(mihomo_control.online) or bool(mihomo_control.starting) or int(mihomo_control.core_pid) > 0:
		mihomo_control.restart()
