class_name UiThemeService
extends Node

signal theme_changed(snapshot: Dictionary)
signal event_logged(message: String)

const CATALOG_PATH := "res://assets/ui/themes.json"
const SETTINGS_PATH := "user://ui_theme.cfg"

var _themes: Dictionary = {}
var _order: Array[String] = []
var _default_id := "blue_healing"
var _current_id := "blue_healing"

func initialize() -> void:
	_load_catalog()
	_load_selection()

func current_theme_id() -> String:
	return _current_id

func catalog() -> Array:
	var result: Array = []
	for theme_id in _order:
		var data: Dictionary = _themes.get(theme_id, {})
		result.append({
			"id": theme_id,
			"name": str(data.get("name", theme_id)),
			"description": str(data.get("description", ""))
		})
	return result

func snapshot() -> Dictionary:
	var data: Dictionary = _themes.get(_current_id, {})
	var result := data.duplicate(true)
	result["id"] = _current_id
	return result

func set_theme(theme_id: String) -> Dictionary:
	if not _themes.has(theme_id):
		return {"ok": false, "message": "未知界面主题。"}
	if theme_id == _current_id:
		return {"ok": true, "message": "界面主题未变化。", "theme": snapshot()}
	_current_id = theme_id
	_save_selection()
	var current := snapshot()
	theme_changed.emit(current)
	event_logged.emit("界面主题已切换为：%s" % str(current.get("name", theme_id)))
	return {"ok": true, "message": "界面主题已更新。", "theme": current}

func _load_catalog() -> void:
	_themes.clear()
	_order.clear()
	var raw := FileAccess.get_file_as_string(CATALOG_PATH)
	var parsed: Variant = JSON.parse_string(raw)
	if not parsed is Dictionary:
		push_error("UI theme catalog is invalid")
		return
	_default_id = str(parsed.get("default", _default_id))

	var theme_list: Variant = parsed.get("themes", [])
	if not theme_list is Array:
		return
	for item in theme_list:
		if not item is Dictionary:
			continue
		var theme_id := str(item.get("id", ""))
		if theme_id.is_empty():
			continue
		_themes[theme_id] = item.duplicate(true)
		_order.append(theme_id)
	if not _themes.has(_default_id) and not _order.is_empty():
		_default_id = _order[0]
	_current_id = _default_id

func _load_selection() -> void:
	var settings := ConfigFile.new()
	if settings.load(SETTINGS_PATH) != OK:
		return
	var saved := str(settings.get_value("ui", "theme", _default_id))
	if _themes.has(saved):
		_current_id = saved

func _save_selection() -> void:
	var settings := ConfigFile.new()
	settings.set_value("ui", "theme", _current_id)
	settings.save(SETTINGS_PATH)

func dispose() -> void:
	_themes.clear()
	_order.clear()
