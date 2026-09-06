extends Control

const AppControllerScript = preload("res://scripts/app/app_controller.gd")
const RuntimeCoordinatorScript = preload("res://scripts/app/runtime_coordinator.gd")
const SubscriptionCoordinatorScript = preload("res://scripts/app/subscription_coordinator.gd")
const SettingsCoordinatorScript = preload("res://scripts/app/settings_coordinator.gd")
const PortConflictCoordinatorScript = preload("res://scripts/app/port_conflict_coordinator.gd")
const NodeRuntimeCoordinatorScript = preload("res://scripts/app/node_runtime_coordinator.gd")
const NodeFailoverCoordinatorScript = preload("res://scripts/app/node_failover_coordinator.gd")
const RoutingCoordinatorScript = preload("res://scripts/app/routing_coordinator.gd")
const TerminalCoordinatorScript = preload("res://scripts/app/terminal_coordinator.gd")
const WindowModeControllerScript = preload("res://scripts/app/window_mode_controller.gd")
const WindowChromeCoordinatorScript = preload("res://scripts/app/window_chrome_coordinator.gd")
const UiThemeCoordinatorScript = preload("res://scripts/app/ui_theme_coordinator.gd")
const UserDataBrandMigratorScript = preload("res://scripts/core/user_data_brand_migrator.gd")
const UiFactoryScript = preload("res://scripts/ui/ui_factory.gd")
const ResidentControllerScript = preload("res://scripts/ui/resident_controller.gd")
const SubscriptionPanelScript = preload("res://scripts/ui/subscription_panel.gd")
const NodesPanelScript = preload("res://scripts/ui/nodes_panel.gd")
const DashboardPanelScript = preload("res://scripts/ui/dashboard_panel.gd")
const RoutingPanelScript = preload("res://scripts/ui/routing_panel.gd")
const TerminalPanelScript = preload("res://scripts/ui/terminal_panel.gd")
const SettingsPanelScript = preload("res://scripts/ui/settings_panel.gd")
const AppShellScript = preload("res://scripts/ui/app_shell.gd")

const SURFACE := Color("e9fbfbd4")
const SURFACE_2 := Color("d8f4f3dc")
const BORDER := Color("a8e8e8e8")
const TEXT := Color("12384a")
const MUTED := Color("527384")
const GREEN := Color("16866f")
const GREEN_DARK := Color("c5f1dfde")
const CRYSTAL_WHITE := Color("f7ffffdf")

var app: AppController
var runtime: RuntimeCoordinator
var subscription_coordinator: SubscriptionCoordinator
var settings_coordinator: SettingsCoordinator
var port_conflict_coordinator: PortConflictCoordinator
var node_runtime_coordinator: NodeRuntimeCoordinator
var node_failover_coordinator: NodeFailoverCoordinator
var routing_coordinator: RoutingCoordinator
var terminal_coordinator: TerminalCoordinator
var window_mode_controller: WindowModeController
var window_chrome_coordinator: WindowChromeCoordinator
var ui_theme_coordinator: UiThemeCoordinator
var ui: UiFactory
var resident: ResidentController
var subscription_panel: SubscriptionPanel
var nodes_panel: NodesPanel
var dashboard_panel: DashboardPanel
var routing_panel: RoutingPanel
var terminal_panel: TerminalPanel
var settings_panel: SettingsPanel
var app_shell: AppShell
var proxy_service
var mihomo_control
var core_update_service
var system_proxy_service
var subscription_service
var autostart_service
var command_console_service
var command_preset_service
var port_conflict_service
var application_routing_service
var node_failover_service
var ui_theme_service
var _quitting := false

