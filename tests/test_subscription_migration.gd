extends SceneTree

const CoreControllerScript = preload("res://scripts/core_controller.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var profile_dir := ProjectSettings.globalize_path("user://profiles")
	var provider_dir := ProjectSettings.globalize_path("user://runtime/providers")
	DirAccess.make_dir_recursive_absolute(profile_dir)
	DirAccess.make_dir_recursive_absolute(provider_dir)
	var legacy_yaml := """# 六角代理生成的 V2 分享链接配置
mixed-port: 7890
proxy-providers:
  hexagon-v2:
    type: file
    path: ./providers/hexagon-v2.txt
proxy-groups:
  - name: 六角选择
    type: select
    use: [hexagon-v2]
rules:
  - MATCH,六角选择
"""
	if not _write_file(profile_dir.path_join("active.yaml"), legacy_yaml):
		_fail("无法准备旧 active.yaml", 2)
		return
	if not _write_file(provider_dir.path_join("hexagon-v2.txt"), "hysteria2://password@127.0.0.1:24443?sni=example.com#Migration\n"):
		_fail("无法准备旧 V2 provider", 3)
		return
	var controller: CoreController = CoreControllerScript.new()
	root.add_child(controller)
	await process_frame
	var entries := controller.get_subscriptions()
	if entries.size() != 1 or str(entries[0].get("type", "")) != "v2":
		_fail("旧 V2 配置没有迁移到订阅库", 4)
		return
	var migrated_yaml := FileAccess.get_file_as_string(controller.profile_path())
	if not migrated_yaml.contains("./providers/library/"):
		_fail("迁移后的 V2 配置仍引用旧 provider 路径", 5)
		return
	var provider_file := str(entries[0].get("provider_file", ""))
	if provider_file.is_empty() or not FileAccess.file_exists(controller.subscription_provider_dir().path_join(provider_file)):
		_fail("迁移后的 V2 provider 文件不存在", 6)
		return
	print("PASS: 旧 active.yaml 与 V2 provider 自动迁移")
	quit(0)

func _write_file(path: String, content: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(content)
	file.close()
	return true

func _fail(message: String, code: int) -> void:
	printerr("FAIL: %s" % message)
	quit(code)
