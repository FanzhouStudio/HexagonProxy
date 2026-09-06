class_name WindowChromeCoordinator
extends Node

## 主窗口顶栏与快捷键协调器
## AppShell 只发 action id；窗口、托盘与退出逻辑继续复用现有控制器。

var app_shell
var window_controller
var resident
var _active := false

func setup(shell, mode_controller, resident_controller) -> void:
	app_shell = shell
	window_controller = mode_controller
	resident = resident_controller
	app_shell.window_action_requested.connect(_on_window_action_requested)
	window_controller.exit_shortcut_requested.connect(_on_exit_shortcut_requested)

func start() -> void:
	_active = true

func shutdown() -> void:
	_active = false

func _on_window_action_requested(action_id: String) -> void:
	if not _active:
		return
	match action_id:
		"minimize":
			window_controller.minimize_window()
		"close":
			resident.close_main_window()
		"exit":
			resident.request_exit()

func _on_exit_shortcut_requested() -> void:
	if _active:
		resident.toggle_exit_prompt()
