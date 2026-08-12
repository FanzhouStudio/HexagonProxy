class_name CoreController
extends Node

signal status_changed(online: bool, message: String)
signal event_logged(message: String)
signal api_result(action: String, ok: bool, payload: Variant)
signal download_progress(progress: float, message: String)
signal profile_changed(display_name: String)
signal subscriptions_changed
signal system_proxy_changed(enabled: bool)
signal system_proxy_busy_changed(busy: bool)
signal autostart_changed(enabled: bool)
signal autostart_busy_changed(busy: bool)

const CONTROLLER_HOST := "127.0.0.1"
const CONTROLLER_PORT := 19090
const MIXED_PORT := 7890
const GITHUB_RELEASE_API := "https://api.github.com/repos/MetaCubeX/mihomo/releases/latest"

var core_pid := -1
var online := false
var starting := false
var system_proxy_enabled := false
var current_profile_name := "内置直连配置"
var _subscriptions: Array = []
var _active_subscription_id := ""
var _poll_in_flight := false
var _startup_attempts := 0
var _download_request: HTTPRequest
var _download_archive_path := ""
var _expected_archive_sha256 := ""
var _proxy_state_captured := false
var _system_proxy_pid := -1
var _system_proxy_started_msec := 0
var _system_proxy_target := false
var _system_proxy_busy := false
var _pending_system_proxy: Variant = null
var _autostart_cached := false
var _api_in_flight: Dictionary = {}
var _restart_generation := 0
var _api_secret := ""
var _core_cleanup_pid := -1
var _core_cleanup_started_msec := 0
var _start_after_cleanup := false
var _shutting_down := false

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(runtime_dir())
	DirAccess.make_dir_recursive_absolute(profile_dir())
	_install_bundled_core()
	_ensure_default_profile()
	_load_subscription_library()
	_migrate_legacy_active_profile()
	_install_proxy_helper()
	_install_core_process_helper()
	_autostart_cached = FileAccess.file_exists(autostart_path())
	_migrate_legacy_autostart()

func _process(_delta: float) -> void:
	_finish_system_proxy_process_if_ready()
	_finish_core_cleanup_if_ready()

func runtime_dir() -> String:
	return ProjectSettings.globalize_path("user://runtime")

func profile_dir() -> String:
	return ProjectSettings.globalize_path("user://profiles")

func profile_path() -> String:
	return profile_dir().path_join("active.yaml")

func subscription_library_dir() -> String:
	return profile_dir().path_join("library")

func subscription_index_path() -> String:
	return subscription_library_dir().path_join("index.json")

func subscription_provider_dir() -> String:
	return runtime_dir().path_join("providers").path_join("library")

func core_path() -> String:
	return runtime_dir().path_join("mihomo.exe")

func _install_bundled_core() -> void:
	var destination := core_path()
	if FileAccess.file_exists(destination):
		return
	var bundled := "res://bin/mihomo.exe"
	if not FileAccess.file_exists(bundled):
		return
	var source := FileAccess.open(bundled, FileAccess.READ)
	if source == null:
		return
	var temporary := destination + ".bundled.tmp"
	var target := FileAccess.open(temporary, FileAccess.WRITE)
	if target == null:
		return
	target.store_buffer(source.get_buffer(source.get_length()))
	target.close()
	source.close()
	if DirAccess.rename_absolute(temporary, destination) == OK:
		event_logged.emit("已释放随客户端附带的 Mihomo 内核。")

func has_core() -> bool:
	return FileAccess.file_exists(core_path())

func start_core() -> void:
	if online or starting:
		return
	if not has_core():
		status_changed.emit(false, "需要先下载 Mihomo 内核")
		event_logged.emit("未找到 Mihomo 内核，请在设置页下载。")
		return
	_ensure_default_profile()
	if OS.get_name() == "Windows":
		_start_core_cleanup()
		return
	_launch_core()

func _launch_core() -> void:
	_api_secret = Crypto.new().generate_random_bytes(24).hex_encode()
	var args := PackedStringArray([
		"-d", runtime_dir(),
		"-f", profile_path(),
		"-ext-ctl", "%s:%d" % [CONTROLLER_HOST, CONTROLLER_PORT],
		"-secret", _api_secret
	])
	core_pid = OS.create_process(core_path(), args, false)
	if core_pid <= 0:
		core_pid = -1
		status_changed.emit(false, "内核启动失败")
		event_logged.emit("无法创建 Mihomo 进程。")
		return
	starting = true
	_startup_attempts = 0
	status_changed.emit(false, "六角恐龙正在启动内核…")
	event_logged.emit("Mihomo 已启动，PID %d。" % core_pid)
	await get_tree().create_timer(0.45).timeout
	poll_status()

func stop_core(cancel_pending_restart := true) -> void:
	if cancel_pending_restart:
		_restart_generation += 1
	_cancel_api_requests()
	_start_after_cleanup = false
	if _core_cleanup_pid > 0:
		if OS.is_process_running(_core_cleanup_pid):
			OS.kill(_core_cleanup_pid)
		_core_cleanup_pid = -1
	if system_proxy_enabled:
		set_system_proxy(false)
	if core_pid > 0:
		OS.kill(core_pid)
	core_pid = -1
	starting = false
	_startup_attempts = 0
	_set_online(false, "代理已休息")
	event_logged.emit("Mihomo 已停止。")

func _start_core_cleanup() -> void:
	if _core_cleanup_pid > 0:
		_start_after_cleanup = true
		return
	starting = true
	_start_after_cleanup = true
	status_changed.emit(false, "正在清理旧内核…")
	_core_cleanup_pid = OS.create_process("powershell.exe", PackedStringArray([
		"-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
		"-File", core_process_helper_path(), core_path()
	]), false)
	_core_cleanup_started_msec = Time.get_ticks_msec()
	if _core_cleanup_pid <= 0:
		_core_cleanup_pid = -1
		starting = false
		_start_after_cleanup = false
		status_changed.emit(false, "旧内核清理失败")
		event_logged.emit("无法启动旧内核清理助手。")

