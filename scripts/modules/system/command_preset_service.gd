class_name CommandPresetService
extends Node

## 终端常用命令仓储服务
## 只负责命令预设的校验、CRUD 与本地持久化。

signal presets_changed
signal event_logged(message: String)

const STORAGE_PATH := "user://terminal_command_presets.json"

var _presets: Array = []
var _initialized := false

func initialize() -> void:
	if _initialized:
		return
	_initialized = true
	_load()

func list_presets() -> Array:
	initialize()
	return _presets.duplicate(true)

func add_preset(name: String, shell_name: String, command: String) -> Dictionary:
	initialize()
	var validated := _validate(name, shell_name, command)
	if not bool(validated.get("ok", false)):
		return validated
	var preset := {
		"id": "%d-%s" % [Time.get_ticks_usec(), Crypto.new().generate_random_bytes(3).hex_encode()],
		"name": name.strip_edges(),
		"shell": _normalize_shell(shell_name),
		"command": command.strip_edges()
	}
	_presets.append(preset)
	if not _save():
		_presets.pop_back()
		return {"ok": false, "message": "常用命令保存失败。"}
	presets_changed.emit()
	event_logged.emit("已添加常用命令：%s" % preset.name)
	return {"ok": true, "preset": preset.duplicate(true), "message": "常用命令已保存。"}

func update_preset(preset_id: String, name: String, shell_name: String, command: String) -> Dictionary:
	initialize()
	var validated := _validate(name, shell_name, command)
	if not bool(validated.get("ok", false)):
		return validated
	var index := _find_index(preset_id)
	if index < 0:
		return {"ok": false, "message": "常用命令不存在。"}
	var before: Dictionary = _presets[index].duplicate(true)
	_presets[index] = {
		"id": preset_id,
		"name": name.strip_edges(),
		"shell": _normalize_shell(shell_name),
		"command": command.strip_edges()
	}
	if not _save():
		_presets[index] = before
		return {"ok": false, "message": "常用命令更新失败。"}
	presets_changed.emit()
	event_logged.emit("已更新常用命令：%s" % name.strip_edges())
	return {"ok": true, "preset": _presets[index].duplicate(true), "message": "常用命令已更新。"}

func delete_preset(preset_id: String) -> Dictionary:
	initialize()
	var index := _find_index(preset_id)
	if index < 0:
		return {"ok": false, "message": "常用命令不存在。"}
	var removed: Dictionary = _presets[index].duplicate(true)
	_presets.remove_at(index)
	if not _save():
		_presets.insert(index, removed)
		return {"ok": false, "message": "常用命令删除失败。"}
	presets_changed.emit()
	event_logged.emit("已删除常用命令：%s" % str(removed.get("name", "命令")))
	return {"ok": true, "message": "常用命令已删除。"}
func _validate(name: String, shell_name: String, command: String) -> Dictionary:
	var clean_name := name.strip_edges()
	var clean_command := command.strip_edges()
	if clean_name.is_empty():
		return {"ok": false, "message": "请输入常用命令名称。"}
	if clean_name.length() > 40:
		return {"ok": false, "message": "名称最多 40 个字符。"}
	if clean_command.is_empty():
		return {"ok": false, "message": "请输入实际命令。"}
	if _normalize_shell(shell_name).is_empty():
		return {"ok": false, "message": "Shell 类型只能是 PowerShell 或 CMD。"}
	return {"ok": true}

func _normalize_shell(shell_name: String) -> String:
	var value := shell_name.strip_edges().to_lower()
	if value in ["powershell", "cmd"]:
		return value
	return ""

func _find_index(preset_id: String) -> int:
	for index in _presets.size():
		if str(_presets[index].get("id", "")) == preset_id:
			return index
	return -1
func _load() -> void:
	_presets.clear()
	if not FileAccess.file_exists(STORAGE_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(STORAGE_PATH))
	if not parsed is Dictionary:
		return
	var items: Variant = parsed.get("presets", [])
	if not items is Array:
		return
	for item in items:
		if not item is Dictionary:
			continue
		var id := str(item.get("id", ""))
		var name := str(item.get("name", "")).strip_edges()
		var shell := _normalize_shell(str(item.get("shell", "")))
		var command := str(item.get("command", "")).strip_edges()
		if id.is_empty() or name.is_empty() or shell.is_empty() or command.is_empty():
			continue
		_presets.append({"id": id, "name": name, "shell": shell, "command": command})

func _save() -> bool:
	var temp := STORAGE_PATH + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({"version": 1, "presets": _presets}, "  "))
	file.close()
	if FileAccess.file_exists(STORAGE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(STORAGE_PATH))
	return DirAccess.rename_absolute(
		ProjectSettings.globalize_path(temp),
		ProjectSettings.globalize_path(STORAGE_PATH)
	) == OK

func dispose() -> void:
	_presets.clear()
