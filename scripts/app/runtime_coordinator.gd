class_name RuntimeCoordinator
extends Node

## 连接生命周期协调器
## 负责连接、系统代理与订阅触发；节点/API/轮询由 NodeRuntimeCoordinator 负责。

var proxy_service
var mihomo_control
var system_proxy_service
var subscription_service
var dashboard_panel
var settings_panel
var resident
var app_shell

var _enable_proxy_when_online := false
var _active := false
var _health
var _health_timer: Timer
var _health_message := "代理入口尚未验证"
var _health_state := "checking"
var _last_health_check := -20000

func setup(proxy, control, system_proxy, subscription, dashboard, settings, resident_controller, shell) -> void:
	proxy_service = proxy
	mihomo_control = control
	system_proxy_service = system_proxy
	subscription_service = subscription
	dashboard_panel = dashboard
	settings_panel = settings
	resident = resident_controller
	app_shell = shell
	dashboard_panel.connect_requested.connect(_on_connect_toggled)
	settings_panel.system_proxy_intent_changed.connect(_on_system_proxy_intent_changed)
	system_proxy_service.status_changed.connect(_on_system_proxy_status_changed)
	system_proxy_service.busy_changed.connect(_on_system_proxy_busy_changed)
	resident.connect_requested.connect(_on_resident_connect_requested)
	mihomo_control.state_changed.connect(_on_mihomo_state_changed)
	subscription_service.profile_changed.connect(_on_profile_changed)
	subscription_service.restart_requested.connect(_on_subscription_restart_requested)
	subscription_service.api_request_requested.connect(_on_subscription_api_request)

func start() -> void:
	if _active:
		return
	_active = true
	_health = preload("res://scripts/modules/network/proxy_health_service.gd").new()
	add_child(_health)
	_health.checked.connect(_on_health_checked)
	_health_timer = Timer.new()
	_health_timer.wait_time = 20
	_health_timer.timeout.connect(_check_health)
	add_child(_health_timer)
	_health_timer.start()
	_on_status_changed(false, "代理未连接")

func shutdown() -> void:
	_active = false
	if is_instance_valid(_health_timer):
		_health_timer.stop()
	if is_instance_valid(_health):
		_health.cancel()
		_last_health_check = -20000

func _check_health() -> void:
	if not _active or not mihomo_control.online:
		return
	if Time.get_ticks_msec() - _last_health_check < 20000:
		return
	_last_health_check = Time.get_ticks_msec()
	_health.probe(proxy_service.config.controller_host(), proxy_service.config.mixed_port())
	if _enable_proxy_when_online and not system_proxy_service.busy:
		system_proxy_service.reconcile()

func _on_health_checked(state: String, message: String) -> void:
	if not _active or not mihomo_control.online:
		return
	if state != _health_state:
		mihomo_control.event_logged.emit(message)
	_health_state = state
	_health_message = message
	_on_status_changed(true, message)

func _on_mihomo_state_changed(value_online: bool, _value_starting: bool, _value_pid: int, message: String) -> void:
	if not _active:
		return
	_on_status_changed(value_online, message)
	if value_online:
		_check_health()
	else:
		_health.cancel()
		_last_health_check = -20000
		_health_state = "checking"
		_health_message = "代理入口尚未验证"

func _on_connect_toggled(enabled: bool) -> void:
	if not _active:
		return
	if enabled:
		_enable_proxy_when_online = true
		mihomo_control.start()
		if not proxy_service.config.has_core():
			dashboard_panel.set_connect_pressed(false)
			app_shell.show_page("settings")
	else:
		_enable_proxy_when_online = false
		if system_proxy_service.is_enabled():
			system_proxy_service.set_enabled(false)
		mihomo_control.stop()

func _on_status_changed(is_online: bool, message: String) -> void:
	if is_online:
		message = _health_message
		if not system_proxy_service.is_enabled():
			message += " · 系统代理未开启"
	dashboard_panel.set_status(is_online, bool(mihomo_control.starting), message)
	if is_online:
		dashboard_panel.set_network_health(_health_state == "healthy" and system_proxy_service.is_enabled(), message)
	if is_online and _enable_proxy_when_online and not system_proxy_service.is_enabled():
		system_proxy_service.set_enabled(true)
	if resident:
		resident.set_connection_state(bool(mihomo_control.online), bool(mihomo_control.starting))

func _on_system_proxy_intent_changed(enabled: bool) -> void:
	if not _active:
		return
	if enabled and not mihomo_control.online:
		_enable_proxy_when_online = false
		settings_panel.reject_system_proxy_enable("请先启动代理，再开启系统代理。")
		return
	_enable_proxy_when_online = enabled
	if system_proxy_service.is_enabled() != enabled:
		system_proxy_service.set_enabled(enabled)

func _on_system_proxy_status_changed(enabled: bool) -> void:
	if _active:
		settings_panel.set_system_proxy_state(enabled)
		if mihomo_control.online:
			var message := _health_message + ("" if enabled else " · 系统代理未开启")
			dashboard_panel.set_status(true, false, message)
			dashboard_panel.set_network_health(_health_state == "healthy" and enabled, message)

func _on_system_proxy_busy_changed(busy: bool) -> void:
	if _active:
		settings_panel.set_system_proxy_busy(busy)

func _on_profile_changed(display_name: String) -> void:
	if not _active:
		return
	dashboard_panel.set_profile_name(display_name)

func _on_subscription_restart_requested() -> void:
	if not _active:
		return
	if mihomo_control.online or mihomo_control.starting:
		mihomo_control.restart()
	else:
		mihomo_control.start()

func _on_subscription_api_request(action: String, endpoint: String, method: int, body: String) -> void:
	if _active:
		mihomo_control.request(action, endpoint, method, body)

func _on_resident_connect_requested(enabled: bool) -> void:
	if not _active:
		return
	dashboard_panel.set_connect_pressed(enabled)
	_on_connect_toggled(enabled)
