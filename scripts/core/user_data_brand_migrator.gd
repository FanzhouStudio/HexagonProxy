class_name UserDataBrandMigrator
extends RefCounted

const LEGACY_APP_NAME := "六角代理"

func migrate_if_needed() -> Dictionary:
	if OS.get_name() != "Windows":
		return {"migrated": false, "copied": 0}
	var appdata := OS.get_environment("APPDATA")
	if appdata.is_empty():
		return {"migrated": false, "copied": 0}
	var legacy_root := appdata.path_join("Godot").path_join("app_userdata").path_join(LEGACY_APP_NAME)
	var current_root := ProjectSettings.globalize_path("user://")
	if not DirAccess.dir_exists_absolute(legacy_root):
		return {"migrated": false, "copied": 0}
	if legacy_root.simplify_path().to_lower() == current_root.simplify_path().to_lower():
		return {"migrated": false, "copied": 0}
	var copied := _copy_missing_tree(legacy_root, current_root)
	return {"migrated": copied > 0, "copied": copied, "from": legacy_root, "to": current_root}
func _copy_missing_tree(source_root: String, target_root: String) -> int:
	var source := DirAccess.open(source_root)
	if source == null:
		return 0
	DirAccess.make_dir_recursive_absolute(target_root)
	var copied := 0
	for file_name in source.get_files():
		var source_path := source_root.path_join(file_name)
		var target_path := target_root.path_join(file_name)
		if not FileAccess.file_exists(target_path):
			if DirAccess.copy_absolute(source_path, target_path) == OK:
				copied += 1
	for dir_name in source.get_directories():
		if dir_name in [".", ".."]:
			continue
		copied += _copy_missing_tree(source_root.path_join(dir_name), target_root.path_join(dir_name))
	return copied
