extends SceneTree

const ServiceScript = preload("res://scripts/modules/mihomo/core_update_service.gd")

class TestConfig:
	func runtime_dir() -> String:
		return ProjectSettings.globalize_path("user://core-network-test")
	func core_path() -> String:
		return runtime_dir().path_join("mihomo.exe")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var service := ServiceScript.new()
	root.add_child(service)
	service.bind_config(TestConfig.new())
	service.progress_changed.connect(func(_progress: float, message: String) -> void: print(message))
	service.finished.connect(func(ok: bool, message: String) -> void:
		print("PASS: actual download, digest and executable validation" if ok else "FAIL: " + message)
		service.queue_free()
		quit(0 if ok else 1)
	)
	# Force the same metadata TLS failure as the reported screenshot, then exercise
	# the real Windows fallback and archive download through the normal installer.
	DirAccess.make_dir_recursive_absolute(service.runtime_dir())
	service._busy = true
	service._generation += 1
	service._on_release_received(HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR, 0, PackedStringArray(), PackedByteArray())
