class_name SettingsCoordinator
extends Node

## 设置业务协调器
## 负责内核更新/重启与开机自启，避免 RuntimeCoordinator 吸收所有设置职责。

var mihomo_control
var core_update_service
var autostart_service
var proxy_config
var settings_panel
var resident
var window_mode_controller
var _active := false

func setup(control, core_update, autostart, config, settings, resident_controller, window_controller = null) -> void:
	mihomo_control = control
	core_update_service = core_update
	autostart_service = autostart
	proxy_config = config
	settings_panel = settings
	resident = resident_controller
	window_mode_controller = window_controller
	settings_panel.core_restart_requested.connect(_on_core_restart_requested)
	settings_panel.core_update_requested.connect(_on_core_update_requested)
	settings_panel.ports_apply_requested.connect(_on_ports_apply_requested)
	settings_panel.window_settings_apply_requested.connect(_on_window_settings_apply_requested)
	settings_panel.port_random_requested.connect(_on_port_random_requested)
	core_update_service.progress_changed.connect(_on_core_update_progress_changed)
	core_update_service.finished.connect(_on_core_update_finished)
	resident.autostart_requested.connect(_on_autostart_requested)
	autostart_service.status_changed.connect(_on_autostart_changed)
	autostart_service.busy_changed.connect(_on_autostart_busy_changed)

func start() -> void:
	_active = true
func shutdown() -> void:
	_active = false

func _on_ports_apply_requested(mixed_port: int, controller_port: int) -> void:
	if not _active:
		return
	if _ports_locked():
		_restore_port_controls("请先断开代理，再修改端口。")
		return
	var result: Dictionary = proxy_config.set_ports(mixed_port, controller_port)
	if bool(result.get("ok", false)):
		settings_panel.set_port_values(proxy_config.mixed_port(), proxy_config.controller_port())
	settings_panel.show_port_message(str(result.get("message", "端口设置失败。")), bool(result.get("ok", false)))

func _on_window_settings_apply_requested(borderless: bool, width: int, height: int) -> void:
	if not _active:
		return
	proxy_config.set_window_settings(borderless, width, height)
	if window_mode_controller and window_mode_controller.has_method("apply_saved_window_mode"):
		window_mode_controller.apply_saved_window_mode()

func _on_port_random_requested(kind: String) -> void:
	if not _active:
		return
	if _ports_locked():
		_restore_port_controls("请先断开代理，再随机端口。")
		return
	var other_port: int = int(proxy_config.controller_port() if kind == "mixed" else proxy_config.mixed_port())
	var port: int = int(proxy_config.random_available_port(other_port))
	if port < 0:
		settings_panel.show_port_message("没有找到可用的随机端口。", false)
		return
	var mixed: int = int(port if kind == "mixed" else proxy_config.mixed_port())
	var controller: int = int(port if kind == "controller" else proxy_config.controller_port())
	var result: Dictionary = proxy_config.set_ports(mixed, controller)
	if bool(result.get("ok", false)):
		settings_panel.set_port_values(proxy_config.mixed_port(), proxy_config.controller_port())
		settings_panel.show_port_message("已随机选择可用端口 %d。" % port, true)
	else:
		settings_panel.show_port_message(str(result.get("message", "随机端口保存失败。")), false)

func _ports_locked() -> bool:
	return bool(mihomo_control.online) or bool(mihomo_control.starting) or int(mihomo_control.core_pid) > 0

func _restore_port_controls(message: String) -> void:
	settings_panel.set_port_values(proxy_config.mixed_port(), proxy_config.controller_port())
	settings_panel.show_port_message(message, false)

func _on_core_restart_requested() -> void:
	if _active:
		mihomo_control.restart()

func _on_core_update_requested() -> void:
	if not _active or core_update_service.is_busy():
		return
	if mihomo_control.online or mihomo_control.starting or mihomo_control.core_pid > 0:
		settings_panel.show_core_update_blocked("请先断开代理，再更新 Mihomo 内核")
		return
	core_update_service.download_latest()

func _on_core_update_progress_changed(progress: float, message: String) -> void:
	if _active:
		settings_panel.set_core_update_progress(progress, message)

func _on_core_update_finished(success: bool, _message: String) -> void:
	if success and _active:
		mihomo_control.start()

func _on_autostart_requested(enabled: bool) -> void:
	if _active:
		autostart_service.set_enabled(enabled)
func _on_autostart_changed(enabled: bool) -> void:
	if _active:
		resident.set_autostart_state(enabled)

func _on_autostart_busy_changed(busy: bool) -> void:
	if _active:
		resident.set_autostart_busy(busy)