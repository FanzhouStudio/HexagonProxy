extends SceneTree

const ServiceScript = preload("res://scripts/modules/mihomo/core_update_service.gd")

class TestConfig:
	func runtime_dir() -> String:
		return ProjectSettings.globalize_path("user://download-transport-test")
	func core_path() -> String:
		return runtime_dir().path_join("mihomo.exe")

class RetryService extends ServiceScript:
	var retry_calls := 0
	var selected_url := ""
	var reply := {"ok": true, "body": JSON.stringify({"assets": [{
		"name": "mihomo-windows-amd64-v3-v1.gz",
		"browser_download_url": "https://example.com/core.gz", "digest": "sha256:abcd",
	}]}).to_utf8_buffer()}
	func _native_download(_url: String, _destination: String, _timeout: int) -> Dictionary:
		retry_calls += 1
		return reply
	func _start_archive_download(url: String, _name: String) -> void:
		selected_url = url

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var service := RetryService.new()
	root.add_child(service)
	service.bind_config(TestConfig.new())
	var outcomes: Array = []
	service.finished.connect(func(ok: bool, message: String) -> void: outcomes.append([ok, message]))
	service._busy = true
	await service._on_release_received(HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR, 0, PackedStringArray(), PackedByteArray())
	assert(service.retry_calls == 1 and service.selected_url == "https://example.com/core.gz")
	assert(service._expected_sha256 == "abcd" and service.is_busy() and outcomes.is_empty())
	service.reply = {"ok": false, "message": "certificate rejected"}
	await service._on_archive_received(HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR, 0, PackedStringArray(), PackedByteArray())
	assert(service.retry_calls == 2 and not service.is_busy())
	assert(outcomes.size() == 1 and not outcomes[0][0] and outcomes[0][1].contains("certificate rejected"))
	await service._on_release_received(HTTPRequest.RESULT_SUCCESS, 403, PackedStringArray(), PackedByteArray())
	assert(service.retry_calls == 2, "HTTP errors must not trigger TLS fallback")
	service.queue_free()
	print("PASS: TLS fallback for metadata/archive, digest preservation and HTTP error handling")
	quit(0)
