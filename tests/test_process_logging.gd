extends SceneTree
const ProcessScript = preload("res://scripts/modules/proxy/proxy_process.gd")
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	var process = ProcessScript.new()
	root.add_child(process)
	if not process.launch("powershell.exe", PackedStringArray(["-NoProfile", "-Command", "[Console]::Out.WriteLine('stdout-test');[Console]::Error.WriteLine('stderr-test');Start-Sleep -Seconds 5"])):
		quit(1)
		return
	await create_timer(2.0).timeout
	var log := FileAccess.get_file_as_string("user://diagnostics/mihomo-current.log")
	if not log.contains("stdout-test") or not log.contains("stderr-test") or not process.is_running():
		process.stop()
		printerr("FAIL: live stdout/stderr collection")
		quit(2)
		return
	process.stop()
	if process.is_running():
		quit(3)
		return
	print("PASS: nonblocking process log collection and stop")
	quit(0)
