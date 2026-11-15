extends SceneTree

var service = preload("res://scripts/modules/network/proxy_health_service.gd").new()
var states: Array[String] = []
var messages: Array[String] = []
var diagnostics: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func round_result(first: bool, second: bool) -> void:
	service._results.clear()
	service._reasons.clear()
	service._details.clear()
	for success in [first, second]:
		var request := HTTPRequest.new()
		service.add_child(request)
		service._requests.append(request)
		service._finish(request, service._generation, success)

func _run() -> void:
	root.add_child(service)
	service.checked.connect(func(state: String, message: String) -> void:
		states.append(state)
		messages.append(message)
	)
	service.diagnostic_logged.connect(func(message: String) -> void: diagnostics.append(message))
	round_result(false, false)
	round_result(false, false)
	round_result(true, false)
	round_result(false, false)
	round_result(true, true)
	if states != ["checking", "failed", "partial", "checking", "healthy"]:
		push_error("Health failure threshold or recovery is incorrect: %s" % [states])
		quit(1)
		return
	var stale := HTTPRequest.new()
	service.add_child(stale)
	service._requests.append(stale)
	var generation: int = service._generation
	service.cancel()
	service._finish(stale, generation, true)
	if states.size() != 5 or not service._results.is_empty() or service._failures != 0:
		push_error("Cancelled health probe changed current status")
		quit(2)
		return
	service._route = "HTTP 代理 127.0.0.1:7890"
	for result in [HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR, HTTPRequest.RESULT_TIMEOUT]:
		var request := HTTPRequest.new()
		service.add_child(request)
		service._requests.append(request)
		service._on_probe_result(request, service._generation, service.TARGETS[service._results.size()], result, 0)
	if not messages[-1].contains("TLS 握手失败") or not messages[-1].contains("超时"):
		push_error("Health summary must contain actual error reasons")
		quit(3)
		return
	if not diagnostics[-1].contains(service.TARGETS[0]) or not diagnostics[-1].contains("127.0.0.1:7890") or not diagnostics[-1].contains("result="):
		push_error("Health diagnostics must contain route, URL and raw error code")
		quit(4)
		return
	assert(service._failure_reason(HTTPRequest.RESULT_SUCCESS, 403).contains("HTTP 403"))
	assert(service._failure_reason(HTTPRequest.RESULT_CANT_RESOLVE, 0).contains("DNS"))
	service._local_proxy_reachable = false
	assert(service._failure_reason(HTTPRequest.RESULT_CANT_CONNECT, 0).contains("未监听"))
	service._local_proxy_reachable = true
	assert(service._failure_reason(HTTPRequest.RESULT_CANT_CONNECT, 0).contains("HTTPS 隧道"))
	assert(service._failure_reason(-1, 0, ERR_INVALID_PARAMETER).contains(error_string(ERR_INVALID_PARAMETER)))
	var server := TCPServer.new()
	var test_port := 0
	for port in range(28791, 28811):
		if server.listen(port, "127.0.0.1") == OK:
			test_port = port
			break
	assert(test_port > 0)
	assert(await service._check_proxy_port("127.0.0.1", test_port, service._generation))
	server.stop()
	assert(not await service._check_proxy_port("127.0.0.1", test_port, service._generation))
	service.cancel()
	assert(not service._probing)
	print("PASS: proxy health thresholds, recovery, cancellation and detailed error diagnostics")
	quit(0)
