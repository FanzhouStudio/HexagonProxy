extends SceneTree

func _init() -> void:
	var image := Image.new()
	var error := image.load_svg_from_string(FileAccess.get_file_as_string("res://assets/ui/axolotl_mark.svg"))
	if error != OK:
		quit(1)
		return
	image.resize(176, 176, Image.INTERPOLATE_LANCZOS)
	error = image.save_png("res://assets/ui/boot_mark.png")
	quit(0 if error == OK else 1)
