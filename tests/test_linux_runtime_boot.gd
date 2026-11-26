extends SceneTree

const Service = preload("res://scripts/modules/linux/linux_workspace_service.gd")
var _cookie := ""
var _csrf := ""
var _base := ""

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var service := Service.new()
	service.storage_override = ProjectSettings.globalize_path("user://linux-live-small")
	root.add_child(service)
	service.initialize()
	service.reset_workspace()
	assert(service.start_workspace(1))
	var deadline := Time.get_ticks_msec() + 240000
	while not service.workspace_ready and Time.get_ticks_msec() < deadline:
		if not service.last_error.is_empty():
			print("BOOT DIAGNOSTIC: " + service.last_error)
		if not service.busy and service.process_id <= 0:
			break
		await create_timer(1.0).timeout
	if not service.workspace_ready:
		print("FAIL: " + service.status + " " + service.last_error)
		await service.shutdown()
		service.dispose()
		quit(1)
		return
	assert(service.disk_gb == 1)
	assert(service.snapshot().disk_bytes < 1073741824)
	print("PASS: real QEMU TCG + Linux + Tuxee HTTP ready on a 1 GB disk")
	_base = "http://127.0.0.1:%d" % service.web_port
	assert(await _login(service))
	var payload := "HexagonProxy persistent workspace check"
	var upload := await _request("/api/upload?path=/root/hexagon-persistence.txt", HTTPClient.METHOD_POST, payload, PackedStringArray(["X-Tuxee-Size: %d" % payload.length()]))
	assert(upload.code == 200, "Authenticated write failed: " + str(upload.code))
	print("PASS: real PAM login and authenticated file write")
	await _stop(service)
	for capacity in [1, 10]:
		assert(service.start_workspace(capacity))
		deadline = Time.get_ticks_msec() + 90000
		while not service.workspace_ready and Time.get_ticks_msec() < deadline:
			if not service.busy and service.process_id <= 0:
				break
			await create_timer(0.5).timeout
		if not service.workspace_ready:
			print("FAIL: restart/resize: " + service.last_error)
			await service.shutdown()
			service.dispose()
			quit(1)
			return
		_base = "http://127.0.0.1:%d" % service.web_port
		assert(await _login(service))
		var download := await _request("/api/download?path=/root/hexagon-persistence.txt", HTTPClient.METHOD_GET)
		assert(download.code == 200 and download.body == payload, "File lost across restart or resize")
		assert(service.snapshot().disk_bytes <= capacity * 1073741824)
		print("PASS: PAM login + preserved file after restart at %d GB" % capacity)
		await _stop(service)
	assert(await service.shutdown())
	service.dispose()
	service.free()
	quit()

func _stop(service: Node) -> void:
	service.stop_workspace()
	var deadline := Time.get_ticks_msec() + 15000
	while service.process_id > 0 and Time.get_ticks_msec() < deadline:
		await create_timer(0.2).timeout
	assert(service.process_id <= 0, "Guest did not shut down cleanly")

func _login(service: Node) -> bool:
	_cookie = ""
	_csrf = ""
	var response := await _request("/api/login", HTTPClient.METHOD_POST, JSON.stringify({"username": "root", "password": service._password}))
	if response.code != 200:
		print("Login status: ", response.code, " ", response.body.left(400))
		return false
	var parsed: Dictionary = JSON.parse_string(response.body)
	_csrf = str(parsed.get("csrf", ""))
	for header in response.headers:
		if str(header).to_lower().begins_with("set-cookie:"):
			_cookie = str(header).substr(11).strip_edges().get_slice(";", 0)
	return not _csrf.is_empty() and not _cookie.is_empty()

func _request(endpoint: String, method: int, body := "", extra := PackedStringArray()) -> Dictionary:
	var request := HTTPRequest.new()
	request.timeout = 15
	root.add_child(request)
	var headers := PackedStringArray(["Content-Type: application/json", "X-Tuxee-Client: web", "Origin: " + _base])
	if not _cookie.is_empty():
		headers.append("Cookie: " + _cookie)
		headers.append("X-Tuxee-CSRF: " + _csrf)
	headers.append_array(extra)
	assert(request.request(_base + endpoint, headers, method, body) == OK)
	var response: Array = await request.request_completed
	request.queue_free()
	return {"code": int(response[1]), "headers": response[2], "body": response[3].get_string_from_utf8()}
