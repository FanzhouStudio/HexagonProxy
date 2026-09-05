extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	if str(ProjectSettings.get_setting("application/config/name", "")) != "HexagonProxy":
		_fail("Godot 应用名不是 HexagonProxy", 2)
		return
	var export_text := FileAccess.get_file_as_string("res://export_presets.cfg")
	if not export_text.contains('export_path="dist/HexagonProxy.exe"') or not export_text.contains('application/product_name="HexagonProxy"'):
		_fail("Windows 导出名称没有统一为 HexagonProxy", 3)
		return
	var texture := load("res://assets/app_icon.png") as Texture2D
	if texture == null:
		_fail("无法加载应用图标", 4)
		return
	var image := texture.get_image()
	if image == null or image.get_width() != 256 or image.get_height() != 256:
		_fail("应用图标不是 256x256", 5)
		return
	for point in [Vector2i(0,0), Vector2i(255,0), Vector2i(0,255), Vector2i(255,255)]:
		if image.get_pixelv(point).a > 0.001:
			_fail("应用图标四角不是透明的", 6)
			return
	var used := image.get_used_rect()
	if used.size.x < 210 or used.size.y < 100:
		_fail("图标主体仍然过小：%s" % used, 7)
		return
	var ico_path := ProjectSettings.globalize_path("res://assets/app_icon.ico")
	if not FileAccess.file_exists(ico_path):
		_fail("Windows ICO 图标不存在", 8)
		return
	var ico := FileAccess.open(ico_path, FileAccess.READ)
	if ico == null or ico.get_length() < 1024:
		_fail("Windows ICO 图标无效", 9)
		return
	ico.close()
	print("PASS: HexagonProxy 品牌名与透明放大图标")
	quit(0)

func _fail(message: String, code: int) -> void:
	printerr("FAIL: %s" % message)
	quit(code)
