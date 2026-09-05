class_name ProxyLauncher
extends Node

## Mihomo 启动器
## 负责启动参数和进程调用

signal launched(pid: int)

var process: ProxyProcess

func setup(target_process: ProxyProcess) -> void:
	process = target_process

func launch(executable: String, args: PackedStringArray = PackedStringArray()) -> bool:
	if process == null:
		return false

	var result := process.launch(executable, args)
	if result:
		launched.emit(process.pid)
	return result

func launch_mihomo(executable: String, runtime_dir: String, profile_path: String, host: String, port: int, secret: String) -> bool:
	var args := PackedStringArray([
		"-d", runtime_dir,
		"-f", profile_path,
		"-ext-ctl", "%s:%d" % [host, port],
		"-secret", secret
	])
	return launch(executable, args)

func stop() -> void:
	if process:
		process.stop()
