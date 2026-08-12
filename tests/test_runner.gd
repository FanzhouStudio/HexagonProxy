extends SceneTree

const CoreControllerScript = preload("res://scripts/core_controller.gd")

func _init() -> void:
	var controller := CoreControllerScript.new()
	root.add_child(controller)
	await process_frame
	assert(controller.CONTROLLER_PORT == 19090)
	assert(controller.MIXED_PORT == 7890)
	assert(controller.has_core())
	assert(controller.core_path().contains("runtime"))
	assert(FileAccess.file_exists(controller.profile_path()))
	var profile := FileAccess.get_file_as_string(controller.profile_path())
	assert(profile.contains("mixed-port: 7890"))
	assert(profile.contains("MATCH,六角选择"))
	assert(controller._registry_string_value("    ProxyServer    REG_SZ    127.0.0.1:8888", "REG_SZ") == "127.0.0.1:8888")
	assert(controller._looks_like_base64("dmxlc3M6Ly9leGFtcGxl"))
	assert(not controller._looks_like_base64("not base64!"))
	var base64_sample := Marshalls.utf8_to_base64("vless://example")
	assert(controller._decode_base64_text(base64_sample) == "vless://example")
	assert(controller.autostart_command().contains("--tray-start"))
	assert(controller.autostart_command().contains("--path"))
	print("PASS: 六角代理基础配置与控制器")
	quit(0)
