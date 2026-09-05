class_name V2ShareParser
extends RefCounted

## V2 分享链接解析与 Mihomo provider 配置生成

const SUPPORTED_SCHEMES := [
	"ss://", "ssr://", "vmess://", "vless://", "trojan://",
	"hysteria://", "hysteria2://", "hy2://", "tuic://"
]

func parse_input(content: String) -> Dictionary:
	var cleaned := content.strip_edges()
	if cleaned.is_empty():
		return {"ok": false, "error": "请粘贴至少一条 V2 分享链接。"}
	var uri_lines: Array[String] = []
	var invalid_preview := ""
	var has_uri := false
	for line in cleaned.replace("\r\n", "\n").replace("\r", "\n").split("\n"):
		var item := line.strip_edges()
		if item.is_empty():
			continue
		var matched := false
		for scheme in SUPPORTED_SCHEMES:
			if item.to_lower().begins_with(scheme):
				matched = is_plausible_share_uri(item, scheme)
				if matched:
					has_uri = true
					uri_lines.append(item)
				break
		if not matched and invalid_preview.is_empty():
			invalid_preview = item.left(24)
	if has_uri and not invalid_preview.is_empty():
		return {"ok": false, "error": "分享链接列表中包含无法识别的内容。"}
	if not has_uri:
		var compact := cleaned.replace("\r", "").replace("\n", "").replace(" ", "")
		if compact.length() < 16 or not looks_like_base64(compact):
			return {"ok": false, "error": "无法识别内容；请粘贴 V2 分享链接或 Base64 订阅正文。"}
		var decoded := decode_base64_text(compact)
		if decoded.is_empty():
			return {"ok": false, "error": "Base64 订阅正文无法解码。"}
		for decoded_line in decoded.replace("\r\n", "\n").replace("\r", "\n").split("\n"):
			var decoded_item := decoded_line.strip_edges()
			if decoded_item.is_empty():
				continue
			var decoded_matched := false
			for scheme in SUPPORTED_SCHEMES:
				if decoded_item.to_lower().begins_with(scheme) and is_plausible_share_uri(decoded_item, scheme):
					decoded_matched = true
					uri_lines.append(decoded_item)
					break
			if not decoded_matched:
				return {"ok": false, "error": "Base64 订阅中包含无法识别的节点。"}
	if uri_lines.is_empty():
		return {"ok": false, "error": "Base64 订阅中没有找到节点。"}
	return {
		"ok": true,
		"error": "",
		"uri_lines": uri_lines,
		"count": uri_lines.size()
	}

func normalize_provider_lines(uri_lines: Array[String], entry_id: String) -> Dictionary:
	var regular_lines: Array[String] = []
	var hy2_nodes: Array[Dictionary] = []
	for line in uri_lines:
		var lower := line.to_lower()
		if lower.begins_with("hysteria2://") or lower.begins_with("hy2://"):
			var node := parse_hysteria2_uri(line)
			if not node.is_empty():
				hy2_nodes.append(node)
				continue
		regular_lines.append(line)
	return {
		"regular_lines": regular_lines,
		"hy2_yaml": hysteria2_provider_yaml(hy2_nodes, entry_id) if not hy2_nodes.is_empty() else ""
	}

func parse_hysteria2_uri(link: String) -> Dictionary:
	var scheme_end := link.find("://")
	if scheme_end < 0:
		return {}
	var payload := link.substr(scheme_end + 3)
	var fragment := ""
	var fragment_position := payload.find("#")
	if fragment_position >= 0:
		fragment = payload.substr(fragment_position + 1).uri_decode()
		payload = payload.left(fragment_position)
	var query := ""
	var query_position := payload.find("?")
	if query_position >= 0:
		query = payload.substr(query_position + 1)
		payload = payload.left(query_position)
	var at_position := payload.rfind("@")
	if at_position <= 0:
		return {}
	var password := payload.left(at_position).uri_decode()
	var server_part := payload.substr(at_position + 1)
	var server := ""
	var port_text := ""
	if server_part.begins_with("["):
		var bracket_end := server_part.find("]")
		if bracket_end < 0 or bracket_end + 2 > server_part.length():
			return {}
		server = server_part.substr(1, bracket_end - 1)
		port_text = server_part.substr(bracket_end + 2)
	else:
		var colon_position := server_part.rfind(":")
		if colon_position <= 0:
			return {}
		server = server_part.left(colon_position).uri_decode()
		port_text = server_part.substr(colon_position + 1)
	if not port_text.is_valid_int():
		return {}
	var port := int(port_text)
	if port <= 0 or port > 65535:
		return {}
	var params := uri_query_parameters(query)
	var node := {
		"name": fragment if not fragment.is_empty() else "%s-hy2" % server,
		"server": server,
		"port": port,
		"password": password,
		"skip_cert_verify": query_bool(params, ["insecure", "allowinsecure", "skip-cert-verify"])
	}
	for mapping in [
		["sni", ["sni", "servername", "peer"]],
		["ports", ["mport", "ports"]],
		["hop_interval", ["hop-interval", "hopinterval"]],
		["obfs", ["obfs"]],
		["obfs_password", ["obfs-password", "obfspassword"]],
		["up", ["up"]],
		["down", ["down"]],
		["fingerprint", ["fingerprint"]],
		["alpn", ["alpn"]]
	]:
		var value := first_query_value(params, mapping[1])
		if not value.is_empty():
			node[mapping[0]] = value
	return node