func _finish_core_cleanup_if_ready() -> void:
	if _core_cleanup_pid <= 0:
		return
	if OS.is_process_running(_core_cleanup_pid):
		if Time.get_ticks_msec() - _core_cleanup_started_msec <= 10000:
			return
		OS.kill(_core_cleanup_pid)
		_core_cleanup_pid = -1
		starting = false
		_start_after_cleanup = false
		status_changed.emit(false, "旧内核清理超时")
		event_logged.emit("旧 Mihomo 进程未能及时退出，请稍后重试。")
		return
	var exit_code := OS.get_process_exit_code(_core_cleanup_pid)
	_core_cleanup_pid = -1
	starting = false
	if exit_code != 0:
		_start_after_cleanup = false
		status_changed.emit(false, "旧内核清理失败")
		event_logged.emit("旧 Mihomo 进程清理失败，请检查 Windows 权限。")
		return
	if _start_after_cleanup and not _shutting_down:
		_start_after_cleanup = false
		_launch_core()

func restart_core() -> void:
	_restart_generation += 1
	var generation := _restart_generation
	stop_core(false)
	await get_tree().create_timer(0.35).timeout
	if generation != _restart_generation or _shutting_down:
		return
	start_core()

func poll_status() -> void:
	if _poll_in_flight:
		return
	if _core_cleanup_pid > 0:
		return
	if starting and core_pid <= 0:
		starting = false
		_set_online(false, "内核启动失败，请检查配置")
		return
	if core_pid > 0 and not OS.is_process_running(core_pid):
		core_pid = -1
		starting = false
		if system_proxy_enabled:
			set_system_proxy(false)
		_set_online(false, "内核已退出，请检查配置")
		event_logged.emit("Mihomo 进程意外退出，可能是配置格式无效。")
		return
	_poll_in_flight = true
	_api_request("version", "/version", HTTPClient.METHOD_GET)

func refresh_runtime() -> void:
	if not online:
		return
	_api_request("proxies", "/proxies", HTTPClient.METHOD_GET)
	_api_request("connections", "/connections", HTTPClient.METHOD_GET)
	_api_request("config", "/configs", HTTPClient.METHOD_GET)

func set_mode(mode: String) -> void:
	if mode not in ["rule", "global", "direct"]:
		return
	_api_request("set_mode", "/configs", HTTPClient.METHOD_PATCH, JSON.stringify({"mode": mode}))

func select_proxy(group_name: String, proxy_name: String) -> void:
	_api_request("select_proxy", "/proxies/%s" % group_name.uri_encode(), HTTPClient.METHOD_PUT, JSON.stringify({"name": proxy_name}))

func test_proxy_delay(proxy_name: String) -> void:
	var test_url := "https://www.gstatic.com/generate_204".uri_encode()
	var path := "/proxies/%s/delay?url=%s&timeout=5000" % [proxy_name.uri_encode(), test_url]
	_api_request("delay:%s" % proxy_name, path, HTTPClient.METHOD_GET)

func test_group_delay(group_name: String) -> void:
	if group_name.is_empty():
		return
	var test_url := "https://www.gstatic.com/generate_204".uri_encode()
	var path := "/group/%s/delay?url=%s&timeout=5000" % [group_name.uri_encode(), test_url]
	_api_request("group_delay", path, HTTPClient.METHOD_GET)

func is_autostart_enabled() -> bool:
	return _autostart_cached

func refresh_autostart_state() -> void:
	_autostart_cached = OS.get_name() == "Windows" and FileAccess.file_exists(autostart_path())
	autostart_changed.emit(_autostart_cached)

func set_autostart(enabled: bool) -> void:
	if OS.get_name() != "Windows":
		event_logged.emit("开机自启当前仅支持 Windows。")
		return
	autostart_busy_changed.emit(true)
	var code := OK
	if enabled:
		DirAccess.make_dir_recursive_absolute(autostart_path().get_base_dir())
		var file := FileAccess.open(autostart_path(), FileAccess.WRITE)
		if file == null:
			code = FileAccess.get_open_error()
		else:
			var command := autostart_command().replace("\"", "\"\"")
			file.store_string("Set shell = CreateObject(\"WScript.Shell\")\r\nshell.Run \"%s\", 0, False\r\n" % command)
			file.close()
	else:
		if FileAccess.file_exists(autostart_path()):
			code = DirAccess.remove_absolute(autostart_path())
	_autostart_cached = code == OK and enabled
	autostart_changed.emit(_autostart_cached)
	autostart_busy_changed.emit(false)
	if code == OK:
		event_logged.emit("开机自启已%s。" % ("开启" if enabled else "关闭"))
	else:
		event_logged.emit("开机自启设置失败（%s）。" % error_string(code))

func autostart_path() -> String:
	return OS.get_environment("APPDATA").path_join("Microsoft/Windows/Start Menu/Programs/Startup/HexagonProxy.vbs")

func _migrate_legacy_autostart() -> void:
	if OS.get_name() == "Windows":
		OS.create_process("reg.exe", PackedStringArray([
			"delete", "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run",
			"/v", "HexagonProxy", "/f"
		]), false)

func autostart_command() -> String:
	var executable := OS.get_executable_path()
	if OS.has_feature("editor"):
		var project_dir := ProjectSettings.globalize_path("res://").trim_suffix("/").trim_suffix("\\")
		return "\"%s\" --path \"%s\" -- --tray-start" % [executable, project_dir]
	return "\"%s\" -- --tray-start" % executable

