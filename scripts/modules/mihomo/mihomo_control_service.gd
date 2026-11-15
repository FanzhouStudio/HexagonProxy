class_name MihomoControlService
extends Node

## Mihomo 控制面服务
## 负责进程状态映射、控制 API 调度和运行时健康检查

signal state_changed(online: bool, starting: bool, core_pid: int, message: String)
signal event_logged(message: String)
signal api_result(action: String, ok: bool, payload: Variant)

const STARTUP_MAX_ATTEMPTS := 12

var proxy_service
var api_service
var online := false
var starting := false
var core_pid := -1
var _poll_in_flight := false
var _startup_attempts := 0
var _health_failures := 0
var _shutting_down := false
var _provider_delay_pending: Dictionary = {}
var _provider_delay_retries: Dictionary = {}

func setup(proxy, api) -> void:
	_disconnect_dependencies()
	proxy_service = proxy
	api_service = api
	_connect_dependencies()
	if proxy_service and api_service and not str(proxy_service.api_secret).is_empty():
		api_service.set_secret(proxy_service.api_secret)

func start() -> void:
	if proxy_service:
		proxy_service.start()
func stop() -> void:
	cancel_requests()
	if proxy_service:
		proxy_service.stop()

func restart() -> void:
	if proxy_service:
		proxy_service.restart()

func poll_status() -> void:
	if _poll_in_flight or api_service == null or proxy_service == null:
		return
	if not proxy_service.is_running() and not online:
		return
	_poll_in_flight = true
	request("version", "/version", HTTPClient.METHOD_GET)

func refresh_runtime(include_connections := true, include_metadata := true) -> void:
	if not online:
		return
	if include_metadata:
		request("proxies", "/proxies", HTTPClient.METHOD_GET)
		request("config", "/configs", HTTPClient.METHOD_GET)
	if include_connections:
		request("connections", "/connections", HTTPClient.METHOD_GET)

func set_mode(mode: String, group_name := "六角选择") -> void:
	if mode not in ["rule", "global", "direct"]:
		return
	if mode == "global":
		if group_name.is_empty():
			event_logged.emit("全局模式找不到可用的策略组。")
			return
		request("resolve_global_proxy", "/proxies/%s" % group_name.uri_encode(), HTTPClient.METHOD_GET)
		return
	request("set_mode", "/configs", HTTPClient.METHOD_PATCH, JSON.stringify({"mode": mode}))

func select_proxy(group_name: String, proxy_name: String, action := "select_proxy") -> void:
	request(action, "/proxies/%s" % group_name.uri_encode(), HTTPClient.METHOD_PUT, JSON.stringify({"name": proxy_name}))

func test_proxy_delay(proxy_name: String) -> void:
	_provider_delay_retries.erase(proxy_name)
	var test_url := "https://www.gstatic.com/generate_204".uri_encode()
	var path := "/proxies/%s/delay?url=%s&timeout=5000" % [proxy_name.uri_encode(), test_url]
	request("delay:%s" % proxy_name, path, HTTPClient.METHOD_GET)

func test_group_delay(group_name: String, action := "group_delay") -> void:
	if group_name.is_empty():
		return
	var test_url := "https://www.gstatic.com/generate_204".uri_encode()
	var path := "/group/%s/delay?url=%s&timeout=5000" % [group_name.uri_encode(), test_url]
	request(action, path, HTTPClient.METHOD_GET)

func request(action: String, endpoint: String, method: int, body := "") -> void:
	if api_service:
		api_service.request(action, endpoint, method, body)
func cancel_requests() -> void:
	_provider_delay_pending.clear()
	_provider_delay_retries.clear()
	if api_service:
		api_service.cancel_all()
	_poll_in_flight = false

func _connect_dependencies() -> void:
	if proxy_service:
		proxy_service.api_secret_changed.connect(_on_api_secret_changed)
		proxy_service.process_started.connect(_on_process_started)
		proxy_service.process_stopped.connect(_on_process_stopped)
		proxy_service.process_crashed.connect(_on_process_crashed)
		proxy_service.start_failed.connect(_on_start_failed)
	if api_service:
		api_service.request_finished.connect(_on_api_result)

func _disconnect_dependencies() -> void:
	if proxy_service:
		_disconnect_signal(proxy_service.api_secret_changed, _on_api_secret_changed)
		_disconnect_signal(proxy_service.process_started, _on_process_started)
		_disconnect_signal(proxy_service.process_stopped, _on_process_stopped)
		_disconnect_signal(proxy_service.process_crashed, _on_process_crashed)
		_disconnect_signal(proxy_service.start_failed, _on_start_failed)
	if api_service:
		_disconnect_signal(api_service.request_finished, _on_api_result)
func _disconnect_signal(signal_value: Signal, callable: Callable) -> void:
	if signal_value.is_connected(callable):
		signal_value.disconnect(callable)

func _on_api_secret_changed(secret: String) -> void:
	if api_service:
		api_service.set_secret(secret)

