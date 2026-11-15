extends Node

signal checked(state: String, message: String)
signal diagnostic_logged(message: String)
const TARGETS := ["https://www.gstatic.com/generate_204", "https://www.google.com/generate_204"]
var _requests: Array[HTTPRequest] = []
var _results: Array[bool] = []
var _generation := 0
var _failures := 0
var _reasons := PackedStringArray()
var _details := PackedStringArray()
var _route := ""
var _probing := false
var _local_proxy_reachable := false

func probe(host: String, port: int, tun_mode := false) -> void:
	if _probing or not _requests.is_empty():
		return
	_probing = true
	_generation += 1
	_results.clear()
	_reasons.clear()
	_details.clear()
	_route = "TUN 路径" if tun_mode else "HTTP 代理 %s:%d" % [host, port]
	var generation := _generation
	_local_proxy_reachable = false
	if not tun_mode:
		var reachable: bool = await _check_proxy_port(host, port, generation)
		if generation != _generation:
			return
		_local_proxy_reachable = reachable
	for url in TARGETS:
		var request := HTTPRequest.new()
		request.timeout = 8
		request.max_redirects = 0
		request.body_size_limit = 4096
		add_child(request)
		if not tun_mode:
			request.set_http_proxy(host, port)
			request.set_https_proxy(host, port)
		_requests.append(request)
		if not tun_mode and not _local_proxy_reachable:
			_on_probe_result.call_deferred(request, generation, url, HTTPRequest.RESULT_CANT_CONNECT, 0, tun_mode)
			continue
		request.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
			_on_probe_result(request, generation, url, result, code, tun_mode)
		)
		var error := request.request(url, PackedStringArray(["Cache-Control: no-cache"]))
		if error != OK:
			_on_probe_result.call_deferred(request, generation, url, -1, 0, tun_mode, error)

func _check_proxy_port(host: String, port: int, generation: int) -> bool:
	var tcp := StreamPeerTCP.new()
	if tcp.connect_to_host(host, port) != OK:
		return false
	var deadline := Time.get_ticks_msec() + 1000
	while generation == _generation and Time.get_ticks_msec() < deadline:
		tcp.poll()
		if tcp.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			tcp.disconnect_from_host()
			return true
		if tcp.get_status() == StreamPeerTCP.STATUS_ERROR:
			break
		await get_tree().create_timer(0.02).timeout
	tcp.disconnect_from_host()
	return false

func _on_probe_result(request: HTTPRequest, generation: int, url: String, result: int, code: int, tun_mode := false, start_error := OK) -> void:
	if generation != _generation:
		return
	var ok := start_error == OK and result == HTTPRequest.RESULT_SUCCESS and code == 204
	if not ok:
		var reason := _failure_reason(result, code, start_error)
		if not _reasons.has(reason):
			_reasons.append(reason)
		_details.append("%s：%s（result=%d，HTTP=%d）" % [url, reason, result, code])
	if tun_mode:
		_record_probe(url, result, code)
	_finish(request, generation, ok, tun_mode)

func _failure_reason(result: int, code: int, start_error := OK) -> String:
	if start_error != OK:
		return "请求无法开始：%s（错误码 %d）" % [error_string(start_error), start_error]
	match result:
		HTTPRequest.RESULT_CANT_RESOLVE: return "DNS 解析失败"
		HTTPRequest.RESULT_CANT_CONNECT:
			if _route == "TUN 路径":
				return "TUN 路径无法连接目标服务器"
			return "本地代理端口可连接，但 HTTPS 隧道建立失败，请检查上游节点" if _local_proxy_reachable else "本地代理端口未监听或无法连接"
		HTTPRequest.RESULT_CONNECTION_ERROR: return "连接中断"
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR: return "TLS 握手失败"
		HTTPRequest.RESULT_TIMEOUT: return "请求超时（8 秒）"
		HTTPRequest.RESULT_NO_RESPONSE: return "服务器未返回响应"
		HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED: return "响应超过 4096 字节限制"
		HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED: return "检测地址返回重定向（要求直接返回 HTTP 204）"
		HTTPRequest.RESULT_SUCCESS: return "HTTP %d（预期 204）" % code
	return "网络请求失败（result=%d）" % result

func _record_probe(url: String, result: int, code: int) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://diagnostics"))
	var path := "user://diagnostics/tun-probes.log"
	var file := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if file:
		file.seek_end()
		file.store_line("%s %s result=%d HTTP=%d" % [Time.get_datetime_string_from_system(), url, result, code])

func _finish(request: HTTPRequest, generation: int, ok: bool, tun_mode := false) -> void:
	if generation != _generation:
		return
	_requests.erase(request)
	request.queue_free()
	_results.append(ok)
	if _results.size() != TARGETS.size():
		return
	_probing = false
	var successes := _results.count(true)
	_reasons.sort()
	_details.sort()
	var reason := "；".join(_reasons) if not _reasons.is_empty() else "请求失败（未返回错误详情）"
	diagnostic_logged.emit("代理连通性检查 [%s]\n%s" % [_route, "\n".join(_details)] if not _details.is_empty() else "")
	_failures = _failures + 1 if successes == 0 else 0
	if successes == TARGETS.size():
		checked.emit("healthy", "TUN 路径 HTTPS 检查通过" if tun_mode else "代理入口 HTTPS 检查通过")
	elif successes > 0:
		checked.emit("partial", "部分检测失败：%s" % reason)
	elif _failures < 2:
		checked.emit("checking", "代理检查：%s，正在复查" % reason)
	else:
		checked.emit("failed", "代理 HTTPS 检查失败：%s（详情见运行记录）" % reason)

func cancel() -> void:
	_generation += 1
	_probing = false
	for request in _requests:
		request.cancel_request()
		request.queue_free()
	_requests.clear()
	_results.clear()
	_reasons.clear()
	_details.clear()
	_failures = 0

func _exit_tree() -> void:
	cancel()