func use_subscription_url(url: String) -> bool:
	var cleaned := url.strip_edges()
	if not (cleaned.begins_with("https://") or cleaned.begins_with("http://")):
		event_logged.emit("订阅地址必须以 http:// 或 https:// 开头。")
		return false
	var escaped := cleaned.replace("'", "''")
	var yaml := """# 六角代理生成的订阅配置
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
proxy-providers:
  hexagon-subscription:
    type: http
    url: '%s'
    path: ./providers/hexagon-subscription.yaml
    interval: 3600
    header:
      User-Agent:
        - 'mihomo'
    health-check:
      enable: true
      url: https://www.gstatic.com/generate_204
      interval: 600
proxy-groups:
  - name: 六角选择
    type: select
    use:
      - hexagon-subscription
  - name: 自动优选
    type: url-test
    use:
      - hexagon-subscription
    url: https://www.gstatic.com/generate_204
    interval: 300
    tolerance: 80
rules:
  - MATCH,六角选择
""" % escaped
	var entry_id := _new_subscription_id()
	var host := cleaned.trim_prefix("https://").trim_prefix("http://").get_slice("/", 0).get_slice("?", 0)
	var display_name := "HTTP 订阅" if host.is_empty() else "HTTP 订阅 · %s" % host
	if not _save_subscription(entry_id, display_name, "http", yaml):
		return false
	_activate_subscription(entry_id, false)
	event_logged.emit("订阅已保存，地址仅保存在本机配置中。")
	return true

func use_v2_share_links(content: String) -> bool:
	var cleaned := content.strip_edges()
	if cleaned.is_empty():
		event_logged.emit("请粘贴至少一条 V2 分享链接。")
		return false
	var supported_schemes := PackedStringArray([
		"ss://", "ssr://", "vmess://", "vless://", "trojan://",
		"hysteria://", "hysteria2://", "hy2://", "tuic://"
	])
	var uri_count := 0
	var has_uri := false
	var invalid_preview := ""
	var uri_lines: Array[String] = []
	for line in cleaned.replace("\r\n", "\n").replace("\r", "\n").split("\n"):
		var item := line.strip_edges()
		if item.is_empty():
			continue
		var matched := false
		for scheme in supported_schemes:
			if item.to_lower().begins_with(scheme):
				matched = _is_plausible_share_uri(item, scheme)
				if matched:
					has_uri = true
					uri_count += 1
					uri_lines.append(item)
				break
		if not matched and invalid_preview.is_empty():
			invalid_preview = item.left(24)
	if has_uri and not invalid_preview.is_empty():
		event_logged.emit("分享链接列表中包含无法识别的内容。")
		return false
	if not has_uri:
		var compact := cleaned.replace("\r", "").replace("\n", "").replace(" ", "")
		if compact.length() < 16 or not _looks_like_base64(compact):
			event_logged.emit("无法识别内容；请粘贴 V2 分享链接或 Base64 订阅正文。")
			return false
		var decoded := _decode_base64_text(compact)
		if decoded.is_empty():
			event_logged.emit("Base64 订阅正文无法解码。")
			return false
		for decoded_line in decoded.replace("\r\n", "\n").replace("\r", "\n").split("\n"):
			var decoded_item := decoded_line.strip_edges()
			if decoded_item.is_empty():
				continue
			var decoded_matched := false
			for scheme in supported_schemes:
				if decoded_item.to_lower().begins_with(scheme) and _is_plausible_share_uri(decoded_item, scheme):
					decoded_matched = true
					uri_count += 1
					uri_lines.append(decoded_item)
					break
			if not decoded_matched:
				event_logged.emit("Base64 订阅中包含无法识别的节点。")
				return false
		if uri_count == 0:
			event_logged.emit("Base64 订阅中没有找到节点。")
			return false
	var entry_id := _new_subscription_id()
	var provider_name := "%s-v2.txt" % entry_id
	var normalized := _normalize_v2_provider_lines(uri_lines, entry_id)
	var regular_lines: Array[String] = normalized.get("regular_lines", [])
	var hy2_yaml := str(normalized.get("hy2_yaml", ""))
	var regular_provider_name := provider_name if not regular_lines.is_empty() else ""
	var hy2_provider_name := "%s-hy2.yaml" % entry_id if not hy2_yaml.is_empty() else ""
	var yaml := _v2_profile_yaml(regular_provider_name, hy2_provider_name)
	var display_name := "V2 分享链接 · %s" % Time.get_datetime_string_from_system(false, true).replace("T", " ")
	if uri_count > 0:
		display_name += " · %d 个节点" % uri_count
	if not regular_provider_name.is_empty() and not _write_text_atomic(subscription_provider_dir().path_join(regular_provider_name), "\n".join(regular_lines) + "\n"):
		event_logged.emit("无法保存 V2 节点文件。")
		return false
	if not hy2_provider_name.is_empty() and not _write_text_atomic(subscription_provider_dir().path_join(hy2_provider_name), hy2_yaml):
		if not regular_provider_name.is_empty():
			DirAccess.remove_absolute(subscription_provider_dir().path_join(regular_provider_name))
		event_logged.emit("无法保存 Hysteria2 节点文件。")
		return false
	if not _save_subscription(entry_id, display_name, "v2", yaml, regular_provider_name, {"hy2_provider_file": hy2_provider_name}):
		for generated_file in [regular_provider_name, hy2_provider_name]:
			if not generated_file.is_empty():
				DirAccess.remove_absolute(subscription_provider_dir().path_join(generated_file))
		return false
	_activate_subscription(entry_id, false)
	event_logged.emit("V2 节点已导入；链接仅保存在本机。")
	return true

