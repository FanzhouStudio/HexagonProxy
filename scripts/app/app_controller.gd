class_name AppController
extends Node

## 应用总控制器
## 只负责应用组装与顶层生命周期

const ServiceContainerScript = preload("res://scripts/core/service_container.gd")
const ProxyServiceScript = preload("res://scripts/modules/proxy/proxy_service.gd")
const MihomoApiServiceScript = preload("res://scripts/modules/mihomo/mihomo_api_service.gd")
const MihomoControlServiceScript = preload("res://scripts/modules/mihomo/mihomo_control_service.gd")
const CoreUpdateServiceScript = preload("res://scripts/modules/mihomo/core_update_service.gd")
const SubscriptionServiceScript = preload("res://scripts/modules/subscription/subscription_service.gd")
const SystemProxyServiceScript = preload("res://scripts/modules/system/system_proxy_service.gd")
const AutostartServiceScript = preload("res://scripts/modules/system/autostart_service.gd")
const CommandConsoleServiceScript = preload("res://scripts/modules/system/command_console_service.gd")
const CommandPresetServiceScript = preload("res://scripts/modules/system/command_preset_service.gd")
const PortConflictServiceScript = preload("res://scripts/modules/system/port_conflict_service.gd")
const ApplicationRoutingServiceScript = preload("res://scripts/modules/routing/application_routing_service.gd")
const NodeFailoverServiceScript = preload("res://scripts/modules/reliability/node_failover_service.gd")
const UiThemeServiceScript = preload("res://scripts/modules/ui/ui_theme_service.gd")
const CodexProfileServiceScript = preload("res://scripts/modules/codex/codex_profile_service.gd")

var service_container

func start() -> void:
	if service_container != null:
		return
	service_container = ServiceContainerScript.new()
	add_child(service_container)

	var proxy = ProxyServiceScript.new()
	var proxy_config = proxy.get_config()
	var mihomo_api = MihomoApiServiceScript.new()
	var mihomo_control = MihomoControlServiceScript.new()
	var core_update = CoreUpdateServiceScript.new()
	var subscription = SubscriptionServiceScript.new()
	var system_proxy = SystemProxyServiceScript.new()
	var autostart = AutostartServiceScript.new()
	var command_console = CommandConsoleServiceScript.new()
	var command_presets = CommandPresetServiceScript.new()
	var port_conflict = PortConflictServiceScript.new()
	var application_routing = ApplicationRoutingServiceScript.new()
	var node_failover = NodeFailoverServiceScript.new()
	var ui_theme = UiThemeServiceScript.new()
	var codex_profiles = CodexProfileServiceScript.new()
	core_update.bind_config(proxy_config)
	subscription.bind_config(proxy_config)
	system_proxy.bind_config(proxy_config)
	command_console.bind_config(proxy_config)
	port_conflict.bind_config(proxy_config)
	mihomo_api.bind_config(proxy_config)
	mihomo_control.setup(proxy, mihomo_api)
	proxy.register_profile_transformer("application_routing", application_routing, 50)

	service_container.register("proxy", proxy)
	service_container.register("mihomo_api", mihomo_api)
	service_container.register("mihomo_control", mihomo_control)
	service_container.register("core_update", core_update)
	service_container.register("subscription", subscription)
	service_container.register("system_proxy", system_proxy)
	service_container.register("autostart", autostart)
	service_container.register("command_console", command_console)
	service_container.register("command_presets", command_presets)
	service_container.register("port_conflict", port_conflict)
	service_container.register("application_routing", application_routing)
	service_container.register("node_failover", node_failover)
	service_container.register("ui_theme", ui_theme)
	service_container.register("codex_profiles", codex_profiles)
	service_container.initialize_all()
	autostart.migrate_legacy_registration()

func get_service(name: String) -> Object:
	if service_container == null:
		return null
	return service_container.get_service(name)

func stop() -> void:
	if service_container:
		service_container.dispose_all()
		service_container.queue_free()
		service_container = null

func _exit_tree() -> void:
	stop()
