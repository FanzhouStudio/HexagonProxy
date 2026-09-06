extends SceneTree

const CoordinatorScript = preload("res://scripts/app/window_chrome_coordinator.gd")

class FakeShell:
	extends Node
	signal window_action_requested(action_id: String)

class FakeWindowController:
	extends Node
	signal exit_shortcut_requested
	var minimizes := 0
	func minimize_window() -> void:
		minimizes += 1

class FakeResident:
	extends Node
	var closes := 0
	var exits := 0
	var toggles := 0
	func close_main_window() -> void:
		closes += 1
	func request_exit() -> void:
		exits += 1
	func toggle_exit_prompt() -> void:
		toggles += 1

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var shell := FakeShell.new()
	var window_controller := FakeWindowController.new()
	var resident := FakeResident.new()
	root.add_child(shell)
	root.add_child(window_controller)
	root.add_child(resident)
	var coordinator = CoordinatorScript.new()
	root.add_child(coordinator)
	coordinator.setup(shell, window_controller, resident)
	coordinator.start()

	shell.window_action_requested.emit("minimize")
	shell.window_action_requested.emit("close")
	shell.window_action_requested.emit("exit")
	window_controller.exit_shortcut_requested.emit()
	if window_controller.minimizes != 1 or resident.closes != 1 or resident.exits != 1 or resident.toggles != 1:
		_fail("窗口 action 或 ESC 路由不正确", 2)
		return

	coordinator.shutdown()
	shell.window_action_requested.emit("exit")
	window_controller.exit_shortcut_requested.emit()
	if resident.exits != 1 or resident.toggles != 1:
		_fail("shutdown 后仍响应窗口意图", 3)
		return
	print("PASS: WindowChromeCoordinator 顶栏动作与 ESC 路由")
	quit(0)

func _fail(message: String, code: int) -> void:
	printerr("FAIL: %s" % message)
	quit(code)