func _v2_profile_yaml(provider_name: String, hy2_provider_name := "") -> String:
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
	return """# 六角代理生成的 V2 分享链接配置
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
rules:
  - MATCH,六角选择
""" % [provider_yaml, use_yaml, use_yaml]

func _normalize_v2_provider_lines(uri_lines: Array[String], entry_id: String) -> Dictionary:
	var regular_lines: Array[String] = []
	var hy2_nodes: Array[Dictionary] = []
	for line in uri_lines:
		var lower := line.to_lower()
		if lower.begins_with("hysteria2://") or lower.begins_with("hy2://"):
			var node := _parse_hysteria2_uri(line)
			if not node.is_empty():
				hy2_nodes.append(node)
				continue
		regular_lines.append(line)
	return {
		"regular_lines": regular_lines,
		"hy2_yaml": _hysteria2_provider_yaml(hy2_nodes, entry_id) if not hy2_nodes.is_empty() else ""
	}

func _parse_hysteria2_uri(link: String) -> Dictionary:
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
	var params := _uri_query_parameters(query)
	var node := {
		"name": fragment if not fragment.is_empty() else "%s-hy2" % server,
		"server": server,
		"port": port,
		"password": password,
		"skip_cert_verify": _query_bool(params, ["insecure", "allowinsecure", "skip-cert-verify"])
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
		var value := _first_query_value(params, mapping[1])
		if not value.is_empty():
			node[mapping[0]] = value
	return node

func _uri_query_parameters(query: String) -> Dictionary:
	var params := {}
	for item in query.split("&", false):
		var separator := item.find("=")
		var key := (item.left(separator) if separator >= 0 else item).uri_decode().to_lower()
		var value := (item.substr(separator + 1) if separator >= 0 else "").uri_decode()
		params[key] = value
	return params

func _first_query_value(params: Dictionary, keys: Array) -> String:
	for key_variant in keys:
		var key := str(key_variant).to_lower()
		if params.has(key):
			return str(params[key])
	return ""

func _query_bool(params: Dictionary, keys: Array) -> bool:
	for key_variant in keys:
		var key := str(key_variant).to_lower()
		if params.has(key) and str(params[key]).to_lower() in ["1", "true", "yes", "on"]:
			return true
	return false

func _hysteria2_provider_yaml(nodes: Array[Dictionary], _entry_id: String) -> String:
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
		yaml += "  - name: %s\n" % _yaml_quote(unique_name)
		yaml += "    type: hysteria2\n"
		yaml += "    server: %s\n" % _yaml_quote(str(node.get("server", "")))
		yaml += "    port: %d\n" % int(node.get("port", 0))
		yaml += "    password: %s\n" % _yaml_quote(str(node.get("password", "")))
		yaml += "    skip-cert-verify: %s\n" % str(bool(node.get("skip_cert_verify", false))).to_lower()
		for field in ["sni", "ports", "hop_interval", "obfs", "obfs_password", "up", "down", "fingerprint"]:
			if not node.has(field):
				continue
			var yaml_field := str(field).replace("_", "-")
			yaml += "    %s: %s\n" % [yaml_field, _yaml_quote(str(node[field]))]
		if node.has("alpn"):
			yaml += "    alpn:\n"
			for alpn_item in str(node["alpn"]).split(",", false):
				yaml += "      - %s\n" % _yaml_quote(alpn_item.strip_edges())
	return yaml

func _yaml_quote(value: String) -> String:
	return "'%s'" % value.replace("'", "''")

func _looks_like_base64(value: String) -> bool:
	var expression := RegEx.new()
	if expression.compile("^[A-Za-z0-9+/=_-]+$") != OK:
		return false
	return expression.search(value) != null

func _decode_base64_text(value: String) -> String:
	var normalized := value.replace("-", "+").replace("_", "/")
	while normalized.length() % 4 != 0:
		normalized += "="
	return Marshalls.base64_to_utf8(normalized)

func _is_plausible_share_uri(value: String, scheme: String) -> bool:
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
		return _looks_like_base64(payload.get_slice("#", 0))
	return true

func import_local_profile(path: String) -> bool:
	if not FileAccess.file_exists(path):
		event_logged.emit("找不到所选配置文件。")
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		event_logged.emit("配置文件无法读取。")
		return false
	var content := file.get_as_text()
	if content.strip_edges().is_empty():
		event_logged.emit("配置文件为空。")
		return false
	var entry_id := _new_subscription_id()
	if not _save_subscription(entry_id, path.get_file(), "local", content):
		return false
	_activate_subscription(entry_id, false)
	event_logged.emit("已导入本地配置：%s" % current_profile_name)
	return true

func update_provider() -> void:
	var index := _subscription_index(_active_subscription_id)
	if index < 0 or str(_subscriptions[index].get("type", "")) != "http":
		event_logged.emit("当前配置不是 HTTP 订阅，无需在线刷新。")
		return
	_api_request("update_provider", "/providers/proxies/hexagon-subscription", HTTPClient.METHOD_PUT)

func get_subscriptions() -> Array:
	return _subscriptions.duplicate(true)

func active_subscription_id() -> String:
	return _active_subscription_id

func activate_subscription(entry_id: String) -> bool:
	return _activate_subscription(entry_id, true)

func delete_subscription(entry_id: String) -> bool:
	var index := _subscription_index(entry_id)
	if index < 0:
		event_logged.emit("找不到要删除的订阅。")
		return false
	var entry: Dictionary = _subscriptions[index]
	var was_active := entry_id == _active_subscription_id
	_subscriptions.remove_at(index)
	_delete_subscription_files(entry)
	if was_active:
		_active_subscription_id = ""
		if not _subscriptions.is_empty():
			var next_index := mini(index, _subscriptions.size() - 1)
			var next_entry: Dictionary = _subscriptions[next_index]
			_active_subscription_id = str(next_entry.get("id", ""))
			if not _copy_subscription_to_active(next_entry):
				return false
			current_profile_name = str(next_entry.get("name", "订阅"))
		else:
			if not _write_profile(_default_profile_yaml()):
				return false
			current_profile_name = "内置直连配置"
	if not _save_subscription_index():
		return false
	profile_changed.emit(current_profile_name)
	subscriptions_changed.emit()
	event_logged.emit("已删除订阅：%s" % str(entry.get("name", "订阅")))
	if was_active:
		_restart_for_profile_change()
	return true

func _save_subscription(entry_id: String, display_name: String, kind: String, yaml: String, provider_file := "", extra := {}) -> bool:
	DirAccess.make_dir_recursive_absolute(subscription_library_dir())
	var config_file := "%s.yaml" % entry_id
	if not _write_text_atomic(subscription_library_dir().path_join(config_file), yaml):
		event_logged.emit("无法保存订阅档案。")
		return false
	var entry := {
		"id": entry_id,
		"name": display_name,
		"type": kind,
		"config_file": config_file,
		"provider_file": provider_file,
		"created_at": int(Time.get_unix_time_from_system())
	}
	for key in extra:
		entry[key] = extra[key]
	_subscriptions.append(entry)
	if not _save_subscription_index():
		_subscriptions.pop_back()
		DirAccess.remove_absolute(subscription_library_dir().path_join(config_file))
		return false
	subscriptions_changed.emit()
	return true

func _activate_subscription(entry_id: String, log_change: bool) -> bool:
	var index := _subscription_index(entry_id)
	if index < 0:
		event_logged.emit("找不到要启用的订阅。")
		return false
	var entry: Dictionary = _subscriptions[index]
	if not _copy_subscription_to_active(entry):
		return false
	var previous_active_id := _active_subscription_id
	_active_subscription_id = entry_id
	current_profile_name = str(entry.get("name", "订阅"))
	if not _save_subscription_index():
		_active_subscription_id = previous_active_id
		return false
	profile_changed.emit(current_profile_name)
	subscriptions_changed.emit()
	if log_change:
		event_logged.emit("已切换订阅：%s" % current_profile_name)
	_restart_for_profile_change()
	return true

func _copy_subscription_to_active(entry: Dictionary) -> bool:
	var config_path := subscription_library_dir().path_join(str(entry.get("config_file", "")))
	if not FileAccess.file_exists(config_path):
		event_logged.emit("订阅配置文件已丢失。")
		return false
	return _write_profile(FileAccess.get_file_as_string(config_path))

func _restart_for_profile_change() -> void:
	if _shutting_down:
		return
	if online or starting:
		restart_core()
	else:
		start_core()

func _subscription_index(entry_id: String) -> int:
	for index in _subscriptions.size():
		var entry: Dictionary = _subscriptions[index]
		if str(entry.get("id", "")) == entry_id:
			return index
	return -1

func _new_subscription_id() -> String:
	return "%d-%s" % [Time.get_ticks_usec(), Crypto.new().generate_random_bytes(4).hex_encode()]

func _save_subscription_index() -> bool:
	var data := {
		"version": 1,
		"active_id": _active_subscription_id,
		"subscriptions": _subscriptions
	}
	if not _write_text_atomic(subscription_index_path(), JSON.stringify(data, "  ")):
		event_logged.emit("无法保存订阅索引。")
		return false
	return true

func _load_subscription_library() -> void:
	DirAccess.make_dir_recursive_absolute(subscription_library_dir())
	_subscriptions = []
	_active_subscription_id = ""
	if not FileAccess.file_exists(subscription_index_path()):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(subscription_index_path()))
	if not parsed is Dictionary:
		return
	var items: Variant = parsed.get("subscriptions", [])
	if items is Array:
		for item in items:
			if item is Dictionary and not str(item.get("id", "")).is_empty():
				_subscriptions.append(item)
	_active_subscription_id = str(parsed.get("active_id", ""))
	for index in _subscriptions.size():
		var entry_variant: Variant = _subscriptions[index]
		if entry_variant is Dictionary:
			var repaired_entry: Dictionary = entry_variant
			_repair_v2_subscription_yaml(repaired_entry)
			_subscriptions[index] = repaired_entry
	var active_index := _subscription_index(_active_subscription_id)
	if active_index >= 0:
		var active_entry: Dictionary = _subscriptions[active_index]
		current_profile_name = str(active_entry.get("name", "订阅"))
	else:
		_active_subscription_id = ""

