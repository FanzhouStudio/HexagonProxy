extends Node

signal checked(state: String, message: String)
const TARGETS := ["https://www.gstatic.com/generate_204", "https://cp.cloudflare.com/generate_204"]
var _requests: Array[HTTPRequest] = []
var _results: Array[bool] = []
var _generation := 0
var _failures := 0

func probe(host: String, port: int) -> void:
	if not _requests.is_empty():
		return
	_generation += 1
	_results.clear()
	var generation := _generation
	for url in TARGETS:
		var request := HTTPRequest.new()
		request.timeout = 8
		request.max_redirects = 0
		request.body_size_limit = 4096
		add_child(request)
		request.set_http_proxy(host, port)
		request.set_https_proxy(host, port)
		_requests.append(request)
		request.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
			_finish(request, generation, result == HTTPRequest.RESULT_SUCCESS and code == 204)
		)
		var error := request.request(url, PackedStringArray(["Cache-Control: no-cache"]))
		if error != OK:
			_finish.call_deferred(request, generation, false)

func _finish(request: HTTPRequest, generation: int, ok: bool) -> void:
	if generation != _generation:
		return
	_requests.erase(request)
	request.queue_free()
	_results.append(ok)
	if _results.size() != TARGETS.size():
		return
	var successes := _results.count(true)
	_failures = _failures + 1 if successes == 0 else 0
	if successes == TARGETS.size():
		checked.emit("healthy", "代理入口 HTTPS 检查通过")
	elif successes > 0:
		checked.emit("partial", "代理可用，但部分检测站点不可达")
	elif _failures < 2:
		checked.emit("checking", "代理入口访问失败，正在复查")
	else:
		checked.emit("failed", "内核运行中，但代理 HTTPS 访问失败；请检查节点、DNS 或上游网络")

func cancel() -> void:
	_generation += 1
	for request in _requests:
		request.cancel_request()
		request.queue_free()
	_requests.clear()
	_results.clear()
	_failures = 0

func _exit_tree() -> void:
	cancel()
