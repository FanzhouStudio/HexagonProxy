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
var _pending_tun_enable := false
var _pending_tun_start := false
var _active := false
var _health
var _health_timer: Timer
var _health_message := "代理入口尚未验证"
var _health_state := "checking"
var _last_health_diagnostic := ""
var _node_load_error := ""
var _last_health_check := -20000
var _tun_watchdog: Timer

func _record_tun_diagnostic(reason: String) -> void:
	var directory := ProjectSettings.globalize_path("user://diagnostics")
	DirAccess.make_dir_recursive_absolute(directory)
	var file := FileAccess.open(directory.path_join("tun-events.log"), FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open(directory.path_join("tun-events.log"), FileAccess.WRITE)
	if file:
		file.seek_end()
		file.store_line("%s %s" % [Time.get_datetime_string_from_system(), reason])
	if OS.get_name() == "Windows":
		var stamp := Time.get_datetime_string_from_system().replace(":", "-") + "-" + str(Time.get_ticks_msec())
		var output := directory.path_join("tun-network-" + stamp + ".json").replace("'", "''")
		var script := "$d=@{time=(Get-Date -Format o);adapters=@(Get-NetAdapter | Select-Object Name,InterfaceDescription,ifIndex,Status);routes=@(Get-NetRoute -AddressFamily IPv4 | Select-Object DestinationPrefix,NextHop,InterfaceIndex,RouteMetric);dns=@(Get-DnsClientServerAddress -AddressFamily IPv4 | Select-Object InterfaceAlias,ServerAddresses)};$d | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath '%s' -Encoding UTF8" % output
		OS.create_process("powershell.exe", PackedStringArray(["-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden", "-Command", script]), false)

func _arm_tun_watchdog() -> void:
	_record_tun_diagnostic("TUN enabled: checking connectivity")
	_tun_watchdog.start()

func _restore_system_proxy() -> void:
	if not _active or not proxy_service.config.tun_enabled():
		return
	_record_tun_diagnostic("TUN failed: restoring system proxy")
	if not proxy_service.config.set_tun_enabled(false):
		settings_panel.reject_tun_enable("TUN 检测失败，恢复设置失败，请关闭代理。")
		return
	_tun_watchdog.stop()
	settings_panel.set_tun_state(false)
	settings_panel.reject_tun_enable("TUN 联网检测失败，正在恢复系统代理。诊断已保存。")
	_enable_proxy_when_online = true
	mihomo_control.restart()

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
	settings_panel.tun_intent_changed.connect(_on_tun_intent_changed)
	system_proxy_service.status_changed.connect(_on_system_proxy_status_changed)
	system_proxy_service.busy_changed.connect(_on_system_proxy_busy_changed)
	resident.connect_requested.connect(_on_resident_connect_requested)
	mihomo_control.state_changed.connect(_on_mihomo_state_changed)
	mihomo_control.api_result.connect(_on_proxy_inventory)
	subscription_service.profile_changed.connect(_on_profile_changed)
	subscription_service.restart_requested.connect(_on_subscription_restart_requested)
	subscription_service.api_request_requested.connect(_on_subscription_api_request)

func start() -> void:
	if _active:
		return
	_active = true
	_tun_watchdog = Timer.new()
	_tun_watchdog.one_shot = true
	_tun_watchdog.wait_time = 45
	_tun_watchdog.timeout.connect(_restore_system_proxy)
	add_child(_tun_watchdog)
	if proxy_service.config.tun_enabled():
		_arm_tun_watchdog()
	_health = preload("res://scripts/modules/network/proxy_health_service.gd").new()
	add_child(_health)
	_health.checked.connect(_on_health_checked)
	_health.diagnostic_logged.connect(_on_health_diagnostic)
	_health_timer = Timer.new()
	_health_timer.wait_time = 20
	_health_timer.timeout.connect(_check_health)
	add_child(_health_timer)
	_health_timer.start()
	_on_status_changed(false, "代理未连接")
	settings_panel.set_tun_state(proxy_service.config.tun_enabled())

func shutdown() -> void:
	_active = false
	_pending_tun_enable = false
	_pending_tun_start = false
	if is_instance_valid(_tun_watchdog):
		_tun_watchdog.stop()
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
	_health.probe(proxy_service.config.controller_host(), proxy_service.config.mixed_port(), proxy_service.config.tun_enabled())
	if _enable_proxy_when_online and not system_proxy_service.busy:
		system_proxy_service.reconcile()

func _on_proxy_inventory(action: String, ok: bool, payload: Variant) -> void:
	if not _active or not mihomo_control.online or action != "proxies" or not ok or not payload is Dictionary:
		return
	var inventory: Variant = payload.get("proxies", {})
	if not inventory is Dictionary:
		return
	var group: Variant = inventory.get("六角选择", {})
	var missing: bool = group is Dictionary and group.get("now", "") == "COMPATIBLE"
	var message := "订阅未加载到节点（COMPATIBLE 回退）；请在订阅页更新并检查订阅地址是否可访问" if missing else ""
	if message == _node_load_error:
		return
	_node_load_error = message
	if missing:
		_on_health_checked("failed", message)
	else:
		_on_health_checked("checking", "节点已加载，等待连通性检查")
		_last_health_check = -20000
		_check_health()

func _on_health_diagnostic(message: String) -> void:
	if not _active or not mihomo_control.online:
		return
	if not message.is_empty() and message != _last_health_diagnostic:
		mihomo_control.event_logged.emit(message)
	_last_health_diagnostic = message

func _on_health_checked(state: String, message: String) -> void:
	if not _active or not mihomo_control.online:
		return
	if not _node_load_error.is_empty():
		state = "failed"
		message = _node_load_error
	if state != _health_state or message != _health_message:
		mihomo_control.event_logged.emit(message)
	_health_state = state
	_health_message = message
	if proxy_service.config.tun_enabled():
		_record_tun_diagnostic("HTTPS check: " + state + " " + message)
		if state == "healthy":
			_tun_watchdog.stop()
		elif state == "partial" and _tun_watchdog.is_stopped():
			_tun_watchdog.start()
		elif state == "failed":
			_restore_system_proxy()
			return
	_on_status_changed(true, message)

func _on_mihomo_state_changed(value_online: bool, value_starting: bool, _value_pid: int, message: String) -> void:
	if not _active:
		return
	_on_status_changed(value_online, message)
	if value_online:
		_check_health()
	else:
		if not value_starting:
			settings_panel.set_tun_busy(false)
		_health.cancel()
		_last_health_check = -20000
		_health_state = "checking"
		_last_health_diagnostic = ""
		_node_load_error = ""
		_health_message = "代理入口尚未验证"

func _on_connect_toggled(enabled: bool) -> void:
	if not _active:
		return
	if enabled:
		if proxy_service.config.tun_enabled() and not proxy_service.config.has_tun_permission():
			_enable_proxy_when_online = false
			dashboard_panel.set_connect_pressed(false)
			settings_panel.reject_tun_enable("TUN 需要管理员权限，请以管理员身份运行 HexagonProxy。")
			app_shell.show_page("settings")
			return
		_enable_proxy_when_online = not proxy_service.config.tun_enabled()
		if proxy_service.config.tun_enabled() and (system_proxy_service.is_enabled() or system_proxy_service.busy):
			_pending_tun_start = true
			system_proxy_service.set_enabled(false)
			return
		_start_mihomo_or_show_settings()
	else:
		_enable_proxy_when_online = false
		_pending_tun_start = false
		if system_proxy_service.is_enabled():
			system_proxy_service.set_enabled(false)
		mihomo_control.stop()

func _start_mihomo_or_show_settings() -> void:
	mihomo_control.start()
	if not proxy_service.config.has_core():
		dashboard_panel.set_connect_pressed(false)
		app_shell.show_page("settings")

func _on_status_changed(is_online: bool, message: String) -> void:
	if is_online:
		message = _health_message
		message += " · TUN" if proxy_service.config.tun_enabled() else ("" if system_proxy_service.is_enabled() else " · 系统代理未开启")
	dashboard_panel.set_status(is_online, bool(mihomo_control.starting), message)
	if is_online:
		dashboard_panel.set_network_health(_health_state == "healthy" and (proxy_service.config.tun_enabled() or system_proxy_service.is_enabled()), message)
		settings_panel.set_tun_busy(false)
	if is_online and proxy_service.config.tun_enabled() and system_proxy_service.is_enabled():
		system_proxy_service.set_enabled(false)
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
	if enabled and proxy_service.config.tun_enabled():
		if not proxy_service.config.set_tun_enabled(false):
			settings_panel.set_system_proxy_state(false)
			settings_panel.reject_tun_enable("无法保存 TUN 设置，系统代理未开启。")
			return
		settings_panel.set_tun_state(false)
		settings_panel.set_tun_busy(true)
		mihomo_control.restart()
		return
	if system_proxy_service.is_enabled() != enabled:
		system_proxy_service.set_enabled(enabled)

func _on_tun_intent_changed(enabled: bool) -> void:
	if not _active:
		return
	if enabled and not mihomo_control.online:
		settings_panel.reject_tun_enable("请先启动代理，再开启 TUN。")
		return
	if enabled and not proxy_service.config.has_tun_permission():
		settings_panel.reject_tun_enable("TUN 需要管理员权限，请以管理员身份运行 HexagonProxy。")
		return
	if proxy_service.config.tun_enabled() == enabled:
		return
	if enabled and (system_proxy_service.is_enabled() or system_proxy_service.busy):
		_pending_tun_enable = true
		settings_panel.set_tun_busy(true)
		system_proxy_service.set_enabled(false)
		return
	_apply_tun_state(enabled)

func _apply_tun_state(enabled: bool) -> void:
	if not proxy_service.config.set_tun_enabled(enabled):
		settings_panel.set_tun_state(not enabled)
		settings_panel.reject_tun_enable("无法保存 TUN 设置。")
		return
	_enable_proxy_when_online = false
	settings_panel.set_tun_state(enabled)
	if enabled:
		_arm_tun_watchdog()
	else:
		_tun_watchdog.stop()
	if mihomo_control.online or mihomo_control.starting or mihomo_control.core_pid > 0:
		settings_panel.set_tun_busy(true)
		mihomo_control.restart()
	else:
		settings_panel.set_tun_busy(false)

func _on_system_proxy_status_changed(enabled: bool) -> void:
	if _active:
		settings_panel.set_system_proxy_state(enabled)
		if _pending_tun_start:
			_pending_tun_start = false
			if enabled:
				dashboard_panel.set_connect_pressed(false)
				settings_panel.reject_tun_enable("系统代理关闭失败，TUN 未启动。")
			else:
				_start_mihomo_or_show_settings()
		if _pending_tun_enable:
			if enabled:
				_pending_tun_enable = false
				settings_panel.set_tun_busy(false)
				settings_panel.reject_tun_enable("系统代理关闭失败，TUN 未开启。")
			else:
				_pending_tun_enable = false
				_apply_tun_state(true)
		if mihomo_control.online:
			var message := _health_message + (" · TUN" if proxy_service.config.tun_enabled() else ("" if enabled else " · 系统代理未开启"))
			dashboard_panel.set_status(true, false, message)
			dashboard_panel.set_network_health(_health_state == "healthy" and (proxy_service.config.tun_enabled() or enabled), message)

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
