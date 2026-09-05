class_name SubscriptionLibrary
extends RefCounted

const SubscriptionCatalogScript = preload("res://scripts/modules/subscription/subscription_catalog.gd")

## 订阅库业务状态
## 负责目录状态、活动配置同步、删除回退与启动期迁移

var proxy_config
var store
var catalog
var profile_factory
var maintenance
var legacy_migrator

func setup(config_value, store_value, factory_value, maintenance_value, migrator_value) -> void:
	proxy_config = config_value
	store = store_value
	catalog = SubscriptionCatalogScript.new()
	catalog.setup(store)
	profile_factory = factory_value
	maintenance = maintenance_value
	legacy_migrator = migrator_value

func initialize() -> Dictionary:
	var messages: Array[String] = []
	_ensure_default_profile(messages)
	catalog.load()
	_repair_loaded_entries(messages)
	var profile_name := _current_profile_name()
	if catalog.is_empty():
		var migration: Dictionary = _migrate_legacy()
		for message in migration.get("messages", []):
			messages.append(str(message))
		if bool(migration.get("migrated", false)):
			profile_name = str(migration.get("profile_name", profile_name))
	return {"profile_name": profile_name, "messages": messages}

func list() -> Array:
	return catalog.list()

func active_id() -> String:
	return str(catalog.active_id)

func active_type() -> String:
	var index: int = catalog.index_of(active_id())
	if index < 0:
		return ""
	return str(catalog.entry_at(index).get("type", ""))

func new_id() -> String:
	return catalog.new_id()

func create_entry(entry_id: String, display_name: String, kind: String, yaml: String, provider_file := "", extra := {}) -> Dictionary:
	var entry: Dictionary = store.create_entry(entry_id, display_name, kind, yaml, provider_file, extra)
	if entry.is_empty():
		return {"ok": false, "error": "无法保存订阅档案。"}
	catalog.append(entry)
	if not catalog.save():
		catalog.pop_back()
		store.remove_entry_config(entry)
		return {"ok": false, "error": "无法保存订阅索引。"}
	return {"ok": true, "entry": entry}

func activate(entry_id: String) -> Dictionary:
	var index: int = catalog.index_of(entry_id)
	if index < 0:
		return {"ok": false, "error": "找不到要启用的订阅。"}
	var entry: Dictionary = catalog.entry_at(index)
	var content: String = store.read_entry_config(entry)
	if content.is_empty():
		return {"ok": false, "error": "订阅配置文件已丢失。"}
	var previous_active_id := str(catalog.active_id)
	var previous_content := ""
	if FileAccess.file_exists(proxy_config.active_profile_path()):
		previous_content = FileAccess.get_file_as_string(proxy_config.active_profile_path())
	if not _write_profile(content):
		return {"ok": false, "error": "保存配置失败。"}
	catalog.set_active(entry_id)
	if not catalog.save():
		catalog.set_active(previous_active_id)
		if not previous_content.is_empty():
			_write_profile(previous_content)
		return {"ok": false, "error": "无法保存订阅索引。"}
	return {
		"ok": true,
		"profile_name": str(entry.get("name", "订阅"))
	}

func delete(entry_id: String) -> Dictionary:
	var index: int = catalog.index_of(entry_id)
	if index < 0:
		return {"ok": false, "error": "找不到要删除的订阅。"}
	var entry: Dictionary = catalog.entry_at(index)
	var previous_active_id := str(catalog.active_id)
	var was_active := entry_id == previous_active_id
	var next_active_id := previous_active_id
	var profile_name := _current_profile_name()
	var next_content := ""
	if was_active:
		if catalog.size() == 1:
			next_active_id = ""
			profile_name = "内置直连配置"
			next_content = profile_factory.default_profile_yaml()
		else:
			var candidate_index := index + 1 if index + 1 < catalog.size() else index - 1
			var next_entry: Dictionary = catalog.entry_at(candidate_index)
			next_active_id = str(next_entry.get("id", ""))
			profile_name = str(next_entry.get("name", "订阅"))
			next_content = store.read_entry_config(next_entry)
			if next_content.is_empty():
				return {"ok": false, "error": "订阅配置文件已丢失。"}
	catalog.remove_at(index)
	catalog.set_active(next_active_id)
	if not catalog.save():
		catalog.insert_at(index, entry)
		catalog.set_active(previous_active_id)
		return {"ok": false, "error": "无法保存订阅索引。"}
	if was_active and not _write_profile(next_content):
		catalog.insert_at(index, entry)
		catalog.set_active(previous_active_id)
		catalog.save()
		return {"ok": false, "error": "保存配置失败。"}
	store.delete_entry_files(entry)
	return {
		"ok": true,
		"was_active": was_active,
		"profile_name": profile_name,
		"deleted_name": str(entry.get("name", "订阅"))
	}

func write_profile(content: String) -> bool:
	return _write_profile(content)

func _repair_loaded_entries(messages: Array[String]) -> void:
	var index_changed := false
	for index in catalog.size():
		var entry: Dictionary = catalog.entry_at(index)
		var result: Dictionary = maintenance.repair_entry(entry, str(catalog.active_id))
		catalog.set_entry(index, result.get("entry", entry))
		index_changed = index_changed or bool(result.get("index_changed", false))
		for message in result.get("messages", []):
			messages.append(str(message))
	if index_changed and not catalog.save():
		messages.append("无法保存订阅索引。")

func _current_profile_name() -> String:
	var index: int = catalog.index_of(str(catalog.active_id))
	if index < 0:
		catalog.clear_active()
		return "内置直连配置"
	return str(catalog.entry_at(index).get("name", "订阅"))

func _migrate_legacy() -> Dictionary:
	var messages: Array[String] = []
	var candidate: Dictionary = legacy_migrator.prepare_candidate()
	if candidate.has("error"):
		return {"migrated": false, "messages": [str(candidate.get("error", "旧配置迁移失败。"))]}
	if candidate.is_empty():
		return {"migrated": false, "messages": messages}
	var entry_id := new_id()
	var created: Dictionary = create_entry(
		entry_id,
		str(candidate.get("display_name", "迁移的本地配置")),
		str(candidate.get("kind", "local")),
		str(candidate.get("yaml", "")),
		str(candidate.get("provider_file", ""))
	)
	if not bool(created.get("ok", false)):
		return {"migrated": false, "messages": [str(created.get("error", "旧配置迁移失败。"))]}
	catalog.set_active(entry_id)
	if not _write_profile(str(candidate.get("yaml", ""))):
		messages.append("保存配置失败。")
	if not catalog.save():
		messages.append("无法保存订阅索引。")
	var last_index: int = catalog.size() - 1
	var entry: Dictionary = catalog.entry_at(last_index)
	var repair: Dictionary = maintenance.repair_entry(entry, str(catalog.active_id))
	catalog.set_entry(last_index, repair.get("entry", entry))
	if bool(repair.get("index_changed", false)) and not catalog.save():
		messages.append("无法保存订阅索引。")
	for message in repair.get("messages", []):
		messages.append(str(message))
	return {
		"migrated": true,
		"profile_name": str(candidate.get("display_name", "迁移的本地配置")),
		"messages": messages
	}

func _ensure_default_profile(messages: Array[String]) -> void:
	if FileAccess.file_exists(proxy_config.active_profile_path()):
		return
	if not _write_profile(profile_factory.default_profile_yaml()):
		messages.append("保存配置失败。")

func _write_profile(content: String) -> bool:
	return store.write_text_atomic(proxy_config.active_profile_path(), content)
