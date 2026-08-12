extends SceneTree

const DesktopPetScript = preload("res://scripts/desktop_pet.gd")

func _init() -> void:
	call_deferred("_capture")

func _capture() -> void:
	var pet: Node = DesktopPetScript.new()
	root.add_child(pet)
	pet.create_pet(Vector2i(120, 120), true)
	pet.set_node_status("东京母鸡-Hysteria2", 213, true)
	await process_frame
	await process_frame
	await create_timer(0.35).timeout
	var image: Image = pet.pet_window.get_texture().get_image()
	var result := image.save_png("res://build/ui-desktop-pet.png")
	print("Desktop pet capture: %s" % error_string(result))
	quit(0 if result == OK else 1)
