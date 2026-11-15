extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _payload(now_name: String, names: Array) -> Dictionary:
	return {"proxies": {
		"六角选择": {
			"type": "Selector",
			"now": now_name,
			"all": names
		}
	}}

func _run() -> void:
	var scene: Control = load("res://main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var panel = scene.nodes_panel
	var shell = scene.app_shell
	shell.show_page("nodes")
	panel.handle_api_result("proxies", true, _payload("A", ["A", "B", "C"]))
	await process_frame
	await process_frame
	if panel._node_views.size() != 3:
		_fail("初始节点网格没有完成构建", 2)
		return
	var grid_id: int = int(panel.node_grid.get_instance_id())
	var card_a: PanelContainer = panel._node_views["A"].get("card")
	var card_a_id: int = int(card_a.get_instance_id())
	for _index in 10:
		panel.handle_api_result("proxies", true, _payload("A", ["A", "B", "C"]))
	if panel.node_grid.get_instance_id() != grid_id or panel._node_views["A"].get("card").get_instance_id() != card_a_id:
		_fail("相同 proxies 周期刷新仍然重建节点 UI", 3)
		return
	var original_style := card_a.get_theme_stylebox("panel")
	for _index in 10:
		panel.handle_api_result("proxies", true, _payload("A", ["A", "B", "C"]))
	if card_a.get_theme_stylebox("panel") != original_style:
		_fail("未变化的节点状态仍在创建新样式", 12)
		return

	panel.handle_api_result("delay:A", true, {"delay": 88})
	var delay_label: Label = panel._node_views["A"].get("delay_label")
	if panel.node_grid.get_instance_id() != grid_id or delay_label.text != "88 ms":
		_fail("单节点延迟更新触发重建或没有原地刷新", 4)
		return

	panel.handle_api_result("proxies", true, _payload("B", ["A", "B", "C"]))
	var choose_a: Button = panel._node_views["A"].get("choose_button")
	var choose_b: Button = panel._node_views["B"].get("choose_button")
	if panel.node_grid.get_instance_id() != grid_id or choose_a.text != "选择" or choose_b.text != "已选":
		_fail("当前节点切换没有使用原地状态刷新", 5)
		return
	panel.set_failover_snapshot({
		"enabled": true,
		"route_group": "六角选择",
		"backups": [{"group": "六角选择", "node": "C"}],
		"status": "测试"
	})
	if panel.node_grid.get_instance_id() != grid_id:
		_fail("备选节点状态变化仍然重建整个节点网格", 6)
		return
	shell.show_page("subscription")
	var hidden_style := card_a.get_theme_stylebox("panel")
	panel.handle_api_result("proxies", true, _payload("C", ["A", "B", "C"]))
	if card_a.get_theme_stylebox("panel") != hidden_style or choose_b.text != "已选":
		_fail("隐藏节点页面仍在更新控件", 13)
		return
	shell.show_page("nodes")
	var choose_c: Button = panel._node_views["C"].get("choose_button")
	if choose_c.text != "已选" or choose_b.text != "选择":
		_fail("重新显示节点页后状态没有恢复到最新数据", 14)
		return

	var many: Array = []
	for index in 40:
		many.append("N%02d" % index)
	panel.handle_api_result("proxies", true, _payload("N00", many))
	if panel.node_grid.get_instance_id() != grid_id or panel.node_grid.get_child_count() != 3:
		_fail("新节点结构构建时提前清空了旧网格", 7)
		return
	for _frame in 5:
		await process_frame
	if panel.node_grid.get_instance_id() == grid_id or panel.node_grid.get_child_count() != 40:
		_fail("双缓冲节点网格没有在构建完成后完成交换", 8)
		return
	var background = shell.aquarium_background
	if not background is ColorRect or background.is_processing():
		_fail("静态背景仍在执行逐帧绘制逻辑", 9)
		return

	scene.queue_free()
	await process_frame
	print("PASS: unchanged style reuse, hidden-page suspension, latest-state restoration and buffered node rendering")
	quit(0)

func _fail(message: String, code: int) -> void:
	printerr("FAIL: %s" % message)
	quit(code)