func _repair_v2_subscription_yaml(entry: Dictionary) -> void:
	if str(entry.get("type", "")) != "v2":
		return
	var config_path := subscription_library_dir().path_join(str(entry.get("config_file", "")))
	if not FileAccess.file_exists(config_path):
		return
	var provider_file := str(entry.get("provider_file", ""))
	var hy2_provider_file := str(entry.get("hy2_provider_file", ""))
	if provider_file.is_empty() and hy2_provider_file.is_empty():
		return
	var legacy_provider_path := subscription_library_dir().path_join(provider_file)
	var provider_path := subscription_provider_dir().path_join(provider_file)
	if not provider_file.is_empty() and FileAccess.file_exists(legacy_provider_path) and not FileAccess.file_exists(provider_path):
		_write_text_atomic(provider_path, FileAccess.get_file_as_string(legacy_provider_path))
		DirAccess.remove_absolute(legacy_provider_path)
	if hy2_provider_file.is_empty() and FileAccess.file_exists(provider_path):
		var lines: Array[String] = []
		for line_variant in FileAccess.get_file_as_string(provider_path).replace("\r\n", "\n").replace("\r", "\n").split("\n"):
			var line := str(line_variant).strip_edges()
			if not line.is_empty():
				lines.append(line)
		var normalized := _normalize_v2_provider_lines(lines, str(entry.get("id", "")))
		var regular_lines: Array[String] = normalized.get("regular_lines", [])
		var hy2_yaml := str(normalized.get("hy2_yaml", ""))
		if not hy2_yaml.is_empty():
			hy2_provider_file = "%s-hy2.yaml" % str(entry.get("id", ""))
			if _write_text_atomic(subscription_provider_dir().path_join(hy2_provider_file), hy2_yaml):
				entry["hy2_provider_file"] = hy2_provider_file
				if regular_lines.is_empty():
					DirAccess.remove_absolute(provider_path)
					provider_file = ""
					entry["provider_file"] = ""
				else:
					_write_text_atomic(provider_path, "\n".join(regular_lines) + "\n")
				_save_subscription_index()
				event_logged.emit("已自动转换旧版 Hysteria2 分享链接。")
	var repaired := _v2_profile_yaml(provider_file, hy2_provider_file)
	if not _write_text_atomic(config_path, repaired):
		return
	if str(entry.get("id", "")) == _active_subscription_id:
		_write_profile(repaired)
	event_logged.emit("已自动修复旧版 V2 配置缩进。")

