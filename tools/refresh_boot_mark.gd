extends SceneTree

# Run with Godot --headless --path . --script tools/refresh_boot_mark.gd.
# Rasterize the canonical vector mark so the engine splash keeps its true colors.
func _init() -> void:
	var image := Image.new()
	var error := image.load_svg_from_string(FileAccess.get_file_as_string("res://assets/ui/axolotl_mark.svg"))
	if error == OK:
		error = image.save_png("res://assets/ui/boot_mark.png")
	if error != OK:
		printerr("Unable to refresh boot mascot: %s" % error_string(error))
	quit(0 if error == OK else 1)
