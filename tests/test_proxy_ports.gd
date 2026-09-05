extends SceneTree

const ProxyConfigScript = preload("res://scripts/modules/proxy/proxy_config.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var config = ProxyConfigScript.new()
	config.ensure_directories()
	var mixed := config.random_available_port()
	var controller := config.random_available_port(mixed)
	if mixed < 0 or controller < 0 or mixed == controller:
		_fail("无法取得两组随机可用端口", 2)
		return
	var result: Dictionary = config.set_ports(mixed, controller)
	if not bool(result.get("ok", false)):
		_fail("可用端口无法保存：%s" % result.get("message", ""), 3)
		return
	var reloaded = ProxyConfigScript.new()
	if reloaded.mixed_port() != mixed or reloaded.controller_port() != controller:
		_fail("端口设置没有持久化", 4)
		return
	var duplicate: Dictionary = reloaded.set_ports(mixed, mixed)
	if bool(duplicate.get("ok", true)):
		_fail("相同的混合端口和控制端口没有被拒绝", 5)
		return

	var blocked_port := reloaded.random_available_port(controller)
	var blocker := TCPServer.new()
	if blocked_port < 0 or blocker.listen(blocked_port, reloaded.controller_host()) != OK:
		_fail("无法建立端口占用测试", 6)
		return
	var occupied: Dictionary = reloaded.set_ports(blocked_port, controller)
	blocker.stop()
	if bool(occupied.get("ok", true)) or not str(occupied.get("message", "")).contains("占用"):
		_fail("已占用端口没有在保存阶段被拒绝", 7)
		return

	var profile_path: String = reloaded.active_profile_path()
	var file := FileAccess.open(profile_path, FileAccess.WRITE)
	if file == null:
		_fail("无法创建活动配置测试文件", 8)
		return
	file.store_string("mixed-port: 7890\nmode: rule\n")
	file.close()
	if not reloaded.apply_runtime_ports_to_profile():
		_fail("活动配置端口更新失败", 9)
		return
	var patched := FileAccess.get_file_as_string(profile_path)
	if not patched.contains("mixed-port: %d" % mixed):
		_fail("活动配置没有使用保存后的混合端口", 10)
		return
	var random_port := reloaded.random_available_port(controller)
	if random_port < reloaded.RANDOM_PORT_MIN or random_port > reloaded.RANDOM_PORT_MAX or random_port == controller:
		_fail("随机端口范围或排除规则错误", 11)
		return

	print("PASS: 端口可编辑、随机、占用检测、持久化与活动配置同步")
	quit(0)

func _fail(message: String, code: int) -> void:
	printerr("FAIL: %s" % message)
	quit(code)
