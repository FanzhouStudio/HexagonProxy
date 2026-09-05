extends SceneTree

const InstallerScript = preload("res://scripts/modules/mihomo/core_archive_installer.gd")
const UpdateServiceScript = preload("res://scripts/modules/mihomo/core_update_service.gd")

class FakeConfig:
	var base_dir := "user://core-installer-test"
	func runtime_dir() -> String: return base_dir
	func core_path() -> String: return base_dir.path_join("mihomo.exe")

class FakeInstaller:
	var calls := 0
	var archive_path := ""
	var target_path := ""
	func install_archive(archive: String, target: String) -> Dictionary:
		calls += 1
		archive_path = archive
		target_path = target
		return {"ok": true, "message": "测试安装完成"}

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var config = FakeConfig.new()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(config.base_dir))
	var installer = InstallerScript.new()
	config.base_dir = ProjectSettings.globalize_path("user://core-installer-test")
	DirAccess.make_dir_recursive_absolute(config.base_dir)
	var broken_path: String = str(config.base_dir).path_join("broken.zip")
	var broken := FileAccess.open(broken_path, FileAccess.WRITE)
	broken.store_string("not-a-zip")
	broken.close()
	var broken_result: Dictionary = installer.install_archive(broken_path, config.core_path())
	if bool(broken_result.get("ok", true)) or not str(broken_result.get("message", "")).contains("压缩包损坏"):
		_fail("损坏 ZIP 没有被本地安装器安全拒绝", 2)
		return
	DirAccess.remove_absolute(broken_path)

	var service = UpdateServiceScript.new()
	root.add_child(service)
	service.bind_config(config)
	var fake_installer = FakeInstaller.new()
	service.archive_installer = fake_installer
	var archive_path: String = str(config.base_dir).path_join("download.zip")
	var archive := FileAccess.open(archive_path, FileAccess.WRITE)
	archive.store_string("download-placeholder")
	archive.close()
	service._archive_path = archive_path
	var outcomes: Array = []
	service.finished.connect(func(success: bool, message: String) -> void:
		outcomes.append({"success": success, "message": message})
	)
	service._on_archive_received(
		HTTPRequest.RESULT_SUCCESS,
		200,
		PackedStringArray(),
		PackedByteArray()
	)
	if fake_installer.calls != 1 or fake_installer.archive_path != archive_path or fake_installer.target_path != config.core_path():
		_fail("CoreUpdateService 没有把已下载文件交给本地安装器", 3)
		return
	if outcomes.size() != 1 or not bool(outcomes[0].get("success", false)) or str(outcomes[0].get("message", "")) != "测试安装完成":
		_fail("安装器结果没有透传为更新完成事件", 4)
		return
	if FileAccess.file_exists(archive_path):
		_fail("更新完成后没有清理下载临时包", 5)
		return
	service.queue_free()
	print("PASS: CoreArchiveInstaller 损坏包保护与 CoreUpdateService 安装委托")
	quit(0)

func _fail(message: String, code: int) -> void:
	printerr("FAIL: %s" % message)
	quit(code)
