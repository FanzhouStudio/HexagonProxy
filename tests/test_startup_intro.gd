extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var intro = load("res://scripts/ui/startup_intro.gd").new()
	intro.animate = false
	root.add_child(intro)
	await process_frame
	assert(intro.emblem.texture != null)
	assert(intro.mouse_filter == Control.MOUSE_FILTER_STOP)
	intro.update_frame(0.4)
	assert(intro.modulate.a == 1.0 and intro.wordmark.modulate.a == 1.0)
	intro.update_frame(1.1)
	assert(intro.modulate.a == 0.0)
	var calls: Array = []
	intro.completed.connect(func() -> void: calls.append(true))
	intro.dismiss()
	intro.dismiss()
	assert(calls.size() == 1 and not intro.visible)
	var path := str(ProjectSettings.get_setting("application/boot_splash/image"))
	assert(path == "res://assets/ui/boot_mark.png" and FileAccess.file_exists(path))
	var timed = load("res://scripts/ui/startup_intro.gd").new()
	root.add_child(timed)
	await create_timer(1.3).timeout
	assert(not is_instance_valid(timed), "Intro must finish automatically without leaving an input-blocking overlay")
	print("PASS: vector mascot, startup fade, dismissal and matching engine splash")
	quit(0)
