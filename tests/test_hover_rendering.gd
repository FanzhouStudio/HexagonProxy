extends SceneTree
var surface: SubViewport

func _init() -> void:
	call_deferred("_run")

func _move(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	surface.push_input(motion, true)

func _run() -> void:
	assert(DisplayServer.get_name() != "headless")
	surface = SubViewport.new()
	surface.size = Vector2i(1920, 1080)
	surface.gui_embed_subwindows = true
	surface.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(surface)
	surface.notify_mouse_entered()
	var scene: Control = load("res://main.tscn").instantiate()
	surface.add_child(scene)
	await create_timer(1.6).timeout
	scene.antigravity_proxy_coordinator.shutdown()
	scene.codex_profile_coordinator.shutdown()
	await process_frame
	assert(root.gui_embed_subwindows, "Application popups must be embedded, not native fullscreen overlays")
	var buttons: Array = [scene.app_shell.window_action_buttons.minimize, scene.app_shell.window_action_buttons.close, scene.app_shell.window_action_buttons.exit]
	var panel = scene.app_shell.antigravity_proxy_panel
	var state := {"accounts": [{"id": "default", "name": "账号"}], "quota_snapshots": {"default": {"ok": true, "checked_at": "initial", "models": [{"name": "Fixture model", "remaining": 75}]}}}
	panel.render(state)
	var account_id: int = scene.app_shell.antigravity_proxy_panel.account_list.get_child(0).get_instance_id()
	var bar_id: int = panel.quota_bars[0].get_instance_id()
	for low_power in [true, false]:
		OS.low_processor_usage_mode = low_power
		var times: Array = []
		for repeat in 3:
			var button: Button = buttons[repeat % 3]
			assert(button.tooltip_text.is_empty(), "Labeled window actions must not spawn tooltip windows")
			_move(Vector2(500, 500))
			await process_frame
			await RenderingServer.frame_post_draw
			var rect := button.get_global_rect()
			var probe := rect.position + Vector2(8, 8)
			var pixel := Vector2i(probe)
			var before := surface.get_texture().get_image().get_pixelv(pixel)
			var start := Time.get_ticks_usec()
			_move(rect.get_center())
			state.quota_snapshots.default.checked_at = "%s/%d" % [low_power, repeat]
			state.quota_snapshots.default.models[0].remaining = 75 - repeat
			panel.render(state)
			await process_frame
			await RenderingServer.frame_post_draw
			var after := surface.get_texture().get_image().get_pixelv(pixel)
			times.append((Time.get_ticks_usec() - start) / 1000.0)
			assert(button.is_hovered() and button.get_draw_mode() == BaseButton.DRAW_HOVER, "Hover must reach the button on the next frame: mouse=%s target=%s hovered=%s" % [surface.get_mouse_position(), rect, surface.gui_get_hovered_control()])
			assert(before != after, "Hover must change actual rendered button pixels")
			assert(scene.app_shell.antigravity_proxy_panel.account_list.get_child(0).get_instance_id() == account_id, "Hover must not rebuild account rows")
			assert(panel.quota_bars[0].get_instance_id() == bar_id, "Background quota updates cannot reconstruct controls while hovering")
			var rect_before := button.get_global_rect()
			var style_before := button.get_theme_stylebox("hover")
			# Keep the mouse still well beyond the tooltip timer; the previous
			# test moved away after one frame and never covered this path.
			for tick in 20:
				await create_timer(0.1).timeout
				state.quota_snapshots.default.checked_at = str(tick)
				panel.render(state)
				assert(button.is_hovered() and button.get_draw_mode() == BaseButton.DRAW_HOVER, "Stationary hover must survive beyond the tooltip delay")
				assert(button.get_global_rect() == rect_before and button.get_theme_stylebox("hover") == style_before, "Stationary hover cannot recreate button styles or resize the top bar")
				assert(panel.quota_bars[0].get_instance_id() == bar_id, "Background polling while hovering must keep model controls")
		print("HOVER low_power=%s frame_ms=%s" % [low_power, times])
	# Other controls still use tooltips, but they must be in the same viewport.
	var tooltip_target := Button.new()
	tooltip_target.text = "内嵌提示测试"
	tooltip_target.tooltip_text = "此提示不能创建独立 Windows 窗口"
	tooltip_target.position = Vector2(600, 300)
	tooltip_target.size = Vector2(260, 50)
	surface.add_child(tooltip_target)
	_move(tooltip_target.get_global_rect().get_center())
	await create_timer(0.5).timeout
	var popups := surface.find_children("*", "PopupPanel", true, false)
	assert(not popups.is_empty(), "Test must wait long enough to actually create a tooltip")
	for popup in popups:
		assert(popup.is_embedded(), "Tooltip must never get its own native window")
	print("PASS: all three stationary hovers, stable layout and actually opened embedded tooltip")
	scene._quit_application()
	quit(0)
