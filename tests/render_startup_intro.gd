extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1600, 900)
	var intro = load("res://scripts/ui/startup_intro.gd").new()
	intro.animate = false
	root.add_child(intro)
	await process_frame
	intro.update_frame(0.4)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/ui-startup.png")
	intro.dismiss()
	quit(0)
