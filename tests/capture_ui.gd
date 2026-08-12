extends SceneTree

func _init() -> void:
	call_deferred("_capture")

func _capture() -> void:
	var scene: Node = load("res://main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	await create_timer(0.35).timeout
	var result := OK
	for page_name in ["dashboard", "nodes", "subscription", "settings"]:
		scene.call("_show_page", page_name)
		await process_frame
		var image := root.get_texture().get_image()
		var file_name := "ui-preview.png" if page_name == "dashboard" else "ui-%s.png" % page_name
		result = image.save_png("res://build/%s" % file_name)
		if result != OK:
			break
	print("UI capture: %s" % error_string(result))
	quit(0 if result == OK else 1)
