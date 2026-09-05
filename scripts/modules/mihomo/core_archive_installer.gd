class_name CoreArchiveInstaller
extends RefCounted

## Mihomo 本地安装器
## 负责压缩包解包、可执行文件校验与原子替换。

func install_archive(archive_path: String, core_path: String) -> Dictionary:
	var extracted: Dictionary = _extract_executable(archive_path)
	if not bool(extracted.get("ok", false)):
		return extracted
	var exe_bytes: PackedByteArray = extracted.get("bytes", PackedByteArray())
	if exe_bytes.size() < 2 or exe_bytes[0] != 0x4d or exe_bytes[1] != 0x5a:
		return _failure("压缩包内没有 mihomo.exe")
	return _install_executable(exe_bytes, core_path)

func _extract_executable(path: String) -> Dictionary:
	if path.ends_with(".gz"):
		var compressed := FileAccess.get_file_as_bytes(path)
		var bytes := compressed.decompress_dynamic(256 * 1024 * 1024, FileAccess.COMPRESSION_GZIP)
		if bytes.is_empty():
			return _failure("压缩包内没有 mihomo.exe")
		return {"ok": true, "bytes": bytes}
	var zip := ZIPReader.new()
	var open_error := zip.open(path)
	if open_error != OK:
		return _failure("压缩包损坏（%s）" % error_string(open_error))
	var exe_bytes := PackedByteArray()
	for file_name in zip.get_files():
		var executable_name := file_name.get_file().to_lower()
		if executable_name.begins_with("mihomo") and executable_name.ends_with(".exe"):
			exe_bytes = zip.read_file(file_name)
			break
	zip.close()
	if exe_bytes.is_empty():
		return _failure("压缩包内没有 mihomo.exe")
	return {"ok": true, "bytes": exe_bytes}

func _install_executable(exe_bytes: PackedByteArray, core_path: String) -> Dictionary:
	var installing_path := core_path.get_basename() + ".installing.exe"
	var output := FileAccess.open(installing_path, FileAccess.WRITE)
	if output == null:
		return _failure("无法写入内核目录")
	output.store_buffer(exe_bytes)
	output.close()
	var version_output: Array = []
	var version_exit_code := OS.execute(
		installing_path, PackedStringArray(["-v"]), version_output, true, false
	)
	if version_exit_code != 0:
		DirAccess.remove_absolute(installing_path)
		return _failure("新内核无法运行，已保留原版本")
	var backup_path := core_path.get_basename() + ".backup.exe"
	if FileAccess.file_exists(backup_path):
		DirAccess.remove_absolute(backup_path)
	if FileAccess.file_exists(core_path) and DirAccess.rename_absolute(core_path, backup_path) != OK:
		DirAccess.remove_absolute(installing_path)
		return _failure("旧内核正在使用或无法替换")
	if DirAccess.rename_absolute(installing_path, core_path) != OK:
		_restore_backup(backup_path, core_path)
		return _failure("安装新内核失败，已恢复原版本")
	if FileAccess.file_exists(backup_path):
		DirAccess.remove_absolute(backup_path)
	return {"ok": true, "message": "Mihomo 内核已就绪"}

func _restore_backup(backup_path: String, core_path: String) -> void:
	if FileAccess.file_exists(backup_path):
		DirAccess.rename_absolute(backup_path, core_path)

func _failure(message: String) -> Dictionary:
	return {"ok": false, "message": message}
