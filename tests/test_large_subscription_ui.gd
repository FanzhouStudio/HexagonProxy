extends SceneTree

const MainScript = preload("res://scripts/main.gd")
const NODE_COUNT := 360

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var main := MainScript.new()
	root.add_child(main)
	await process_frame
	main._show_page("subscription")
	var node_names: Array = []
	for index in NODE_COUNT:
		node_names.append("测试节点-%03d" % index)
	main._apply_proxies({
		"proxies": {
			"GLOBAL": {
				"type": "Selector",
				"now": "DIRECT",
				"all": ["DIRECT", "REJECT", "六角选择", "自动优选"]
			},
			"六角选择": {
				"type": "Selector",
				"now": node_names[0],
				"all": node_names
			}
		}
	})
	await process_frame
	if main.proxy_groups.size() != 1 or main.group_selector.get_item_text(main.selected_group_index) != "六角选择":
		printerr("FAIL: Mihomo GLOBAL 内部策略组被误当成订阅节点组")
		quit(2)
		return
	if main.node_grid.get_child_count() > 1:
		printerr("FAIL: 隐藏的节点页仍同步渲染了大量节点")
		quit(3)
		return
	main._show_page("nodes")
	var deadline := Time.get_ticks_msec() + 5000
	while main.node_grid.get_child_count() < NODE_COUNT and Time.get_ticks_msec() < deadline:
		await process_frame
	if main.node_grid.get_child_count() != NODE_COUNT:
		printerr("FAIL: 节点页分批渲染未完成，实际 %d / %d" % [main.node_grid.get_child_count(), NODE_COUNT])
		quit(4)
		return
	main.delay_cache["测试节点-000"] = -2
	main._rebuild_nodes()
	await process_frame
	var first_card := main.node_grid.get_child(0) as PanelContainer
	var first_delay_label := first_card.get_child(0).get_child(0).get_child(1).get_child(0) as Label
	if first_delay_label.text != "测速中…":
		printerr("FAIL: 单节点测速没有显示进行中状态")
		quit(7)
		return
	main._on_api_result("delay:测试节点-000", false, {})
	await process_frame
	first_card = main.node_grid.get_child(0) as PanelContainer
	first_delay_label = first_card.get_child(0).get_child(0).get_child(1).get_child(0) as Label
	if first_delay_label.text != "失败":
		printerr("FAIL: 单节点测速失败后没有反馈")
		quit(8)
		return
	main._apply_connections({"downloadTotal": 0, "uploadTotal": 0, "connections": null})
	if main.connections_label.text != "0":
		printerr("FAIL: Mihomo connections=null 未被当作空连接列表处理")
		quit(5)
		return
	main._apply_proxies({"proxies": null})
	if not main.proxy_groups.is_empty():
		printerr("FAIL: Mihomo proxies=null 未被当作空策略组处理")
		quit(6)
		return
	print("PASS: 大订阅仅在节点页分批渲染（%d 个节点）" % NODE_COUNT)
	quit(0)
