class_name SubscriptionImporter
extends RefCounted

## 订阅导入准备器
## 负责输入校验、YAML 生成和 V2 provider 文件落盘

var store
var parser
var profile_factory

func setup(store_value, parser_value, factory_value) -> void:
	store = store_value
	parser = parser_value
	profile_factory = factory_value

func prepare_http(url: String) -> Dictionary:
	var cleaned := url.strip_edges()
	if not (cleaned.begins_with("https://") or cleaned.begins_with("http://")):
		return {"ok": false, "error": "订阅地址必须以 http:// 或 https:// 开头。"}
	var host := cleaned.trim_prefix("https://").trim_prefix("http://").get_slice("/", 0).get_slice("?", 0)
	var display_name := "HTTP 订阅" if host.is_empty() else "HTTP 订阅 · %s" % host
	return {
		"ok": true,
		"name": display_name,
		"kind": "http",
		"yaml": profile_factory.http_profile_yaml(cleaned),
		"provider_file": "",
		"extra": {},
		"generated_files": []
	}
func prepare_v2(content: String, entry_id: String) -> Dictionary:
	var parsed: Dictionary = parser.parse_input(content)
	if not bool(parsed.get("ok", false)):
		return {"ok": false, "error": str(parsed.get("error", "无法识别 V2 分享链接。"))}
	var uri_lines: Array[String] = parsed.get("uri_lines", [])
	var uri_count := int(parsed.get("count", uri_lines.size()))
	var provider_name := "%s-v2.txt" % entry_id
	var normalized: Dictionary = parser.normalize_provider_lines(uri_lines, entry_id)
	var regular_lines: Array[String] = normalized.get("regular_lines", [])
	var hy2_yaml := str(normalized.get("hy2_yaml", ""))
	var regular_provider_name := provider_name if not regular_lines.is_empty() else ""
	var hy2_provider_name := "%s-hy2.yaml" % entry_id if not hy2_yaml.is_empty() else ""
	var generated_files: Array[String] = []
	if not regular_provider_name.is_empty():
		var regular_path: String = store.provider_dir().path_join(regular_provider_name)
		if not store.write_text_atomic(regular_path, "\n".join(regular_lines) + "\n"):
			return {"ok": false, "error": "无法保存 V2 节点文件。"}
		generated_files.append(regular_provider_name)
	if not hy2_provider_name.is_empty():
		var hy2_path: String = store.provider_dir().path_join(hy2_provider_name)
		if not store.write_text_atomic(hy2_path, hy2_yaml):
			cleanup_generated(generated_files)
			return {"ok": false, "error": "无法保存 Hysteria2 节点文件。"}
		generated_files.append(hy2_provider_name)
	var display_name := "V2 分享链接 · %s" % Time.get_datetime_string_from_system(false, true).replace("T", " ")
	if uri_count > 0:
		display_name += " · %d 个节点" % uri_count
	return {
		"ok": true,
		"name": display_name,
		"kind": "v2",
		"yaml": profile_factory.v2_profile_yaml(parser, regular_provider_name, hy2_provider_name),
		"provider_file": regular_provider_name,
		"extra": {"hy2_provider_file": hy2_provider_name},
		"generated_files": generated_files
	}

func prepare_local(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "找不到所选配置文件。"}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "配置文件无法读取。"}
	var content := file.get_as_text()
	file.close()
	if content.strip_edges().is_empty():
		return {"ok": false, "error": "配置文件为空。"}
	return {
		"ok": true,
		"name": path.get_file(),
		"kind": "local",
		"yaml": content,
		"provider_file": "",
		"extra": {},
		"generated_files": []
	}

func cleanup_generated(file_names: Array) -> void:
	for file_name in file_names:
		if file_name.is_empty():
			continue
		var path: String = store.provider_dir().path_join(file_name)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
