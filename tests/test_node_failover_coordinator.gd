extends SceneTree

const CoordinatorScript = preload("res://scripts/app/node_failover_coordinator.gd")

class FakeService:
	signal snapshot_changed(snapshot: Dictionary)
	signal probe_requested(group_name: String)
	signal switch_requested(group_name: String, node_name: String, delay: int)
	var calls: Array[String] = []
	var ticks := 0
	func snapshot() -> Dictionary: return {"enabled": true, "status": "就绪", "backups": []}
	func tick() -> void: ticks += 1
	func set_enabled(value: bool) -> bool:
		calls.append("enabled:%s" % value)
		return true
	func set_backup(group: String, node: String, value: bool) -> bool:
		calls.append("backup:%s:%s:%s" % [group, node, value])
		return true
	func observe_manual_selection(group: String, node: String) -> void:
		calls.append("manual:%s:%s" % [group, node])
	func observe_proxies(_payload: Dictionary) -> void:
		calls.append("proxies")
	func observe_probe_result(group: String, ok: bool, _payload: Variant) -> void:
		calls.append("probe_result:%s:%s" % [group, ok])
	func observe_switch_result(ok: bool, group: String, node: String) -> void:
		calls.append("switch_result:%s:%s:%s" % [ok, group, node])

class FakeMihomo:
	signal api_result(action: String, ok: bool, payload: Variant)
	var online := true
	var probes: Array[String] = []
	var selects: Array[String] = []
	var refreshes := 0
	func test_group_delay(group: String, action := "group_delay") -> void:
		probes.append("%s:%s" % [group, action])
	func select_proxy(group: String, node: String, action := "select_proxy") -> void:
		selects.append("%s:%s:%s" % [group, node, action])
	func refresh_runtime() -> void:
		refreshes += 1
class FakeNodes:
	signal failover_enabled_changed(enabled: bool)
	signal backup_toggle_requested(group_name: String, node_name: String, enabled: bool)
	signal proxy_select_requested(group_name: String, proxy_name: String)
	var snapshots: Array = []
	func set_failover_snapshot(snapshot: Dictionary) -> void:
		snapshots.append(snapshot.duplicate(true))

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var service = FakeService.new()
	var mihomo = FakeMihomo.new()
	var nodes = FakeNodes.new()
	var coordinator = CoordinatorScript.new()
	root.add_child(coordinator)
	coordinator.setup(service, mihomo, nodes)
	coordinator.start()
	if nodes.snapshots.size() != 1:
		_fail("启动时没有同步故障切换快照", 2)
		return
	nodes.failover_enabled_changed.emit(false)
	nodes.backup_toggle_requested.emit("六角选择", "节点B", true)
	nodes.proxy_select_requested.emit("六角选择", "节点A")
	if service.calls.slice(0, 3) != ["enabled:false", "backup:六角选择:节点B:true", "manual:六角选择:节点A"]:
		_fail("节点页意图没有正确路由到 FailoverService", 3)
		return
	service.probe_requested.emit("六角选择")
	if mihomo.probes != ["六角选择:failover_group_delay"]:
		_fail("故障探测没有使用独立 action", 4)
		return
	mihomo.api_result.emit("proxies", true, {"proxies": {}})
	mihomo.api_result.emit("failover_group_delay", true, {"节点A": -1, "节点B": 88})
	if "proxies" not in service.calls or "probe_result:六角选择:true" not in service.calls:
		_fail("Mihomo API 结果没有回到 FailoverService", 5)
		return
	service.switch_requested.emit("六角选择", "节点B", 88)
	if mihomo.selects != ["六角选择:节点B:failover_select"]:
		_fail("自动切换没有使用独立 action", 6)
		return
	mihomo.api_result.emit("failover_select", true, {})
	if "switch_result:true:六角选择:节点B" not in service.calls or mihomo.refreshes != 1:
		_fail("自动切换结果没有回写或成功后未刷新运行态", 7)
		return
	coordinator.shutdown()
	var call_count: int = service.calls.size()
	var probe_count: int = mihomo.probes.size()
	nodes.backup_toggle_requested.emit("六角选择", "节点C", true)
	service.probe_requested.emit("六角选择")
	mihomo.api_result.emit("proxies", true, {})
	if service.calls.size() != call_count or mihomo.probes.size() != probe_count:
		_fail("Coordinator 关闭后仍响应自动故障切换事件", 8)
		return
	print("PASS: NodeFailoverCoordinator 意图路由、独立 API action 与关闭保护")
	quit(0)

func _fail(message: String, code: int) -> void:
	printerr("FAIL: %s" % message)
	quit(code)
