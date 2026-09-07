extends SceneTree

const UiThemeServiceScript = preload("res://scripts/modules/ui/ui_theme_service.gd")
const UiFactoryScript = preload("res://scripts/ui/ui_factory.gd")
const CodexAccountsPanelScript = preload("res://scripts/ui/codex_accounts_panel.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var theme = UiThemeServiceScript.new()
	root.add_child(theme)
	theme.initialize()
	var ui = UiFactoryScript.new(theme.snapshot())
	var panel = CodexAccountsPanelScript.new()
	root.add_child(panel)
	panel.setup(ui)
	var page: Control = panel.build()
	root.add_child(page)
	var profiles: Array = [{
		"id": "default",
		"name": "默认账号",
		"builtin": true,
		"login_present": true
	}]
	panel.render({"installed": true, "running": true, "selected_id": "default"}, profiles)
	if panel.status_label == null or not panel.status_label.text.contains("Codex 正在运行"):
		_fail("Codex 运行状态没有正确渲染", 2)
		return
	if panel.profile_list == null or panel.profile_list.get_child_count() != 1:
		_fail("账号配置列表没有正确构建", 3)
		return
	var single_remove: Array = panel.profile_list.find_children("*", "Button", true, false).filter(func(button: Button) -> bool: return button.text == "移除")
	if single_remove.size() != 1 or not single_remove[0].disabled:
		_fail("默认账号应显示移除按钮，但唯一或当前账号必须禁用", 15)
		return
	if panel.launch_button == null or not panel.launch_button.disabled:
		_fail("Codex 运行时启动按钮应被禁用", 4)
		return
	if panel.create_button == null or panel.create_button.disabled:
		_fail("检测到 Codex 后新建账号按钮应可用", 5)
		return
	panel.set_busy(true)
	if not panel.import_button.disabled or not panel.capture_button.disabled or not panel.refresh_button.disabled:
		_fail("操作期间仍可以重复触发账号操作", 6)
		return
	for button in panel._row_actions:
		if not button.disabled:
			_fail("操作期间账号行按钮未锁定", 7)
			return
	panel.set_busy(false)
	panel.render({"installed": false, "running": false, "selected_id": "default"}, profiles)
	if panel.import_button.disabled or panel.create_button.disabled or not panel.launch_button.disabled:
		_fail("未安装桌面版时仍应允许管理账号，同时禁用启动", 8)
		return
	panel.render({"installed": true, "running": false, "selected_id": "default", "recovery_required": true}, profiles)
	if panel.profile_list.get_child_count() != 1 or not panel.recover_button.visible:
		_fail("重复渲染产生重复账号或缺少恢复入口", 9)
		return
	var two_profiles: Array = [profiles[0], {"id": "second", "name": "第二账号", "login_present": true}]
	panel.render({"installed": true, "running": false, "selected_id": "second"}, two_profiles)
	var remove_buttons: Array = panel.profile_list.find_children("*", "Button", true, false).filter(func(button: Button) -> bool: return button.text == "移除")
	if remove_buttons.size() != 2 or remove_buttons[0].disabled or not remove_buttons[1].disabled:
		_fail("非当前默认账号应允许移除，当前账号应保持禁用", 16)
		return
	if panel._format_remaining(null) != "未知" or panel._format_remaining(-1) != "未知" or panel._format_remaining(75) != "75%":
		_fail("剩余额度或未知值格式错误", 10)
		return
	if panel._reset_text(0) != "恢复时间：未知" or not panel._reset_text(int(Time.get_unix_time_from_system()) + 3600).contains("本地"):
		_fail("恢复时间没有直接显示本地时间", 11)
		return
	if panel.profile_list.find_children("*", "ProgressBar", true, false).size() != 4:
		_fail("两个账号卡片缺少各自的双额度进度条", 12)
		return
	for button in panel._row_actions:
		if button.size_flags_vertical != Control.SIZE_SHRINK_CENTER:
			_fail("账号按钮仍随卡片高度拉伸", 13)
			return
	page.size = Vector2(1200, 820)
	await process_frame
	await process_frame
	for button in panel._row_actions:
		if button.size.y > 60:
			_fail("实际布局中按钮高度超出 60 像素", 14)
			return
	print("PASS: CodexAccountsPanel 状态、忙碌、导入、恢复与额度渲染")
	quit(0)

func _fail(message: String, code: int) -> void:
	printerr("FAIL: %s" % message)
	quit(code)