func _on_process_started(pid: int) -> void:
	core_pid = pid
	starting = true
	online = false
	_emit_state("六角恐龙正在启动内核…")
	await get_tree().create_timer(0.45).timeout
	if starting and not _shutting_down:
		poll_status()

func _on_process_stopped() -> void:
	core_pid = -1
	starting = false
	_set_online(false, "代理已休息")

func _on_process_crashed() -> void:
	core_pid = -1
	starting = false
	_set_online(false, "内核意外退出")
	event_logged.emit("检测到 Mihomo 进程意外退出。")
func _on_start_failed(message: String) -> void:
	core_pid = -1
	starting = false
	_set_online(false, message)
	event_logged.emit(message)

func _on_api_result(action: String, ok: bool, payload: Variant) -> void:
	if action == "resolve_delay_providers":
		_resolve_provider_delays(ok, payload)
		return
	if action.begins_with("delay:"):
		var name := action.trim_prefix("delay:")
		if not ok and payload is Dictionary and int(payload.get("_http_status", 0)) == 404 and not _provider_delay_retries.has(name):
			_provider_delay_pending[name] = true
			_provider_delay_retries[name] = true
			request("resolve_delay_providers", "/providers/proxies", HTTPClient.METHOD_GET)
			return
		_provider_delay_retries.erase(name)
		if not ok:
			event_logged.emit("节点测速失败：%s · %s" % [name, _delay_error(payload)])
	if action == "version":
		_poll_in_flight = false
		if ok:
			_startup_attempts = 0
			_health_failures = 0
			_set_online(true, "内核已连接 · 等待代理入口验证")
		elif starting:
			_startup_attempts += 1
			if _startup_attempts >= STARTUP_MAX_ATTEMPTS:
				starting = false
				_emit_state("代理未连接")
				event_logged.emit("等待控制接口超时，配置可能无效或端口被占用。")
			else:
				await get_tree().create_timer(0.7).timeout
				poll_status()
		elif online:
			_health_failures += 1
			if _health_failures >= 3:
				event_logged.emit("Mihomo 控制接口连续三次无响应。")
				_set_online(false, "控制接口失联，正在重新检测")
		else:
			_emit_state("控制接口尚未恢复")
	if action == "set_mode" and ok:
		event_logged.emit("代理模式已切换。")
	if action == "resolve_global_proxy":
		var selected_node := str(payload.get("now", "")) if ok and payload is Dictionary else ""
		if selected_node.is_empty():
			event_logged.emit("全局模式无法读取当前节点。")
		else:
			request("select_global_proxy", "/proxies/GLOBAL", HTTPClient.METHOD_PUT, JSON.stringify({"name": selected_node}))
	if action == "select_global_proxy":
		if ok:
			request("set_mode", "/configs", HTTPClient.METHOD_PATCH, JSON.stringify({"mode": "global"}))
		else:
			event_logged.emit("全局模式无法绑定当前节点。")
	if action == "select_proxy" and ok:
		event_logged.emit("节点切换成功。")
	if action == "update_provider":
		event_logged.emit("订阅更新%s。" % ("完成" if ok else "失败"))
	api_result.emit(action, ok, payload)

func _delay_error(payload: Variant) -> String:
	if payload is Dictionary:
		match int(payload.get("_http_status", 0)):
			404: return "节点未在内核中找到，请刷新订阅。"
			504: return "连接超时，请检查节点服务、UDP 网络和认证参数。"
		return str(payload.get("message", "测速请求失败"))
	return "测速请求失败"

func _resolve_provider_delays(ok: bool, payload: Variant) -> void:
	var pending := _provider_delay_pending.keys()
	_provider_delay_pending.clear()
	var providers: Dictionary = payload.get("providers", {}) if ok and payload is Dictionary else {}
	var provider_names := providers.keys()
	provider_names.sort()
	for name: String in pending:
		var found := ""
		for provider_name: String in provider_names:
			var provider: Variant = providers[provider_name]
			if not provider is Dictionary:
				continue
			for node in provider.get("proxies", []):
				if node is Dictionary and str(node.get("name", "")) == name:
					found = provider_name
					break
			if not found.is_empty():
				break
		if found.is_empty():
			_provider_delay_retries.erase(name)
			api_result.emit("delay:" + name, false, {"_http_status": 404, "message": "节点未在订阅中找到，请刷新订阅。"} if ok else payload)
			continue
		var path := "/providers/proxies/%s/%s/healthcheck?url=%s&timeout=5000" % [found.uri_encode(), name.uri_encode(), "https://www.gstatic.com/generate_204".uri_encode()]
		request("delay:" + name, path, HTTPClient.METHOD_GET)

func _set_online(value: bool, message: String) -> void:
	var changed := online != value
	online = value
	if proxy_service:
		proxy_service.set_online_state(value)
	if value:
		starting = false
	_emit_state(message)
	if changed and value:
		event_logged.emit("已连接 Mihomo 控制器。")
func _emit_state(message: String) -> void:
	state_changed.emit(online, starting, core_pid, message)

func dispose() -> void:
	_shutting_down = true
	cancel_requests()
	_disconnect_dependencies()
	proxy_service = null
	api_service = null
