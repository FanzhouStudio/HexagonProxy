class_name LinuxWorkspaceService
extends Node

signal state_changed(state: Dictionary)
signal event_logged(message: String)

const BUNDLE := "res://third_party/linux_runtime/runtime.zip"
const MIN_DISK_GB := 1
const MAX_DISK_GB := 10
const GIB := 1073741824
# Reserve metadata headroom so the qcow2 file, not only its guest payload, fits the cap.
const DISK_METADATA_RESERVE := 16 * 1024 * 1024

var storage_override := ""
var disk_gb := 10
var status := "尚未安装"
var busy := false
var workspace_ready := false
var last_error := ""
var process_id := -1
var web_port := 0
var _control_port := 0
var _thread: Thread
var _operation := ""
var _password := ""
var _token := ""
var _poll_elapsed := 0.0
var _boot_deadline := 0
var _log_offset := 0
var _health: HTTPRequest
var _health_pending := false
var _disposing := false
var _stopping := false
var _control: StreamPeerTCP
var _child: Dictionary = {}
var _boot_tail := ""

func storage_dir() -> String:
	return storage_override if not storage_override.is_empty() else ProjectSettings.globalize_path("user://linux_workspace")

func runtime_dir() -> String:
	return storage_dir().path_join("runtime")

func disk_path() -> String:
	return storage_dir().path_join("linux.qcow2")

static func virtual_disk_bytes(capacity_gb: int) -> int:
	return clampi(capacity_gb, MIN_DISK_GB, MAX_DISK_GB) * GIB - DISK_METADATA_RESERVE

func initialize() -> void:
	DirAccess.make_dir_recursive_absolute(storage_dir())
	var config := ConfigFile.new()
	if config.load(storage_dir().path_join("settings.cfg")) == OK:
		disk_gb = clampi(int(config.get_value("disk", "capacity_gb", 10)), MIN_DISK_GB, MAX_DISK_GB)
		_password = str(config.get_value("login", "password", ""))
		_token = str(config.get_value("control", "token", ""))
	status = "已安装 · 已停止" if FileAccess.file_exists(disk_path()) else "尚未安装"
	_health = HTTPRequest.new()
	_health.timeout = 2.0
	add_child(_health)
	_health.request_completed.connect(_on_health_completed)
	set_process(false)

func snapshot() -> Dictionary:
	var allocated := 0
	if FileAccess.file_exists(disk_path()):
		var file := FileAccess.open(disk_path(), FileAccess.READ)
		if file:
			allocated = file.get_length()
	return {"status": status, "busy": busy, "running": process_id > 0, "ready": workspace_ready,
		"installed": FileAccess.file_exists(disk_path()), "disk_gb": disk_gb,
		"disk_bytes": allocated, "error": last_error, "path": storage_dir(),
		"url": "http://127.0.0.1:%d" % web_port if workspace_ready else "",
		"bundle_available": FileAccess.file_exists(BUNDLE)}

func start_workspace(capacity_gb: int = 10) -> bool:
	if busy or process_id > 0 or _disposing:
		return false
	if OS.get_name() != "Windows":
		_fail("当前内置 QEMU 运行包仅支持 Windows x64。")
		return false
	if capacity_gb < MIN_DISK_GB or capacity_gb > MAX_DISK_GB:
		_fail("磁盘容量必须在 1～10 GB 之间。")
		return false
	if FileAccess.file_exists(disk_path()) and capacity_gb < disk_gb:
		_fail("已有系统盘不能缩小，请选择当前容量或更大的容量（最大 10 GB）。")
		return false
	if _password.is_empty():
		if FileAccess.file_exists(disk_path()):
			_fail("本地登录凭据缺失，系统盘已保留。请恢复 settings.cfg 或明确重建系统盘。")
			return false
		_password = Crypto.new().generate_random_bytes(16).hex_encode()
		_token = Crypto.new().generate_random_bytes(24).hex_encode()
	_operation = "prepare"
	busy = true
	last_error = ""
	status = "正在准备离线 Linux 环境…"
	_emit()
	_thread = Thread.new()
	var error := _thread.start(_prepare_worker.bind(capacity_gb))
	if error != OK:
		_thread = null
		_fail("无法启动安装线程：%s" % error_string(error))
		return false
	set_process(true)
	return true

