extends SceneTree

const CoreControllerScript = preload("res://scripts/core_controller.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var controller: CoreController = CoreControllerScript.new()
	root.add_child(controller)
	await process_frame
	controller._shutting_down = true
	var links := "\n".join(PackedStringArray([
		"vless://123e4567-e89b-12d3-a456-426614174000@127.0.0.1:443?encryption=none&security=reality&sni=example.com&pbk=test&type=tcp#VLESS-Test",
		"hysteria2://p%40ss%3Aword@hy2.example.com:24517?sni=sni.example.com&insecure=0&allowInsecure=1&obfs=salamander&obfs-password=o%27bfs&mport=20000-30000&hop-interval=20&up=30&down=100&alpn=h3#HY2-Test"
	]))
	if not controller.use_v2_share_links(links):
		_fail("VLESS/HY2 混合导入失败", 2)
		return
	var entry: Dictionary = controller.get_subscriptions().back()
	var regular_file := str(entry.get("provider_file", ""))
	var hy2_file := str(entry.get("hy2_provider_file", ""))
	if regular_file.is_empty() or hy2_file.is_empty():
		_fail("混合导入没有拆分普通 URI 与 HY2 YAML provider", 3)
		return
	var regular_path := controller.subscription_provider_dir().path_join(regular_file)
	var hy2_path := controller.subscription_provider_dir().path_join(hy2_file)
	var regular := FileAccess.get_file_as_string(regular_path)
	var hy2 := FileAccess.get_file_as_string(hy2_path)
	if not regular.contains("vless://") or regular.contains("hysteria2://"):
		_fail("普通 provider 仍包含 HY2 URI", 4)
		return
	for expected in [
		"type: hysteria2", "server: 'hy2.example.com'", "port: 24517",
		"password: 'p@ss:word'", "sni: 'sni.example.com'",
		"skip-cert-verify: true", "obfs: 'salamander'", "obfs-password: 'o''bfs'",
		"ports: '20000-30000'", "hop-interval: '20'", "up: '30'", "down: '100'",
		"- 'h3'"
	]:
		if not hy2.contains(expected):
			_fail("HY2 YAML 缺少字段：%s" % expected, 5)
			return
	var active_yaml := FileAccess.get_file_as_string(controller.profile_path())
	if not active_yaml.contains("hexagon-v2-hy2") or active_yaml.count("url: https://www.gstatic.com/generate_204") != 1:
		_fail("活动配置没有同时引用两个 provider 或测速 URL 重复", 6)
		return
	controller.queue_free()
	await process_frame
	controller = CoreControllerScript.new()
	root.add_child(controller)
	await process_frame
	controller._shutting_down = true
	entry = controller.get_subscriptions().back()
	if str(entry.get("hy2_provider_file", "")) != hy2_file or not FileAccess.file_exists(hy2_path):
		_fail("重启后 HY2 provider 没有保留", 7)
		return
	print("PASS: Hysteria2 URI 转换为 Mihomo YAML 并与其他 V2 节点共存")
	quit(0)

func _fail(message: String, code: int) -> void:
	printerr("FAIL: %s" % message)
	quit(code)
