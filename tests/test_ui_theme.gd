extends SceneTree

const ThemeServiceScript = preload("res://scripts/modules/ui/ui_theme_service.gd")
const UiFactoryScript = preload("res://scripts/ui/ui_factory.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var storage := ProjectSettings.globalize_path("user://ui_theme.cfg")
	if FileAccess.file_exists(storage):
		DirAccess.remove_absolute(storage)
	var service = ThemeServiceScript.new()
	root.add_child(service)
	service.initialize()
	if service.current_theme_id() != "blue_healing" or service.catalog().size() < 2:
		_fail("默认主题或主题目录不正确", 2)
		return
	var ui = UiFactoryScript.new(service.snapshot())
	var label := ui.label("主题文字", 13, Color("12384a"))
	var panel := ui.panel(Color("e9fbfbd4"), Color("a8e8e8e8"), 16)
	var dynamic_panel := ui.panel(ui.surface_color, ui.border_color, 16)
	var dynamic_label := ui.label("动态语义文字", 13, ui.text_color)
	var button := ui.button("纹理按钮", Color("c5f1dfde"), Color("16866f"))
	var small_button := ui.small_choice_button("小按钮")
	var option := OptionButton.new()
	option.custom_minimum_size.y = 40
	ui.apply_crystal_option_theme(option)
	var input := LineEdit.new()
	input.custom_minimum_size.y = 42
	ui.apply_line_edit_theme(input, 13)
	var console := RichTextLabel.new()
	ui.apply_console_theme(console, 12)
	var blue_style: StyleBox = button.get_theme_stylebox("normal")
	if not blue_style is StyleBoxTexture:
		_fail("标准按钮没有使用图片纹理底图", 3)
		return
	var blue_texture := blue_style as StyleBoxTexture
	if blue_texture.texture == null or str(blue_texture.get_meta("source_path", "")).get_file() != "button_blue_normal.svg":
		_fail("海蓝主题没有使用蓝色按钮底图", 4)
		return
	var blue_panel := panel.get_theme_stylebox("panel") as StyleBoxTexture
	var blue_input := input.get_theme_stylebox("normal") as StyleBoxTexture
	var blue_console := console.get_theme_stylebox("normal") as StyleBoxTexture
	if blue_panel == null or str(blue_panel.get_meta("source_path", "")).get_file() != "panel_blue_surface.svg":
		_fail("海蓝主题主卡片没有使用纹理底图", 19)
		return
	if blue_input == null or str(blue_input.get_meta("source_path", "")).get_file() != "panel_blue_input.svg":
		_fail("海蓝主题输入框没有使用纹理底图", 20)
		return
	if blue_console == null or str(blue_console.get_meta("source_path", "")).get_file() != "panel_blue_console.svg":
		_fail("海蓝主题终端框没有使用纹理底图", 21)
		return
	var small_style := small_button.get_theme_stylebox("normal") as StyleBoxTexture
	var option_style := option.get_theme_stylebox("normal") as StyleBoxTexture
	if small_style == null or small_style.texture_margin_top + small_style.texture_margin_bottom >= small_button.custom_minimum_size.y:
		_fail("小按钮九宫格上下边距会互相重叠", 25)
		return
	if option_style == null or option_style.texture_margin_top + option_style.texture_margin_bottom >= option.custom_minimum_size.y:
		_fail("下拉框九宫格上下边距会互相重叠", 26)
		return
	if blue_input.texture_margin_top + blue_input.texture_margin_bottom >= input.custom_minimum_size.y:
		_fail("输入框九宫格上下边距会互相重叠", 27)
		return
	if label.get_theme_font_size("font_size") <= 13:
		_fail("主题字号倍率没有生效", 5)
		return
	var result: Dictionary = service.set_theme("midnight")
	if not bool(result.get("ok", false)):
		_fail("无法切换夜海黑主题", 6)
		return
	ui.apply_theme(result.get("theme", {}))
	if ui.theme_id() != "midnight":
		_fail("UiFactory 没有切换到夜海黑主题", 7)
		return
	var dark_text := label.get_theme_color("font_color")
	var dark_input := input.get_theme_stylebox("normal") as StyleBoxTexture
	var dark_panel := panel.get_theme_stylebox("panel") as StyleBoxTexture
	var dynamic_dark_panel := dynamic_panel.get_theme_stylebox("panel") as StyleBoxTexture
	if dynamic_label.get_theme_color("font_color") != ui.text_color:
		_fail("UiFactory 内部动态语义文字没有随主题更新", 18)
		return
	if dark_panel == null or str(dark_panel.get_meta("source_path", "")).get_file() != "panel_dark_surface.svg":
		_fail("夜海黑主卡片没有切换纹理底图", 22)
		return
	if dynamic_dark_panel == null or str(dynamic_dark_panel.get_meta("source_path", "")).get_file() != "panel_dark_surface.svg":
		_fail("动态语义卡片没有随主题切换纹理", 23)
		return
	if dark_text.get_luminance() <= ui.surface_color.get_luminance():
		_fail("深色主题文字对比度不足", 8)
		return
	if ui.color("input").get_luminance() >= 0.25 or dark_input == null or str(dark_input.get_meta("source_path", "")).get_file() != "panel_dark_input.svg":
		_fail("夜海黑输入框背景或纹理不正确", 9)
		return
	var dark_console := console.get_theme_stylebox("normal") as StyleBoxTexture
	if dark_console == null or str(dark_console.get_meta("source_path", "")).get_file() != "panel_dark_console.svg":
		_fail("夜海黑终端框没有切换纹理底图", 24)
		return
	if console.get_theme_color("default_color") != ui.console_text_color:
		_fail("终端输出文字没有随主题更新", 10)
		return
	var dark_style: StyleBox = button.get_theme_stylebox("normal")
	if not dark_style is StyleBoxTexture:
		_fail("深色主题按钮丢失图片底图", 11)
		return
	var dark_texture := dark_style as StyleBoxTexture
	if dark_texture.texture == null or str(dark_texture.get_meta("source_path", "")).get_file() != "button_dark_normal.svg":
		_fail("夜海黑没有切换到深色按钮底图", 12)
		return
	var second = ThemeServiceScript.new()
	root.add_child(second)
	second.initialize()
	if second.current_theme_id() != "midnight":
		_fail("主题选择没有持久化", 13)
		return
	var back: Dictionary = second.set_theme("blue_healing")
	if not bool(back.get("ok", false)):
		_fail("无法切回海蓝治愈主题", 14)
		return
	ui.apply_theme(back.get("theme", {}))
	var restored_style: StyleBox = button.get_theme_stylebox("normal")
	if not restored_style is StyleBoxTexture:
		_fail("切回海蓝后按钮纹理丢失", 15)
		return
	var restored_texture := restored_style as StyleBoxTexture
	if restored_texture.texture == null or str(restored_texture.get_meta("source_path", "")).get_file() != "button_blue_normal.svg":
		_fail("切回海蓝后按钮底图没有恢复", 16)
		return
	if label.get_theme_color("font_color") != ui.text_color:
		_fail("切回海蓝后文字颜色没有恢复", 17)
		return
	for node in [label, panel, dynamic_panel, dynamic_label, button, small_button, option, input, console]:
		if is_instance_valid(node):
			node.free()
	service.free()
	second.free()
	print("PASS: UI 主题数据、图片按钮、明暗对比、字号与持久化")
	call_deferred("_finish")

func _finish() -> void:
	quit(0)

func _fail(message: String, code: int) -> void:
	printerr("FAIL: %s" % message)
	quit(code)
