class_name ProxyConfig
extends RefCounted

## Mihomo 运行路径、可配置端口与运行时资源配置

const CONTROLLER_HOST := "127.0.0.1"
const DEFAULT_CONTROLLER_PORT := 19090
const DEFAULT_MIXED_PORT := 7890
const MIN_PORT := 1024
const MAX_PORT := 65535
const RANDOM_PORT_MIN := 20000
const RANDOM_PORT_MAX := 60000
const SETTINGS_PATH := "user://proxy_settings.cfg"
const CLEANUP_HELPER_SOURCE := "res://scripts/core_process_helper.ps1"
const BUNDLED_CORE_SOURCE := "res://bin/mihomo.exe"
const ROUTING_RULE_SOURCE_DIR := "res://third_party/meta-rules-dat"

var _mixed_port := DEFAULT_MIXED_PORT
var _controller_port := DEFAULT_CONTROLLER_PORT
var _window_borderless := true
var _window_width := 1920
var _window_height := 1080

func _init() -> void:
	_load_ports()

func runtime_dir() -> String:
	return ProjectSettings.globalize_path("user://runtime")

func profile_dir() -> String:
	return ProjectSettings.globalize_path("user://profiles")

func active_profile_path() -> String:
	return profile_dir().path_join("active.yaml")

func core_path() -> String:
	return runtime_dir().path_join("mihomo.exe")

func cleanup_helper_path() -> String:
	return runtime_dir().path_join("core_process_helper.ps1")

func controller_host() -> String:
	return CONTROLLER_HOST

func controller_port() -> int:
	return _controller_port

func mixed_port() -> int:
	return _mixed_port

func window_borderless() -> bool:
	return _window_borderless

func window_size() -> Vector2i:
	return Vector2i(_window_width, _window_height)

func set_window_settings(borderless: bool, width: int, height: int) -> void:
	_window_borderless = borderless
	_window_width = clampi(width, 800, 3840)
	_window_height = clampi(height, 600, 2160)
	_save_window_settings()

func set_ports(mixed: int, controller: int) -> Dictionary:
	if not _valid_port(mixed) or not _valid_port(controller):
		return {"ok": false, "message": "端口范围必须为 %d-%d。" % [MIN_PORT, MAX_PORT]}
	if mixed == controller:
		return {"ok": false, "message": "混合端口与控制端口不能相同。"}
	if not is_port_available(mixed):
		return {"ok": false, "message": "混合端口 %d 已被占用。" % mixed}
	if not is_port_available(controller):
		return {"ok": false, "message": "控制端口 %d 已被占用。" % controller}
	_mixed_port = mixed
	_controller_port = controller
	_save_ports()
	return {"ok": true, "message": "端口设置已保存。"}

func random_available_port(excluded_port := -1) -> int:
	for _attempt in 128:
		var candidate := randi_range(RANDOM_PORT_MIN, RANDOM_PORT_MAX)
		if candidate != excluded_port and is_port_available(candidate):
			return candidate
	for candidate in range(RANDOM_PORT_MIN, RANDOM_PORT_MAX + 1):
		if candidate != excluded_port and is_port_available(candidate):
			return candidate
	return -1

func is_port_available(port: int) -> bool:
	if not _valid_port(port):
		return false
	var server := TCPServer.new()
	var result := server.listen(port, CONTROLLER_HOST)
	server.stop()
	return result == OK

func apply_runtime_ports_to_profile() -> bool:
	var path := active_profile_path()
	if not FileAccess.file_exists(path):
		return true
	var content := FileAccess.get_file_as_string(path)
	var expression := RegEx.new()
	if expression.compile("(?m)^mixed-port\\s*:\\s*\\d+\\s*(?:#.*)?$") != OK:
		return false
	var replacement := "mixed-port: %d" % _mixed_port
	if expression.search(content) != null:
		content = expression.sub(content, replacement, true)
	else:
		content = replacement + "\n" + content
	return _write_text_atomic(path, content)

