extends SceneTree

const CoreControllerScript = preload("res://scripts/core_controller.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var controller: CoreController = CoreControllerScript.new()
	root.add_child(controller)
	await process_frame
	controller._shutting_down = true # Persistence test: do not start Mihomo.
	if not controller.use_subscription_url("https://one.example/subscription?token=secret"):
		_fail("HTTP 订阅导入失败", 2)
		return
	var http_id := controller.active_subscription_id()
	var v2_link := "hysteria2://password@127.0.0.1:24443?sni=example.com#Library-Test"
	if not controller.use_v2_share_links(v2_link):
		_fail("V2 订阅导入失败", 3)
		return
	var v2_id := controller.active_subscription_id()
	if controller.get_subscriptions().size() != 2 or http_id == v2_id:
		_fail("HTTP 与 V2 订阅未能共存", 4)
		return
	controller.queue_free()
	await process_frame
	controller = CoreControllerScript.new()
	root.add_child(controller)
	await process_frame
	controller._shutting_down = true
	if controller.get_subscriptions().size() != 2 or controller.active_subscription_id() != v2_id:
		_fail("应用重启后订阅库或活动订阅未恢复", 13)
		return
	if not controller.activate_subscription(http_id):
		_fail("HTTP 订阅切换失败", 5)
		return
	var active_yaml := FileAccess.get_file_as_string(controller.profile_path())
	if not active_yaml.contains("one.example") or active_yaml.contains("hysteria2"):
		_fail("切换后 active.yaml 不是 HTTP 订阅", 6)
		return
	if not controller.activate_subscription(v2_id):
		_fail("V2 订阅切换失败", 7)
		return
	active_yaml = FileAccess.get_file_as_string(controller.profile_path())
	if not active_yaml.contains("hexagon-v2"):
		_fail("切换后 active.yaml 不是 V2 配置", 8)
		return
	if not controller.delete_subscription(v2_id):
		_fail("活动 V2 订阅删除失败", 9)
		return
	if controller.get_subscriptions().size() != 1 or controller.active_subscription_id() != http_id:
		_fail("删除活动订阅后未切换到剩余 HTTP 订阅", 10)
		return
	if not controller.delete_subscription(http_id):
		_fail("最后一个订阅删除失败", 11)
		return
	if not controller.get_subscriptions().is_empty() or not FileAccess.get_file_as_string(controller.profile_path()).contains("默认直连配置"):
		_fail("删除全部订阅后未恢复内置直连", 12)
		return
	print("PASS: HTTP/V2 订阅共存、切换、删除与直连回退")
	quit(0)

func _fail(message: String, code: int) -> void:
	printerr("FAIL: %s" % message)
	quit(code)
