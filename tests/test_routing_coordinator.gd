extends SceneTree

const RoutingCoordinatorScript = preload("res://scripts/app/routing_coordinator.gd")

class FakeService:
	signal rules_changed
	signal restart_requested
	var enabled := true
	var rules: Array = []
	var added: Array[String] = []
	var target_changes: Array[String] = []
	var enabled_changes: Array[String] = []
	var deleted: Array[String] = []
	func snapshot() -> Dictionary:
		return {"enabled": enabled, "rules": rules.duplicate(true), "targets": [{"id":"proxy","label":"走代理"},{"id":"direct","label":"直连"}]}
	func add_application(path: String) -> Dictionary:
		added.append(path)
		return {"ok": true}
	func set_enabled(value: bool) -> bool:
		enabled = value
		return true
	func set_rule_target(id: String, target: String) -> bool:
		target_changes.append(id + ":" + target)
		return true
	func set_rule_enabled(id: String, value: bool) -> bool:
		enabled_changes.append(id + ":" + str(value))
		return true
	func delete_rule(id: String) -> bool:
		deleted.append(id)
		return true

class FakePanel:
	signal application_add_requested(path: String)
	signal master_enabled_changed(enabled: bool)
	signal rule_target_changed(rule_id: String, target: String)
	signal rule_enabled_changed(rule_id: String, enabled: bool)
	signal rule_delete_requested(rule_id: String)
	var snapshots := 0
	var messages: Array[String] = []
	func set_snapshot(_snapshot: Dictionary) -> void: snapshots += 1
	func show_message(message: String, _success: bool) -> void: messages.append(message)

class FakeControl:
	var online := false
	var starting := false
	var core_pid := -1
	var restarts := 0
	func restart() -> void: restarts += 1

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var service = FakeService.new()
	var panel = FakePanel.new()
	var control = FakeControl.new()
	var coordinator = RoutingCoordinatorScript.new()
	root.add_child(coordinator)
	coordinator.setup(service, panel, control)
	coordinator.start()
	if panel.snapshots != 1:
		_fail("启动时没有同步应用分流快照", 2)
		return
	panel.application_add_requested.emit("C:/Apps/Game.exe")
	panel.master_enabled_changed.emit(false)
	panel.rule_target_changed.emit("r1", "direct")
	panel.rule_enabled_changed.emit("r1", false)
	panel.rule_delete_requested.emit("r1")
	if service.added != ["C:/Apps/Game.exe"] or service.enabled:
		_fail("添加应用或总开关意图路由失败", 3)
		return
	if service.target_changes != ["r1:direct"] or service.enabled_changes != ["r1:false"] or service.deleted != ["r1"]:
		_fail("规则编辑意图没有路由到 Service", 4)
		return
	service.rules_changed.emit()
	if panel.snapshots != 2:
		_fail("规则变化后没有刷新快照", 5)
		return
	service.restart_requested.emit()
	if control.restarts != 0:
		_fail("离线状态不应为了规则变更重启内核", 6)
		return
	control.online = true
	service.restart_requested.emit()
	if control.restarts != 1:
		_fail("在线状态规则变更没有重启内核", 7)
		return
	coordinator.shutdown()
	panel.application_add_requested.emit("C:/Apps/After.exe")
	service.rules_changed.emit()
	service.restart_requested.emit()
	if service.added.size() != 1 or panel.snapshots != 2 or control.restarts != 1:
		_fail("协调器关闭后仍响应分流事件", 8)
		return
	print("PASS: RoutingCoordinator 分流意图、快照、运行中重启与关闭保护")
	quit(0)

func _fail(message: String, code: int) -> void:
	printerr("FAIL: %s" % message)
	quit(code)
