extends SceneTree

const FixtureScript = preload("res://tests/helpers/proxy_runtime_fixture.gd")
const CoreUpdateServiceScript = preload("res://scripts/modules/mihomo/core_update_service.gd")

var fixture
var core_update
var download_done := false
var download_ok := false
var core_online := false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	fixture = FixtureScript.new()
	root.add_child(fixture)
	fixture.initialize(false)
	await process_frame
	core_update = CoreUpdateServiceScript.new()
	root.add_child(core_update)
	core_update.progress_changed.connect(func(progress: float, message: String) -> void:
		print("CORE DOWNLOAD: %s (%d%%)" % [message, int(maxf(progress, 0.0) * 100.0)])
		if progress < 0.0 or progress >= 1.0:
			download_done = true
			download_ok = progress >= 1.0
	)
	fixture.control.state_changed.connect(func(online: bool, _starting: bool, _pid: int, message: String) -> void:
		print("CORE STATUS: %s" % message)
		core_online = online
	)
	if fixture.config().has_core():
		download_done = true
		download_ok = true
	else:
		core_update.download_latest()
	var deadline := Time.get_ticks_msec() + 240000
	while not download_done and Time.get_ticks_msec() < deadline:
		await create_timer(0.2).timeout
	if not download_ok:
		printerr("FAIL: Mihomo 下载/安装")
		quit(2)
		return
	fixture.control.start()
	while not core_online and Time.get_ticks_msec() < deadline:
		fixture.control.poll_status()
		await create_timer(0.4).timeout
	if not core_online:
		printerr("FAIL: Mihomo 控制接口")
		fixture.control.stop()
		quit(3)
		return
	print("PASS: Mihomo 下载、校验、安装、启动与控制接口")
	fixture.control.stop()
	fixture.shutdown()
	quit(0)
