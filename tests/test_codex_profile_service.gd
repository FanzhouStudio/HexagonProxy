extends SceneTree

const CodexProfileServiceScript = preload("res://scripts/modules/codex/codex_profile_service.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var service = CodexProfileServiceScript.new()
	root.add_child(service)
	service.initialize()
	var initial: Array = service.profiles()
	if initial.size() != 1 or str(initial[0].get("id", "")) != "default":
		_fail("默认账号配置没有正确初始化", 2)
		return

	var created: Dictionary = service.create_profile("测试账号")
	if not bool(created.get("ok", false)):
		_fail("测试账号配置创建失败", 3)
		return
	var profile_id := str(created.get("profile_id", ""))
	var profiles: Array = service.profiles()
	if profiles.size() != 2:
		_fail("创建后账号数量不正确", 4)
		return
	if service.selected_id() != "default":
		_fail("新建账号不应自动改变当前配置", 5)
		return

	var profile_path := service.profile_path(profile_id)
	if profile_path.is_empty() or not DirAccess.dir_exists_absolute(profile_path):
		_fail("独立 profile 目录没有创建", 6)
		return
	var removed: Dictionary = service.forget_profile(profile_id)
	if not bool(removed.get("ok", false)):
		_fail("测试账号入口移除失败", 7)
		return
	if service.profiles().size() != 1:
		_fail("移除后账号列表没有恢复", 8)
		return
	if not DirAccess.dir_exists_absolute(profile_path):
		_fail("移除入口不应删除本地 profile 数据", 9)
		return
	service.dispose()
	service.queue_free()
	print("PASS: CodexProfileService profile 创建、保存与移除")
	quit(0)

func _fail(message: String, code: int) -> void:
	printerr("FAIL: %s" % message)
	quit(code)
