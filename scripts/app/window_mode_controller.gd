class_name WindowModeController
extends Node

## 主窗口显示模式控制器
## 图形环境默认进入无边框全屏；F11 不再切换窗口模式。
## ESC 只发出退出提示意图，具体退出流程由 ResidentController 负责。

signal exit_shortcut_requested

const WINDOWED_SIZE := Vector2i(1920, 1080)
const DEFAULT_FULLSCREEN := true

var target_window: Window
var _active := false

func setup(window: Window) -> void:
	target_window = window

func start() -> void:
	_active = true
	set_process_unhandled_key_input(true)
	var tray_start := "--tray-start" in OS.get_cmdline_user_args()
	if DEFAULT_FULLSCREEN and not tray_start and DisplayServer.get_name().to_lower() != "headless":
		call_deferred("set_fullscreen", true)

func startup_fullscreen_enabled() -> bool:
	return DEFAULT_FULLSCREEN

func shutdown() -> void:
	_active = false
	set_process_unhandled_key_input(false)

func is_fullscreen() -> bool:
	if not is_instance_valid(target_window):
		return false
	return target_window.mode in [Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN]

func minimize_window() -> void:
	if not is_instance_valid(target_window) or DisplayServer.get_name().to_lower() == "headless":
		return
	target_window.mode = Window.MODE_MINIMIZED

func set_fullscreen(enabled: bool) -> void:
	if not is_instance_valid(target_window):
		return
	if enabled:
		target_window.borderless = true
		target_window.mode = Window.MODE_FULLSCREEN
		return
	target_window.mode = Window.MODE_WINDOWED
	target_window.borderless = false
	target_window.size = WINDOWED_SIZE
	call_deferred("_center_window")

func _center_window() -> void:
	if not is_instance_valid(target_window):
		return
	var screen := DisplayServer.window_get_current_screen(target_window.get_window_id())
	var usable := DisplayServer.screen_get_usable_rect(screen)
	target_window.position = usable.position + (usable.size - target_window.size) / 2

func _unhandled_key_input(event: InputEvent) -> void:
	if not _active or not event is InputEventKey:
		return
	var key := event as InputEventKey
	if key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
		exit_shortcut_requested.emit()
		get_viewport().set_input_as_handled()
