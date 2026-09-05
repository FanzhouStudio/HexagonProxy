class_name TrayController
extends Node

## 系统托盘 UI 控制器
## 只负责菜单、状态图标和用户动作，不直接操作业务服务

signal show_main_requested
signal pet_toggle_requested(enabled: bool)
signal connect_requested(enabled: bool)
signal autostart_toggle_requested(enabled: bool)
signal exit_requested

const TRAY_SHOW_MAIN := 1
const TRAY_SHOW_PET := 2
const TRAY_CONNECT := 3
const TRAY_AUTOSTART := 4
const TRAY_EXIT := 9

var ui: UiFactory
var tray_indicator: StatusIndicator
var tray_menu: PopupMenu
var pet_enabled := true
var autostart_enabled := false
var online := false
var starting := false

func setup(factory: UiFactory) -> void:
	ui = factory

func build() -> void:
	if DisplayServer.get_name() == "headless":
		return
	tray_menu = PopupMenu.new()
	tray_menu.name = "TrayMenu"
	tray_menu.prefer_native_menu = true
	tray_menu.add_item("显示 HexagonProxy", TRAY_SHOW_MAIN)
	tray_menu.add_check_item("显示桌面宠物", TRAY_SHOW_PET)
	tray_menu.add_check_item("连接代理", TRAY_CONNECT)
	tray_menu.add_separator()
	tray_menu.add_check_item("开机自启", TRAY_AUTOSTART)
	tray_menu.add_separator()
	tray_menu.add_item("退出 HexagonProxy", TRAY_EXIT)
	tray_menu.id_pressed.connect(_on_menu_pressed)
	add_child(tray_menu)

	tray_indicator = StatusIndicator.new()
	tray_indicator.name = "TrayIndicator"
	tray_indicator.icon = load("res://assets/app_icon.png")
	tray_indicator.tooltip = "HexagonProxy · 未连接"
	add_child(tray_indicator)
	tray_indicator.menu = tray_indicator.get_path_to(tray_menu)
	_refresh_menu()

func set_connection_state(value_online: bool, value_starting: bool) -> void:
	online = value_online
	starting = value_starting
	_refresh_menu()

func set_pet_enabled(enabled: bool) -> void:
	pet_enabled = enabled
	_refresh_menu()
func set_autostart_enabled(enabled: bool) -> void:
	autostart_enabled = enabled
	_refresh_menu()

func set_node_status(node_name: String, delay: int, value_online: bool) -> void:
	if not is_instance_valid(tray_indicator):
		return
	if not value_online:
		tray_indicator.tooltip = "HexagonProxy · 未连接"
	elif node_name.is_empty():
		tray_indicator.tooltip = "HexagonProxy · 已连接"
	else:
		var delay_text := "测速中" if delay <= 0 else "%d ms" % delay
		tray_indicator.tooltip = "HexagonProxy · %s · %s" % [node_name, delay_text]

func hide_indicator() -> void:
	if is_instance_valid(tray_indicator):
		tray_indicator.visible = false

func _refresh_menu() -> void:
	if not is_instance_valid(tray_menu):
		return
	var pet_index := tray_menu.get_item_index(TRAY_SHOW_PET)
	var connect_index := tray_menu.get_item_index(TRAY_CONNECT)
	var startup_index := tray_menu.get_item_index(TRAY_AUTOSTART)
	tray_menu.set_item_checked(pet_index, pet_enabled)
	tray_menu.set_item_checked(connect_index, online or starting)
	tray_menu.set_item_text(connect_index, "断开代理" if online or starting else "连接代理")
	tray_menu.set_item_checked(startup_index, autostart_enabled)
func _on_menu_pressed(id: int) -> void:
	match id:
		TRAY_SHOW_MAIN:
			show_main_requested.emit()
		TRAY_SHOW_PET:
			pet_toggle_requested.emit(not pet_enabled)
		TRAY_CONNECT:
			connect_requested.emit(not (online or starting))
		TRAY_AUTOSTART:
			autostart_toggle_requested.emit(not autostart_enabled)
		TRAY_EXIT:
			exit_requested.emit()
