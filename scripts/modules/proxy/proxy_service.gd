class_name ProxyService
extends Node

## Mihomo 代理生命周期服务
## 负责校验、旧进程清理、启动、停止和有限恢复

signal api_secret_changed(secret: String)
signal process_started(pid: int)
signal process_stopped
signal process_crashed
signal start_failed(message: String)

const ProxyProcessScript = preload("res://scripts/modules/proxy/proxy_process.gd")
const ProxyLauncherScript = preload("res://scripts/modules/proxy/proxy_launcher.gd")
const ProxyValidatorScript = preload("res://scripts/modules/proxy/proxy_validator.gd")
const ProxyCleanupScript = preload("res://scripts/modules/proxy/proxy_cleanup.gd")
const ProxyRecoveryScript = preload("res://scripts/modules/proxy/proxy_recovery.gd")
const ProxyConfigScript = preload("res://scripts/modules/proxy/proxy_config.gd")
const RuntimeProfilePipelineScript = preload("res://scripts/modules/proxy/runtime_profile_pipeline.gd")
const PortProfileTransformerScript = preload("res://scripts/modules/proxy/port_profile_transformer.gd")
const TunProfileTransformerScript = preload("res://scripts/modules/proxy/tun_profile_transformer.gd")

var process
var launcher
var validator
var cleanup
var recovery
var config
var profile_pipeline
var port_profile_transformer
var tun_profile_transformer
var online := false
var starting := false
var api_secret := ""
var desired_running := false
var _start_generation := 0

func _ready() -> void:
	_ensure_components()

func _ensure_components() -> void:
	if process != null:
		return
	process = ProxyProcessScript.new()
	launcher = ProxyLauncherScript.new()
	validator = ProxyValidatorScript.new()
	cleanup = ProxyCleanupScript.new()
	recovery = ProxyRecoveryScript.new()
	config = ProxyConfigScript.new()
	profile_pipeline = RuntimeProfilePipelineScript.new()
	port_profile_transformer = PortProfileTransformerScript.new()
	port_profile_transformer.setup(config)
	profile_pipeline.register_transformer("runtime_ports", port_profile_transformer, 10)
	tun_profile_transformer = TunProfileTransformerScript.new()
	tun_profile_transformer.setup(config)
	profile_pipeline.register_transformer("tun_mode", tun_profile_transformer, 20)
	add_child(process)
	add_child(launcher)
	add_child(validator)
	add_child(cleanup)
	add_child(recovery)
	config.ensure_directories()
	launcher.setup(process)
	validator.setup(config.core_path(), config.runtime_dir(), config.active_profile_path())
	process.process_started.connect(_on_process_started)
	process.process_stopped.connect(_on_process_stopped)
	process.process_crashed.connect(_on_process_crashed)
	recovery.recovery_requested.connect(_on_recovery_requested)
	recovery.recovery_exhausted.connect(_on_recovery_exhausted)

func get_config():
	_ensure_components()
	return config

func register_profile_transformer(id: String, transformer, priority := 100) -> void:
	_ensure_components()
	profile_pipeline.register_transformer(id, transformer, priority)

func unregister_profile_transformer(id: String) -> void:
	_ensure_components()
	profile_pipeline.unregister_transformer(id)

func start() -> void:
	_ensure_components()
	if desired_running and is_running():
		return
	desired_running = true
	recovery.reset()
	_start_generation += 1
	_start_internal(_start_generation)

func _start_internal(generation: int) -> void:
	if not desired_running or generation != _start_generation:
		return
	starting = true
	online = false
	config.ensure_directories()
	var transform_result: Dictionary = profile_pipeline.apply(config.active_profile_path(), {"config": config})
	if not bool(transform_result.get("ok", false)):
		_fail_start(str(transform_result.get("message", "无法处理运行配置")))
		return
	validator.setup(config.core_path(), config.runtime_dir(), config.active_profile_path())
	var validation: Dictionary = validator.validate()
	if not bool(validation.get("ok", false)):
		_fail_start(str(validation.get("message", "配置校验失败")))
		return
	var occupied := _occupied_ports()
	if not occupied.is_empty():
		_fail_start("端口 %s 已被占用" % ", ".join(occupied))
		return
	if OS.get_name() == "Windows":
		if not cleanup.begin(config.core_path(), config.cleanup_helper_path()):
			_fail_start("旧内核清理助手启动失败")
			return
		var cleaned: bool = await cleanup.wait_for_completion()
		if not cleaned:
			_fail_start("旧内核清理失败或超时")
			return
	if not desired_running or generation != _start_generation:
		starting = false
		return
	api_secret = Crypto.new().generate_random_bytes(24).hex_encode()
	api_secret_changed.emit(api_secret)
	var launched: bool = launcher.launch_mihomo(
		config.core_path(),
		config.runtime_dir(),
		config.active_profile_path(),
		config.controller_host(),
		config.controller_port(),
		api_secret
	)
	if not launched:
		_fail_start("Mihomo 启动失败")
func stop() -> void:
	_ensure_components()
	desired_running = false
	_start_generation += 1
	recovery.cancel()
	cleanup.stop()
	starting = false
	online = false
	api_secret = ""
	api_secret_changed.emit("")
	launcher.stop()

func restart() -> void:
	stop()
	await get_tree().process_frame
	start()

func set_online_state(value: bool) -> void:
	_ensure_components()
	online = value
	if value:
		starting = false
		recovery.reset()
	elif not process.is_running():
		starting = false

func is_running() -> bool:
	_ensure_components()
	return online or starting or process.is_running()

func _on_process_started(pid: int) -> void:
	starting = true
	process_started.emit(pid)

func _on_process_stopped() -> void:
	starting = false
	online = false
	process_stopped.emit()

func _on_process_crashed() -> void:
	starting = false
	online = false
	process_crashed.emit()
	if desired_running:
		recovery.schedule()

func _on_recovery_requested(_attempt: int) -> void:
	if not desired_running:
		return
	_start_generation += 1
	_start_internal(_start_generation)
func _on_recovery_exhausted() -> void:
	desired_running = false
	_fail_start("自动恢复失败，请检查配置或端口")

func _fail_start(message: String) -> void:
	starting = false
	online = false
	start_failed.emit(message)

func _occupied_ports() -> PackedStringArray:
	_ensure_components()
	var occupied := PackedStringArray()
	for port in [config.mixed_port(), config.controller_port()]:
		var server := TCPServer.new()
		var result := server.listen(port, config.controller_host())
		server.stop()
		if result != OK:
			occupied.append(str(port))
	return occupied

func dispose() -> void:
	stop()
