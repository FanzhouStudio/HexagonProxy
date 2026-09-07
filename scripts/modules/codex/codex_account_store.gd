class_name CodexAccountStore
extends Node

signal accounts_changed

const STORE_VERSION := 2
var _accounts: Array[Dictionary] = []
var _store_path := "user://codex_accounts.json"
var _auto_save := false

func configure(path: String = "") -> void:
	if not path.is_empty():
		_store_path = path
		_auto_save = true

func load_accounts(items: Array = []) -> void:
	_accounts.clear()
	for item in items:
		if item is Dictionary and not str(item.get("id", "")).is_empty() and find(str(item["id"])).is_empty():
			_accounts.append((item as Dictionary).duplicate(true))
	accounts_changed.emit()

func all() -> Array:
	var result: Array = []
	for item in _accounts:
		result.append(item.duplicate(true))
	return result

func find(account_id: String) -> Dictionary:
	for item in _accounts:
		if str(item.get("id", "")) == account_id:
			return item
	return {}

func add(account: Dictionary) -> bool:
	if str(account.get("id", "")).is_empty() or not find(str(account.get("id", ""))).is_empty():
		return false
	_accounts.append(account.duplicate(true))
	save()
	accounts_changed.emit()
	return true

func remove(account_id: String) -> bool:
	for i in range(_accounts.size()):
		if str(_accounts[i].get("id", "")) == account_id:
			_accounts.remove_at(i)
			save()
			accounts_changed.emit()
			return true
	return false

func update(account_id: String, patch: Dictionary) -> bool:
	var account := find(account_id)
	if account.is_empty():
		return false
	for key in patch.keys():
		account[key] = patch[key]
	save()
	accounts_changed.emit()
	return true

func save() -> void:
	if not _auto_save:
		return
	var file := FileAccess.open(_store_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({
			"version": STORE_VERSION,
			"accounts": _accounts
		}))
		file.close()

func _load() -> void:
	if not FileAccess.file_exists(_store_path):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(_store_path))
	if data is Dictionary:
		var items = data.get("accounts", [])
		if items is Array:
			for item in items:
				if item is Dictionary:
					_accounts.append((item as Dictionary).duplicate(true))
