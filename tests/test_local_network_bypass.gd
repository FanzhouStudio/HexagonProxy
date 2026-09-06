extends SceneTree

const CatalogScript = preload("res://scripts/modules/network/local_network_catalog.gd")
const ProfileFactoryScript = preload("res://scripts/modules/subscription/subscription_profile_factory.gd")

func _init() -> void:
	var catalog = CatalogScript.new()
	var profile_factory = ProfileFactoryScript.new()
	var bypass: String = catalog.windows_proxy_override()
	var rules: String = profile_factory.generated_routing_rules()
	for required in [
		"<local>", "localhost", "*.localhost", "*.local", "*.lan", "*.home.arpa",
		"127.*", "10.*", "169.254.*", "192.168.*",
		"172.16.*", "172.31.*", "100.64.*", "100.127.*", "[::1]"
	]:
		if not required in bypass.split(";"):
			_fail("Windows ProxyOverride 缺少：%s" % required, 2)
			return
	if "172.32.*" in bypass or "100.128.*" in bypass:
		_fail("Windows ProxyOverride 私网范围越界", 3)
		return
	for required_rule in [
		"IP-CIDR,127.0.0.0/8,DIRECT,no-resolve",
		"IP-CIDR,10.0.0.0/8,DIRECT,no-resolve",
		"IP-CIDR,100.64.0.0/10,DIRECT,no-resolve",
		"IP-CIDR,169.254.0.0/16,DIRECT,no-resolve",
		"IP-CIDR,172.16.0.0/12,DIRECT,no-resolve",
		"IP-CIDR,192.168.0.0/16,DIRECT,no-resolve",
		"IP-CIDR6,::1/128,DIRECT,no-resolve",
		"IP-CIDR6,fc00::/7,DIRECT,no-resolve",
		"IP-CIDR6,fe80::/10,DIRECT,no-resolve",
	]:
		if not rules.contains(required_rule):
			_fail("Mihomo DIRECT 缺少：%s" % required_rule, 4)
			return
	var helper := FileAccess.get_file_as_string("res://scripts/windows_proxy_helper.ps1")
	if not helper.contains("Merge-ProxyOverride") or not helper.contains("$existingOverride"):
		_fail("Windows helper 没有合并用户原有 ProxyOverride", 5)
		return
	print("PASS: 回环/私网 Windows bypass 与 Mihomo DIRECT 使用统一数据目录")
	quit(0)

func _fail(message: String, code: int) -> void:
	printerr("FAIL: %s" % message)
	quit(code)
