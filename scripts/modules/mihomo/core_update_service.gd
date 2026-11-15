class_name CoreUpdateService
extends Node

## Mihomo 内核更新服务
## 负责版本查询、下载、哈希校验和安装流程；本地解包/替换交给 CoreArchiveInstaller。

signal progress_changed(progress: float, message: String)
signal event_logged(message: String)
signal finished(success: bool, message: String)

const ProxyConfigScript = preload("res://scripts/modules/proxy/proxy_config.gd")
const CoreArchiveInstallerScript = preload("res://scripts/modules/mihomo/core_archive_installer.gd")
const RELEASE_API := "https://api.github.com/repos/MetaCubeX/mihomo/releases/latest"
const USER_AGENT := "HexagonProxy"
const NATIVE_HELPER := "res://scripts/windows_core_download_helper.ps1"

var proxy_config
var archive_installer = CoreArchiveInstallerScript.new()
var _request: HTTPRequest
var _archive_path := ""
var _expected_sha256 := ""
var before_install: Callable
var download_proxy_port := 0
var _busy := false
var _generation := 0
var _native_pid := 0
var _native_files := PackedStringArray()
var _asset_url := ""

func bind_config(config) -> void:
	proxy_config = config

func _ensure_config() -> void:
	if proxy_config == null:
		proxy_config = ProxyConfigScript.new()

func is_busy() -> bool:
	return _busy

func download_latest() -> void:
	if is_busy():
		return
	_busy = true
	_generation += 1
	DirAccess.make_dir_recursive_absolute(runtime_dir())
	_archive_path = ""
	_expected_sha256 = ""
	progress_changed.emit(0.02, "正在查询 Mihomo 最新版本…")
	_request = HTTPRequest.new()
	_request.timeout = 25.0
	_request.max_redirects = 8
	add_child(_request)
	_configure_transport()
	_request.request_completed.connect(_on_release_received)
	var error := _request.request(RELEASE_API, [
		"Accept: application/vnd.github+json",
		"User-Agent: %s" % USER_AGENT
	])
	if error != OK:
		_finish(false, "无法连接 GitHub（%s）" % error_string(error))