func _migrate_legacy_active_profile() -> void:
	if not _subscriptions.is_empty() or not FileAccess.file_exists(profile_path()):
		return
	var yaml := FileAccess.get_file_as_string(profile_path())
	if yaml.contains("# 六角代理默认直连配置"):
		return
	var kind := "local"
	var display_name := "迁移的本地配置"
	var provider_file := ""
	if yaml.contains("hexagon-subscription"):
		kind = "http"
		display_name = "HTTP 订阅（已迁移）"
	elif yaml.contains("hexagon-v2"):
		kind = "v2"
		display_name = "V2 分享链接（已迁移）"
		var legacy_provider := runtime_dir().path_join("providers").path_join("hexagon-v2.txt")
		if FileAccess.file_exists(legacy_provider):
			provider_file = "%s-v2.txt" % _new_subscription_id()
			_write_text_atomic(subscription_provider_dir().path_join(provider_file), FileAccess.get_file_as_string(legacy_provider))
			yaml = yaml.replace("./providers/hexagon-v2.txt", "./providers/library/%s" % provider_file)
	var entry_id := _new_subscription_id()
	if _save_subscription(entry_id, display_name, kind, yaml, provider_file):
		_active_subscription_id = entry_id
		current_profile_name = display_name
		_write_profile(yaml)
		_save_subscription_index()
		if kind == "v2":
			_repair_v2_subscription_yaml(_subscriptions.back())

func _delete_subscription_files(entry: Dictionary) -> void:
	var config_file := str(entry.get("config_file", ""))
	if not config_file.is_empty():
		var config_path := subscription_library_dir().path_join(config_file)
		if FileAccess.file_exists(config_path):
			DirAccess.remove_absolute(config_path)
	var provider_file := str(entry.get("provider_file", ""))
	var provider_files := [provider_file, str(entry.get("hy2_provider_file", ""))]
	for stored_provider_file in provider_files:
		if not stored_provider_file.is_empty():
			for provider_path in [subscription_provider_dir().path_join(stored_provider_file), subscription_library_dir().path_join(stored_provider_file)]:
				if FileAccess.file_exists(provider_path):
					DirAccess.remove_absolute(provider_path)

func _write_text_atomic(path: String, content: String) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var temp_path := path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(content)
	file.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	return DirAccess.rename_absolute(temp_path, path) == OK

func set_system_proxy(enabled: bool) -> void:
	if OS.get_name() != "Windows":
		event_logged.emit("当前版本的系统代理开关仅支持 Windows。")
		return
	if enabled and not online:
		event_logged.emit("请先启动代理，再开启系统代理。")
		system_proxy_changed.emit(system_proxy_enabled)
		return
	if _system_proxy_busy:
		_pending_system_proxy = enabled
		return
	if enabled == system_proxy_enabled:
		system_proxy_changed.emit(system_proxy_enabled)
		return
	if not enabled and not _proxy_state_captured:
		system_proxy_enabled = false
		system_proxy_changed.emit(false)
		return
	_system_proxy_busy = true
	_system_proxy_target = enabled
	system_proxy_busy_changed.emit(true)
	var action := "enable" if enabled else "disable"
	_system_proxy_pid = OS.create_process("powershell.exe", PackedStringArray([
		"-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
		"-File", proxy_helper_path(), action, proxy_state_path()
	]), false)
	_system_proxy_started_msec = Time.get_ticks_msec()
	if _system_proxy_pid <= 0:
		_system_proxy_pid = -1
		_system_proxy_busy = false
		system_proxy_busy_changed.emit(false)
		event_logged.emit("无法启动系统代理设置助手。")
		system_proxy_changed.emit(system_proxy_enabled)

func _finish_system_proxy_process_if_ready() -> void:
	if _system_proxy_pid <= 0:
		return
	if OS.is_process_running(_system_proxy_pid):
		if Time.get_ticks_msec() - _system_proxy_started_msec <= 12000:
			return
		OS.kill(_system_proxy_pid)
		_finish_system_proxy_process(false, true)
		return
	var code := OS.get_process_exit_code(_system_proxy_pid)
	_finish_system_proxy_process(code == 0, false)