func _process(delta: float) -> void:
	if _thread != null and not _thread.is_alive():
		var result: Dictionary = _thread.wait_to_finish()
		_thread = null
		if not bool(result.get("ok", false)):
			_fail(str(result.get("message", "Linux 环境准备失败。")))
		elif not _disposing:
			disk_gb = int(result.disk_gb)
			_launch(bool(result.install))
	_poll_elapsed += delta
	if process_id <= 0 or _poll_elapsed < 1.0:
		return
	_poll_elapsed = 0.0
	_read_boot_log()
	_read_process_error()
	if not OS.is_process_running(process_id):
		process_id = -1
		workspace_ready = false
		if _stopping:
			_stopping = false
			busy = false
			status = "已停止 · 文件已保留"
			_emit()
		elif last_error.is_empty():
			_fail("QEMU 已退出；系统盘已保留。\n" + _qemu_error() + "\n" + _boot_tail.right(1400))
		else:
			busy = false
			status = "已停止"
			_emit()
		_close_pipes()
		set_process(false)
		return
	if not workspace_ready and not _stopping and Time.get_ticks_msec() > _boot_deadline:
		# Leave the process and disk intact for diagnosis; never silently kill a writing guest.
		busy = false
		last_error = "Linux 启动尚未完成，可查看日志或停止后重试。软件模拟首次初始化可能较慢。"
		_emit()
		_boot_deadline = Time.get_ticks_msec() + 120000
	if not workspace_ready and not _health_pending and not _stopping:
		_health_pending = _health.request("http://127.0.0.1:%d/" % web_port) == OK

func _launch(install: bool) -> void:
	web_port = _free_port()
	_control_port = _free_port(web_port)
	if web_port <= 0 or _control_port <= 0:
		_fail("无法分配本地 Linux 工作区端口。")
		return
	_log_offset = 0
	_boot_tail = ""
	for filename in ["serial.log", "qemu-error.log"]:
		var file := FileAccess.open(storage_dir().path_join(filename), FileAccess.WRITE)
		if file:
			file.close()
	var args := launch_arguments(install)
	_child = OS.execute_with_pipe(runtime_dir().path_join("qemu/qemu-system-x86_64.exe"), args, false)
	process_id = int(_child.get("pid", -1))
	if process_id <= 0:
		_fail("无法启动内置 QEMU。请检查运行文件是否被安全软件隔离。")
		return
	_boot_deadline = Time.get_ticks_msec() + 180000
	status = "首次初始化系统盘…" if install else "Linux 正在启动…"
	_emit()

func launch_arguments(install: bool) -> PackedStringArray:
	var args := PackedStringArray(["-name", "HexagonProxy Linux", "-machine", "q35", "-accel", "tcg,thread=multi",
		"-smp", "2", "-m", "512", "-display", "none", "-monitor", "none", "-no-reboot",
		"-L", runtime_dir().path_join("qemu/share"), "-kernel", runtime_dir().path_join("vmlinuz"),
		"-initrd", storage_dir().path_join("boot-initramfs.gz"), "-append",
		"console=ttyS0 panic=5" + (" hexagon.install=1" if install else ""),
		"-drive", "file=%s,format=qcow2,if=virtio,discard=unmap" % _qemu_path(disk_path()),
		"-netdev", "user,id=net0,hostfwd=tcp:127.0.0.1:%d-:80" % web_port,
		"-device", "virtio-net-pci,netdev=net0", "-serial", "file:" + storage_dir().path_join("serial.log"),
		"-chardev", "socket,id=control,host=127.0.0.1,port=%d,server=on,wait=off" % _control_port,
		"-serial", "chardev:control", "-D", storage_dir().path_join("qemu-error.log")])
	if install:
		args.append_array(PackedStringArray(["-drive", "file=%s,format=raw,if=virtio,readonly=on" % _qemu_path(runtime_dir().path_join("rootfs.tar.gz"))]))
	return args

func stop_workspace() -> void:
	if process_id <= 0 or _stopping:
		return
	_stopping = true
	busy = true
	workspace_ready = false
	status = "正在保存文件并关闭 Linux…"
	_emit()
	_control = StreamPeerTCP.new()
	var error := _control.connect_to_host("127.0.0.1", _control_port)
	if error == OK:
		for index in 30:
			_control.poll()
			if _control.get_status() == StreamPeerTCP.STATUS_CONNECTED:
				_control.put_data(("shutdown:%s\n" % _token).to_utf8_buffer())
				return
			await get_tree().create_timer(0.05).timeout
	_stopping = false
	busy = false
	last_error = "关闭指令未送达，Linux 可能仍在初始化。请稍后重试，系统盘未被强制断电。"
	_emit()

func shutdown() -> bool:
	_disposing = true
	set_process(false)
	if _thread != null:
		# Do not block the UI thread while archive verification is running.
		while _thread.is_alive():
			await get_tree().create_timer(0.1).timeout
		_thread.wait_to_finish()
		_thread = null
	if process_id > 0:
		stop_workspace()
		var deadline := Time.get_ticks_msec() + 15000
		while process_id > 0 and OS.is_process_running(process_id) and Time.get_ticks_msec() < deadline:
			await get_tree().create_timer(0.1).timeout
		if OS.is_process_running(process_id):
			_disposing = false
			set_process(true)
			_stopping = false
			busy = false
			last_error = "Linux 仍在保存或初始化。为保留磁盘数据，本次退出已取消，请稍后停止工作区再退出。"
			_emit()
			return false
	process_id = -1
	return true