func _on_release_received(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_clear_request()
	if _should_retry_native(result):
		var generation := _generation
		var native: Dictionary = await _native_download(RELEASE_API, "", 25)
		if generation != _generation:
			return
		if not native.get("ok", false):
			_finish(false, "查询版本失败：Windows HTTPS 重试失败（%s）" % native.get("message", "未知错误"))
			return
		body = native.get("body", PackedByteArray())
		result = HTTPRequest.RESULT_SUCCESS
		response_code = 200
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		_finish(false, _failure_message("查询版本", result, response_code))
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not parsed is Dictionary:
		_finish(false, "GitHub 返回了无法识别的数据")
		return
	var asset := _select_windows_asset(parsed.get("assets", []))
	var asset_url := str(asset.get("url", ""))
	var asset_name := str(asset.get("name", ""))
	_expected_sha256 = str(asset.get("sha256", ""))
	if asset_url.is_empty():
		_finish(false, "没有找到 Windows x64 内核压缩包")
		return
	_start_archive_download(asset_url, asset_name)

func _select_windows_asset(assets: Array) -> Dictionary:
	var fallback := {}
	for item in assets:
		if not item is Dictionary:
			continue
		var name := str(item.get("name", ""))
		var url := str(item.get("browser_download_url", ""))
		var digest_value: Variant = item.get("digest", "")
		var digest := "" if digest_value == null else str(digest_value).trim_prefix("sha256:")
		var supported := name.ends_with(".gz") or name.ends_with(".zip")
		if name.contains("windows-amd64-v3-v") and supported:
			return {"name": name, "url": url, "sha256": digest}
		if name.contains("windows-amd64") and supported and not name.contains("compatible"):
			fallback = {"name": name, "url": url, "sha256": digest}
	return fallback

func _start_archive_download(url: String, asset_name: String) -> void:
	_asset_url = url
	progress_changed.emit(0.12, "正在下载 %s…" % asset_name)
	_request = HTTPRequest.new()
	_request.timeout = 180.0
	# Preserve the release gzip bytes; archive decompression belongs to the installer.
	_request.accept_gzip = false
	_request.max_redirects = 8
	_archive_path = runtime_dir().path_join(
		"mihomo-download.gz" if asset_name.ends_with(".gz") else "mihomo-download.zip"
	)
	_request.download_file = _archive_path
	add_child(_request)
	_configure_transport()
	_request.request_completed.connect(_on_archive_received)
	var error := _request.request(url, ["User-Agent: %s" % USER_AGENT])
	if error != OK:
		_finish(false, "内核下载无法开始（%s）" % error_string(error))

func _on_archive_received(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	_clear_request()
	if _should_retry_native(result):
		var retry_generation := _generation
		var native: Dictionary = await _native_download(_asset_url, _archive_path, 180)
		if retry_generation != _generation:
			return
		if not native.get("ok", false):
			_finish(false, "内核下载失败：Windows HTTPS 重试失败（%s）" % native.get("message", "未知错误"))
			return
		result = HTTPRequest.RESULT_SUCCESS
		response_code = 200
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		_finish(false, _failure_message("内核下载", result, response_code))
		return
	if not _expected_sha256.is_empty():
		var actual_digest := FileAccess.get_sha256(_archive_path)
		if actual_digest.to_lower() != _expected_sha256.to_lower():
			_finish(false, "内核校验失败，已拒绝安装")
			return
	progress_changed.emit(0.82, "正在安装内核…")
	var generation := _generation
	if before_install.is_valid():
		var ready: bool = await before_install.call()
		if generation != _generation:
			return
		if not ready:
			_finish(false, "无法停止旧内核，已取消替换并保留原版本")
			return
	var install_result: Dictionary = archive_installer.install_archive(_archive_path, core_path())
	_finish(bool(install_result.get("ok", false)), str(install_result.get("message", "安装内核失败")))

func _finish(success: bool, message: String) -> void:
	_busy = false
	_clear_request()
	if not _archive_path.is_empty() and FileAccess.file_exists(_archive_path):
		DirAccess.remove_absolute(_archive_path)
	_archive_path = ""
	_expected_sha256 = ""
	progress_changed.emit(1.0 if success else -1.0, message)
	event_logged.emit(message)
	finished.emit(success, message)

func cancel() -> void:
	_generation += 1
	if _native_pid > 0 and OS.is_process_running(_native_pid):
		OS.kill(_native_pid)
	_native_pid = 0
	_clear_native_files()
	_busy = false
	if _request != null and is_instance_valid(_request):
		_request.cancel_request()
	_clear_request()
	if not _archive_path.is_empty() and FileAccess.file_exists(_archive_path):
		DirAccess.remove_absolute(_archive_path)
	_archive_path = ""
	_expected_sha256 = ""

func stop() -> void:
	cancel()

func _exit_tree() -> void:
	cancel()

func _should_retry_native(result: int) -> bool:
	return OS.get_name() == "Windows" and result in [
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR, HTTPRequest.RESULT_CANT_CONNECT,
		HTTPRequest.RESULT_CANT_RESOLVE, HTTPRequest.RESULT_CONNECTION_ERROR,
		HTTPRequest.RESULT_TIMEOUT,
	]

func _native_download(url: String, destination: String, timeout_seconds: int) -> Dictionary:
	progress_changed.emit(0.12 if not destination.is_empty() else 0.03, "正在使用 Windows HTTPS 重试…")
	var helper := runtime_dir().path_join("windows_core_download_helper.ps1")
	var helper_file := FileAccess.open(helper, FileAccess.WRITE)
	if helper_file == null:
		return {"ok": false, "message": "无法写入下载助手"}
	helper_file.store_string(FileAccess.get_file_as_string(NATIVE_HELPER))
	helper_file.close()
	var prefix := runtime_dir().path_join("core-request-%d" % Time.get_ticks_usec())
	var result_path := prefix + ".json"
	var output_path := destination if not destination.is_empty() else prefix + ".body"
	_native_files = PackedStringArray([result_path, result_path + ".tmp"])
	if destination.is_empty():
		_native_files.append(output_path)
	var generation := _generation
	_native_pid = OS.create_process("powershell.exe", PackedStringArray([
		"-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "RemoteSigned",
		"-File", helper, "-Url", url, "-OutputPath", output_path,
		"-ResultPath", result_path, "-ProxyPort", str(download_proxy_port),
		"-TimeoutSeconds", str(timeout_seconds),
	]), false)
	if _native_pid <= 0:
		_clear_native_files()
		return {"ok": false, "message": "无法启动 Windows 下载助手"}
	var deadline := Time.get_ticks_msec() + (timeout_seconds + 10) * 1000
	while not FileAccess.file_exists(result_path):
		if generation != _generation:
			return {"ok": false, "message": "下载已取消"}
		if not OS.is_process_running(_native_pid) or Time.get_ticks_msec() >= deadline:
			if OS.is_process_running(_native_pid):
				OS.kill(_native_pid)
			_native_pid = 0
			_clear_native_files()
			return {"ok": false, "message": "下载助手退出或请求超时"}
		await get_tree().create_timer(0.1).timeout
	_native_pid = 0
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(result_path))
	var response: Dictionary = parsed if parsed is Dictionary else {"ok": false, "message": "下载助手返回格式异常"}
	if response.get("ok", false) and destination.is_empty():
		response["body"] = FileAccess.get_file_as_bytes(output_path)
	_clear_native_files()
	return response

func _clear_native_files() -> void:
	for path in _native_files:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	_native_files.clear()

func _configure_transport() -> void:
	if download_proxy_port > 0:
		_request.set_http_proxy("127.0.0.1", download_proxy_port)
		_request.set_https_proxy("127.0.0.1", download_proxy_port)

func _failure_message(stage: String, result: int, status: int) -> String:
	var reason := "请求失败（网络结果 %d）" % result
	match result:
		HTTPRequest.RESULT_CANT_RESOLVE: reason = "DNS 解析失败"
		HTTPRequest.RESULT_CANT_CONNECT: reason = "无法连接下载服务器或本地代理"
		HTTPRequest.RESULT_CONNECTION_ERROR: reason = "连接中断"
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR: reason = "TLS 握手失败，请检查系统时间及证书"
		HTTPRequest.RESULT_TIMEOUT: reason = "请求超时"
		HTTPRequest.RESULT_DOWNLOAD_FILE_CANT_OPEN: reason = "无法创建下载文件，请检查目录权限"
		HTTPRequest.RESULT_DOWNLOAD_FILE_WRITE_ERROR: reason = "下载文件写入失败，请检查磁盘空间"
		HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED: reason = "重定向次数过多"
		HTTPRequest.RESULT_SUCCESS: reason = "服务器返回 HTTP %d" % status
	var route := "本地代理" if download_proxy_port > 0 else "直连；如无法访问 GitHub，请先连接代理再更新"
	return "%s失败：%s（%s）" % [stage, reason, route]

func _clear_request() -> void:
	if _request != null and is_instance_valid(_request):
		_request.queue_free()
	_request = null

func runtime_dir() -> String:
	_ensure_config()
	return proxy_config.runtime_dir()

func core_path() -> String:
	_ensure_config()
	return proxy_config.core_path()
