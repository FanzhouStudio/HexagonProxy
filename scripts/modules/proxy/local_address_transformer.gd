extends RefCounted

const Catalog = preload("res://scripts/modules/network/local_network_catalog.gd")

# Run after application routing, so a process-wide proxy rule cannot capture localhost.
func transform_profile(content: String, _context := {}) -> Dictionary:
	var protected_rules: PackedStringArray = Catalog.new().mihomo_loopback_rules()
	var lines := content.replace("\r\n", "\n").replace("\r", "\n").split("\n")
	var result: Array[String] = []
	var rules_header := RegEx.new()
	rules_header.compile("^(?:rules|[\"']rules[\"'])\\s*:\\s*(.*)$")
	var in_rules := false
	var found := false
	for line in lines:
		var match_result := rules_header.search(line)
		if match_result:
			var tail := match_result.get_string(1).strip_edges()
			if not tail.is_empty() and not tail.begins_with("#") and tail != "[]":
				var inline_rules: Variant = _parse_inline_rules(tail)
				if not inline_rules is Array:
					return {"ok": false, "message": "本地地址保护需要 rules 使用多行列表或 JSON 字符串数组，请展开内联规则。"}
				result.append("rules:")
				result.append_array(protected_rules)
				for rule in inline_rules:
					if not rule is String:
						return {"ok": false, "message": "rules 列表中的规则必须是字符串。"}
					if "  - " + rule not in protected_rules:
						result.append("  - " + JSON.stringify(rule))
				found = true
				continue
			result.append("rules:")
			result.append_array(protected_rules)
			in_rules = true
			found = true
			continue
		if in_rules and not line.is_empty() and line[0] not in [" ", "\t", "#", "-"]:
			in_rules = false
		var duplicate := false
		if in_rules:
			for rule in protected_rules:
				if line.strip_edges() == rule.strip_edges():
					duplicate = true
		if not duplicate:
			result.append("  " + line if in_rules and line.begins_with("-") else line)
	if not found:
		result.append("rules:")
		result.append_array(protected_rules)
	return {"ok": true, "content": "\n".join(result)}

func _parse_inline_rules(tail: String) -> Variant:
	var decoded: Variant = JSON.parse_string(tail)
	if decoded is Array:
		return decoded
	if not tail.begins_with("[") or not tail.ends_with("]"):
		return null
	var body := tail.substr(1, tail.length() - 2).strip_edges()
	var expression := RegEx.new()
	expression.compile("(?:^|,)\\s*('(?:[^']|'')*'|\"(?:[^\"\\\\]|\\\\.)*\")\\s*(?=,|$)")
	var rules: Array = []
	var consumed := 0
	for token in expression.search_all(body):
		if token.get_start() != consumed:
			return null
		var value: String = token.get_string(1)
		rules.append(value.substr(1, value.length() - 2).replace("''", "'") if value.begins_with("'") else JSON.parse_string(value))
		consumed = token.get_end()
	return rules if consumed == body.length() else null
