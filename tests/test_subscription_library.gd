extends SceneTree

const SubscriptionServiceScript = preload("res://scripts/modules/subscription/subscription_service.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var subscription = SubscriptionServiceScript.new()
	root.add_child(subscription)
	await process_frame
	subscription.initialize()
	if not subscription.use_subscription_url("https://one.example/subscription?token=secret"):
		_fail("HTTP 订阅导入失败", 2)
		return
	var http_id: String = subscription.active_subscription_id()
	var v2_link := "hysteria2://password@127.0.0.1:24443?sni=example.com#Library-Test"
	if not subscription.use_v2_share_links(v2_link):
		_fail("V2 订阅导入失败", 3)
		return
	var v2_id: String = subscription.active_subscription_id()
	if subscription.get_subscriptions().size() != 2 or http_id == v2_id:
		_fail("HTTP 与 V2 订阅未能共存", 4)
		return
	subscription.queue_free()
	await process_frame
	subscription = SubscriptionServiceScript.new()
	root.add_child(subscription)
	await process_frame
	subscription.initialize()
	if subscription.get_subscriptions().size() != 2 or subscription.active_subscription_id() != v2_id:
		_fail("应用重启后订阅库或活动订阅未恢复", 13)
		return
	if not subscription.use_subscription_url("https://unused.example/subscription"):
		_fail("用于非活动删除测试的订阅导入失败", 14)
		return
	var unused_id: String = subscription.active_subscription_id()
	if not subscription.activate_subscription(v2_id):
		_fail("非活动删除测试无法恢复 V2 活动项", 15)
		return
	if not subscription.delete_subscription(unused_id):
		_fail("非活动订阅删除失败", 16)
		return
	if subscription.active_subscription_id() != v2_id or subscription.current_profile_name.find("V2 分享链接") < 0:
		_fail("删除非活动订阅错误地改变了活动状态", 17)
		return
	if not FileAccess.get_file_as_string(subscription.profile_path()).contains("hexagon-v2"):
		_fail("删除非活动订阅错误地覆盖了 active.yaml", 18)
		return
	if not subscription.activate_subscription(http_id):
		_fail("HTTP 订阅切换失败", 5)
		return
	var active_yaml := FileAccess.get_file_as_string(subscription.profile_path())
	if not active_yaml.contains("one.example") or active_yaml.contains("hysteria2"):
		_fail("切换后 active.yaml 不是 HTTP 订阅", 6)
		return
	if not subscription.activate_subscription(v2_id):
		_fail("V2 订阅切换失败", 7)
		return
	active_yaml = FileAccess.get_file_as_string(subscription.profile_path())
	if not active_yaml.contains("hexagon-v2"):
		_fail("切换后 active.yaml 不是 V2 配置", 8)
		return
	if not subscription.delete_subscription(v2_id):
		_fail("活动 V2 订阅删除失败", 9)
		return
	if subscription.get_subscriptions().size() != 1 or subscription.active_subscription_id() != http_id:
		_fail("删除活动订阅后未切换到剩余 HTTP 订阅", 10)
		return
	if not subscription.delete_subscription(http_id):
		_fail("最后一个订阅删除失败", 11)
		return
	if not subscription.get_subscriptions().is_empty() or not FileAccess.get_file_as_string(subscription.profile_path()).contains("默认直连配置"):
		_fail("删除全部订阅后未恢复内置直连", 12)
		return
	print("PASS: HTTP/V2 订阅共存、切换、删除与直连回退")
	quit(0)

func _fail(message: String, code: int) -> void:
	printerr("FAIL: %s" % message)
	quit(code)
