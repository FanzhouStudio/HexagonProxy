extends SceneTree

const FixtureScript = preload("res://tests/helpers/proxy_runtime_fixture.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var fixture = FixtureScript.new()
	root.add_child(fixture)
	fixture.initialize()
	await process_frame
	var proxy = fixture.proxy
	var config = fixture.config()
	var subscription = fixture.subscription
	var valid_profile := FileAccess.get_file_as_string(subscription.profile_path())
	if not bool(proxy.validator.validate().get("ok", false)):
		_fail("默认配置未通过 Mihomo 校验", 2)
		return
	if not _write_text(subscription.profile_path(), "broken: [\n"):
		_fail("无法写入无效配置测试样本", 3)
		return
	proxy.validator.setup(config.core_path(), config.runtime_dir(), subscription.profile_path())
	if bool(proxy.validator.validate().get("ok", true)):
		_fail("无效配置没有被启动前校验拦截", 4)
		return
	if not _write_text(subscription.profile_path(), valid_profile):
		_fail("无法恢复有效配置测试样本", 9)
		return
	proxy.validator.setup(config.core_path(), config.runtime_dir(), subscription.profile_path())

	var blocker := TCPServer.new()
	var owns_blocker := false
	if _tcp_port_is_available(config.controller_port(), config.controller_host()):
		owns_blocker = blocker.listen(config.controller_port(), config.controller_host()) == OK
	if owns_blocker and str(config.controller_port()) not in proxy._occupied_ports():
		blocker.stop()
		_fail("ProxyService 没有检测到控制端口冲突", 5)
		return
	if owns_blocker:
		blocker.stop()

	for method_name in ["start", "stop", "restart", "set_online_state", "is_running"]:
		if not proxy.has_method(method_name):
			_fail("ProxyService 缺少生命周期方法：%s" % method_name, 6)
			return
	if proxy.recovery.DELAYS != [1.0, 3.0, 8.0]:
		_fail("恢复退避参数不一致", 7)
		return
	proxy.api_secret_changed.emit("test-secret")
	if fixture.api.api_secret != "test-secret":
		_fail("ProxyService API secret 没有同步到 MihomoApiService", 8)
		return
	fixture.shutdown()
	print("PASS: 配置预检、端口冲突与 ProxyService 生命周期契约")
	quit(0)

func _write_text(path: String, content: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(content)
	file.close()
	return true

func _tcp_port_is_available(port: int, host: String) -> bool:
	var server := TCPServer.new()
	var result := server.listen(port, host)
	server.stop()
	return result == OK

func _fail(message: String, code: int) -> void:
	printerr("FAIL: %s" % message)
	quit(code)
