extends SceneTree

const MigratorScript = preload("res://scripts/core/user_data_brand_migrator.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	if OS.get_name() != "Windows":
		print("PASS: 非 Windows 跳过品牌目录迁移测试")
		quit(0)
		return
	var appdata := OS.get_environment("APPDATA")
	var legacy_root := appdata.path_join("Godot").path_join("app_userdata").path_join("六角代理")
	var legacy_probe := legacy_root.path_join("migration_probe")
	var current_probe := ProjectSettings.globalize_path("user://migration_probe")
	DirAccess.make_dir_recursive_absolute(legacy_probe)
	DirAccess.make_dir_recursive_absolute(current_probe)
	if not _write(legacy_probe.path_join("legacy.txt"), "legacy-data"):
		_fail("无法准备旧用户数据", 2)
		return
	_write(legacy_probe.path_join("keep.txt"), "legacy-value")
	_write(current_probe.path_join("keep.txt"), "current-value")
	var result: Dictionary = MigratorScript.new().migrate_if_needed()
	if not bool(result.get("migrated", false)):
		_fail("旧品牌用户数据没有触发迁移", 3)
		return
	var migrated := current_probe.path_join("legacy.txt")
	if not FileAccess.file_exists(migrated) or FileAccess.get_file_as_string(migrated) != "legacy-data":
		_fail("旧用户数据没有复制到 HexagonProxy user://", 4)
		return
	if FileAccess.get_file_as_string(current_probe.path_join("keep.txt")) != "current-value":
		_fail("品牌迁移覆盖了新目录已有文件", 5)
		return
	print("PASS: 旧六角代理用户数据迁移到 HexagonProxy 且不覆盖新数据")
	quit(0)

func _write(path: String, content: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(content)
	file.close()
	return true

func _fail(message: String, code: int) -> void:
	printerr("FAIL: %s" % message)
	quit(code)
