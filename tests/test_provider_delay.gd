extends SceneTree
const ControlScript = preload("res://scripts/modules/mihomo/mihomo_control_service.gd")
class FakeApi:
	var calls: Array = []
	func request(action: String, path: String, _method: int, _body: String) -> void:
		calls.append({"action": action, "path": path})
	func cancel_all() -> void: pass
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	var service = ControlScript.new()
	root.add_child(service)
	var api = FakeApi.new()
	service.api_service = api
	var results: Array = []
	service.api_result.connect(func(action: String, ok: bool, payload: Variant) -> void: results.append([action, ok, payload]))
	service.test_proxy_delay("HY2 测试 / #")
	service._on_api_result("delay:HY2 测试 / #", false, {"_http_status": 404})
	if results.size() != 0 or api.calls.back().path != "/providers/proxies":
		_fail("404 must resolve provider before reporting failure")
		return
	service._on_api_result("resolve_delay_providers", true, {"providers": {"订阅 / 1": {"proxies": [{"name": "HY2 测试 / #"}]}}})
	var expected := "/providers/proxies/%s/%s/healthcheck?" % ["订阅 / 1".uri_encode(), "HY2 测试 / #".uri_encode()]
	if not api.calls.back().path.begins_with(expected):
		_fail("provider and node path segments must be escaped")
		return
	service._on_api_result("delay:HY2 测试 / #", true, {"delay": 123})
	if results.size() != 1 or results[0][2].delay != 123:
		_fail("final delay result must keep the original action")
		return
	service.test_proxy_delay("timed-out")
	var count: int = api.calls.size()
	service._on_api_result("delay:timed-out", false, {"_http_status": 504, "message": "Timeout"})
	if api.calls.size() != count or results.back()[1]:
		_fail("real connection errors must not trigger provider retries")
		return
	service.test_proxy_delay("stale")
	service._on_api_result("delay:stale", false, {"_http_status": 404})
	service._on_api_result("resolve_delay_providers", true, {"providers": {}})
	if results.back()[2]._http_status != 404:
		_fail("missing node must fail without recursive lookup")
		return
	service.test_proxy_delay("retry-once")
	service._on_api_result("delay:retry-once", false, {"_http_status": 404})
	service._on_api_result("resolve_delay_providers", true, {"providers": {"p": {"proxies": [{"name": "retry-once"}]}}})
	count = api.calls.size()
	service._on_api_result("delay:retry-once", false, {"_http_status": 404})
	if api.calls.size() != count:
		_fail("provider retry must be bounded")
		return
	service.cancel_requests()
	if not service._provider_delay_pending.is_empty() or not service._provider_delay_retries.is_empty():
		_fail("cancel must discard pending lookups")
		return
	service.api_service = null
	print("PASS: provider delay fallback, path escaping, real errors, missing nodes, bounded retries and cancellation")
	quit(0)
func _fail(message: String) -> void:
	printerr("FAIL: " + message)
	quit(1)
