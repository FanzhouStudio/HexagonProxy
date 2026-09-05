extends SceneTree

const RoutingServiceScript = preload("res://scripts/modules/routing/application_routing_service.gd")
const ProxyConfigScript = preload("res://scripts/modules/proxy/proxy_config.gd")
const ProxyValidatorScript = preload("res://scripts/modules/proxy/proxy_validator.gd")

var service

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	service = RoutingServiceScript.new()
	root.add_child(service)
	service.initialize()
	var app_dir := ProjectSettings.globalize_path("user://routing-test")
	DirAccess.make_dir_recursive_absolute(app_dir)
	var exe_path := app_dir.path_join("ExampleGame.exe")
	var exe := FileAccess.open(exe_path, FileAccess.WRITE)
	if exe == null:
		_fail("无法创建测试 exe", 2)
		return
	exe.store_string("test")
	exe.close()
	var added: Dictionary = service.add_application(exe_path)
	if not bool(added.get("ok", false)):
		_fail("无法添加应用规则", 3)
		return
	var rule_id := str(added.get("rule", {}).get("id", ""))
	if rule_id.is_empty() or service.snapshot().get("rules", []).size() != 1:
		_fail("应用规则快照不正确", 4)
		return
	var profile := """mixed-port: 7890
mode: rule
proxy-groups:
  - name: 六角选择
    type: select
    proxies: [DIRECT]
rules:
  - DOMAIN,example.com,DIRECT
  - MATCH,六角选择
"""
	var transformed: Dictionary = service.transform_profile(profile)
	var yaml := str(transformed.get("content", ""))
	if not bool(transformed.get("ok", false)) or not yaml.contains("PROCESS-NAME,ExampleGame.exe,六角选择"):
		_fail("代理应用规则没有编译到 YAML", 5)
		return
	if yaml.find("PROCESS-NAME") > yaml.find("DOMAIN,example.com"):
		_fail("应用规则优先级没有置于普通规则之前", 6)
		return
	var second := str(service.transform_profile(yaml).get("content", ""))
	if second.count("HEXAGON-APP-ROUTING-BEGIN") != 1 or second.count("PROCESS-NAME,ExampleGame.exe") != 1:
		_fail("重复转换产生了重复应用规则", 7)
		return
	var config = ProxyConfigScript.new()
	config.ensure_directories()
	var profile_file := FileAccess.open(config.active_profile_path(), FileAccess.WRITE)
	if profile_file == null:
		_fail("无法写入 Mihomo 分流校验配置", 14)
		return
	profile_file.store_string(yaml)
	profile_file.close()
	var validator = ProxyValidatorScript.new()
	root.add_child(validator)
	validator.setup(config.core_path(), config.runtime_dir(), config.active_profile_path())
	var validation: Dictionary = validator.validate()
	if not bool(validation.get("ok", false)):
		_fail("Mihomo 不接受生成的应用分流配置：%s" % str(validation.get("message", "")), 15)
		return
	validator.queue_free()
	if not service.set_rule_target(rule_id, "direct"):
		_fail("无法修改应用规则策略", 8)
		return
	var direct_yaml := str(service.transform_profile(profile).get("content", ""))
	if not direct_yaml.contains("PROCESS-NAME,ExampleGame.exe,DIRECT"):
		_fail("直连策略没有编译到 YAML", 9)
		return
	if not service.set_rule_target(rule_id, "proxy"):
		_fail("无法恢复代理策略", 10)
		return
	var fallback_profile := "mixed-port: 7890\nmode: rule\nrules:\n  - MATCH,DIRECT\n"
	var fallback_yaml := str(service.transform_profile(fallback_profile).get("content", ""))
	if not fallback_yaml.contains("PROCESS-NAME,ExampleGame.exe,GLOBAL"):
		_fail("无六角选择策略组时没有回退到 GLOBAL", 11)
		return
	service.set_enabled(false)
	var disabled_yaml := str(service.transform_profile(yaml).get("content", ""))
	if disabled_yaml.contains("HEXAGON-APP-ROUTING") or disabled_yaml.contains("PROCESS-NAME,ExampleGame.exe"):
		_fail("关闭应用分流后仍残留生成规则", 12)
		return
	var second_service = RoutingServiceScript.new()
	root.add_child(second_service)
	second_service.initialize()
	var persisted: Dictionary = second_service.snapshot()
	if bool(persisted.get("enabled", true)) or persisted.get("rules", []).size() != 1:
		_fail("应用分流状态没有持久化", 13)
		return
	second_service.queue_free()
	service.queue_free()
	print("PASS: 应用分流规则持久化、优先级、策略编译与重复注入保护")
	quit(0)

func _fail(message: String, code: int) -> void:
	printerr("FAIL: %s" % message)
	quit(code)
