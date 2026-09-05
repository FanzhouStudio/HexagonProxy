extends SceneTree

const SettingsCoordinatorScript = preload("res://scripts/app/settings_coordinator.gd")

class FakeMihomo:
	var online := false
	var starting := false
	var core_pid := -1
	var restarts := 0
	var starts := 0
	func restart() -> void: restarts += 1
	func start() -> void: starts += 1

class FakeCoreUpdate:
	signal progress_changed(progress: float, message: String)
	signal finished(success: bool, message: String)
	var busy := false
	var downloads := 0
	func is_busy() -> bool: return busy
	func download_latest() -> void: downloads += 1

class FakeAutostart:
	signal status_changed(enabled: bool)
	signal busy_changed(busy: bool)
	var requests: Array[bool] = []
	func set_enabled(value: bool) -> void: requests.append(value)

class FakeSettings:
	signal core_restart_requested
	signal core_update_requested
	signal ports_apply_requested(mixed_port: int, controller_port: int)
	signal port_random_requested(kind: String)
	var blocked_messages: Array[String] = []
	var port_messages: Array[String] = []
	var port_values := Vector2i.ZERO
	var progress := -2.0
	var progress_message := ""
	func show_core_update_blocked(message: String) -> void: blocked_messages.append(message)
	func set_port_values(mixed_port: int, controller_port: int) -> void: port_values = Vector2i(mixed_port, controller_port)
	func show_port_message(message: String, _success: bool) -> void: port_messages.append(message)
	func set_core_update_progress(value: float, message: String) -> void:
		progress = value
		progress_message = message

class FakeConfig:
	var mixed := 7890
	var controller := 19090
	func mixed_port() -> int: return mixed
	func controller_port() -> int: return controller
	func set_ports(mixed_port: int, controller_port: int) -> Dictionary:
		if mixed_port == controller_port:
			return {"ok": false, "message": "端口不能相同"}
		mixed = mixed_port
		controller = controller_port
		return {"ok": true, "message": "端口设置已保存。"}
	func random_available_port(excluded_port := -1) -> int:
		return 25001 if excluded_port != 25001 else 25002

class FakeResident:
	signal autostart_requested(enabled: bool)
	var autostart_enabled := false
	var autostart_busy := false
	func set_autostart_state(value: bool) -> void: autostart_enabled = value
	func set_autostart_busy(value: bool) -> void: autostart_busy = value

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var mihomo = FakeMihomo.new()
	var core_update = FakeCoreUpdate.new()
	var autostart = FakeAutostart.new()
	var config = FakeConfig.new()
	var settings = FakeSettings.new()
	var resident = FakeResident.new()
	var coordinator = SettingsCoordinatorScript.new()
	root.add_child(coordinator)
	coordinator.setup(mihomo, core_update, autostart, config, settings, resident)
	coordinator.start()
	resident.autostart_requested.emit(true)
	autostart.status_changed.emit(true)
	autostart.busy_changed.emit(true)
	if autostart.requests != [true] or not resident.autostart_enabled or not resident.autostart_busy:
		_fail("开机自启意图或状态同步失败", 2)
		return

	settings.ports_apply_requested.emit(23456, 23457)
	if config.mixed != 23456 or config.controller != 23457 or settings.port_values != Vector2i(23456, 23457):
		_fail("手动端口设置没有通过协调器保存并回写", 9)
		return
	settings.port_random_requested.emit("mixed")
	settings.port_random_requested.emit("controller")
	if config.mixed != 25001 or config.controller != 25002:
		_fail("随机端口没有分别应用到混合端口和控制端口", 10)
		return
	mihomo.online = true
	settings.ports_apply_requested.emit(26000, 26001)
	if config.mixed == 26000 or settings.port_messages.is_empty() or not settings.port_messages.back().contains("先断开"):
		_fail("代理运行中仍允许修改端口", 11)
		return
	mihomo.online = false

	core_update.progress_changed.emit(0.5, "下载中")
	if settings.progress != 0.5 or settings.progress_message != "下载中":
		_fail("内核更新进度没有回写设置面板", 3)
		return
	settings.core_update_requested.emit()
	if core_update.downloads != 1:
		_fail("离线时内核更新请求没有执行", 4)
		return
	mihomo.online = true
	settings.core_update_requested.emit()
	if core_update.downloads != 1 or settings.blocked_messages.is_empty():
		_fail("在线时内核更新没有被阻止", 5)
		return
	settings.core_restart_requested.emit()
	if mihomo.restarts != 1:
		_fail("内核重启请求没有执行", 6)
		return
	core_update.finished.emit(true, "完成")
	if mihomo.starts != 1:
		_fail("内核更新成功后没有启动 Mihomo", 7)
		return

	coordinator.shutdown()
	var starts_before: int = int(mihomo.starts)
	var restarts_before: int = int(mihomo.restarts)
	var requests_before: int = autostart.requests.size()
	core_update.finished.emit(true, "关闭后")
	settings.core_restart_requested.emit()
	resident.autostart_requested.emit(false)
	if mihomo.starts != starts_before or mihomo.restarts != restarts_before or autostart.requests.size() != requests_before:
		_fail("协调器关闭后仍响应设置事件", 8)
		return
	print("PASS: SettingsCoordinator 内核更新、重启、自启与关闭保护")
	quit(0)

func _fail(message: String, code: int) -> void:
	printerr("FAIL: %s" % message)
	quit(code)