func uri_query_parameters(query: String) -> Dictionary:
	var params := {}
	for item in query.split("&", false):
		var separator := item.find("=")
		var key := (item.left(separator) if separator >= 0 else item).uri_decode().to_lower()
		var value := (item.substr(separator + 1) if separator >= 0 else "").uri_decode()
		params[key] = value
	return params

func first_query_value(params: Dictionary, keys: Array) -> String:
	for key_variant in keys:
		var key := str(key_variant).to_lower()
		if params.has(key):
			return str(params[key])
	return ""

func query_bool(params: Dictionary, keys: Array) -> bool:
	for key_variant in keys:
		var key := str(key_variant).to_lower()
		if params.has(key) and str(params[key]).to_lower() in ["1", "true", "yes", "on"]:
			return true
	return false

func hysteria2_provider_yaml(nodes: Array[Dictionary], _entry_id: String) -> String:
	var yaml := "proxies:\n"
	var used_names := {}
	for node in nodes:
		var node_name := str(node.get("name", "Hysteria2"))
		var unique_name := node_name
		var suffix := 2
		while used_names.has(unique_name):
			unique_name = "%s (%d)" % [node_name, suffix]
			suffix += 1
		used_names[unique_name] = true
		yaml += "  - name: %s\n" % yaml_quote(unique_name)
		yaml += "    type: hysteria2\n"
		yaml += "    server: %s\n" % yaml_quote(str(node.get("server", "")))
		yaml += "    port: %d\n" % int(node.get("port", 0))
		yaml += "    password: %s\n" % yaml_quote(str(node.get("password", "")))
		yaml += "    skip-cert-verify: %s\n" % str(bool(node.get("skip_cert_verify", false))).to_lower()
		for field in ["sni", "ports", "hop_interval", "obfs", "obfs_password", "up", "down", "fingerprint"]:
			if not node.has(field):
				continue
			var yaml_field := str(field).replace("_", "-")
			yaml += "    %s: %s\n" % [yaml_field, yaml_quote(str(node[field]))]
		if node.has("alpn"):
			yaml += "    alpn:\n"
			for alpn_item in str(node["alpn"]).split(",", false):
				yaml += "      - %s\n" % yaml_quote(alpn_item.strip_edges())
	return yaml

func yaml_quote(value: String) -> String:
	return "'%s'" % value.replace("'", "''")

func looks_like_base64(value: String) -> bool:
	var expression := RegEx.new()
	if expression.compile("^[A-Za-z0-9+/=_-]+$") != OK:
		return false
	return expression.search(value) != null

func decode_base64_text(value: String) -> String:
	var normalized := value.replace("-", "+").replace("_", "/")
	while normalized.length() % 4 != 0:
		normalized += "="
	return Marshalls.base64_to_utf8(normalized)

func is_plausible_share_uri(value: String, scheme: String) -> bool:
	var payload := value.substr(scheme.length()).strip_edges()
	if payload.length() < 8:
		return false
	if scheme in ["vless://", "trojan://", "hysteria://", "hysteria2://", "hy2://", "tuic://"]:
		var authority := payload.get_slice("#", 0).get_slice("?", 0)
		var at_position := authority.rfind("@")
		if at_position <= 0 or at_position >= authority.length() - 1:
			return false
		var server_part := authority.substr(at_position + 1)
		return server_part.contains(":")
	if scheme in ["vmess://", "ssr://"]:
		return looks_like_base64(payload.get_slice("#", 0))
	return true

func v2_profile_yaml(provider_name: String, hy2_provider_name: String, rule_providers: String, routing_rules: String) -> String:
	var provider_yaml := ""
	var provider_uses: Array[String] = []
	if not provider_name.is_empty():
		provider_yaml += "  hexagon-v2:\n    type: file\n    path: ./providers/library/%s\n" % provider_name
		provider_uses.append("hexagon-v2")
	if not hy2_provider_name.is_empty():
		provider_yaml += "  hexagon-v2-hy2:\n    type: file\n    path: ./providers/library/%s\n" % hy2_provider_name
		provider_uses.append("hexagon-v2-hy2")
	var use_yaml := ""
	for provider_id in provider_uses:
		use_yaml += "      - %s\n" % provider_id
	return """# HexagonProxy生成的 V2 分享链接配置
mixed-port: 7890
allow-lan: false
mode: rule
log-level: info
ipv6: false
unified-delay: true
tcp-concurrent: true
profile:
  store-selected: true
  store-fake-ip: true
%s
proxy-providers:
%sproxy-groups:
  - name: 六角选择
    type: select
    use:
%s  - name: 自动优选
    type: url-test
    use:
%s    url: https://www.gstatic.com/generate_204
    interval: 300
    tolerance: 80
%s""" % [rule_providers, provider_yaml, use_yaml, use_yaml, routing_rules]
