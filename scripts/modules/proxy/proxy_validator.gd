class_name ProxyValidator
extends Node

## Mihomo 配置校验模块

signal validation_failed(message: String)

var core_path := ""
var runtime_path := ""
var profile_path := ""

func setup(core: String, runtime: String, profile: String) -> void:
	core_path = core
	runtime_path = runtime
	profile_path = profile

func validate() -> Dictionary:
	if core_path.is_empty():
		return {"ok": false, "message": "未找到 Mihomo 内核"}

	var output: Array = []
	var exit_code := OS.execute(core_path, PackedStringArray([
		"-t", "-d", runtime_path, "-f", profile_path
	]), output, true, false)

	if exit_code == 0:
		return {"ok": true, "message": ""}

	var detail := ""
	if not output.is_empty():
		detail = str(output.back()).strip_edges()

	validation_failed.emit(detail)
	return {"ok": false, "message": detail}
