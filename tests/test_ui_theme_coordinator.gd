extends SceneTree

const CoordinatorScript = preload("res://scripts/app/ui_theme_coordinator.gd")
const UiFactoryScript = preload("res://scripts/ui/ui_factory.gd")

class FakeService:
	signal theme_changed(snapshot: Dictionary)
	var current := "blue_healing"
	var calls: Array[String] = []
	func catalog() -> Array:
		return [{"id":"blue_healing","name":"海蓝治愈"},{"id":"midnight","name":"夜海黑"}]
	func current_theme_id() -> String:
		return current
	func snapshot() -> Dictionary:
		return {"id": current, "name": "夜海黑" if current == "midnight" else "海蓝治愈", "colors": {}, "button_textures": {}}
	func set_theme(theme_id: String) -> Dictionary:
		calls.append(theme_id)
		current = theme_id
		var data := snapshot()
		theme_changed.emit(data)
		return {"ok": true, "theme": data}

class FakeFactory:
	var applied: Array[String] = []
	func apply_theme(snapshot: Dictionary) -> void:
		applied.append(str(snapshot.get("id", "")))
class FakePanel:
	signal ui_theme_requested(theme_id: String)
	var catalogs := 0
	var states: Array[String] = []
	var messages: Array[String] = []
	func set_theme_catalog(_items: Array, _current_id: String) -> void:
		catalogs += 1
	func set_theme_state(snapshot: Dictionary) -> void:
		states.append(str(snapshot.get("id", "")))
	func show_theme_message(message: String, _success: bool) -> void:
		messages.append(message)

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var service = FakeService.new()
	var panel = FakePanel.new()
	var ui = UiFactoryScript.new()
	var coordinator = CoordinatorScript.new()
	root.add_child(coordinator)
	coordinator.setup(service, ui, panel)
	coordinator.start()
	if panel.catalogs != 1 or panel.states != ["blue_healing"]:
		_fail("主题协调器启动时没有同步目录和当前主题", 2)
		return
	panel.ui_theme_requested.emit("midnight")
	if service.calls != ["midnight"] or ui.theme_id() != "midnight":
		_fail("主题选择意图没有路由到 Service/UiFactory", 3)
		return
	if panel.states.back() != "midnight" or panel.messages.is_empty():
		_fail("主题切换后没有回写设置页状态", 4)
		return
	coordinator.shutdown()
	panel.ui_theme_requested.emit("blue_healing")
	if service.calls.size() != 1 or ui.theme_id() != "midnight":
		_fail("协调器关闭后仍响应主题意图", 5)
		return
	print("PASS: UiThemeCoordinator 主题目录、切换意图、实时应用与关闭保护")
	quit(0)

func _fail(message: String, code: int) -> void:
	printerr("FAIL: %s" % message)
	quit(code)
