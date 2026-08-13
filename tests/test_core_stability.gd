extends SceneTree

const CoreControllerScript = preload("res://scripts/core_controller.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var controller: CoreController = CoreControllerScript.new()
	root.add_child(controller)
	await process_frame
	var valid_profile := FileAccess.get_file_as_string(controller.profile_path())
	if not bool(controller._validate_active_profile().get("ok", false)):
		printerr("FAIL: 默认配置未通过 Mihomo 校验")
		quit(2)
		return
	if not controller._write_profile("broken: [\n"):
		printerr("FAIL: 无法写入无效配置测试样本")
		quit(3)
		return
	if bool(controller._validate_active_profile().get("ok", true)):
		printerr("FAIL: 无效配置没有被启动前校验拦截")
		quit(4)
		return
	controller._write_profile(valid_profile)

	var blocker := TCPServer.new()
	var owns_blocker := false
	if controller._tcp_port_is_available(controller.CONTROLLER_PORT):
		owns_blocker = blocker.listen(controller.CONTROLLER_PORT, controller.CONTROLLER_HOST) == OK
	controller._should_run = true
	controller._launch_core()
	await process_frame
	if controller.core_pid > 0 or controller._should_run:
		if controller.core_pid > 0:
			controller.stop_core()
		if owns_blocker:
			blocker.stop()
		printerr("FAIL: 端口冲突没有阻止内核启动")
		quit(5)
		return
	if owns_blocker:
		blocker.stop()

	controller.core_pid = 2147483647
	controller._core_started_msec = Time.get_ticks_msec() - controller.CORE_PROCESS_START_GRACE_MSEC
	controller._should_run = true
	controller._monitor_core_process()
	await process_frame
	if controller.core_pid != -1 or not controller._recovery_pending or controller._recovery_attempts != 1:
		controller.stop_core()
		printerr("FAIL: 异常退出没有进入有限自动恢复")
		quit(6)
		return
	controller.stop_core()
	print("PASS: 配置预检、端口冲突拦截与恢复参数")
	quit(0)
