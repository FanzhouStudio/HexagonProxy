extends SceneTree

const CommandPresetServiceScript = preload("res://scripts/modules/system/command_preset_service.gd")

var service

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var storage := ProjectSettings.globalize_path("user://terminal_command_presets.json")
	if FileAccess.file_exists(storage):
		DirAccess.remove_absolute(storage)
	service = CommandPresetServiceScript.new()
	root.add_child(service)
	service.initialize()

	var invalid: Dictionary = service.add_preset("", "powershell", "Get-Date")
	if bool(invalid.get("ok", false)):
		_fail("空名称被错误接受", 2)
		return
	invalid = service.add_preset("测试", "bash", "echo test")
	if bool(invalid.get("ok", false)):
		_fail("不支持的 Shell 被错误接受", 3)
		return
	var added: Dictionary = service.add_preset("查看端口", "PowerShell", "Get-NetTCPConnection")
	if not bool(added.get("ok", false)):
		_fail("无法新增 PowerShell 常用命令", 4)
		return
	var preset: Dictionary = added.get("preset", {})
	var preset_id := str(preset.get("id", ""))
	if preset_id.is_empty() or str(preset.get("shell", "")) != "powershell":
		_fail("常用命令没有生成 ID 或规范化 Shell", 5)
		return

	var updated: Dictionary = service.update_preset(preset_id, "查看监听", "CMD", "netstat -ano")
	if not bool(updated.get("ok", false)):
		_fail("常用命令无法编辑", 6)
		return
	var snapshot: Array = service.list_presets()
	if snapshot.size() != 1 or str(snapshot[0].get("name", "")) != "查看监听" or str(snapshot[0].get("shell", "")) != "cmd":
		_fail("编辑后的快照不正确", 7)
		return
	var second = CommandPresetServiceScript.new()
	root.add_child(second)
	second.initialize()
	var persisted: Array = second.list_presets()
	if persisted.size() != 1 or str(persisted[0].get("command", "")) != "netstat -ano":
		_fail("常用命令没有持久化到新 Service 实例", 8)
		return

	var deleted: Dictionary = second.delete_preset(preset_id)
	if not bool(deleted.get("ok", false)) or not second.list_presets().is_empty():
		_fail("常用命令无法删除", 9)
		return
	var third = CommandPresetServiceScript.new()
	root.add_child(third)
	third.initialize()
	if not third.list_presets().is_empty():
		_fail("删除结果没有持久化", 10)
		return

	print("PASS: 常用命令新增、编辑、删除、Shell 校验与持久化")
	quit(0)

func _fail(message: String, code: int) -> void:
	printerr("FAIL: %s" % message)
	quit(code)
