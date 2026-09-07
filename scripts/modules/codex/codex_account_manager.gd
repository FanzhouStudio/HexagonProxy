class_name CodexAccountManager
extends Node

signal usage_changed(account_id: String, usage: Dictionary)
signal accounts_changed

var store: CodexAccountStore
var usage_service: CodexUsageService
var switch_controller: CodexSwitchController
var profile_service: CodexProfileService

func setup(s: CodexAccountStore, u: CodexUsageService, c: CodexSwitchController, p: CodexProfileService = null) -> void:
	store = s
	usage_service = u
	switch_controller = c
	profile_service = p

func accounts() -> Array:
	return store.all() if store else []

func switch_account(account_id: String) -> Dictionary:
	if switch_controller == null:
		return {"ok": false, "message": "Switch controller unavailable."}
	return await switch_controller.switch_to(account_id)

func create_account(name: String) -> Dictionary:
	if profile_service == null:
		return {"ok": false, "message": "Profile service unavailable."}
	var result := await profile_service.create_profile(name)
	if bool(result.get("ok", false)):
		accounts_changed.emit()
	return result

func usage(account_id: String) -> Dictionary:
	return usage_service.get_usage(account_id) if usage_service else {}

func refresh_usage(account_id: String) -> Dictionary:
	var data := await usage_service.refresh_usage(account_id)
	usage_changed.emit(account_id, data)
	return data