func _valid_port(port: int) -> bool:
	return port >= MIN_PORT and port <= MAX_PORT

func _load_ports() -> void:
	var settings := ConfigFile.new()
	if settings.load(SETTINGS_PATH) != OK:
		return
	var mixed := int(settings.get_value("network", "mixed_port", DEFAULT_MIXED_PORT))
	var controller := int(settings.get_value("network", "controller_port", DEFAULT_CONTROLLER_PORT))
	if _valid_port(mixed) and _valid_port(controller) and mixed != controller:
		_mixed_port = mixed
		_controller_port = controller
	_window_borderless = bool(settings.get_value("window", "borderless", true))
	_window_width = int(settings.get_value("window", "width", 1920))
	_window_height = int(settings.get_value("window", "height", 1080))

func _save_ports() -> void:
	var settings := ConfigFile.new()
	settings.set_value("network", "mixed_port", _mixed_port)
	settings.set_value("network", "controller_port", _controller_port)
	settings.save(SETTINGS_PATH)

func _save_window_settings() -> void:
	var settings := ConfigFile.new()
	settings.set_value("window", "borderless", _window_borderless)
	settings.set_value("window", "width", _window_width)
	settings.set_value("window", "height", _window_height)
	settings.save(SETTINGS_PATH)

func _write_text_atomic(path: String, content: String) -> bool:
	var temporary := path + ".ports.tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(content)
	file.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	if DirAccess.rename_absolute(temporary, path) != OK:
		DirAccess.remove_absolute(temporary)
		return false
	return true

func ensure_directories() -> void:
	DirAccess.make_dir_recursive_absolute(runtime_dir())
	DirAccess.make_dir_recursive_absolute(profile_dir())
	_install_bundled_core()
	_install_bundled_routing_rules()
	_install_cleanup_helper()

func has_core() -> bool:
	return _is_valid_core_executable(core_path())

func _is_valid_core_executable(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() < 2:
		return false
	var signature := file.get_buffer(2)
	file.close()
	return signature.size() == 2 and signature[0] == 0x4d and signature[1] == 0x5a

func _install_bundled_core() -> void:
	var destination := core_path()
	if _is_valid_core_executable(destination):
		return
	if not FileAccess.file_exists(BUNDLED_CORE_SOURCE):
		return
	var source := FileAccess.open(BUNDLED_CORE_SOURCE, FileAccess.READ)
	if source == null:
		return
	var temporary := destination + ".bundled.tmp"
	var target := FileAccess.open(temporary, FileAccess.WRITE)
	if target == null:
		source.close()
		return
	target.store_buffer(source.get_buffer(source.get_length()))
	target.close()
	source.close()
	if FileAccess.file_exists(destination):
		DirAccess.remove_absolute(destination)
	if DirAccess.rename_absolute(temporary, destination) != OK:
		DirAccess.remove_absolute(temporary)

func _install_bundled_routing_rules() -> void:
	var destination_dir := runtime_dir().path_join("rules")
	DirAccess.make_dir_recursive_absolute(destination_dir)
	for file_name in ["geosite-cn.mrs", "geoip-cn.mrs"]:
		var source_path := ROUTING_RULE_SOURCE_DIR.path_join(file_name)
		var source := FileAccess.open(source_path, FileAccess.READ)
		if source == null:
			continue
		var target := FileAccess.open(destination_dir.path_join(file_name), FileAccess.WRITE)
		if target != null:
			target.store_buffer(source.get_buffer(source.get_length()))
			target.close()
		source.close()

func _install_cleanup_helper() -> void:
	var source := FileAccess.open(CLEANUP_HELPER_SOURCE, FileAccess.READ)
	if source == null:
		return
	var target := FileAccess.open(cleanup_helper_path(), FileAccess.WRITE)
	if target != null:
		target.store_buffer(source.get_buffer(source.get_length()))
		target.close()
	source.close()
