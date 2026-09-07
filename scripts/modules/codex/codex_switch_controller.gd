class_name CodexSwitchController
extends Node

signal switch_started
signal switch_finished(result: Dictionary)

var _profile_service: CodexProfileService

func setup(profile_service: CodexProfileService) -> void:
	_profile_service = profile_service

func switch_to(account_id: String) -> Dictionary:
	if _profile_service == null:
		return {"ok": false, "message": "Profile service unavailable."}

	switch_started.emit()
	var result := await _profile_service.switch_profile(account_id)
	switch_finished.emit(result)
	return result

func launch_current() -> Dictionary:
	if _profile_service == null:
		return {"ok": false, "message": "Profile service unavailable."}
	return await _profile_service.launch_selected()
