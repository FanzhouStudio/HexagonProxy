class_name NodeFailoverStore
extends RefCounted

## 节点故障切换持久化仓储
## 只负责 JSON 读写与基础数据清洗。

const STORAGE_PATH := "user://node_failover.json"
const DEFAULT_SETTINGS := {
	"probe_interval_sec": 10,
	"failure_threshold": 2,
	"cooldown_sec": 30,
	"circuit_reset_sec": 60,
	"max_delay_ms": 5000
}

func load_state() -> Dictionary:
	var state := _default_state()
	if not FileAccess.file_exists(STORAGE_PATH):
		return state
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(STORAGE_PATH))
	if not parsed is Dictionary:
		return state
	state["enabled"] = bool(parsed.get("enabled", true))
	state["settings"] = _sanitize_settings(parsed.get("settings", {}))
	state["backups"] = _sanitize_backups(parsed.get("backups", []))
	return state
func save_state(state: Dictionary) -> bool:
	var normalized := {
		"version": 1,
		"enabled": bool(state.get("enabled", true)),
		"settings": _sanitize_settings(state.get("settings", {})),
		"backups": _sanitize_backups(state.get("backups", []))
	}
	var path := ProjectSettings.globalize_path(STORAGE_PATH)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var temp_path := path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(normalized, "  "))
	file.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	return DirAccess.rename_absolute(temp_path, path) == OK

func _default_state() -> Dictionary:
	return {
		"enabled": true,
		"settings": DEFAULT_SETTINGS.duplicate(true),
		"backups": []
	}
func _sanitize_settings(value: Variant) -> Dictionary:
	var source: Dictionary = value if value is Dictionary else {}
	return {
		"probe_interval_sec": clampi(int(source.get("probe_interval_sec", DEFAULT_SETTINGS.probe_interval_sec)), 3, 60),
		"failure_threshold": clampi(int(source.get("failure_threshold", DEFAULT_SETTINGS.failure_threshold)), 1, 10),
		"cooldown_sec": clampi(int(source.get("cooldown_sec", DEFAULT_SETTINGS.cooldown_sec)), 5, 300),
		"circuit_reset_sec": clampi(int(source.get("circuit_reset_sec", DEFAULT_SETTINGS.circuit_reset_sec)), 15, 900),
		"max_delay_ms": clampi(int(source.get("max_delay_ms", DEFAULT_SETTINGS.max_delay_ms)), 100, 10000)
	}

func _sanitize_backups(value: Variant) -> Array:
	var result: Array = []
	if not value is Array:
		return result
	var seen := {}
	for item in value:
		if not item is Dictionary:
			continue
		var group := str(item.get("group", "")).strip_edges()
		var node := str(item.get("node", "")).strip_edges()
		var key := "%s\n%s" % [group, node]
		if group.is_empty() or node.is_empty() or seen.has(key):
			continue
		seen[key] = true
		result.append({"group": group, "node": node})
	return result
