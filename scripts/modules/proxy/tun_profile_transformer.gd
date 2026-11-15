class_name TunProfileTransformer
extends RefCounted

## Mihomo 顶层 TUN 配置注入器。
## 活动配置始终由这里决定 TUN 开关，避免订阅自带的 tun 配置绕过 UI 状态。

var proxy_config

func setup(config) -> void:
	proxy_config = config

func transform_profile(content: String, _context := {}) -> Dictionary:
	if proxy_config == null:
		return {"ok": false, "message": "TUN 配置尚未绑定。"}
	var cleaned := _remove_top_level_tun(content)
	var block := PackedStringArray([
		"tun:",
		"  enable: %s" % ("true" if proxy_config.tun_enabled() else "false")
	])
	if proxy_config.tun_enabled():
		cleaned = _ensure_dns(cleaned)
		var outbound: String = proxy_config.tun_outbound_interface()
		if not outbound.is_empty():
			cleaned = _remove_top_level_key(cleaned, "interface-name")
			cleaned = "interface-name: " + JSON.stringify(outbound) + "\n" + cleaned
		block.append_array(PackedStringArray([
			"  stack: gvisor",
			"  auto-route: true",
			"  auto-detect-interface: %s" % ("true" if outbound.is_empty() else "false"),
			"  dns-hijack:",
			"    - any:53",
			"    - tcp://any:53",
			"  strict-route: true",
			"  route-exclude-address:",
			"    - 127.0.0.0/8",
			"    - ::1/128",
			"  mtu: 1500"
		]))
	return {"ok": true, "content": "\n".join(block) + "\n" + cleaned.trim_prefix("\n")}

func _ensure_dns(content: String) -> String:
	var lines := content.split("\n")
	var start := -1
	var end := lines.size()
	var pattern := RegEx.new()
	pattern.compile("^(?:dns|[\"']dns[\"'])\\s*:\\s*(?:#.*)?$")
	for i in lines.size():
		if start < 0 and pattern.search(lines[i]) != null:
			start = i
		elif start >= 0 and _is_next_top_level_key(lines[i]):
			end = i
			break
	if start < 0:
		return "dns:\n  enable: true\n  ipv6: false\n  enhanced-mode: fake-ip\n  fake-ip-range: 198.18.0.1/16\n  default-nameserver:\n    - 223.5.5.5\n    - 119.29.29.29\n  nameserver:\n    - https://dns.alidns.com/dns-query\n    - https://doh.pub/dns-query\n" + content
	var result: Array[String] = []
	var has_nameserver := false
	var enable_pattern := RegEx.new()
	enable_pattern.compile("^  (?:enable|[\"']enable[\"'])\\s*:")
	for i in lines.size():
		if i == start:
			result.append(lines[i])
			result.append("  enable: true")
			continue
		if i > start and i < end:
			if enable_pattern.search(lines[i]) != null:
				continue
			if lines[i].begins_with("  nameserver:"):
				has_nameserver = true
		if i == end and not has_nameserver:
			result.append("  nameserver: [223.5.5.5, 119.29.29.29]")
		result.append(lines[i])
	if end == lines.size() and not has_nameserver:
		result.append("  nameserver: [223.5.5.5, 119.29.29.29]")
	return "\n".join(result)

func _remove_top_level_tun(content: String) -> String:
	return _remove_top_level_key(content, "tun")

func _remove_top_level_key(content: String, key: String) -> String:
	var lines := content.replace("\r\n", "\n").replace("\r", "\n").split("\n")
	var result: Array[String] = []
	var skipping := false
	for raw in lines:
		var line := str(raw)
		var header := RegEx.new()
		header.compile("^(?:%s|[\"']%s[\"'])\\s*:" % [key, key])
		if not skipping and header.search(line) != null:
			skipping = true
			continue
		if skipping:
			if _is_next_top_level_key(line):
				skipping = false
				result.append(line)
			continue
		result.append(line)
	return "\n".join(result)

func _is_tun_header(line: String) -> bool:
	if line.is_empty() or line[0] in [" ", "\t", "#"]:
		return false
	var expression := RegEx.new()
	return expression.compile("^(?:tun|[\\\"']tun[\\\"'])\\s*:") == OK and expression.search(line) != null

func _is_next_top_level_key(line: String) -> bool:
	if line.strip_edges().is_empty() or line.begins_with("#"):
		return false
	if line[0] in [" ", "\t", "-"]:
		return false
	return line.contains(":")
