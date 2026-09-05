class_name ProxyRuntimeFixture
extends Node

const ProxyServiceScript = preload("res://scripts/modules/proxy/proxy_service.gd")
const MihomoApiServiceScript = preload("res://scripts/modules/mihomo/mihomo_api_service.gd")
const MihomoControlServiceScript = preload("res://scripts/modules/mihomo/mihomo_control_service.gd")
const SubscriptionServiceScript = preload("res://scripts/modules/subscription/subscription_service.gd")

var proxy
var api
var control
var subscription

func initialize(with_subscription := true) -> void:
	proxy = ProxyServiceScript.new()
	add_child(proxy)
	api = MihomoApiServiceScript.new()
	add_child(api)
	api.bind_config(proxy.get_config())
	control = MihomoControlServiceScript.new()
	add_child(control)
	control.setup(proxy, api)
	if with_subscription:
		subscription = SubscriptionServiceScript.new()
		subscription.bind_config(proxy.get_config())
		add_child(subscription)
		subscription.initialize()
func shutdown() -> void:
	if control:
		control.stop()
	if is_inside_tree():
		queue_free()

func config():
	return proxy.config if proxy else null
