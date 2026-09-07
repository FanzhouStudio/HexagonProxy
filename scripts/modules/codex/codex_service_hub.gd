class_name CodexServiceHub
extends Node

# Codex 账号功能统一入口。
# 负责连接账号、profile、切换、额度模块。

var account_manager: CodexAccountManager
var account_store: CodexAccountStore
var usage_service: CodexUsageService
var switch_controller: CodexSwitchController

func setup(profile_service: CodexProfileService) -> void:
	account_store = profile_service.account_store
	usage_service = CodexUsageService.new()
	add_child(usage_service)
	usage_service.setup(profile_service)
	switch_controller = CodexSwitchController.new()
	add_child(switch_controller)
	switch_controller.setup(profile_service)

	account_manager = CodexAccountManager.new()
	add_child(account_manager)
	account_manager.setup(
		account_store,
		usage_service,
		switch_controller,
		profile_service
	)

func get_accounts() -> Array:
	return account_manager.accounts() if account_manager else []

func switch_account(account_id: String) -> Dictionary:
	if account_manager == null:
		return {"ok": false}
	return await account_manager.switch_account(account_id)

func get_usage(account_id: String) -> Dictionary:
	if account_manager == null:
		return {}
	return account_manager.usage(account_id)
