extends SceneTree

const CoreControllerScript = preload("res://scripts/core_controller.gd")

var controller: CoreController
var download_done := false
var download_ok := false
var core_online := false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	controller = CoreControllerScript.new()
	root.add_child(controller)
	await process_frame
	controller.download_progress.connect(func(progress: float, message: String) -> void:
		print("CORE DOWNLOAD: %s (%d%%)" % [message, int(maxf(progress, 0.0) * 100.0)])
		if progress < 0.0 or progress >= 1.0:
			download_done = true
			download_ok = progress >= 1.0
	)
	controller.status_changed.connect(func(online: bool, message: String) -> void:
		print("CORE STATUS: %s" % message)
		core_online = online
	)
	if controller.has_core():
		download_done = true
		download_ok = true
	else:
		controller.download_latest_core()
	var deadline := Time.get_ticks_msec() + 240000
	while not download_done and Time.get_ticks_msec() < deadline:
		await create_timer(0.2).timeout
	if not download_ok:
		printerr("FAIL: Mihomo 下载/安装")
		quit(2)
		return
	controller.start_core()
	while not core_online and Time.get_ticks_msec() < deadline:
		controller.poll_status()
		await create_timer(0.4).timeout
	if not core_online:
		printerr("FAIL: Mihomo 控制接口")
		controller.stop_core()
		quit(3)
		return
	print("PASS: Mihomo 下载、校验、安装、启动与控制接口")
	controller.stop_core()
	quit(0)
