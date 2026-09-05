class_name SubscriptionService
extends Node

## 订阅与配置业务服务
## 负责导入、切换、迁移、修复和活动配置持久化

signal profile_changed(display_name: String)
signal subscriptions_changed
signal event_logged(message: String)
signal restart_requested
signal api_request_requested(action: String, endpoint: String, method: int, body: String)

const ProxyConfigScript = preload("res://scripts/modules/proxy/proxy_config.gd")
const SubscriptionStoreScript = preload("res://scripts/modules/subscription/subscription_store.gd")
const V2ShareParserScript = preload("res://scripts/modules/subscription/v2_share_parser.gd")
const SubscriptionProfileFactoryScript = preload("res://scripts/modules/subscription/subscription_profile_factory.gd")
const SubscriptionProfileMaintenanceScript = preload("res://scripts/modules/subscription/subscription_profile_maintenance.gd")
const SubscriptionLegacyMigratorScript = preload("res://scripts/modules/subscription/subscription_legacy_migrator.gd")
const SubscriptionImporterScript = preload("res://scripts/modules/subscription/subscription_importer.gd")
const SubscriptionLibraryScript = preload("res://scripts/modules/subscription/subscription_library.gd")

var proxy_config
var subscription_store
var v2_parser
var profile_factory
var profile_maintenance
var legacy_migrator
var importer
var library
var current_profile_name := "内置直连配置"
var _initialized := false

func bind_config(config) -> void:
	proxy_config = config
	profile_maintenance = null
	legacy_migrator = null
	importer = null
	library = null
	if subscription_store:
		subscription_store.setup(profile_dir(), runtime_dir())

func _ensure_config() -> void:
	if proxy_config == null:
		proxy_config = ProxyConfigScript.new()

func initialize() -> void:
	if _initialized:
		return
	_initialized = true
	_ensure_dependencies()
	DirAccess.make_dir_recursive_absolute(runtime_dir())
	DirAccess.make_dir_recursive_absolute(profile_dir())
	var result: Dictionary = library.initialize()
	current_profile_name = str(result.get("profile_name", "内置直连配置"))
	for message in result.get("messages", []):
		event_logged.emit(str(message))

func runtime_dir() -> String:
	_ensure_config()
	return proxy_config.runtime_dir()

func profile_dir() -> String:
	_ensure_config()
	return proxy_config.profile_dir()

func profile_path() -> String:
	_ensure_config()
	return proxy_config.active_profile_path()

func subscription_provider_dir() -> String:
	_ensure_dependencies()
	return subscription_store.provider_dir()

func _ensure_dependencies() -> void:
	_ensure_config()
	if subscription_store == null:
		subscription_store = SubscriptionStoreScript.new()
		subscription_store.setup(proxy_config.profile_dir(), proxy_config.runtime_dir())
	if v2_parser == null:
		v2_parser = V2ShareParserScript.new()
	if profile_factory == null:
		profile_factory = SubscriptionProfileFactoryScript.new()
	if profile_maintenance == null:
		profile_maintenance = SubscriptionProfileMaintenanceScript.new()
		profile_maintenance.setup(proxy_config, subscription_store, v2_parser, profile_factory)
	if legacy_migrator == null:
		legacy_migrator = SubscriptionLegacyMigratorScript.new()
		legacy_migrator.setup(proxy_config, subscription_store)
	if importer == null:
		importer = SubscriptionImporterScript.new()
		importer.setup(subscription_store, v2_parser, profile_factory)
	if library == null:
		library = SubscriptionLibraryScript.new()
		library.setup(proxy_config, subscription_store, profile_factory, profile_maintenance, legacy_migrator)

func use_subscription_url(url: String) -> bool:
	_ensure_dependencies()
	var prepared: Dictionary = importer.prepare_http(url)
	if not _commit_prepared_import(_new_subscription_id(), prepared):
		return false
	event_logged.emit("订阅已保存，地址仅保存在本机配置中。")
	return true

func use_v2_share_links(content: String) -> bool:
	_ensure_dependencies()
	var entry_id := _new_subscription_id()
	var prepared: Dictionary = importer.prepare_v2(content, entry_id)
	if not _commit_prepared_import(entry_id, prepared):
		return false
	event_logged.emit("V2 节点已导入；链接仅保存在本机。")
	return true

func import_local_profile(path: String) -> bool:
	_ensure_dependencies()
	var prepared: Dictionary = importer.prepare_local(path)
	if not _commit_prepared_import(_new_subscription_id(), prepared):
		return false
	event_logged.emit("已导入本地配置：%s" % current_profile_name)
	return true

func _commit_prepared_import(entry_id: String, prepared: Dictionary) -> bool:
	if not bool(prepared.get("ok", false)):
		event_logged.emit(str(prepared.get("error", "导入失败。")))
		return false
	var generated_files: Array = prepared.get("generated_files", [])
	var extra: Dictionary = prepared.get("extra", {})
	if not _save_subscription(
		entry_id,
		str(prepared.get("name", "订阅")),
		str(prepared.get("kind", "local")),
		str(prepared.get("yaml", "")),
		str(prepared.get("provider_file", "")),
		extra
	):
		importer.cleanup_generated(generated_files)
		return false
	_activate_subscription(entry_id, false)
	return true

func update_provider() -> void:
	_ensure_dependencies()
	if library.active_type() != "http":
		event_logged.emit("当前配置不是 HTTP 订阅，无需在线刷新。")
		return
	api_request_requested.emit("update_provider", "/providers/proxies/hexagon-subscription", HTTPClient.METHOD_PUT, "")

func get_subscriptions() -> Array:
	_ensure_dependencies()
	return library.list()

func active_subscription_id() -> String:
	_ensure_dependencies()
	return library.active_id()

func activate_subscription(entry_id: String) -> bool:
	return _activate_subscription(entry_id, true)

func delete_subscription(entry_id: String) -> bool:
	_ensure_dependencies()
	var result: Dictionary = library.delete(entry_id)
	if not bool(result.get("ok", false)):
		event_logged.emit(str(result.get("error", "删除订阅失败。")))
		return false
	current_profile_name = str(result.get("profile_name", current_profile_name))
	profile_changed.emit(current_profile_name)
	subscriptions_changed.emit()
	event_logged.emit("已删除订阅：%s" % str(result.get("deleted_name", "订阅")))
	if bool(result.get("was_active", false)):
		_restart_for_profile_change()
	return true

func _save_subscription(entry_id: String, display_name: String, kind: String, yaml: String, provider_file := "", extra := {}) -> bool:
	_ensure_dependencies()
	var result: Dictionary = library.create_entry(entry_id, display_name, kind, yaml, provider_file, extra)
	if not bool(result.get("ok", false)):
		event_logged.emit(str(result.get("error", "无法保存订阅档案。")))
		return false
	subscriptions_changed.emit()
	return true

func _activate_subscription(entry_id: String, log_change: bool) -> bool:
	_ensure_dependencies()
	var result: Dictionary = library.activate(entry_id)
	if not bool(result.get("ok", false)):
		event_logged.emit(str(result.get("error", "切换订阅失败。")))
		return false
	current_profile_name = str(result.get("profile_name", "订阅"))
	profile_changed.emit(current_profile_name)
	subscriptions_changed.emit()
	if log_change:
		event_logged.emit("已切换订阅：%s" % current_profile_name)
	_restart_for_profile_change()
	return true

func _restart_for_profile_change() -> void:
	restart_requested.emit()

func _new_subscription_id() -> String:
	_ensure_dependencies()
	return library.new_id()
