class_name NodeFailoverCoordinator
extends Node

## 节点故障切换协调器
## 连接 FailoverService、MihomoControl 与 NodesPanel，不承载选路算法。

var failover_service
var mihomo_control
var nodes_panel
var _active := false
var _timer: Timer
var _pending_probe_group := ""
var _pending_switch_group := ""
var _pending_switch_node := ""

func setup(service, control, nodes) -> void:
	failover_service = service
	mihomo_control = control
	nodes_panel = nodes
	failover_service.snapshot_changed.connect(_on_snapshot_changed)
	failover_service.probe_requested.connect(_on_probe_requested)
	failover_service.switch_requested.connect(_on_switch_requested)
	nodes_panel.failover_enabled_changed.connect(_on_enabled_changed)
	nodes_panel.backup_toggle_requested.connect(_on_backup_toggle_requested)
	nodes_panel.proxy_select_requested.connect(_on_manual_proxy_selected)
	mihomo_control.api_result.connect(_on_api_result)
func start() -> void:
	if _active:
		return
	_active = true
	_timer = Timer.new()
	_timer.wait_time = 1.0
	_timer.autostart = true
	_timer.timeout.connect(_on_tick)
	add_child(_timer)
	nodes_panel.set_failover_snapshot(failover_service.snapshot())

func shutdown() -> void:
	_active = false
	if is_instance_valid(_timer):
		_timer.stop()

func _on_tick() -> void:
	if _active and bool(mihomo_control.online):
		failover_service.tick()

func _on_snapshot_changed(snapshot: Dictionary) -> void:
	if _active:
		nodes_panel.set_failover_snapshot(snapshot)

func _on_enabled_changed(enabled: bool) -> void:
	if _active:
		failover_service.set_enabled(enabled)
func _on_backup_toggle_requested(group_name: String, node_name: String, enabled: bool) -> void:
	if _active:
		failover_service.set_backup(group_name, node_name, enabled)

func _on_manual_proxy_selected(group_name: String, node_name: String) -> void:
	if _active:
		failover_service.observe_manual_selection(group_name, node_name)

func _on_probe_requested(group_name: String) -> void:
	if not _active or not bool(mihomo_control.online):
		return
	_pending_probe_group = group_name
	mihomo_control.test_group_delay(group_name, "failover_group_delay")

func _on_switch_requested(group_name: String, node_name: String, _delay: int) -> void:
	if not _active or not bool(mihomo_control.online):
		return
	_pending_switch_group = group_name
	_pending_switch_node = node_name
	mihomo_control.select_proxy(group_name, node_name, "failover_select")
func _on_api_result(action: String, ok: bool, payload: Variant) -> void:
	if not _active:
		return
	if action == "proxies" and ok and payload is Dictionary:
		failover_service.observe_proxies(payload)
		return
	if action == "failover_group_delay":
		failover_service.observe_probe_result(_pending_probe_group, ok, payload)
		_pending_probe_group = ""
		return
	if action == "failover_select":
		failover_service.observe_switch_result(ok, _pending_switch_group, _pending_switch_node)
		if ok:
			mihomo_control.refresh_runtime()
		_pending_switch_group = ""
		_pending_switch_node = ""