func _ready() -> void:
	var brand_migration: Dictionary = UserDataBrandMigratorScript.new().migrate_if_needed()
	if bool(brand_migration.get("migrated", false)):
		print("HexagonProxy user data migrated: %d files" % int(brand_migration.get("copied", 0)))
	window_mode_controller = WindowModeControllerScript.new()
	add_child(window_mode_controller)
	window_mode_controller.setup(get_window())
	window_mode_controller.start()
	app = AppControllerScript.new()
	add_child(app)
	app.start()
	ui_theme_service = app.get_service("ui_theme")
	ui = UiFactoryScript.new(ui_theme_service.snapshot())

	proxy_service = app.get_service("proxy")
	mihomo_control = app.get_service("mihomo_control")
	core_update_service = app.get_service("core_update")
	system_proxy_service = app.get_service("system_proxy")
	subscription_service = app.get_service("subscription")
	autostart_service = app.get_service("autostart")
	command_console_service = app.get_service("command_console")
	command_preset_service = app.get_service("command_presets")
	port_conflict_service = app.get_service("port_conflict")
	application_routing_service = app.get_service("application_routing")
	node_failover_service = app.get_service("node_failover")
	resident = ResidentControllerScript.new()
	add_child(resident)
	resident.setup(self, ui, proxy_service.config, autostart_service.is_enabled())
	resident.quit_requested.connect(_quit_application)
	subscription_panel = SubscriptionPanelScript.new()
	add_child(subscription_panel)
	subscription_panel.setup(self, ui)
	nodes_panel = NodesPanelScript.new()
	add_child(nodes_panel)
	nodes_panel.setup(ui)
	dashboard_panel = DashboardPanelScript.new()
	add_child(dashboard_panel)
	dashboard_panel.setup(ui)
	resident.log_message.connect(dashboard_panel.append_log)
	routing_panel = RoutingPanelScript.new()
	add_child(routing_panel)
	routing_panel.setup(ui)
	terminal_panel = TerminalPanelScript.new()
	add_child(terminal_panel)
	terminal_panel.setup(ui)
	settings_panel = SettingsPanelScript.new()
	add_child(settings_panel)
	settings_panel.setup(ui, proxy_service.config, system_proxy_service.is_enabled(), self)
	settings_panel.log_message.connect(dashboard_panel.append_log)
	mihomo_control.event_logged.connect(dashboard_panel.append_log)
	core_update_service.event_logged.connect(dashboard_panel.append_log)
	subscription_service.event_logged.connect(dashboard_panel.append_log)
	system_proxy_service.event_logged.connect(dashboard_panel.append_log)
	autostart_service.event_logged.connect(dashboard_panel.append_log)
	command_preset_service.event_logged.connect(dashboard_panel.append_log)
	application_routing_service.event_logged.connect(dashboard_panel.append_log)
	node_failover_service.event_logged.connect(dashboard_panel.append_log)
	ui_theme_service.event_logged.connect(dashboard_panel.append_log)
	app_shell = AppShellScript.new()
	add_child(app_shell)
	app_shell.setup(self, ui, dashboard_panel, nodes_panel, subscription_panel, routing_panel, terminal_panel, settings_panel)
	app_shell.build(subscription_service.current_profile_name)
	ui_theme_coordinator = UiThemeCoordinatorScript.new()
	add_child(ui_theme_coordinator)
	ui_theme_coordinator.setup(ui_theme_service, ui, settings_panel)
	ui_theme_coordinator.start()
	resident.bind_controls(settings_panel.pet_control(), settings_panel.autostart_control())
	resident.build()
	window_chrome_coordinator = WindowChromeCoordinatorScript.new()
	add_child(window_chrome_coordinator)
	window_chrome_coordinator.setup(app_shell, window_mode_controller, resident)
	window_chrome_coordinator.start()
	subscription_coordinator = SubscriptionCoordinatorScript.new()
	add_child(subscription_coordinator)
	subscription_coordinator.setup(subscription_service, subscription_panel)
	subscription_coordinator.start()
	routing_coordinator = RoutingCoordinatorScript.new()
	add_child(routing_coordinator)
	routing_coordinator.setup(application_routing_service, routing_panel, mihomo_control)
	routing_coordinator.start()
	terminal_coordinator = TerminalCoordinatorScript.new()
	add_child(terminal_coordinator)
	terminal_coordinator.setup(command_console_service, command_preset_service, terminal_panel)
	terminal_coordinator.start()
	settings_coordinator = SettingsCoordinatorScript.new()
	add_child(settings_coordinator)
	settings_coordinator.setup(mihomo_control, core_update_service, autostart_service, proxy_service.config, settings_panel, resident)
	settings_coordinator.start()
	port_conflict_coordinator = PortConflictCoordinatorScript.new()
	add_child(port_conflict_coordinator)
	port_conflict_coordinator.setup(port_conflict_service, settings_panel, mihomo_control)
	port_conflict_coordinator.start()
	node_runtime_coordinator = NodeRuntimeCoordinatorScript.new()
	add_child(node_runtime_coordinator)
	node_runtime_coordinator.setup(mihomo_control, dashboard_panel, nodes_panel, resident)
	node_runtime_coordinator.start()
	node_failover_coordinator = NodeFailoverCoordinatorScript.new()
	add_child(node_failover_coordinator)
	node_failover_coordinator.setup(node_failover_service, mihomo_control, nodes_panel)
	node_failover_coordinator.start()
	runtime = RuntimeCoordinatorScript.new()
	add_child(runtime)
	runtime.setup(proxy_service, mihomo_control, system_proxy_service, subscription_service, dashboard_panel, settings_panel, resident, app_shell)
	runtime.start()
	autostart_service.refresh_state()
	app_shell.show_page("dashboard")
	dashboard_panel.append_log("HexagonProxy 已准备好。")
	if not proxy_service.config.has_core():
		dashboard_panel.append_log("第一次使用：请到“设置”下载 Mihomo 内核。")
	get_tree().auto_accept_quit = false
	get_window().close_requested.connect(resident.request_close)
	if "--tray-start" in OS.get_cmdline_user_args():
		resident.call_deferred("start_in_tray")

func _quit_application() -> void:
	if _quitting:
		return
	_quitting = true
	if runtime:
		runtime.shutdown()
	if subscription_coordinator:
		subscription_coordinator.shutdown()
	if routing_coordinator:
		routing_coordinator.shutdown()
	if terminal_coordinator:
		terminal_coordinator.shutdown()
	if settings_coordinator:
		settings_coordinator.shutdown()
	if port_conflict_coordinator:
		port_conflict_coordinator.shutdown()
	if node_runtime_coordinator:
		node_runtime_coordinator.shutdown()
	if node_failover_coordinator:
		node_failover_coordinator.shutdown()
	if ui_theme_coordinator:
		ui_theme_coordinator.shutdown()
	if window_chrome_coordinator:
		window_chrome_coordinator.shutdown()
	if window_mode_controller:
		window_mode_controller.shutdown()
	app.stop()
	get_tree().quit()