func dispose() -> void:
	if _health:
		_health.cancel_request()
	_close_pipes()

func _close_pipes() -> void:
	for key in ["stdio", "stderr"]:
		if _child.has(key):
			_child[key].close()
	_child.clear()

func copy_password() -> void:
	if not _password.is_empty():
		DisplayServer.clipboard_set(_password)

func open_workspace() -> void:
	if workspace_ready:
		OS.shell_open("http://127.0.0.1:%d/" % web_port)

func _on_health_completed(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	_health_pending = false
	if not workspace_ready and not _stopping and process_id > 0 and result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 400:
		workspace_ready = true
		busy = false
		last_error = ""
		status = "运行中 · Linux 工作区已就绪"
		DirAccess.remove_absolute(storage_dir().path_join("needs-install"))
		_emit()

func _prepare_worker(capacity: int) -> Dictionary:
	var result := _extract_bundle()
	if not result.get("ok", false):
		return result
	var new_disk := not FileAccess.file_exists(disk_path())
	var install := new_disk or FileAccess.file_exists(storage_dir().path_join("needs-install"))
	var img := runtime_dir().path_join("qemu/qemu-img.exe")
	var output: Array = []
	var measure_args := PackedStringArray(["measure", "--output=json", "-O", "qcow2", "-o", "cluster_size=65536,lazy_refcounts=on", "--size", str(virtual_disk_bytes(capacity))])
	if OS.execute(img, measure_args, output, true, false) != 0:
		return {"ok": false, "message": "无法校验磁盘最大占用：" + "\n".join(output).left(1000)}
	var measured: Variant = JSON.parse_string("\n".join(output))
	if not measured is Dictionary or int(measured.get("fully-allocated", capacity * GIB + 1)) > capacity * GIB:
		return {"ok": false, "message": "镜像含元数据的最大占用超过所选容量，已取消创建。"}
	output.clear()
	var args := PackedStringArray(["create", "-f", "qcow2", "-o", "cluster_size=65536,lazy_refcounts=on", disk_path() + ".partial", str(virtual_disk_bytes(capacity))]) if new_disk else PackedStringArray(["resize", disk_path(), str(virtual_disk_bytes(capacity))])
	if new_disk:
		var marker := FileAccess.open(storage_dir().path_join("needs-install"), FileAccess.WRITE)
		if not marker:
			return {"ok": false, "message": "无法写入安装状态。"}
		marker.close()
	if new_disk or capacity > disk_gb:
		if OS.execute(img, args, output, true, false) != 0:
			return {"ok": false, "message": "系统盘创建/扩容失败：" + "\n".join(output).left(1800)}
		if new_disk and DirAccess.rename_absolute(disk_path() + ".partial", disk_path()) != OK:
			return {"ok": false, "message": "无法保存新系统盘。"}
	var config := ConfigFile.new()
	config.set_value("disk", "capacity_gb", capacity)
	config.set_value("login", "password", _password)
	config.set_value("control", "token", _token)
	if config.save(storage_dir().path_join("settings.cfg")) != OK:
		return {"ok": false, "message": "无法保存 Linux 工作区设置。"}
	var initrd := FileAccess.get_file_as_bytes(runtime_dir().path_join("initramfs.gz"))
	var seed := "LOGIN_PASSWORD='%s'\nCONTROL_TOKEN='%s'\n" % [_password, _token]
	initrd.append_array(_seed_archive(seed).compress(FileAccess.COMPRESSION_GZIP))
	var file := FileAccess.open(storage_dir().path_join("boot-initramfs.gz"), FileAccess.WRITE)
	if not file:
		return {"ok": false, "message": "无法写入 Linux 启动文件。"}
	file.store_buffer(initrd)
	file.close()
	# Credentials stay in the current user's Windows app-data directory, never
	# in the application folder, logs, or child-process command arguments.
	return {"ok": true, "install": install, "disk_gb": capacity}

func reset_workspace() -> void:
	if busy or process_id > 0:
		return
	for name in ["linux.qcow2", "linux.qcow2.partial", "needs-install", "boot-initramfs.gz"]:
		var target := storage_dir().path_join(name)
		if FileAccess.file_exists(target) and DirAccess.remove_absolute(target) != OK:
			_fail("无法删除系统盘文件：" + name)
			return
	last_error = ""
	status = "尚未安装"
	_password = ""
	_token = ""
	_emit()

func _extract_bundle() -> Dictionary:
	if FileAccess.file_exists(runtime_dir().path_join(".verified")):
		return {"ok": true}
	var reader := ZIPReader.new()
	if reader.open(BUNDLE) != OK:
		return {"ok": false, "message": "离线 Linux 运行包缺失，请使用包含 QEMU 资源的完整 HexagonProxy 安装包。"}
	var manifest: Variant = JSON.parse_string(reader.read_file("manifest.json").get_string_from_utf8())
	if not manifest is Dictionary or not manifest.get("files") is Array:
		reader.close()
		return {"ok": false, "message": "Linux 运行包清单无效。"}
	for entry in manifest.files:
		var name := str(entry.get("path", ""))
		if not safe_bundle_path(name):
			reader.close()
			return {"ok": false, "message": "Linux 运行包包含非法路径。"}
		var data := reader.read_file(name)
		var hash := HashingContext.new()
		hash.start(HashingContext.HASH_SHA256)
		if not data.is_empty():
			hash.update(data)
		if data.size() != int(entry.get("size", -1)) or hash.finish().hex_encode() != str(entry.get("sha256", "")):
			reader.close()
			return {"ok": false, "message": "Linux 运行文件校验失败：" + name}
		var target := runtime_dir().path_join(name)
		DirAccess.make_dir_recursive_absolute(target.get_base_dir())
		var file := FileAccess.open(target, FileAccess.WRITE)
		if not file:
			reader.close()
			return {"ok": false, "message": "无法写入 Linux 运行文件：" + name}
		file.store_buffer(data)
		file.close()
	reader.close()
	var marker := FileAccess.open(runtime_dir().path_join(".verified"), FileAccess.WRITE)
	if not marker:
		return {"ok": false, "message": "无法保存运行包校验状态。"}
	marker.store_string("1")
	return {"ok": true}

static func safe_bundle_path(name: String) -> bool:
	return not name.is_empty() and not name.is_absolute_path() and not ":" in name and not "\\" in name and not ".." in name.split("/")

static func _seed_archive(seed: String) -> PackedByteArray:
	var result := PackedByteArray()
	for item in [["init", FileAccess.get_file_as_bytes("res://scripts/linux/init.sh"), 33261],
		["hexagon/guest-init", FileAccess.get_file_as_bytes("res://scripts/linux/guest-init.sh"), 33261],
		["hexagon/seed.env", seed.to_utf8_buffer(), 33152], ["TRAILER!!!", PackedByteArray(), 0]]:
		var name: PackedByteArray = str(item[0]).to_ascii_buffer()
		name.append(0)
		var data: PackedByteArray = item[1]
		var header := "070701"
		for value in [1, item[2], 0, 0, 1, 0, data.size(), 0, 0, 0, 0, name.size(), 0]:
			header += "%08x" % int(value)
		result.append_array(header.to_ascii_buffer())
		result.append_array(name)
		while result.size() % 4 != 0:
			result.append(0)
		result.append_array(data)
		while result.size() % 4 != 0:
			result.append(0)
	return result

static func _qemu_path(value: String) -> String:
	return value.replace("\\", "/").replace(",", ",,")

func _free_port(exclude: int = 0) -> int:
	var listener := TCPServer.new()
	for attempt in 30:
		var candidate := randi_range(21000, 49000)
		if candidate != exclude and listener.listen(candidate, "127.0.0.1") == OK:
			listener.stop()
			return candidate
	return 0

func _read_boot_log() -> void:
	var file := FileAccess.open(storage_dir().path_join("serial.log"), FileAccess.READ)
	if not file:
		return
	file.seek(_log_offset)
	var text := file.get_buffer(mini(file.get_length() - _log_offset, 65536)).get_string_from_utf8()
	_boot_tail = (_boot_tail + text).right(2000)
	_log_offset = file.get_position()
	for line in text.split("\n"):
		if line.contains("HEXAGON_ERROR:"):
			last_error = line.strip_edges()
			busy = false
			_emit()

func _qemu_error() -> String:
	return FileAccess.get_file_as_string(storage_dir().path_join("qemu-error.log")).right(1200)

func _read_process_error() -> void:
	if _child.has("stderr"):
		var data: PackedByteArray = _child.stderr.get_buffer(8192)
		if not data.is_empty():
			var file := FileAccess.open(storage_dir().path_join("qemu-error.log"), FileAccess.READ_WRITE)
			if file:
				file.seek_end()
				file.store_buffer(data)

func _fail(message: String) -> void:
	busy = false
	last_error = message
	status = "操作失败"
	_emit()

func _emit() -> void:
	state_changed.emit(snapshot())
	if not last_error.is_empty():
		event_logged.emit("Linux 工作区：" + last_error)
