class_name ApplicationRoutingStore
extends RefCounted

## 应用分流规则仓储
## 仅负责 JSON 持久化，不参与 UI/YAML 生成。

const SETTINGS_PATH := "user://application_routing.json"

func load_state() -> Dictionary:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return {"version": 1, "enabled": true, "rules": []}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS_PATH))
	if not parsed is Dictionary:
		return {"version": 1, "enabled": true, "rules": []}
	var rules: Array = []
	var raw_rules: Variant = parsed.get("rules", [])
	if raw_rules is Array:
		for item in raw_rules:
			if item is Dictionary and not str(item.get("id", "")).is_empty():
				rules.append(_normalize_rule(item))
	return {
		"version": 1,
		"enabled": bool(parsed.get("enabled", true)),
		"rules": rules
	}
func save_state(enabled: bool, rules: Array) -> bool:
	var payload := {
		"version": 1,
		"enabled": enabled,
		"rules": rules
	}
	var temporary := SETTINGS_PATH + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(payload, "  "))
	file.close()
	if FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(SETTINGS_PATH)
	return DirAccess.rename_absolute(temporary, SETTINGS_PATH) == OK

func _normalize_rule(rule: Dictionary) -> Dictionary:
	return {
		"id": str(rule.get("id", "")),
		"display_name": str(rule.get("display_name", rule.get("process_name", "应用"))),
		"path": str(rule.get("path", "")),
		"process_name": str(rule.get("process_name", "")),
		"target": str(rule.get("target", "proxy")),
		"enabled": bool(rule.get("enabled", true))
	}
