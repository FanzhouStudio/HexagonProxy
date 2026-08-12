extends SceneTree

const CoreControllerScript = preload("res://scripts/core_controller.gd")

var controller: CoreController
var core_online := false
var proxy_payload: Dictionary = {}

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	controller = CoreControllerScript.new()
	root.add_child(controller)
	await process_frame
	controller.status_changed.connect(func(online: bool, message: String) -> void:
		print("V2 IMPORT STATUS: %s" % message)
		core_online = online
		if online:
			controller.refresh_runtime()
	)
	controller.api_result.connect(func(action: String, ok: bool, payload: Variant) -> void:
		if action == "proxies" and ok and payload is Dictionary:
			proxy_payload = payload
	)
	var profile_before_invalid := FileAccess.get_file_as_string(controller.profile_path())
	if controller.use_v2_share_links("vless://broken"):
		printerr("FAIL: 损坏的 V2 链接未被拒绝")
		quit(4)
		return
	if FileAccess.get_file_as_string(controller.profile_path()) != profile_before_invalid:
		printerr("FAIL: 损坏链接覆盖了原配置")
		quit(5)
		return
	var links := "\n".join(PackedStringArray([
		"vless://123e4567-e89b-12d3-a456-426614174000@127.0.0.1:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.microsoft.com&fp=chrome&pbk=9tstfawAZxQjbaOfcCPANU9GvlmXl-FzZs43lX3_8XA&sid=0123456789abcdef&type=tcp#VLESS-Reality-Test",
		"hysteria2://test-password@127.0.0.1:24517?sni=example.com&insecure=1#HY2-Test"
	]))
	if not controller.use_v2_share_links(links):
		printerr("FAIL: V2 分享链接未被接受")
		quit(2)
		return
	var deadline := Time.get_ticks_msec() + 30000
	while not core_online and Time.get_ticks_msec() < deadline:
		controller.poll_status()
		await create_timer(0.35).timeout
	while proxy_payload.is_empty() and Time.get_ticks_msec() < deadline:
		await create_timer(0.2).timeout
	var proxies: Dictionary = proxy_payload.get("proxies", {})
	var selector: Dictionary = proxies.get("六角选择", {})
	var imported_names: Array = selector.get("all", [])
	var vless_found := imported_names.has("VLESS-Reality-Test")
	var hy2_found := imported_names.has("HY2-Test")
	controller.stop_core()
	if not vless_found or not hy2_found:
		print("IMPORTED NODES: %s" % ", ".join(PackedStringArray(imported_names)))
		printerr("FAIL: V2 节点未出现在 Mihomo API，VLESS=%s HY2=%s" % [vless_found, hy2_found])
		quit(3)
		return
	await create_timer(0.3).timeout
	core_online = false
	proxy_payload = {}
	var base64_subscription := Marshalls.utf8_to_base64(links)
	if not controller.use_v2_share_links(base64_subscription):
		printerr("FAIL: V2RayN Base64 订阅正文未被接受")
		quit(6)
		return
	deadline = Time.get_ticks_msec() + 30000
	while not core_online and Time.get_ticks_msec() < deadline:
		controller.poll_status()
		await create_timer(0.35).timeout
	while proxy_payload.is_empty() and Time.get_ticks_msec() < deadline:
		await create_timer(0.2).timeout
	proxies = proxy_payload.get("proxies", {})
	selector = proxies.get("六角选择", {})
	imported_names = selector.get("all", [])
	controller.stop_core()
	if not imported_names.has("VLESS-Reality-Test") or not imported_names.has("HY2-Test"):
		printerr("FAIL: Base64 订阅节点未出现在 Mihomo API")
		quit(7)
		return
	print("PASS: VLESS Reality、Hysteria2 分享链接与 Base64 订阅正文导入")
	quit(0)
