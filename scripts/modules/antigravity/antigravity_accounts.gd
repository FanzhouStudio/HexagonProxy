extends Node

const HELPER := "res://scripts/windows_antigravity_accounts_helper.ps1"
const WORKSPACE_HELPER := "res://scripts/windows_antigravity_workspace_helper.ps1"
var workspace_home_override := ""
var storage := ""
var entries: Array = []
var selected := "default"
var busy := false
var quotas: Dictionary = {}

func initialize(path: String) -> void:
	storage = path
	DirAccess.make_dir_recursive_absolute(storage)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(storage.path_join("index.json"))) if FileAccess.file_exists(storage.path_join("index.json")) else {}
	if parsed is Dictionary:
		if parsed.get("quotas", {}) is Dictionary:
			quotas = parsed.get("quotas", {})
		for item in parsed.get("entries", []):
			if item is Dictionary and str(item.get("id", "")).length() == 32 and str(item.id).is_valid_hex_number(false):
				entries.append(item)
		selected = str(parsed.get("selected", "default"))
	if not exists(selected):
		selected = "default"

func exists(id: String) -> bool:
	return id == "default" or entries.any(func(item: Dictionary) -> bool: return item.id == id)

func list() -> Array:
	return [{"id": "default", "name": "默认账号（原有配置）"}] + entries.duplicate(true)

func save() -> bool:
	var path := storage.path_join("index.json")
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if not file:
		return false
	file.store_string(JSON.stringify({"entries": entries, "selected": selected, "quotas": quotas}))
	file.close()
	return DirAccess.rename_absolute(path + ".tmp", path) == OK

func add(name: String) -> Dictionary:
	name = name.strip_edges()
	if name.is_empty():
		name = "Antigravity 账号 %d" % (entries.size() + 1)
	if busy or name.length() > 60:
		return {"ok": false, "message": "请输入 1–60 字账号备注，并等待操作完成。"}
	if entries.any(func(item: Dictionary) -> bool: return str(item.name).nocasecmp_to(name) == 0):
		return {"ok": false, "message": "账号备注已存在。"}
	var id := Crypto.new().generate_random_bytes(16).hex_encode()
	entries.append({"id": id, "name": name})
	if not save():
		entries.pop_back()
		return {"ok": false, "message": "账号列表保存失败。"}
	return {"ok": true, "id": id, "message": "账号已添加，正在打开官方登录窗口。"}

func run(action: String, id: String, executable: String) -> Dictionary:
	if busy or not exists(id) or action not in ["launch", "quota"]:
		return {"ok": false, "message": "操作繁忙或账号不存在。"}
	busy = true
	var helper := storage.path_join("helper.ps1")
	var file := FileAccess.open(helper, FileAccess.WRITE)
	if not file:
		busy = false
		return {"ok": false, "message": "无法写入账号助手。"}
	# Godot's UTF-8 string conversion strips a leading BOM. Write its bytes
	# explicitly: Windows PowerShell 5.1 otherwise parses Chinese as ANSI.
	file.store_buffer(PackedByteArray([0xef, 0xbb, 0xbf]))
	file.store_buffer(FileAccess.get_file_as_string(HELPER).trim_prefix("\ufeff").to_utf8_buffer())
	file.close()
	var workspace_file := FileAccess.open(storage.path_join("windows_antigravity_workspace_helper.ps1"), FileAccess.WRITE)
	if not workspace_file:
		busy = false
		return {"ok": false, "message": "无法准备共享工作区助手。"}
	workspace_file.store_buffer(PackedByteArray([0xef, 0xbb, 0xbf]))
	workspace_file.store_buffer(FileAccess.get_file_as_string(WORKSPACE_HELPER).trim_prefix("\ufeff").to_utf8_buffer())
	workspace_file.close()
	var result_path := storage.path_join("result-%d.json" % Time.get_ticks_usec())
	var args := PackedStringArray(["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "RemoteSigned", "-File", helper, "-Action", action, "-AccountId", id, "-Root", storage, "-ExePath", executable, "-ResultPath", result_path])
	if not workspace_home_override.is_empty():
		args.append_array(PackedStringArray(["-WorkspaceHome", workspace_home_override]))
	var child := OS.execute_with_pipe("powershell.exe", args, false)
	var pid := int(child.get("pid", -1))
	var stderr := ""
	var deadline := Time.get_ticks_msec() + 25000
	# Launch may migrate a large history. Keep its transaction alive rather than
	# killing the helper halfway through moving a workspace directory.
	while pid > 0 and not FileAccess.file_exists(result_path) and OS.is_process_running(pid) and (action == "launch" or Time.get_ticks_msec() < deadline):
		if child.has("stderr"):
			stderr += child.stderr.get_buffer(8192).get_string_from_utf8()
		if child.has("stdio"):
			child.stdio.get_buffer(8192)
		await get_tree().create_timer(0.1).timeout
	if child.has("stderr"):
		stderr += child.stderr.get_buffer(8192).get_string_from_utf8()
		child.stderr.close()
	if child.has("stdio"):
		child.stdio.close()
	var reason := "账号助手启动失败。" if pid <= 0 else "账号助手超时。" if Time.get_ticks_msec() >= deadline else "账号助手异常退出。"
	if not stderr.strip_edges().is_empty():
		reason += "\n" + stderr.strip_edges().left(1600)
	var result: Dictionary = {"ok": false, "message": reason}
	if FileAccess.file_exists(result_path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(result_path).trim_prefix("\ufeff"))
		if parsed is Dictionary:
			result = parsed
		DirAccess.remove_absolute(result_path)
	elif pid > 0 and OS.is_process_running(pid):
		OS.kill(pid)
	if action == "launch" and result.get("ok", false):
		selected = id
		if not save():
			result.message = "已打开配置，但默认选择保存失败。"
	elif action == "quota":
		for entry in entries:
			if entry.id == id and result.has("logged_in"):
				entry["logged_in"] = result.logged_in
				if not str(result.get("email", "")).is_empty():
					entry["email"] = str(result.email)
		if result.get("ok", false):
			quotas[id] = result.duplicate(true)
		save()
	busy = false
	return result
