class_name LocalNetworkCatalog
extends RefCounted

## 本地/私有网络目录
## 同一份数据同时驱动 Mihomo DIRECT 规则与 Windows ProxyOverride。

const IPV4_NETWORKS := [
	{"cidr": "127.0.0.0/8", "windows": ["127.*"]},
	{"cidr": "10.0.0.0/8", "windows": ["10.*"]},
	{"cidr": "100.64.0.0/10", "windows_range": [64, 127], "prefix": "100"},
	{"cidr": "169.254.0.0/16", "windows": ["169.254.*"]},
	{"cidr": "172.16.0.0/12", "windows_range": [16, 31], "prefix": "172"},
	{"cidr": "192.168.0.0/16", "windows": ["192.168.*"]},
]

const IPV6_NETWORKS := [
	"::1/128",
	"fc00::/7",
	"fe80::/10",
]

const LOCAL_HOST_PATTERNS := [
	"<local>", "localhost", "*.localhost", "*.local", "*.lan", "*.home.arpa", "[::1]"
]

func mihomo_direct_rules() -> PackedStringArray:
	var rules := PackedStringArray([
		"  - DOMAIN,localhost,DIRECT",
		"  - DOMAIN-SUFFIX,localhost,DIRECT",
	])
	for network: Dictionary in IPV4_NETWORKS:
		rules.append("  - IP-CIDR,%s,DIRECT,no-resolve" % str(network.get("cidr", "")))
	for cidr: String in IPV6_NETWORKS:
		rules.append("  - IP-CIDR6,%s,DIRECT,no-resolve" % cidr)
	return rules

func windows_proxy_override() -> String:
	var patterns := PackedStringArray()
	for pattern: String in LOCAL_HOST_PATTERNS:
		_append_unique(patterns, pattern)
	for network: Dictionary in IPV4_NETWORKS:
		for pattern: String in network.get("windows", []):
			_append_unique(patterns, pattern)
		if network.has("windows_range"):
			var bounds: Array = network.get("windows_range", [])
			for second_octet in range(int(bounds[0]), int(bounds[1]) + 1):
				_append_unique(patterns, "%s.%d.*" % [str(network.get("prefix", "")), second_octet])
	return ";".join(patterns)

func _append_unique(target: PackedStringArray, value: String) -> void:
	if not value.is_empty() and value not in target:
		target.append(value)
