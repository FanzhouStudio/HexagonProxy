class_name PortConflictService
extends Node

## Windows 端口占用诊断与用户确认后的释放服务。
## 不自动结束进程；调用者必须先 inspect，再由用户确认 release。

const ProxyConfigScript = preload("res://scripts/modules/proxy/proxy_config.gd")
const HELPER_SOURCE := "res://scripts/windows_port_helper.ps1"
const PROTECTED_PROCESS_NAMES := [
	"system", "registry", "smss", "csrss", "wininit",
	"services", "lsass", "winlogon", "svchost"
]

var proxy_config

func bind_config(config) -> void:
	proxy_config = config

func initialize() -> void:
	_ensure_config()
	DirAccess.make_dir_recursive_absolute(proxy_config.runtime_dir())
	_install_helper()

func inspect_port(port: int) -> Dictionary:
	if OS.get_name() != "Windows":
		return _failure("端口占用释放目前仅支持 Windows。")
	if port < 1 or port > 65535:
		return _failure("端口范围无效。")
	return _call_helper("inspect", port, PackedInt32Array())
func release_port(port: int, pids: PackedInt32Array) -> Dictionary:
	if OS.get_name() != "Windows":
		return _failure("端口占用释放目前仅支持 Windows。")
	if pids.is_empty():
		return _failure("没有可结束的占用进程。")
	return _call_helper("release", port, pids)

func is_protected_process(process_name: String, pid: int) -> bool:
	if pid <= 4 or pid == OS.get_process_id():
		return true
	return process_name.to_lower().trim_suffix(".exe") in PROTECTED_PROCESS_NAMES

func helper_path() -> String:
	_ensure_config()
	return proxy_config.runtime_dir().path_join("windows_port_helper.ps1")

func _call_helper(action: String, port: int, pids: PackedInt32Array) -> Dictionary:
	if not FileAccess.file_exists(helper_path()):
		_install_helper()
	if not FileAccess.file_exists(helper_path()):
		return _failure("端口诊断助手不可用。")
	var output: Array = []
	var pid_parts := PackedStringArray()
	for pid in pids:
		pid_parts.append(str(pid))
	var pid_text := ",".join(pid_parts)
	var args := PackedStringArray([
		"-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
		"-File", helper_path(), "-Action", action, "-Port", str(port),
		"-CallerPid", str(OS.get_process_id()),
		"-ProtectedNames", ";".join(PROTECTED_PROCESS_NAMES)
	])
	if not pid_text.is_empty():
		args.append_array(PackedStringArray(["-Pids", pid_text]))
	var exit_code := OS.execute("powershell.exe", args, output, true, false)
	var text := "\n".join(output).strip_edges()
	if exit_code != 0:
		return _failure("端口操作失败，请检查 Windows 权限。")
	var parsed = JSON.parse_string(text)
	if parsed is Dictionary:
		var result: Dictionary = parsed
		result["message"] = _message_for_result(result, port)
		return result
	return _failure("端口助手返回了无法识别的结果。")

func _message_for_result(result: Dictionary, port: int) -> String:
	var code := str(result.get("message_code", ""))
	match code:
		"occupied": return "端口 %d 已被占用。" % port
		"free": return "端口 %d 当前可用。" % port
		"already_free": return "端口 %d 已经可用。" % port
		"protected": return "检测到受保护的系统进程，已拒绝结束。"
		"changed": return "端口占用进程已经变化，请重新检测后再试。"
		"kill_failed": return "无法结束占用进程，请检查 Windows 权限。"
		"still_occupied": return "进程已结束，但端口 %d 仍被占用。" % port
		"released": return "端口 %d 已释放。" % port
	return "端口操作已完成。" if bool(result.get("ok", false)) else "端口操作失败。"

func _install_helper() -> void:
	_ensure_config()
	var source := FileAccess.open(HELPER_SOURCE, FileAccess.READ)
	if source == null:
		return
	var target := FileAccess.open(helper_path(), FileAccess.WRITE)
	if target != null:
		target.store_buffer(source.get_buffer(source.get_length()))
		target.close()
	source.close()

func _ensure_config() -> void:
	if proxy_config == null:
		proxy_config = ProxyConfigScript.new()

func _failure(message: String) -> Dictionary:
	return {"ok": false, "message": message}

func dispose() -> void:
	pass