func _finish_system_proxy_process(success: bool, timed_out: bool) -> void:
	_system_proxy_pid = -1
	_system_proxy_busy = false
	if success:
		system_proxy_enabled = _system_proxy_target
		_proxy_state_captured = system_proxy_enabled and FileAccess.file_exists(proxy_state_path())
		event_logged.emit("系统代理已%s。" % ("开启" if system_proxy_enabled else "关闭"))
	else:
		event_logged.emit("系统代理设置%s。" % ("超时，操作已终止" if timed_out else "失败，请检查 Windows 权限"))
	system_proxy_changed.emit(system_proxy_enabled)
	system_proxy_busy_changed.emit(false)
	if _pending_system_proxy != null and not _shutting_down:
		var pending := bool(_pending_system_proxy)
		_pending_system_proxy = null
		if pending != system_proxy_enabled:
			set_system_proxy(pending)

func proxy_helper_path() -> String:
	return runtime_dir().path_join("windows_proxy_helper.ps1")

func core_process_helper_path() -> String:
	return runtime_dir().path_join("core_process_helper.ps1")

func proxy_state_path() -> String:
	return runtime_dir().path_join("windows_proxy_state.json")

func _install_proxy_helper() -> void:
	var source := FileAccess.open("res://scripts/windows_proxy_helper.ps1", FileAccess.READ)
	if source == null:
		return
	var target := FileAccess.open(proxy_helper_path(), FileAccess.WRITE)
	if target != null:
		target.store_buffer(source.get_buffer(source.get_length()))
		target.close()
	source.close()

func _install_core_process_helper() -> void:
	var source := FileAccess.open("res://scripts/core_process_helper.ps1", FileAccess.READ)
	if source == null:
		return
	var target := FileAccess.open(core_process_helper_path(), FileAccess.WRITE)
	if target != null:
		target.store_buffer(source.get_buffer(source.get_length()))
		target.close()
	source.close()

func _registry_string_value(output: String, marker: String) -> String:
	for line in output.split("\n"):
		var position := line.find(marker)
		if position >= 0:
			return line.substr(position + marker.length()).strip_edges()
	return ""

func download_latest_core() -> void:
	if _download_request != null:
		return
	download_progress.emit(0.02, "正在查询 Mihomo 最新版本…")
	_download_request = HTTPRequest.new()
	_download_request.timeout = 25.0
	_download_request.max_redirects = 8
	add_child(_download_request)
	_download_request.request_completed.connect(_on_release_received)
	var error := _download_request.request(GITHUB_RELEASE_API, ["Accept: application/vnd.github+json", "User-Agent: HexagonProxy"])
	if error != OK:
		_finish_download(false, "无法连接 GitHub（%s）" % error_string(error))

