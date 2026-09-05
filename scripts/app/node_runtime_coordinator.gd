class_name NodeRuntimeCoordinator
extends Node

## 节点与 Mihomo 运行数据协调器
## 负责节点操作、API 结果分发和周期轮询。

var mihomo_control
var dashboard_panel
var nodes_panel
var resident
var _active := false
var _refresh_tick := 0
var _poll_timer: Timer

func setup(control, dashboard, nodes, resident_controller) -> void:
	mihomo_control = control
	dashboard_panel = dashboard
	nodes_panel = nodes
	resident = resident_controller
	dashboard_panel.mode_requested.connect(_on_mode_requested)
	nodes_panel.node_status_changed.connect(_on_node_status_changed)
	nodes_panel.proxy_select_requested.connect(_on_proxy_select_requested)
	nodes_panel.proxy_delay_requested.connect(_on_proxy_delay_requested)
	nodes_panel.group_delay_requested.connect(_on_group_delay_requested)
	nodes_panel.global_group_requested.connect(_on_global_group_requested)
	nodes_panel.runtime_refresh_requested.connect(_on_runtime_refresh_requested)
	mihomo_control.state_changed.connect(_on_mihomo_state_changed)
	mihomo_control.api_result.connect(_on_api_result)

func start() -> void:
	if _active:
		return
	_active = true
	_poll_timer = Timer.new()
	_poll_timer.wait_time = 1.0
	_poll_timer.autostart = true
	_poll_timer.timeout.connect(_on_poll_timer)
	add_child(_poll_timer)
	_update_resident_node_status()

func shutdown() -> void:
	_active = false
	if is_instance_valid(_poll_timer):
		_poll_timer.stop()

func _on_mihomo_state_changed(is_online: bool, _starting: bool, _core_pid: int, _message: String) -> void:
	if not _active:
		return
	if is_online:
		mihomo_control.refresh_runtime()
	_update_resident_node_status()

func _on_poll_timer() -> void:
	if not _active:
		return
	_refresh_tick += 1
	if mihomo_control.online:
		if _refresh_tick % 2 == 0:
			mihomo_control.refresh_runtime()
		if _refresh_tick % 5 == 0:
			mihomo_control.poll_status()
		if _refresh_tick % 10 == 0:
			var group: Dictionary = nodes_panel.selected_group()
			if not group.is_empty():
				mihomo_control.test_group_delay(str(group.get("name", "")))
	else:
		dashboard_panel.push_zero_sample()
		if mihomo_control.starting or mihomo_control.core_pid > 0:
			mihomo_control.poll_status()

func _on_api_result(action: String, ok: bool, payload: Variant) -> void:
	if not _active:
		return
	if nodes_panel.handle_api_result(action, ok, payload):
		return
	if not ok:
		return
	if action == "connections" and payload is Dictionary:
		dashboard_panel.apply_connections(payload)
	elif action == "config" and payload is Dictionary:
		var mode := str(payload.get("mode", "rule")).to_lower()
		nodes_panel.set_global_mode_active(mode == "global")
		dashboard_panel.set_mode(mode)
	elif action in ["update_provider", "set_mode"]:
		mihomo_control.refresh_runtime()

func _on_node_status_changed(node_name: String, delay: int) -> void:
	if _active and resident:
		resident.set_node_status(node_name, delay, bool(mihomo_control.online))

func _on_proxy_select_requested(group_name: String, proxy_name: String) -> void:
	if _active:
		mihomo_control.select_proxy(group_name, proxy_name)

func _on_proxy_delay_requested(proxy_name: String) -> void:
	if _active:
		mihomo_control.test_proxy_delay(proxy_name)

func _on_group_delay_requested(group_name: String) -> void:
	if _active:
		mihomo_control.test_group_delay(group_name)

func _on_global_group_requested(group_name: String) -> void:
	if _active:
		mihomo_control.set_mode("global", group_name)

func _on_runtime_refresh_requested() -> void:
	if _active:
		mihomo_control.refresh_runtime()

func _on_mode_requested(mode: String) -> void:
	if not _active:
		return
	nodes_panel.set_global_mode_active(mode == "global")
	var group_name := str(nodes_panel.selected_group().get("name", "六角选择"))
	mihomo_control.set_mode(mode, group_name)

func _update_resident_node_status() -> void:
	if resident:
		resident.set_node_status(
			nodes_panel.current_node_name(),
			nodes_panel.current_delay(),
			bool(mihomo_control.online)
		)