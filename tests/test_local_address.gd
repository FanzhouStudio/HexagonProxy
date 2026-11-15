extends SceneTree
const Transformer = preload("res://scripts/modules/proxy/local_address_transformer.gd")
const Config = preload("res://scripts/modules/proxy/proxy_config.gd")
const CoreProcess = preload("res://scripts/modules/proxy/proxy_process.gd")
var server := TCPServer.new()
var peer: StreamPeerTCP
var core
var done := false
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	var transform = Transformer.new()
	var source := "mixed-port: 7890\nrules:\n  - PROCESS-NAME,test.exe,REJECT\n  - MATCH,REJECT\n"
	var output: String = transform.transform_profile(source).content
	if output.find("IP-CIDR,127.0.0.0/8,DIRECT") > output.find("PROCESS-NAME") or transform.transform_profile(output).content != output:
		_finish(false, "local rules precedence/idempotence")
		return
	var inline_result: Dictionary = transform.transform_profile('rules: ["MATCH,REJECT"]\n')
	if not inline_result.ok or not inline_result.content.contains('"MATCH,REJECT"'):
		_finish(false, "inline rules preservation")
		return
	var cfg = Config.new()
	var mixed: int = cfg.random_available_port()
	var local_port: int = cfg.random_available_port(mixed)
	if server.listen(local_port, "127.0.0.1") != OK:
		_finish(false, "local server startup")
		return
	var path := ProjectSettings.globalize_path("user://local-address-test.yaml")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(transform.transform_profile("mixed-port: %d\nmode: rule\nproxies: []\nrules:\n  - MATCH,REJECT\n" % mixed).content)
	file.close()
	core = CoreProcess.new()
	root.add_child(core)
	if not core.launch(ProjectSettings.globalize_path("res://bin/mihomo.exe"), PackedStringArray(["-d", ProjectSettings.globalize_path("user://"), "-f", path])):
		_finish(false, "core startup")
		return
	await create_timer(1).timeout
	var request := HTTPRequest.new()
	root.add_child(request)
	request.timeout = 5
	request.set_http_proxy("127.0.0.1", mixed)
	request.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
		_finish(result == HTTPRequest.RESULT_SUCCESS and code == 200 and body.get_string_from_utf8() == "local-ok", "localhost through mixed proxy with MATCH,REJECT")
	)
	request.request("http://127.0.0.1:%d/" % local_port)
	await create_timer(7).timeout
	if not done:
		_finish(false, "local request timeout")
func _process(_delta: float) -> bool:
	if peer == null and server.is_connection_available():
		peer = server.take_connection()
	if peer:
		peer.poll()
		if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED and peer.get_available_bytes() > 0:
			peer.get_data(peer.get_available_bytes())
			peer.put_data("HTTP/1.1 200 OK\r\nContent-Length: 8\r\nConnection: close\r\n\r\nlocal-ok".to_utf8_buffer())
	return false
func _finish(ok: bool, message: String) -> void:
	if done:
		return
	done = true
	if core:
		core.stop()
	server.stop()
	if ok:
		print("PASS: local address protection, rule priority and real core localhost request")
	else:
		printerr("FAIL: " + message)
	quit(0 if ok else 1)
