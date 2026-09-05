class_name SubscriptionProfileMaintenance
extends RefCounted

## 已保存订阅配置的兼容修复与规则升级
## 只处理已有文件，不负责订阅列表业务状态

var proxy_config
var store
var parser
var profile_factory

func setup(config_value, store_value, parser_value, factory_value) -> void:
	proxy_config = config_value
	store = store_value
	parser = parser_value
	profile_factory = factory_value

func repair_entry(entry: Dictionary, active_id: String) -> Dictionary:
	var repaired: Dictionary = entry.duplicate(true)
	var messages: Array[String] = []
	var index_changed := _repair_v2(repaired, active_id, messages)
	_upgrade_routing_rules(repaired, active_id, messages)
	return {
		"entry": repaired,
		"index_changed": index_changed,
		"messages": messages
	}
func _repair_v2(entry: Dictionary, active_id: String, messages: Array[String]) -> bool:
	if str(entry.get("type", "")) != "v2":
		return false
	var config_path: String = store.library_dir().path_join(str(entry.get("config_file", "")))
	if not FileAccess.file_exists(config_path):
		return false
	var provider_file := str(entry.get("provider_file", ""))
	var hy2_provider_file := str(entry.get("hy2_provider_file", ""))
	if provider_file.is_empty() and hy2_provider_file.is_empty():
		return false
	var index_changed := false
	var legacy_provider_path: String = store.library_dir().path_join(provider_file)
	var provider_path: String = store.provider_dir().path_join(provider_file)
	if not provider_file.is_empty() and FileAccess.file_exists(legacy_provider_path) and not FileAccess.file_exists(provider_path):
		store.write_text_atomic(provider_path, FileAccess.get_file_as_string(legacy_provider_path))
		DirAccess.remove_absolute(legacy_provider_path)
	if hy2_provider_file.is_empty() and FileAccess.file_exists(provider_path):
		var lines: Array[String] = []
		for raw_line in FileAccess.get_file_as_string(provider_path).replace("\r\n", "\n").replace("\r", "\n").split("\n"):
			var line := str(raw_line).strip_edges()
			if not line.is_empty():
				lines.append(line)
		var normalized: Dictionary = parser.normalize_provider_lines(lines, str(entry.get("id", "")))
		var regular_lines: Array[String] = normalized.get("regular_lines", [])
		var hy2_yaml := str(normalized.get("hy2_yaml", ""))
		if not hy2_yaml.is_empty():
			hy2_provider_file = "%s-hy2.yaml" % str(entry.get("id", ""))
			if store.write_text_atomic(store.provider_dir().path_join(hy2_provider_file), hy2_yaml):
				entry["hy2_provider_file"] = hy2_provider_file
				if regular_lines.is_empty():
					DirAccess.remove_absolute(provider_path)
					provider_file = ""
					entry["provider_file"] = ""
				else:
					store.write_text_atomic(provider_path, "\n".join(regular_lines) + "\n")
				index_changed = true
				messages.append("已自动转换旧版 Hysteria2 分享链接。")
	var repaired_yaml: String = profile_factory.v2_profile_yaml(parser, provider_file, hy2_provider_file)
	if not store.write_text_atomic(config_path, repaired_yaml):
		return index_changed
	if str(entry.get("id", "")) == active_id:
		store.write_text_atomic(proxy_config.active_profile_path(), repaired_yaml)
	messages.append("已自动修复旧版 V2 配置缩进。")
	return index_changed

func _upgrade_routing_rules(entry: Dictionary, active_id: String, messages: Array[String]) -> void:
	if str(entry.get("type", "")) not in ["http", "v2"]:
		return
	var config_path: String = store.library_dir().path_join(str(entry.get("config_file", "")))
	if not FileAccess.file_exists(config_path):
		return
	var yaml := FileAccess.get_file_as_string(config_path)
	if yaml.contains("IP-CIDR,127.0.0.0/8,DIRECT") and yaml.contains("RULE-SET,hexagon-cn-ip,DIRECT"):
		return
	var proxy_marker := "\nproxy-providers:\n"
	var proxy_position := yaml.find(proxy_marker)
	var rules_marker := "\nrules:\n"
	var rules_position := yaml.find(rules_marker)
	if proxy_position < 0 or rules_position < 0:
		return
	var upgraded: String = (
		yaml.left(proxy_position + 1)
		+ profile_factory.generated_rule_providers()
		+ yaml.substr(proxy_position + 1, rules_position - proxy_position)
		+ profile_factory.generated_routing_rules()
	)
	if not store.write_text_atomic(config_path, upgraded):
		return
	if str(entry.get("id", "")) == active_id:
		store.write_text_atomic(proxy_config.active_profile_path(), upgraded)
	messages.append("已升级旧配置的本地与国内直连规则。")
