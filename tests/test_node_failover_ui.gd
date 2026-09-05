extends SceneTree

const NodesPanelScript = preload("res://scripts/ui/nodes_panel.gd")
const UiFactoryScript = preload("res://scripts/ui/ui_factory.gd")

var toggles: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var ui = UiFactoryScript.new(Color("12384a"), Color("527384"), Color("16866f"), Color("c5f1dfde"), Color("a8e8e8e8"), Color("e9fbfbd4"), Color("d8f4f3dc"), Color("f7ffffdf"))
	var panel = NodesPanelScript.new()
	root.add_child(panel)
	panel.setup(ui)
	var page: Control = panel.build()
	root.add_child(page)
	panel.backup_toggle_requested.connect(func(group: String, node: String, enabled: bool) -> void:
		toggles.append("%s/%s/%s" % [group, node, enabled]))
	panel.set_failover_snapshot({"enabled": true, "status": "当前节点健康", "route_group": "六角选择", "backups": [{"group": "六角选择", "node": "节点B"}]})
	panel.set_active(true)
	panel.handle_api_result("proxies", true, {"proxies": {"六角选择": {"type": "Selector", "now": "节点A", "all": ["节点A", "节点B", "节点C"]}}})
	await process_frame
	if not panel.failover_toggle.button_pressed or panel.failover_status_label.text != "当前节点健康":
		_fail("故障切换快照没有同步到顶部 UI", 2)
		return
	var backup_button: Button
	for node in page.find_children("*", "Button", true, false):
		var button := node as Button
		if button and button.text == "★ 备选":
			backup_button = button
			break
	if backup_button == null:
		_fail("备选节点没有渲染为 ★ 备选", 3)
		return
	backup_button.pressed.emit()
	if toggles != ["六角选择/节点B/false"]:
		_fail("点击备选按钮没有发出数据化 toggle 意图", 4)
		return
	print("PASS: 节点故障切换顶部状态与备选按钮 UI 契约")
	quit(0)

func _fail(message: String, code: int) -> void:
	printerr("FAIL: %s" % message)
	quit(code)
