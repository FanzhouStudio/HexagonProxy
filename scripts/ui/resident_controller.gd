class_name ResidentController
extends Node

signal connect_requested(enabled: bool)
signal autostart_requested(enabled: bool)
signal quit_requested
signal log_message(message: String)

const DesktopPetScript = preload("res://scripts/desktop_pet.gd")
const ClosePromptScript = preload("res://scripts/ui/close_prompt.gd")
const TrayControllerScript = preload("res://scripts/ui/tray_controller.gd")
const WindowVisibilityControllerScript = preload("res://scripts/ui/window_visibility_controller.gd")

var host: Control
var ui: UiFactory
var pet_toggle: CheckButton
var autostart_toggle: CheckButton
var tray_controller
var window_visibility
var desktop_pet: Node
var app_settings := ConfigFile.new()
var close_prompt: Control
var desktop_pet_enabled := true
var quitting := false
var _autostart_enabled := false
var _connection_online := false
var _connection_starting := false

func setup(owner: Control, factory: UiFactory, config, autostart_enabled: bool) -> void:
	host = owner
	ui = factory
	_autostart_enabled = autostart_enabled
	window_visibility = WindowVisibilityControllerScript.new()
	window_visibility.setup(owner, config)
	app_settings.load("user://settings.cfg")
	desktop_pet_enabled = bool(app_settings.get_value("desktop_pet", "visible", true))

func bind_controls(pet_control: CheckButton, startup_control: CheckButton) -> void:
	pet_toggle = pet_control
	autostart_toggle = startup_control
	pet_toggle.set_pressed_no_signal(desktop_pet_enabled)
	pet_toggle.toggled.connect(set_desktop_pet_visible)
	autostart_toggle.set_pressed_no_signal(_autostart_enabled)
	autostart_toggle.toggled.connect(_on_autostart_requested)

func is_pet_enabled() -> bool:
	return desktop_pet_enabled

func build() -> void:
	if DisplayServer.get_name() == "headless":
		return
	tray_controller = TrayControllerScript.new()
	add_child(tray_controller)
	tray_controller.setup(ui)
	tray_controller.show_main_requested.connect(show_main_window)
	tray_controller.pet_toggle_requested.connect(set_desktop_pet_visible)
	tray_controller.connect_requested.connect(_on_tray_connect_requested)
	tray_controller.autostart_toggle_requested.connect(_on_autostart_requested)
	tray_controller.exit_requested.connect(quit)
	tray_controller.set_pet_enabled(desktop_pet_enabled)
	tray_controller.set_autostart_enabled(_autostart_enabled)
	tray_controller.set_connection_state(_connection_online, _connection_starting)
	tray_controller.build()

	desktop_pet = DesktopPetScript.new()
	add_child(desktop_pet)
	desktop_pet.main_requested.connect(show_main_window)
	desktop_pet.hidden_by_user.connect(_on_pet_hidden_by_user)
	var stored_position := Vector2i(
		int(app_settings.get_value("desktop_pet", "x", -10000)),
		int(app_settings.get_value("desktop_pet", "y", -10000))
	)
	desktop_pet.create_pet(stored_position, desktop_pet_enabled)
	desktop_pet.set_node_status("", 0, false)

func set_connection_state(online: bool, starting: bool) -> void:
	_connection_online = online
	_connection_starting = starting
	if tray_controller:
		tray_controller.set_connection_state(online, starting)

func set_node_status(node_name: String, delay: int, online: bool) -> void:
	if is_instance_valid(desktop_pet):
		desktop_pet.set_node_status(node_name, delay, online)
	if tray_controller:
		tray_controller.set_node_status(node_name, delay, online)

func _on_tray_connect_requested(enabled: bool) -> void:
	connect_requested.emit(enabled)

func request_close() -> void:
	if quitting or is_instance_valid(close_prompt):
		return
	_show_close_prompt()

func start_in_tray() -> void:
	_hide_main_to_tray()
	connect_requested.emit(true)

func set_desktop_pet_visible(enabled: bool) -> void:
	desktop_pet_enabled = enabled
	if is_instance_valid(desktop_pet):
		desktop_pet.set_pet_visible(enabled)
	if is_instance_valid(pet_toggle):
		pet_toggle.set_pressed_no_signal(enabled)
	_save_settings()
	_update_tray_menu()

func _on_pet_hidden_by_user() -> void:
	set_desktop_pet_visible(false)

func _on_autostart_requested(enabled: bool) -> void:
	autostart_requested.emit(enabled)

func set_autostart_state(enabled: bool) -> void:
	_autostart_enabled = enabled
	if is_instance_valid(autostart_toggle):
		autostart_toggle.set_pressed_no_signal(enabled)
	_update_tray_menu()

func set_autostart_busy(busy: bool) -> void:
	if is_instance_valid(autostart_toggle):
		autostart_toggle.disabled = busy
		autostart_toggle.text = "处理中…" if busy else "启用"

func _update_tray_menu() -> void:
	if tray_controller == null:
		return
	tray_controller.set_pet_enabled(desktop_pet_enabled)
	tray_controller.set_autostart_enabled(_autostart_enabled)
	tray_controller.set_connection_state(_connection_online, _connection_starting)

func _save_settings() -> void:
	app_settings.set_value("desktop_pet", "visible", desktop_pet_enabled)
	if is_instance_valid(desktop_pet):
		var pet_position: Vector2i = desktop_pet.get_pet_position()
		app_settings.set_value("desktop_pet", "x", pet_position.x)
		app_settings.set_value("desktop_pet", "y", pet_position.y)
	app_settings.save("user://settings.cfg")

func _hide_main_to_tray() -> void:
	_dismiss_close_prompt()
	if window_visibility.is_hidden():
		return
	if not window_visibility.hide_main():
		log_message.emit("无法加载窗口助手，请检查运行目录权限。")
		return
	log_message.emit("主窗口已最小化到托盘。")

func show_main_window() -> void:
	if not window_visibility.show_main():
		log_message.emit("无法加载窗口助手，请检查运行目录权限。")

func _dismiss_close_prompt() -> void:
	if is_instance_valid(close_prompt):
		close_prompt.queue_free()
	close_prompt = null

func quit() -> void:
	if quitting:
		return
	quitting = true
	_save_settings()
	if tray_controller:
		tray_controller.hide_indicator()
	quit_requested.emit()

func _exit_tree() -> void:
	_save_settings()

func _show_close_prompt() -> void:
	var prompt = ClosePromptScript.new()
	host.add_child(prompt)
	close_prompt = prompt
	prompt.setup(ui)
	prompt.tray_requested.connect(_hide_main_to_tray)
	prompt.exit_requested.connect(quit)
