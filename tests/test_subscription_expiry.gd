extends SceneTree

func _init() -> void: call_deferred("run")
func run() -> void:
	var service = preload("res://scripts/modules/subscription/subscription_service.gd").new()
	root.add_child(service)
	service._ensure_dependencies()
	var path := OS.get_environment("TEMP").path_join("hexagon-expiry-%d" % Time.get_ticks_usec())
	service.subscription_store.setup(path, path)
	service.library.catalog.entries = [{"id": "a", "type": "http"}, {"id": "b", "type": "http"}]
	service.save_expiry("a", {"subscriptionInfo": {"Expire": 1900000000}})
	var entries: Array = service.subscription_store.load_index()["subscriptions"]
	assert(entries[0].expires_at == 1900000000)
	assert(not entries[1].has("expires_at"))
	var panel = preload("res://scripts/ui/subscription_panel.gd").new()
	assert(panel._expiry_text(entries[0]).contains("到期："))
	assert(panel._expiry_text(entries[1]).contains("待获取"))
	service.save_expiry("a", {"subscriptionInfo": {"Expire": 0}})
	assert(panel._expiry_text(service.library.catalog.entries[0]).contains("未提供"))
	service.save_expiry("a", {"subscriptionInfo": {"Expire": 1}})
	assert(panel._expiry_text(service.library.catalog.entries[0]).contains("已到期"))
	service.save_expiry("a", {"subscriptionInfo": {"Expire": "bad"}})
	assert(panel._expiry_text(service.library.catalog.entries[0]).contains("未提供"))
	assert(panel._expiry_text({"type": "local"}).contains("不适用"))
	panel.free()
	print("PASS: subscription expiry persistence, account isolation and date states")
	quit(0)
