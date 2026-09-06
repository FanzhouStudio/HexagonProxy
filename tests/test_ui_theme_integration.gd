extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var storage := ProjectSettings.globalize_path("user://ui_theme.cfg")
	if FileAccess.file_exists(storage):
		DirAccess.remove_absolute(storage)
	var scene: Control = load("res://main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	await create_timer(0.08).timeout
	var shell = scene.app_shell
	var settings = scene.settings_panel
	if shell.window_action_buttons.size() != 3 or not shell.window_action_buttons.has("minimize") or not shell.window_action_buttons.has("close") or not shell.window_action_buttons.has("exit"):
		_fail("右上角窗口操作按钮没有按数据目录构建", 13)
		return
	var exit_button: Button = shell.window_action_buttons["exit"]
	if exit_button.get_theme_color("font_color") != scene.ui.danger_color:
		_fail("退出按钮没有使用主题危险色", 14)
		return
	if scene.ui.theme_id() != "blue_healing" or settings.theme_selector.item_count < 2:
		_fail("主界面没有加载默认主题目录", 2)
		return
	shell.show_page("settings")
	await process_frame
	var nav: Button = shell.nav_buttons["dashboard"]
	var blue_style: StyleBoxTexture = nav.get_theme_stylebox("normal") as StyleBoxTexture
	if blue_style == null or str(blue_style.get_meta("source_path", "")).get_file() != "button_blue_normal.svg":
		_fail("主界面导航没有使用海蓝图片按钮", 3)
		return
	var blue_option: StyleBoxTexture = settings.theme_selector.get_theme_stylebox("normal") as StyleBoxTexture
	if blue_option == null or str(blue_option.get_meta("source_path", "")).get_file() != "button_blue_normal.svg":
		_fail("主题下拉选择器没有使用海蓝图片底图", 11)
		return
	settings.ui_theme_requested.emit("midnight")
	await process_frame
	await process_frame
	if scene.ui.theme_id() != "midnight":
		_fail("设置页主题意图没有实时切换主界面", 4)
		return
	if exit_button.get_theme_color("font_color") != scene.ui.danger_color:
		_fail("夜海黑切换后退出按钮危险色没有同步更新", 15)
		return
	var dark_style: StyleBoxTexture = nav.get_theme_stylebox("normal") as StyleBoxTexture
	if dark_style == null or str(dark_style.get_meta("source_path", "")).get_file() != "button_dark_normal.svg":
		_fail("切夜海黑后导航按钮没有更换深色底图", 5)
		return
	var dark_option: StyleBoxTexture = settings.theme_selector.get_theme_stylebox("normal") as StyleBoxTexture
	if dark_option == null or str(dark_option.get_meta("source_path", "")).get_file() != "button_dark_normal.svg":
		_fail("夜海黑主题下拉选择器没有更换深色图片底图", 12)
		return
	if shell.aquarium_background.modulate != scene.ui.background_modulate_color:
		_fail("夜海黑没有同步压暗水族箱背景", 6)
		return
	var settings_page: Control = shell.pages["settings"]
	var appearance_card := settings_page.get_child(0) as PanelContainer
	var appearance_style := appearance_card.get_theme_stylebox("panel") as StyleBoxTexture
	if appearance_style == null or str(appearance_style.get_meta("source_path", "")).get_file() != "panel_dark_surface.svg":
		_fail("设置页卡片没有实时切换深色纹理 Surface", 7)
		return
	if settings.theme_description_label.get_theme_color("font_color") != scene.ui.muted_color:
		_fail("设置页说明文字没有切换为深色主题可读颜色", 8)
		return
	settings.ui_theme_requested.emit("blue_healing")
	await process_frame
	await process_frame
	var restored_style: StyleBoxTexture = nav.get_theme_stylebox("normal") as StyleBoxTexture
	if scene.ui.theme_id() != "blue_healing" or restored_style == null:
		_fail("无法从夜海黑切回海蓝治愈", 9)
		return
	if str(restored_style.get_meta("source_path", "")).get_file() != "button_blue_normal.svg":
		_fail("切回海蓝后导航按钮底图没有恢复", 10)
		return
	scene.queue_free()
	await process_frame
	print("PASS: 主界面蓝/黑主题实时切换、图片按钮、背景与文字联动")
	quit(0)

func _fail(message: String, code: int) -> void:
	printerr("FAIL: %s" % message)
	quit(code)
