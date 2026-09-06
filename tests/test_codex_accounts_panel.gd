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
	if panel.launch_button == null or not panel.launch_button.disabled:
		_fail("Codex 运行时启动按钮应被禁用", 4)
		return
	if panel.create_button == null or panel.create_button.disabled:
		_fail("检测到 Codex 后新建账号按钮应可用", 5)
		return
	print("PASS: CodexAccountsPanel 构建与状态渲染")
	quit(0)

func _fail(message: String, code: int) -> void:
	printerr("FAIL: %s" % message)
	quit(code)
