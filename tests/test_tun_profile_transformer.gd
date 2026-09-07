extends SceneTree

const TransformerScript = preload("res://scripts/modules/proxy/tun_profile_transformer.gd")

class FakeConfig:
	var enabled := false
	func tun_enabled() -> bool: return enabled

func _init() -> void:
	var config := FakeConfig.new()
	var transformer = TransformerScript.new()
	transformer.setup(config)
	var source := "mixed-port: 7890\ntun:\n  enable: true\n  stack: gvisor\nmode: rule\n"
	var disabled: String = transformer.transform_profile(source).content
	if disabled.count("tun:") != 1 or not disabled.contains("  enable: false") or disabled.contains("stack: gvisor"):
		_fail("关闭状态没有覆盖订阅自带 TUN", 2)
		return
	config.enabled = true
	var enabled: String = transformer.transform_profile(disabled).content
	if enabled.count("tun:") != 1 or not enabled.contains("stack: mixed") or not enabled.contains("auto-route: true") or not enabled.contains("strict-route: false"):
		_fail("启用状态没有生成轻量 TUN 配置", 3)
		return
	var repeated: String = transformer.transform_profile(enabled).content
	if repeated != enabled:
		_fail("重复转换不稳定", 4)
		return
	print("PASS: TUN 配置互斥覆盖与幂等转换")
	quit(0)

func _fail(message: String, code: int) -> void:
	printerr("FAIL: %s" % message)
	quit(code)
