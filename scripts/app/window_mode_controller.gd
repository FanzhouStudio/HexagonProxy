class_name WindowModeController
extends Node

## 主窗口显示模式控制器
## 图形环境默认进入无边框全屏；F11 不再切换窗口模式。
## ESC 只发出退出提示意图，具体退出流程由 ResidentController 负责。

signal exit_shortcut_requested

const DEFAULT_WINDOW_SIZE := Vector2i(1920, 1080)

var target_window: Window
var proxy_config
var _active := false

func setup(window: Window, config = null) -> void:
	target_window = window
	proxy_config = config

func start() -> void:
	_active = true
	set_process_unhandled_key_input(true)
	var tray_start := "--tray-start" in OS.get_cmdline_user_args()
	if not tray_start and DisplayServer.get_name().to_lower() != "headless":
		call_deferred("apply_saved_window_mode")

func startup_fullscreen_enabled() -> bool:
	return _is_borderless()

func apply_saved_window_mode() -> void:
	set_fullscreen(_is_borderless())

func _is_borderless() -> bool:
	if proxy_config and proxy_config.has_method("window_borderless"):
		return proxy_config.window_borderless()
	return true

func _window_size() -> Vector2i:
	if proxy_config and proxy_config.has_method("window_size"):
		return proxy_config.window_size()
	return DEFAULT_WINDOW_SIZE

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
	# 避免无边框全屏窗口直接切换 MINIMIZED 导致 Windows 重建窗口表面产生闪屏。
	# 先恢复窗口焦点状态，再交给系统最小化。
	if target_window.mode == Window.MODE_FULLSCREEN:
		target_window.mode = Window.MODE_WINDOWED
		await get_tree().process_frame
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
	target_window.size = _window_size()
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
