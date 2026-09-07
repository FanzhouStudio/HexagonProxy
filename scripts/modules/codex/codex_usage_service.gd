class_name CodexUsageService
extends Node

signal usage_updated(profile_id: String, usage: Dictionary)

var _cache: Dictionary = {}
var _profile_service: CodexProfileService

func setup(service: CodexProfileService) -> void:
	_profile_service = service

func get_usage(profile_id: String) -> Dictionary:
	if _profile_service:
		return _profile_service.account_store.find(profile_id).get("usage", {}).duplicate(true)
	if _cache.has(profile_id):
		return (_cache[profile_id] as Dictionary).duplicate(true)
	return {
		"five_hour": -1,
		"weekly": -1,
		"updated_at": ""
	}

func set_usage(profile_id: String, usage: Dictionary) -> void:
	_cache[profile_id] = usage.duplicate(true)
	usage_updated.emit(profile_id, get_usage(profile_id))

func refresh_usage(profile_id: String) -> Dictionary:
	if _profile_service == null:
		return {"ok": false, "message": "额度服务尚未连接。"}
	var result := await _profile_service.refresh_usage(profile_id)
	if bool(result.get("ok", false)):
		usage_updated.emit(profile_id, result.get("usage", {}))
	return result

func format_percent(value: float) -> String:
	if value < 0:
		return "未知"
	return "%d%%" % int(clampf(value, 0, 100))
