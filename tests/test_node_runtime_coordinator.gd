extends SceneTree

const NodeRuntimeCoordinatorScript = preload("res://scripts/app/node_runtime_coordinator.gd")

class FakeMihomo:
	signal state_changed(online: bool, starting: bool, core_pid: int, message: String)
	signal api_result(action: String, ok: bool, payload: Variant)
	var online := false
	var starting := false
	var core_pid := -1
	var refreshes := 0
	var polls := 0
	var modes: Array[String] = []
	var selected: Array[String] = []
	var tested_proxies: Array[String] = []
	var tested_groups: Array[String] = []
	func refresh_runtime() -> void: refreshes += 1
	func poll_status() -> void: polls += 1
	func select_proxy(group_name: String, proxy_name: String) -> void: selected.append(group_name + "/" + proxy_name)
	func test_proxy_delay(proxy_name: String) -> void: tested_proxies.append(proxy_name)
	func test_group_delay(group_name: String) -> void: tested_groups.append(group_name)
	func set_mode(mode: String, _group := "") -> void: modes.append(mode)
class FakeDashboard:
	signal mode_requested(mode: String)
	var zero_samples := 0
	var applied_connections := 0
	var last_mode := ""
	func push_zero_sample() -> void: zero_samples += 1
	func apply_connections(_payload: Dictionary) -> void: applied_connections += 1
	func set_mode(mode: String) -> void: last_mode = mode

class FakeNodes:
	signal node_status_changed(node_name: String, delay: int)
	signal proxy_select_requested(group_name: String, proxy_name: String)
	signal proxy_delay_requested(proxy_name: String)
	signal group_delay_requested(group_name: String)
	signal global_group_requested(group_name: String)
	signal runtime_refresh_requested
	var global_mode := false
	var handled_actions: Array[String] = []
	func selected_group() -> Dictionary: return {"name": "六角选择"}
	func current_node_name() -> String: return "测试节点"
	func current_delay() -> int: return 42
	func handle_api_result(action: String, _ok: bool, _payload: Variant) -> bool:
		handled_actions.append(action)
		return false
	func set_global_mode_active(value: bool) -> void: global_mode = value
class FakeResident:
	var node_name := ""
	var delay := 0
	var online := false
	func set_node_status(value_name: String, value_delay: int, value_online: bool) -> void:
		node_name = value_name
		delay = value_delay
		online = value_online

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var mihomo = FakeMihomo.new()
	var dashboard = FakeDashboard.new()
	var nodes = FakeNodes.new()
	var resident = FakeResident.new()
	var coordinator = NodeRuntimeCoordinatorScript.new()
	root.add_child(coordinator)
	coordinator.setup(mihomo, dashboard, nodes, resident)
	coordinator.start()
	if resident.node_name != "测试节点" or resident.delay != 42 or resident.online:
		_fail("启动时节点快照没有同步到驻留 UI", 2)
		return
	nodes.proxy_select_requested.emit("六角选择", "节点A")
	nodes.proxy_delay_requested.emit("节点A")
	nodes.group_delay_requested.emit("六角选择")
	nodes.global_group_requested.emit("六角选择")
	nodes.runtime_refresh_requested.emit()
	dashboard.mode_requested.emit("global")
	if "六角选择/节点A" not in mihomo.selected or "节点A" not in mihomo.tested_proxies or "六角选择" not in mihomo.tested_groups:
		_fail("节点操作没有通过 NodeRuntimeCoordinator 路由", 3)
		return
	if mihomo.modes.size() < 2 or mihomo.modes.back() != "global" or not nodes.global_mode:
		_fail("代理模式没有通过 NodeRuntimeCoordinator 协调", 4)
		return

	mihomo.online = true
	mihomo.state_changed.emit(true, false, 1234, "在线")
	if not resident.online or mihomo.refreshes < 2:
		_fail("Mihomo 上线后没有同步节点状态或刷新运行数据", 5)
		return
	mihomo.api_result.emit("connections", true, {})
	mihomo.api_result.emit("config", true, {"mode": "global"})
	if dashboard.applied_connections != 1 or dashboard.last_mode != "global" or not nodes.global_mode:
		_fail("API 结果没有正确分发到节点和仪表盘", 6)
		return
	var refreshes_before_poll: int = mihomo.refreshes
	var polls_before: int = mihomo.polls
	var groups_before: int = mihomo.tested_groups.size()
	for _i in range(10):
		coordinator._on_poll_timer()
	if mihomo.refreshes != refreshes_before_poll + 5 or mihomo.polls != polls_before + 2 or mihomo.tested_groups.size() != groups_before + 1:
		_fail("周期轮询节奏与节点延迟测试不正确", 7)
		return

	coordinator.shutdown()
	var refreshes_before_shutdown: int = mihomo.refreshes
	var modes_before_shutdown: int = mihomo.modes.size()
	nodes.runtime_refresh_requested.emit()
	dashboard.mode_requested.emit("rule")
	mihomo.state_changed.emit(true, false, 1234, "关闭后")
	if mihomo.refreshes != refreshes_before_shutdown or mihomo.modes.size() != modes_before_shutdown:
		_fail("NodeRuntimeCoordinator 关闭后仍响应运行时事件", 8)
		return
	print("PASS: NodeRuntimeCoordinator 节点意图、API 分发、轮询与关闭保护")
	quit(0)

func _fail(message: String, code: int) -> void:
	printerr("FAIL: %s" % message)
	quit(code)
