class_name NodeFailoverService
extends Node

## 节点自动故障切换状态机
## 消费 Mihomo 运行快照/延迟结果，输出探测与切换意图。

signal snapshot_changed(snapshot: Dictionary)
signal probe_requested(group_name: String)
signal switch_requested(group_name: String, node_name: String, delay: int)
signal event_logged(message: String)

const StoreScript = preload("res://scripts/modules/reliability/node_failover_store.gd")
const PolicyScript = preload("res://scripts/modules/reliability/node_failover_policy.gd")

var store
var policy
var enabled := true
var settings: Dictionary = {}
var backups: Array = []
var route_group := ""
var current_node := ""
var latest_delays: Dictionary = {}
var _failure_count := 0
var _attempted: Dictionary = {}
var _switch_pending := false
var _cooldown_until_msec := 0
var _circuit_open := false
var _circuit_opened_msec := 0
var _last_probe_msec := 0
var _status := "等待节点数据"
var _initialized := false
func initialize() -> void:
	if _initialized:
		return
	_initialized = true
	store = StoreScript.new()
	policy = PolicyScript.new()
	var state: Dictionary = store.load_state()
	enabled = bool(state.get("enabled", true))
	settings = state.get("settings", {}).duplicate(true)
	backups = state.get("backups", []).duplicate(true)
	_emit_snapshot()

func snapshot() -> Dictionary:
	return {
		"enabled": enabled,
		"settings": settings.duplicate(true),
		"backups": backups.duplicate(true),
		"route_group": route_group,
		"current_node": current_node,
		"delays": latest_delays.duplicate(true),
		"failure_count": _failure_count,
		"attempted": _attempted.keys(),
		"switch_pending": _switch_pending,
		"circuit_open": _circuit_open,
		"status": _status
	}

func set_enabled(value: bool) -> bool:
	initialize()
	if enabled == value:
		return true
	enabled = value
	_reset_outage("守护已启用" if enabled else "守护已关闭")
	return _save_and_emit()
func set_backup(group_name: String, node_name: String, value: bool) -> bool:
	initialize()
	var group := group_name.strip_edges()
	var node := node_name.strip_edges()
	if group.is_empty() or node.is_empty():
		return false
	var found := -1
	for index in backups.size():
		var item: Dictionary = backups[index]
		if str(item.get("group", "")) == group and str(item.get("node", "")) == node:
			found = index
			break
	if value and found < 0:
		backups.append({"group": group, "node": node})
	elif not value and found >= 0:
		backups.remove_at(found)
	else:
		return true
	_attempted.erase(node)
	return _save_and_emit()

func is_backup(group_name: String, node_name: String) -> bool:
	for item in backups:
		if item is Dictionary and str(item.get("group", "")) == group_name and str(item.get("node", "")) == node_name:
			return true
	return false
func observe_proxies(payload: Dictionary) -> void:
	initialize()
	var proxy_map_value: Variant = payload.get("proxies", {})
	var proxy_map: Dictionary = proxy_map_value if proxy_map_value is Dictionary else {}
	var group_name := _resolve_route_group(proxy_map)
	if group_name.is_empty():
		route_group = ""
		current_node = ""
		_status = "未找到可守护的选择组"
		_emit_snapshot()
		return
	var group_value: Variant = proxy_map.get(group_name, {})
	var group: Dictionary = group_value if group_value is Dictionary else {}
	var next_node := str(group.get("now", ""))
	if route_group != group_name:
		route_group = group_name
		_reset_outage("守护组：%s" % route_group)
	if not next_node.is_empty() and current_node != next_node:
		current_node = next_node
		_status = "当前节点：%s" % current_node
	_emit_snapshot()

func observe_manual_selection(group_name: String, node_name: String) -> void:
	if group_name == route_group and not node_name.is_empty():
		current_node = node_name
		_reset_outage("已手动切换：%s" % node_name)
func tick(now_msec := -1) -> void:
	initialize()
	if not enabled or route_group.is_empty() or current_node.is_empty() or _switch_pending:
		return
	if not _has_backups_for_route_group():
		return
	var now := Time.get_ticks_msec() if now_msec < 0 else now_msec
	var interval_ms := int(settings.get("probe_interval_sec", 10)) * 1000
	if now - _last_probe_msec < interval_ms:
		return
	_last_probe_msec = now
	probe_requested.emit(route_group)

