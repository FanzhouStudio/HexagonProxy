extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var service = load("res://scripts/modules/ui/ui_theme_service.gd").new()
	root.add_child(service)
	service.initialize()
	var ui = load("res://scripts/ui/ui_factory.gd").new(service.snapshot())
	var panel = load("res://scripts/ui/nodes_panel.gd").new()
	root.add_child(panel)
	panel.setup(ui)
	var page: Control = panel.build()
	root.add_child(page)
	var names: Array = []
	for i in 600:
		names.append("benchmark-%04d" % i)
	var payload := {"proxies": {"六角选择": {"type": "Selector", "now": names[0], "all": names}}}
	panel.set_active(true)
	panel.handle_api_result("proxies", true, payload)
	while panel._node_views.size() != names.size():
		await process_frame
	var card: PanelContainer = panel._node_views[names[0]].card
	var original_style := card.get_theme_stylebox("panel")
	var visible_times: Array = []
	for i in 7:
		var start := Time.get_ticks_usec()
		panel.handle_api_result("proxies", true, payload)
		visible_times.append((Time.get_ticks_usec() - start) / 1000.0)
	visible_times.sort()
	var style_reused: bool = original_style == card.get_theme_stylebox("panel")
	panel.set_active(false)
	var hidden_start := Time.get_ticks_usec()
	for i in 7:
		panel.handle_api_result("proxies", true, payload)
	var result := {"nodes": names.size(), "visible_refresh_median_ms": visible_times[3], "hidden_refresh_mean_ms": (Time.get_ticks_usec() - hidden_start) / 7000.0, "unchanged_style_reused": style_reused}
	print(JSON.stringify(result))
	var output := OS.get_environment("HEXAGON_BENCHMARK_OUTPUT")
	if not output.is_empty():
		var file := FileAccess.open(output, FileAccess.WRITE)
		file.store_string(JSON.stringify(result, "  "))
	quit(0)
