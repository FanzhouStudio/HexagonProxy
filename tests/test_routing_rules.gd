extends SceneTree

const CoreControllerScript = preload("res://scripts/core_controller.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var profiles := ProjectSettings.globalize_path("user://profiles")
	var library := profiles.path_join("library")
	DirAccess.make_dir_recursive_absolute(library)
	var old_http := """# 六角代理生成的订阅配置
mixed-port: 7890
mode: rule
proxy-providers:
  hexagon-subscription:
    type: http
    url: 'https://example.com/sub'
    path: ./providers/hexagon-subscription.yaml
proxy-groups:
  - name: 六角选择
    type: select
    use: [hexagon-subscription]
rules:
  - MATCH,六角选择
"""
	var local_yaml := """mixed-port: 7890
mode: rule
proxies: []
rules:
  - MATCH,DIRECT
"""
	if not _write_file(library.path_join("http.yaml"), old_http):
		_fail("无法准备旧 HTTP 配置", 2)
		return
	if not _write_file(library.path_join("local.yaml"), local_yaml):
		_fail("无法准备本地 YAML", 3)
		return
	if not _write_file(profiles.path_join("active.yaml"), old_http):
		_fail("无法准备活动配置", 4)
		return
	var index := {
		"version": 1,
		"active_id": "http-entry",
		"subscriptions": [
			{"id": "http-entry", "name": "旧 HTTP", "type": "http", "config_file": "http.yaml"},
			{"id": "local-entry", "name": "本地 YAML", "type": "local", "config_file": "local.yaml"}
		]
	}
	if not _write_file(library.path_join("index.json"), JSON.stringify(index, "  ")):
		_fail("无法准备订阅索引", 5)
		return
	var controller: CoreController = CoreControllerScript.new()
	root.add_child(controller)
	await process_frame
	controller._shutting_down = true
	var upgraded := FileAccess.get_file_as_string(library.path_join("http.yaml"))
	var active := FileAccess.get_file_as_string(controller.profile_path())
	var local_after := FileAccess.get_file_as_string(library.path_join("local.yaml"))
	for required in [
		"IP-CIDR,127.0.0.0/8,DIRECT,no-resolve",
		"IP-CIDR,192.168.0.0/16,DIRECT,no-resolve",
		"RULE-SET,hexagon-cn-domain,DIRECT",
		"RULE-SET,hexagon-cn-ip,DIRECT,no-resolve",
		"MATCH,六角选择"
	]:
		if not upgraded.contains(required) or not active.contains(required):
			_fail("旧配置没有升级规则：%s" % required, 6)
			return
	if upgraded.count("rule-providers:") != 1 or upgraded.count("rules:") != 1:
		_fail("升级后出现重复规则区块", 7)
		return
	if local_after != local_yaml:
		_fail("本地 YAML 被自动改写", 8)
		return
	if not FileAccess.file_exists(controller.runtime_dir().path_join("rules/geosite-cn.mrs")):
		_fail("国内域名规则集没有释放", 9)
		return
	if not FileAccess.file_exists(controller.runtime_dir().path_join("rules/geoip-cn.mrs")):
		_fail("国内 IP 规则集没有释放", 10)
		return
	print("PASS: 国内直连规则升级、本地 YAML 保持原样与离线规则集")
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