func observe_probe_result(group_name: String, ok: bool, payload: Variant, now_msec := -1) -> void:
	initialize()
	if not enabled or group_name != route_group:
		return
	var now := Time.get_ticks_msec() if now_msec < 0 else now_msec
	latest_delays.clear()
	if ok and payload is Dictionary:
		for key in payload:
			latest_delays[str(key)] = int(payload[key])
	var current_delay := int(latest_delays.get(current_node, -1))
	var max_delay := int(settings.get("max_delay_ms", 5000))
	if current_delay > 0 and current_delay <= max_delay:
		_reset_outage("当前节点健康 · %d ms" % current_delay)
		return
	_failure_count += 1
	_status = "当前节点探测失败 %d/%d" % [_failure_count, int(settings.get("failure_threshold", 2))]
	_emit_snapshot()
	if _failure_count >= int(settings.get("failure_threshold", 2)):
		_evaluate_failover(now)
func observe_switch_result(ok: bool, group_name: String, node_name: String) -> void:
	if group_name != route_group:
		return
	_switch_pending = false
	if ok:
		current_node = node_name
		_status = "已切换到备选：%s，等待健康确认" % node_name
		event_logged.emit("当前节点异常，已自动切换到备选节点：%s。" % node_name)
	else:
		_status = "切换 %s 失败，等待下一次探测" % node_name
		event_logged.emit("自动切换备选节点失败：%s。" % node_name)
	_emit_snapshot()

func _evaluate_failover(now_msec: int) -> void:
	if _switch_pending or now_msec < _cooldown_until_msec:
		return
	if _circuit_open:
		var reset_ms := int(settings.get("circuit_reset_sec", 60)) * 1000
		if now_msec - _circuit_opened_msec < reset_ms:
			return
		var recovered: Dictionary = policy.choose_best(route_group, backups, latest_delays, current_node, {}, int(settings.get("max_delay_ms", 5000)))
		if str(recovered.get("node", "")).is_empty():
			return
		_attempted.clear()
		_circuit_open = false
		_status = "检测到备选恢复，重新允许故障切换"
	var candidate: Dictionary = policy.choose_best(route_group, backups, latest_delays, current_node, _attempted, int(settings.get("max_delay_ms", 5000)))
	var node_name := str(candidate.get("node", ""))
	if node_name.is_empty():
		_open_circuit(now_msec)
		return
	_attempted[node_name] = true
	_switch_pending = true
	_cooldown_until_msec = now_msec + int(settings.get("cooldown_sec", 30)) * 1000
	_status = "正在切换：%s · %d ms" % [node_name, int(candidate.get("delay", -1))]
	_emit_snapshot()
	switch_requested.emit(route_group, node_name, int(candidate.get("delay", -1)))
func _open_circuit(now_msec: int) -> void:
	if not _circuit_open:
		event_logged.emit("备选节点当前全部不可用，自动切换已熔断；将继续探测但不会循环切换。")
	_circuit_open = true
	_circuit_opened_msec = now_msec
	_switch_pending = false
	_status = "备选全部不可用 · 已熔断"
	_emit_snapshot()

func _resolve_route_group(proxy_map: Dictionary) -> String:
	if proxy_map.has("六角选择"):
		var preferred: Variant = proxy_map["六角选择"]
		if preferred is Dictionary and str(preferred.get("type", "")) == "Selector":
			return "六角选择"
	if not route_group.is_empty() and proxy_map.has(route_group):
		var existing: Variant = proxy_map[route_group]
		if existing is Dictionary and str(existing.get("type", "")) == "Selector":
			return route_group
	for name in proxy_map:
		var data: Variant = proxy_map[name]
		if data is Dictionary and str(data.get("type", "")) == "Selector":
			return str(name)
	return ""

func _has_backups_for_route_group() -> bool:
	for item in backups:
		if item is Dictionary and str(item.get("group", "")) == route_group:
			return true
	return false

func _reset_outage(message: String) -> void:
	_failure_count = 0
	_attempted.clear()
	_switch_pending = false
	_cooldown_until_msec = 0
	_circuit_open = false
	_circuit_opened_msec = 0
	_status = message
	_emit_snapshot()
func _save_and_emit() -> bool:
	var ok: bool = store.save_state({
		"enabled": enabled,
		"settings": settings,
		"backups": backups
	})
	if ok:
		_emit_snapshot()
	else:
		event_logged.emit("无法保存节点故障切换设置。")
	return ok

func _emit_snapshot() -> void:
	snapshot_changed.emit(snapshot())

func dispose() -> void:
	_switch_pending = false
	_attempted.clear()
