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
		block.append_array(PackedStringArray([
			"  stack: mixed",
			"  auto-route: true",
			"  auto-detect-interface: true",
			"  dns-hijack:",
			"    - any:53",
			"    - tcp://any:53",
			"  strict-route: false"
		]))
	return {"ok": true, "content": "\n".join(block) + "\n" + cleaned.trim_prefix("\n")}

func _remove_top_level_tun(content: String) -> String:
	var lines := content.replace("\r\n", "\n").replace("\r", "\n").split("\n")
	var result: Array[String] = []
	var skipping := false
	for raw in lines:
		var line := str(raw)
		if not skipping and _is_tun_header(line):
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
