extends SceneTree

const FailoverServiceScript = preload("res://scripts/modules/reliability/node_failover_service.gd")

var service
var switches: Array[String] = []
var probes: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var storage := ProjectSettings.globalize_path("user://node_failover.json")
	if FileAccess.file_exists(storage):
		DirAccess.remove_absolute(storage)
	service = FailoverServiceScript.new()
	root.add_child(service)
	service.initialize()
	service.switch_requested.connect(func(group: String, node: String, delay: int) -> void:
		switches.append("%s/%s/%d" % [group, node, delay]))
	service.probe_requested.connect(func(group: String) -> void: probes.append(group))
	service.settings["failure_threshold"] = 2
	service.settings["cooldown_sec"] = 30
	service.settings["circuit_reset_sec"] = 60
	service.observe_proxies(_proxy_snapshot("节点A"))
	service.tick(10000)
	if not probes.is_empty():
		_fail("未配置备选节点时仍发起了自动健康探测", 11)
		return
	service.set_backup("六角选择", "节点B", true)
	service.set_backup("六角选择", "节点C", true)
	service.observe_probe_result("六角选择", true, {"节点A": -1, "节点B": 80, "节点C": 120}, 1000)
	if not switches.is_empty():
		_fail("单次探测失败就触发了切换", 2)
		return
	service.observe_probe_result("六角选择", true, {"节点A": -1, "节点B": 80, "节点C": 120}, 11000)
	if switches != ["六角选择/节点B/80"]:
		_fail("没有选择延迟最低的可用备选节点", 3)
		return
	service.observe_switch_result(true, "六角选择", "节点B")
	service.observe_probe_result("六角选择", true, {"节点A": -1, "节点B": -1, "节点C": 90}, 22000)
	if switches.size() != 1:
		_fail("冷却期间发生了二次切换", 4)
		return
	service.observe_probe_result("六角选择", true, {"节点A": -1, "节点B": -1, "节点C": 90}, 42000)
	if switches.size() != 2 or not switches[1].contains("节点C/90"):
		_fail("冷却结束后没有切到下一可用备选", 5)
		return
	service.observe_switch_result(true, "六角选择", "节点C")
	service.observe_probe_result("六角选择", true, {"节点A": -1, "节点B": -1, "节点C": -1}, 73000)
	if not bool(service.snapshot().get("circuit_open", false)):
		_fail("备选全部不可用时没有进入熔断", 6)
		return
	var switch_count: int = switches.size()
	for now in [83000, 93000, 103000, 113000, 123000, 133000]:
		service.observe_probe_result("六角选择", true, {"节点A": -1, "节点B": -1, "节点C": -1}, now)
	if switches.size() != switch_count:
		_fail("熔断期间发生了循环切换", 7)
		return
	service.observe_probe_result("六角选择", true, {"节点A": -1, "节点B": 70, "节点C": -1}, 140000)
	if switches.size() != switch_count + 1 or not switches.back().contains("节点B/70"):
		_fail("熔断恢复后没有重新选择已恢复的最低延迟节点", 8)
		return
	service.observe_switch_result(true, "六角选择", "节点B")
	service.observe_probe_result("六角选择", true, {"节点A": -1, "节点B": 65, "节点C": -1}, 151000)
	var healthy: Dictionary = service.snapshot()
	if int(healthy.get("failure_count", -1)) != 0 or bool(healthy.get("circuit_open", true)) or not (healthy.get("attempted", []) as Array).is_empty():
		_fail("节点恢复健康后没有清空故障周期", 9)
		return
	var second = FailoverServiceScript.new()
	root.add_child(second)
	second.initialize()
	var persisted: Array = second.snapshot().get("backups", [])
	if persisted.size() != 2:
		_fail("备选组没有持久化", 10)
		return
	print("PASS: 节点故障切换最低延迟、冷却、熔断、恢复与持久化")
	quit(0)

func _proxy_snapshot(now_node: String) -> Dictionary:
	return {"proxies": {
		"六角选择": {
			"type": "Selector",
			"now": now_node,
			"all": ["节点A", "节点B", "节点C"]
		}
	}}

func _fail(message: String, code: int) -> void:
	printerr("FAIL: %s" % message)
	quit(code)
