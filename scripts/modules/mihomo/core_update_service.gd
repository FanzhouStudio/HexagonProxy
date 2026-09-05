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

var proxy_config
var archive_installer = CoreArchiveInstallerScript.new()
var _request: HTTPRequest
var _archive_path := ""
var _expected_sha256 := ""

func bind_config(config) -> void:
	proxy_config = config

func _ensure_config() -> void:
	if proxy_config == null:
		proxy_config = ProxyConfigScript.new()

func is_busy() -> bool:
	return _request != null

func download_latest() -> void:
	if is_busy():
		return
	DirAccess.make_dir_recursive_absolute(runtime_dir())
	_archive_path = ""
	_expected_sha256 = ""
	progress_changed.emit(0.02, "正在查询 Mihomo 最新版本…")
	_request = HTTPRequest.new()
	_request.timeout = 25.0
	_request.max_redirects = 8
	add_child(_request)
	_request.request_completed.connect(_on_release_received)
	var error := _request.request(RELEASE_API, [
		"Accept: application/vnd.github+json",
		"User-Agent: %s" % USER_AGENT
	])
	if error != OK:
		_finish(false, "无法连接 GitHub（%s）" % error_string(error))

func _on_release_received(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_clear_request()
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		_finish(false, "查询版本失败，HTTP %d" % response_code)
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
	progress_changed.emit(0.12, "正在下载 %s…" % asset_name)
	_request = HTTPRequest.new()
	_request.timeout = 180.0
	_request.max_redirects = 8
	_archive_path = runtime_dir().path_join(
		"mihomo-download.gz" if asset_name.ends_with(".gz") else "mihomo-download.zip"
	)
	_request.download_file = _archive_path
	add_child(_request)
	_request.request_completed.connect(_on_archive_received)
	var error := _request.request(url, ["User-Agent: %s" % USER_AGENT])
	if error != OK:
		_finish(false, "内核下载无法开始（%s）" % error_string(error))

func _on_archive_received(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	_clear_request()
	if result != HTTPRequest.RESULT_SUCCESS or response_code not in [200, 206]:
		_finish(false, "内核下载失败，HTTP %d" % response_code)
		return
	if not _expected_sha256.is_empty():
		var actual_digest := FileAccess.get_sha256(_archive_path)
		if actual_digest.to_lower() != _expected_sha256.to_lower():
			_finish(false, "内核校验失败，已拒绝安装")
			return
	progress_changed.emit(0.82, "正在安装内核…")
	var install_result: Dictionary = archive_installer.install_archive(_archive_path, core_path())
	_finish(bool(install_result.get("ok", false)), str(install_result.get("message", "安装内核失败")))

func _finish(success: bool, message: String) -> void:
	_clear_request()
	if not _archive_path.is_empty() and FileAccess.file_exists(_archive_path):
		DirAccess.remove_absolute(_archive_path)
	_archive_path = ""
	_expected_sha256 = ""
	progress_changed.emit(1.0 if success else -1.0, message)
	event_logged.emit(message)
	finished.emit(success, message)

func cancel() -> void:
	if _request != null and is_instance_valid(_request):
		_request.cancel_request()
	_clear_request()
	if not _archive_path.is_empty() and FileAccess.file_exists(_archive_path):
		DirAccess.remove_absolute(_archive_path)
	_archive_path = ""
	_expected_sha256 = ""

func stop() -> void:
	cancel()

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
