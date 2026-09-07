extends SceneTree

const RuntimeCoordinatorScript = preload("res://scripts/app/runtime_coordinator.gd")

class FakeProxyConfig:
	var core_available := true
	var tun := false
	func has_core() -> bool:
		return core_available
	func controller_host() -> String: return "127.0.0.1"
	func mixed_port() -> int: return 7890
	func tun_enabled() -> bool: return tun
	func set_tun_enabled(value: bool) -> bool:
		tun = value
		return true
	func has_tun_permission() -> bool: return true

class FakeProxy:
	var config = FakeProxyConfig.new()

class FakeMihomo:
	signal state_changed(online: bool, starting: bool, core_pid: int, message: String)
	signal api_result(action: String, ok: bool, payload: Variant)
	var online := false
	var starting := false
	var core_pid := -1
	var starts := 0
	var stops := 0
	var refreshes := 0
	var modes: Array[String] = []
	var restarts := 0
	var requests: Array[String] = []
	var selected_proxies: Array[String] = []
	var tested_proxies: Array[String] = []
	var tested_groups: Array[String] = []
	func start() -> void: starts += 1
	func stop() -> void: stops += 1
	func restart() -> void: restarts += 1
	func request(action: String, _endpoint: String, _method: int, _body := "") -> void: requests.append(action)
	func refresh_runtime() -> void: refreshes += 1
	func poll_status() -> void: pass
	func select_proxy(group_name: String, proxy_name: String) -> void: selected_proxies.append(group_name + "/" + proxy_name)
	func test_proxy_delay(proxy_name: String) -> void: tested_proxies.append(proxy_name)
	func test_group_delay(group_name: String) -> void: tested_groups.append(group_name)
	func set_mode(mode: String, _group := "") -> void: modes.append(mode)

class FakeSystemProxy:
	signal status_changed(enabled: bool)
	signal busy_changed(busy: bool)
	var enabled := false
	var busy := false
	func is_enabled() -> bool: return enabled
	func set_enabled(value: bool) -> void:
		enabled = value
		status_changed.emit(value)
	func reconcile() -> void: pass

class FakeDashboard:
	signal connect_requested(enabled: bool)
	signal mode_requested(mode: String)
	var pressed := false
	var last_mode := ""
	var profile_name := ""
	var network_healthy := false
	func set_status(_online: bool, _starting: bool, _message: String) -> void: pass
	func set_connect_pressed(value: bool) -> void: pressed = value
	func apply_connections(_payload: Dictionary) -> void: pass
	func set_mode(mode: String) -> void: last_mode = mode
	func set_profile_name(value: String) -> void: profile_name = value
	func set_network_health(value: bool, _message: String) -> void: network_healthy = value
	func push_zero_sample() -> void: pass

class FakeNodes:
	signal node_status_changed(node_name: String, delay: int)
	signal proxy_select_requested(group_name: String, proxy_name: String)
	signal proxy_delay_requested(proxy_name: String)
	signal group_delay_requested(group_name: String)
	signal global_group_requested(group_name: String)
	signal runtime_refresh_requested
	var global_mode := false
	func selected_group() -> Dictionary: return {"name": "六角选择"}
	func current_node_name() -> String: return "测试节点"
	func current_delay() -> int: return 42
	func handle_api_result(_action: String, _ok: bool, _payload: Variant) -> bool: return false
	func set_global_mode_active(value: bool) -> void: global_mode = value

class FakeSubscription:
	signal profile_changed(display_name: String)
	signal restart_requested
	signal api_request_requested(action: String, endpoint: String, method: int, body: String)

class FakeCoreUpdate:
	signal progress_changed(progress: float, message: String)
	signal finished(success: bool, message: String)
	var busy := false
	var downloads := 0
	func is_busy() -> bool: return busy
	func download_latest() -> void: downloads += 1

class FakeAutostart:
	signal status_changed(enabled: bool)
	signal busy_changed(busy: bool)
	var enabled := false
	var requests: Array[bool] = []
	func set_enabled(value: bool) -> void:
		enabled = value
		requests.append(value)

class FakeSettings:
	signal system_proxy_intent_changed(enabled: bool)
	signal tun_intent_changed(enabled: bool)
	signal core_restart_requested
	signal core_update_requested
	var rejected_proxy_messages: Array[String] = []
	var blocked_update_messages: Array[String] = []
	var proxy_enabled := false
	var proxy_busy := false
	var tun_enabled := false
	var tun_busy := false
	var core_progress := -2.0
	var core_progress_message := ""
	func reject_system_proxy_enable(message: String) -> void: rejected_proxy_messages.append(message)
	func show_core_update_blocked(message: String) -> void: blocked_update_messages.append(message)
	func set_system_proxy_state(value: bool) -> void: proxy_enabled = value
	func set_system_proxy_busy(value: bool) -> void: proxy_busy = value
	func set_tun_state(value: bool) -> void: tun_enabled = value
	func set_tun_busy(value: bool) -> void: tun_busy = value
	func reject_tun_enable(message: String) -> void:
		rejected_proxy_messages.append(message)
		tun_enabled = false
	func set_core_update_progress(value: float, message: String) -> void:
		core_progress = value
		core_progress_message = message

