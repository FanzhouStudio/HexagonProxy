extends SceneTree

const Controller = preload("res://scripts/app/window_mode_controller.gd")

class WindowConfig extends RefCounted:
	func window_borderless() -> bool:
		return false
	func window_size() -> Vector2i:
		return Vector2i(1280, 720)

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	assert(DisplayServer.has_method("window_start_drag"))
	var controller := Controller.new()
	root.add_child(controller)
	controller.setup(root, WindowConfig.new())
	controller.start()
	controller.apply_saved_window_mode()
	await process_frame
	await process_frame
	assert(root.mode == Window.MODE_WINDOWED and root.borderless and root.size == Vector2i(1280, 720), "Existing windowed preferences must hide system decorations without forcing fullscreen")
	if DisplayServer.get_name().to_lower() != "headless":
		assert(DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_BORDERLESS), "Native system title bar must be removed")
	controller.toggle_maximized()
	await process_frame
	assert(root.mode == Window.MODE_MAXIMIZED and root.borderless)
	controller.toggle_maximized()
	await process_frame
	assert(root.mode == Window.MODE_WINDOWED and root.borderless)
	if DisplayServer.get_name().to_lower() != "headless":
		controller.minimize_window()
		await process_frame
		assert(root.mode == Window.MODE_MINIMIZED)
		controller.apply_saved_window_mode()
		await process_frame
		assert(root.mode == Window.MODE_WINDOWED and root.borderless)
	var scene: Control = load("res://main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var actions: Array = []
	scene.app_shell.window_action_requested.connect(func(action: String) -> void: actions.append(action))
	scene.window_chrome_coordinator.shutdown()
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	scene.app_shell.page_title.gui_input.emit(click)
	click.double_click = true
	scene.app_shell.page_title.gui_input.emit(click)
	click.button_index = MOUSE_BUTTON_RIGHT
	scene.app_shell.page_title.gui_input.emit(click)
	assert(actions == ["drag", "maximize"], "Only left clicks on the title region move or maximize the window")
	scene._quit_application()
	controller.shutdown()
	print("PASS: borderless windowed mode, maximize/restore, native chrome, minimize and title input routing")
	quit(0)
