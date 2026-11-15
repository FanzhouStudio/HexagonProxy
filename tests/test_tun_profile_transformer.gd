extends SceneTree

const TransformerScript = preload("res://scripts/modules/proxy/tun_profile_transformer.gd")

class FakeConfig:
	var enabled := false
	var outbound := ""
	func tun_enabled() -> bool: return enabled
	func tun_outbound_interface() -> String: return outbound

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
	if enabled.count("tun:") != 1 or not enabled.contains("stack: gvisor") or not enabled.contains("auto-route: true") or not enabled.contains("strict-route: true") or not enabled.contains("dns:\n  enable: true"):
		_fail("启用状态没有生成轻量 TUN 配置", 3)
		return
	var custom: String = transformer.transform_profile("dns:\n  enable: false\n  nameserver:\n    - 1.1.1.1\nmode: rule\n").content
	if not custom.contains("dns:\n  enable: true") or not custom.contains("    - 1.1.1.1") or custom.contains("  enable: false"):
		_fail("TUN 应启用 DNS 并保留已有解析服务器", 5)
		return
	var repeated: String = transformer.transform_profile(enabled).content
	if not enabled.contains("    - 127.0.0.0/8") or not enabled.contains("    - ::1/128") or enabled.contains("    - 198.18.0.0/16"):
		_fail("回环地址应绕过 TUN，fake-ip 网段必须留在 TUN 内", 8)
		return
	if repeated != enabled:
		_fail("重复转换不稳定", 4)
		return
	config.outbound = "WLAN 2"
	var bound: String = transformer.transform_profile("interface-name: Meta\nmode: rule\n").content
	if bound.count("interface-name:") != 1 or not bound.contains('interface-name: "WLAN 2"') or not bound.contains("auto-detect-interface: false"):
		_fail("TUN 出口没有绑定真实默认路由网卡", 6)
		return
	if transformer.transform_profile(bound).content != bound:
		_fail("出口网卡重复转换不稳定", 7)
		return
	print("PASS: TUN 配置互斥覆盖、出口绑定与幂等转换")
	quit(0)

func _fail(message: String, code: int) -> void:
	printerr("FAIL: %s" % message)
	quit(code)
