class_name MihomoApiService
extends Node

signal request_finished(action: String, ok: bool, payload: Variant)

const DEFAULT_CONTROLLER_HOST := "127.0.0.1"
const DEFAULT_CONTROLLER_PORT := 19090

var proxy_config
var api_secret := ""
var _requests: Dictionary = {}

func bind_config(config) -> void:
	proxy_config = config

func set_secret(secret: String) -> void:
	api_secret = secret

func request(action: String, endpoint: String, method: int, body := "") -> void:
	if _requests.has(action):
		return
	var http_request := HTTPRequest.new()
	http_request.timeout = 8.0
	add_child(http_request)
	_requests[action] = http_request

	http_request.request_completed.connect(func(result: int, response_code: int, _headers: PackedStringArray, data: PackedByteArray) -> void:
		_requests.erase(action)
		var ok := result == HTTPRequest.RESULT_SUCCESS and response_code >= 200 and response_code < 300
		var payload: Variant = {}
		if not data.is_empty():
			var decoded: Variant = JSON.parse_string(data.get_string_from_utf8())
			payload = decoded if decoded != null else data.get_string_from_utf8()
		request_finished.emit(action, ok, payload)
		http_request.queue_free()
	)

	var headers := PackedStringArray([
		"Authorization: Bearer %s" % api_secret,
		"Content-Type: application/json"
	])
	var controller_host := DEFAULT_CONTROLLER_HOST
	var controller_port := DEFAULT_CONTROLLER_PORT
	if proxy_config != null:
		controller_host = str(proxy_config.controller_host())
		controller_port = int(proxy_config.controller_port())
	var error := http_request.request(
		"http://%s:%d%s" % [controller_host, controller_port, endpoint],
		headers,
		method,
		body
	)
	if error != OK:
		_requests.erase(action)
		request_finished.emit(action, false, {"error": error_string(error)})
		http_request.queue_free()

func cancel_all() -> void:
	for value in _requests.values():
		var http_request := value as HTTPRequest
		if is_instance_valid(http_request):
			http_request.cancel_request()
			http_request.queue_free()
	_requests.clear()