class FakeResident:
	signal connect_requested(enabled: bool)
	signal autostart_requested(enabled: bool)
	var online := false
	var autostart_enabled := false
	var autostart_busy := false
	func set_node_status(_name: String, _delay: int, value: bool) -> void: online = value
	func set_connection_state(value: bool, _starting: bool) -> void: online = value
	func set_autostart_state(value: bool) -> void: autostart_enabled = value
	func set_autostart_busy(value: bool) -> void: autostart_busy = value

class FakeShell:
	var page := ""
	func show_page(value: String) -> void: page = value

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var proxy = FakeProxy.new()
	var mihomo = FakeMihomo.new()
	var system_proxy = FakeSystemProxy.new()
	var subscription = FakeSubscription.new()
	var dashboard = FakeDashboard.new()
	var settings = FakeSettings.new()
	var resident = FakeResident.new()
	var shell = FakeShell.new()
	var runtime = RuntimeCoordinatorScript.new()
	root.add_child(runtime)
	runtime.setup(proxy, mihomo, system_proxy, subscription, dashboard, settings, resident, shell)
	runtime.start()

	system_proxy.status_changed.emit(true)
	system_proxy.busy_changed.emit(true)
	if not settings.proxy_enabled or not settings.proxy_busy:
		_fail("系统代理状态没有通过协调器回写设置面板", 2)
		return
	system_proxy.status_changed.emit(false)
	system_proxy.busy_changed.emit(false)

	settings.system_proxy_intent_changed.emit(true)
	if system_proxy.enabled or settings.rejected_proxy_messages.is_empty():
		_fail("离线时系统代理开启意图没有被协调器拒绝", 2)
		return

	dashboard.connect_requested.emit(true)
	if mihomo.starts != 1:
		_fail("连接请求没有启动 Mihomo", 2)
		return
	mihomo.online = true
	mihomo.state_changed.emit(true, false, 1234, "在线")
	if not system_proxy.enabled or not resident.online:
		_fail("上线后系统代理或驻留状态没有同步", 3)
		return

	settings.system_proxy_intent_changed.emit(false)
	if system_proxy.enabled:
		_fail("系统代理关闭意图没有交给协调器执行", 4)
		return
	settings.system_proxy_intent_changed.emit(true)
	if not system_proxy.enabled:
		_fail("系统代理开启意图没有交给协调器执行", 5)
		return
	settings.tun_intent_changed.emit(true)
	if system_proxy.enabled or not proxy.config.tun or mihomo.restarts != 1:
		_fail("TUN 没有先关闭系统代理并重启内核", 5)
		return
	mihomo.online = true
	mihomo.state_changed.emit(true, false, 1234, "在线")
	settings.system_proxy_intent_changed.emit(true)
	if proxy.config.tun or system_proxy.enabled or mihomo.restarts != 2:
		_fail("系统代理没有先关闭 TUN 并等待内核重启", 5)
		return
	mihomo.state_changed.emit(true, false, 1234, "在线")
	if not system_proxy.enabled:
		_fail("关闭 TUN 后没有自动开启系统代理", 5)
		return

	subscription.profile_changed.emit("测试订阅")
	subscription.restart_requested.emit()
	subscription.api_request_requested.emit("update_provider", "/provider", 2, "")
	if dashboard.profile_name != "测试订阅" or mihomo.restarts != 3 or "update_provider" not in mihomo.requests:
		_fail("订阅运行时事件没有统一协调", 5)
		return

	resident.connect_requested.emit(false)
	if mihomo.stops != 1 or system_proxy.enabled or dashboard.pressed:
		_fail("驻留断开请求没有完整关闭连接状态", 6)
		return
	runtime.shutdown()
	var starts_before_shutdown_signal: int = int(mihomo.starts)
	var profile_before_shutdown_signal: String = dashboard.profile_name
	subscription.profile_changed.emit("关闭后不应更新")
	resident.connect_requested.emit(true)
	if mihomo.starts != starts_before_shutdown_signal or dashboard.profile_name != profile_before_shutdown_signal:
		_fail("协调器关闭后仍响应运行时事件", 9)
		return

	print("PASS: RuntimeCoordinator 连接、系统代理、订阅、驻留与关闭状态协调")
	quit(0)

func _fail(message: String, code: int) -> void:
	printerr("FAIL: %s" % message)
	quit(code)