func _on_release_received(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_clear_download_request()
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		_finish_download(false, "查询版本失败，HTTP %d" % response_code)
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not parsed is Dictionary:
		_finish_download(false, "GitHub 返回了无法识别的数据")
		return
	var asset_url := ""
	var asset_name := ""
	var fallback_url := ""
	var fallback_name := ""
	var fallback_digest := ""
	for item in parsed.get("assets", []):
		if not item is Dictionary:
			continue
		var archive_name := str(item.get("name", ""))
		var url := str(item.get("browser_download_url", ""))
		var digest_value: Variant = item.get("digest", "")
		var digest: String = "" if digest_value == null else str(digest_value).trim_prefix("sha256:")
		var supported_archive := archive_name.ends_with(".gz") or archive_name.ends_with(".zip")
		if archive_name.contains("windows-amd64-v3-v") and supported_archive:
			asset_name = archive_name
			asset_url = url
			_expected_archive_sha256 = digest
			break
		if archive_name.contains("windows-amd64") and supported_archive and not archive_name.contains("compatible"):
			fallback_name = archive_name
			fallback_url = url
			fallback_digest = digest
	if asset_url.is_empty():
		asset_url = fallback_url
		asset_name = fallback_name
		_expected_archive_sha256 = fallback_digest
	if asset_url.is_empty():
		_finish_download(false, "没有找到 Windows x64 内核压缩包")
		return
	download_progress.emit(0.12, "正在下载 %s…" % asset_name)
	_download_request = HTTPRequest.new()
	_download_request.timeout = 180.0
	_download_request.max_redirects = 8
	_download_archive_path = runtime_dir().path_join("mihomo-download.gz" if asset_name.ends_with(".gz") else "mihomo-download.zip")
	_download_request.download_file = _download_archive_path
	add_child(_download_request)
	_download_request.request_completed.connect(_on_core_archive_received)
	var error := _download_request.request(asset_url, ["User-Agent: HexagonProxy"])
	if error != OK:
		_finish_download(false, "内核下载无法开始（%s）" % error_string(error))

func _on_core_archive_received(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	_clear_download_request()
	if result != HTTPRequest.RESULT_SUCCESS or response_code not in [200, 206]:
		_finish_download(false, "内核下载失败，HTTP %d" % response_code)
		return
	if not _expected_archive_sha256.is_empty():
		var actual_digest := FileAccess.get_sha256(_download_archive_path)
		if actual_digest.to_lower() != _expected_archive_sha256.to_lower():
			_finish_download(false, "内核校验失败，已拒绝安装")
			return
	download_progress.emit(0.82, "正在安装内核…")
	var exe_bytes := PackedByteArray()
	if _download_archive_path.ends_with(".gz"):
		var compressed := FileAccess.get_file_as_bytes(_download_archive_path)
		exe_bytes = compressed.decompress_dynamic(256 * 1024 * 1024, FileAccess.COMPRESSION_GZIP)
	else:
		var zip := ZIPReader.new()
		var open_error := zip.open(_download_archive_path)
		if open_error != OK:
			_finish_download(false, "压缩包损坏（%s）" % error_string(open_error))
			return
		for file_name in zip.get_files():
			var executable_name: String = file_name.get_file().to_lower()
			if executable_name.begins_with("mihomo") and executable_name.ends_with(".exe"):
				exe_bytes = zip.read_file(file_name)
				break
		zip.close()
	if exe_bytes.size() < 2 or exe_bytes[0] != 0x4d or exe_bytes[1] != 0x5a:
		_finish_download(false, "压缩包内没有 mihomo.exe")
		return
	var output := FileAccess.open(core_path(), FileAccess.WRITE)
	if output == null:
		_finish_download(false, "无法写入内核目录")
		return
	output.store_buffer(exe_bytes)
	output.close()
	DirAccess.remove_absolute(_download_archive_path)
	_download_archive_path = ""
	_finish_download(true, "Mihomo 内核已就绪")

func _finish_download(success: bool, message: String) -> void:
	_clear_download_request()
	if not success and not _download_archive_path.is_empty() and FileAccess.file_exists(_download_archive_path):
		DirAccess.remove_absolute(_download_archive_path)
	if not success:
		_download_archive_path = ""
	_expected_archive_sha256 = ""
	download_progress.emit(1.0 if success else -1.0, message)
	event_logged.emit(message)
	if success:
		start_core()

func _clear_download_request() -> void:
	if _download_request != null:
		_download_request.queue_free()
		_download_request = null

func _api_request(action: String, endpoint: String, method: int, body := "") -> void:
	if _api_in_flight.has(action):
		return
	var request := HTTPRequest.new()
	request.timeout = 8.0
	add_child(request)
	_api_in_flight[action] = request
	request.request_completed.connect(func(result: int, response_code: int, _headers: PackedStringArray, data: PackedByteArray) -> void:
		_api_in_flight.erase(action)
		if action == "version":
			_poll_in_flight = false
		var ok := result == HTTPRequest.RESULT_SUCCESS and response_code >= 200 and response_code < 300
		var payload: Variant = {}
		if not data.is_empty():
			var decoded: Variant = JSON.parse_string(data.get_string_from_utf8())
			payload = decoded if decoded != null else data.get_string_from_utf8()
		if action == "version":
			if ok:
				_startup_attempts = 0
				_set_online(true, "守护中 · 连接安全")
			elif starting:
				_startup_attempts += 1
				if _startup_attempts >= 12:
					starting = false
					if core_pid > 0:
						OS.kill(core_pid)
					core_pid = -1
					_set_online(false, "内核启动失败，请检查配置")
					event_logged.emit("等待控制接口超时，配置可能无效或端口被占用。")
				else:
					await get_tree().create_timer(0.7).timeout
					poll_status()
			else:
				_set_online(false, "代理未连接")
		if action == "set_mode" and ok:
			event_logged.emit("代理模式已切换。")
		if action == "select_proxy" and ok:
			event_logged.emit("节点切换成功。")
		if action == "update_provider":
			event_logged.emit("订阅更新%s。" % ("完成" if ok else "失败"))
		api_result.emit(action, ok, payload)
		request.queue_free()
	)
	var headers := PackedStringArray([
		"Authorization: Bearer %s" % _api_secret,
		"Content-Type: application/json"
	])
	var error := request.request("http://%s:%d%s" % [CONTROLLER_HOST, CONTROLLER_PORT, endpoint], headers, method, body)
	if error != OK:
		_api_in_flight.erase(action)
		if action == "version":
			_poll_in_flight = false
		api_result.emit(action, false, {"error": error_string(error)})
		request.queue_free()

func _cancel_api_requests() -> void:
	for value in _api_in_flight.values():
		var request := value as HTTPRequest
		if is_instance_valid(request):
			request.cancel_request()
			request.queue_free()
	_api_in_flight.clear()
	_poll_in_flight = false

func _set_online(value: bool, message: String) -> void:
	var changed := online != value
	online = value
	if value:
		starting = false
	if changed or not message.is_empty():
		status_changed.emit(value, message)
	if changed and value:
		event_logged.emit("已连接 Mihomo 控制器。")

func _ensure_default_profile() -> void:
	if FileAccess.file_exists(profile_path()):
		return
	_write_profile(_default_profile_yaml())

func _default_profile_yaml() -> String:
	return """# 六角代理默认直连配置
mixed-port: 7890
allow-lan: false
mode: rule
log-level: info
ipv6: false
profile:
  store-selected: true
proxies: []
proxy-groups:
  - name: 六角选择
    type: select
    proxies:
      - DIRECT
rules:
  - MATCH,六角选择
"""

func _write_profile(content: String) -> bool:
	DirAccess.make_dir_recursive_absolute(profile_dir())
	var temp_path := profile_path() + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		event_logged.emit("无法写入配置目录。")
		return false
	file.store_string(content)
	file.close()
	if FileAccess.file_exists(profile_path()):
		DirAccess.remove_absolute(profile_path())
	var result := DirAccess.rename_absolute(temp_path, profile_path())
	if result != OK:
		event_logged.emit("保存配置失败（%s）。" % error_string(result))
		return false
	return true

func _exit_tree() -> void:
	_shutting_down = true
	_restart_generation += 1
	_cancel_api_requests()
	_start_after_cleanup = false
	if _core_cleanup_pid > 0 and OS.is_process_running(_core_cleanup_pid):
		OS.kill(_core_cleanup_pid)
	_core_cleanup_pid = -1
	_pending_system_proxy = null
	if _system_proxy_pid > 0 and OS.is_process_running(_system_proxy_pid):
		OS.kill(_system_proxy_pid)
	_system_proxy_pid = -1
	if (system_proxy_enabled or FileAccess.file_exists(proxy_state_path())) and FileAccess.file_exists(proxy_helper_path()):
		OS.create_process("powershell.exe", PackedStringArray([
			"-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
			"-File", proxy_helper_path(), "disable", proxy_state_path()
		]), false)
	if core_pid > 0:
		OS.kill(core_pid)
