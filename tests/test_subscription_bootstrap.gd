extends SceneTree

const Service = preload("res://scripts/modules/subscription/subscription_service.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var service := Service.new()
	root.add_child(service)
	service.initialize()
	assert(service.use_subscription_url("https://example.com/subscription?token=fixture"))
	var entries: Array = service.get_subscriptions()
	var entry: Dictionary = entries[-1]
	var path: String = service.subscription_store.library_dir().path_join(entry.config_file)
	var yaml := FileAccess.get_file_as_string(path)
	assert(yaml.contains("type: http\n    proxy: DIRECT\n"))
	var legacy := yaml.replace("    proxy: DIRECT\n", "")
	assert(service.subscription_store.write_text_atomic(path, legacy))
	service.profile_maintenance.repair_entry(entry, str(entry.id))
	var repaired := FileAccess.get_file_as_string(path)
	assert(repaired == yaml, "Legacy repair must only add the provider download route")
	assert(FileAccess.get_file_as_string(service.profile_path()) == yaml)
	var custom := yaml.replace("    proxy: DIRECT\n", "    proxy: OtherProxy\n")
	assert(service.subscription_store.write_text_atomic(path, custom))
	service.profile_maintenance.repair_entry(entry, str(entry.id))
	assert(FileAccess.get_file_as_string(path) == custom, "Keep an explicitly configured provider proxy")
	service.queue_free()
	print("PASS: HTTP subscription bootstrap route, legacy repair and custom route preservation")
	quit(0)
