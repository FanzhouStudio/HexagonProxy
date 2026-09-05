extends SceneTree

const SubscriptionCoordinatorScript = preload("res://scripts/app/subscription_coordinator.gd")

class FakeService:
	signal subscriptions_changed
	var entries: Array = [{"id": "a", "name": "订阅A"}]
	var active_id := "a"
	var urls: Array[String] = []
	var v2_values: Array[String] = []
	var refreshes := 0
	var activations: Array[String] = []
	var deletions: Array[String] = []
	var local_paths: Array[String] = []
	func get_subscriptions() -> Array: return entries
	func active_subscription_id() -> String: return active_id
	func use_subscription_url(value: String) -> bool:
		urls.append(value)
		return value == "ok"
	func use_v2_share_links(value: String) -> bool:
		v2_values.append(value)
		return value == "ok-v2"
	func update_provider() -> void: refreshes += 1
	func activate_subscription(value: String) -> bool:
		activations.append(value)
		return true
	func delete_subscription(value: String) -> bool:
		deletions.append(value)
		return true
	func import_local_profile(value: String) -> bool:
		local_paths.append(value)
		return true

class FakePanel:
	signal subscription_url_requested(url: String)
	signal v2_import_requested(content: String)
	signal provider_refresh_requested
	signal subscription_activate_requested(entry_id: String)
	signal subscription_delete_requested(entry_id: String)
	signal local_profile_requested(path: String)
	var snapshot_entries: Array = []
	var snapshot_active := ""
	var url_clears := 0
	var v2_clears := 0
	func set_subscriptions(entries: Array, active_id: String) -> void:
		snapshot_entries = entries.duplicate(true)
		snapshot_active = active_id
	func clear_subscription_input() -> void: url_clears += 1
	func clear_v2_input() -> void: v2_clears += 1

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var service = FakeService.new()
	var panel = FakePanel.new()
	var coordinator = SubscriptionCoordinatorScript.new()
	root.add_child(coordinator)
	coordinator.setup(service, panel)
	coordinator.start()
	if panel.snapshot_entries.size() != 1 or panel.snapshot_active != "a":
		_fail("启动时没有同步订阅快照", 2)
		return
	panel.subscription_url_requested.emit("bad")
	panel.subscription_url_requested.emit("ok")
	panel.v2_import_requested.emit("bad-v2")
	panel.v2_import_requested.emit("ok-v2")
	if service.urls != ["bad", "ok"] or panel.url_clears != 1:
		_fail("HTTP 订阅意图或成功回执不正确", 3)
		return
	if service.v2_values != ["bad-v2", "ok-v2"] or panel.v2_clears != 1:
		_fail("V2 订阅意图或成功回执不正确", 4)
		return
	panel.provider_refresh_requested.emit()
	panel.subscription_activate_requested.emit("b")
	panel.subscription_delete_requested.emit("c")
	panel.local_profile_requested.emit("C:/test.yaml")
	if service.refreshes != 1 or service.activations != ["b"] or service.deletions != ["c"] or service.local_paths != ["C:/test.yaml"]:
		_fail("订阅操作没有通过协调器路由", 5)
		return
	service.entries = [{"id": "b", "name": "订阅B"}]
	service.active_id = "b"
	service.subscriptions_changed.emit()
	if panel.snapshot_active != "b" or str(panel.snapshot_entries[0].get("id", "")) != "b":
		_fail("订阅变更后没有刷新快照", 6)
		return
	coordinator.shutdown()
	var refreshes_before_shutdown: int = int(service.refreshes)
	panel.provider_refresh_requested.emit()
	if service.refreshes != refreshes_before_shutdown:
		_fail("协调器关闭后仍响应订阅意图", 7)
		return
	print("PASS: SubscriptionCoordinator 意图路由、快照同步与关闭保护")
	quit(0)

func _fail(message: String, code: int) -> void:
	printerr("FAIL: %s" % message)
	quit(code)