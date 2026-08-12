extends SceneTree

func _init() -> void:
	call_deferred("_capture")

func _capture() -> void:
	var scene: Node = load("res://main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	scene.call("_show_close_prompt")
	await process_frame
	await create_timer(0.25).timeout
	var image := root.get_texture().get_image()
	var result := image.save_png("res://build/ui-close-prompt.png")
	print("Close prompt capture: %s" % error_string(result))
	quit(0 if result == OK else 1)
