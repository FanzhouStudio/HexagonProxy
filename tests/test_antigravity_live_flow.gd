extends SceneTree

# Opt-in native smoke check against a dedicated local profile, never the normal
# HexagonProxy account index. No email, quota values or tokens are printed.
func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var storage := OS.get_environment("HEXAGON_ANTIGRAVITY_TEST_ROOT")
	if storage.is_empty():
		printerr("Live test requires HEXAGON_ANTIGRAVITY_TEST_ROOT")
		quit(2)
		return
	var accounts = load("res://scripts/modules/antigravity/antigravity_accounts.gd").new()
	root.add_child(accounts)
	accounts.initialize(storage)
	accounts.workspace_home_override = storage.path_join("shared-workspace")
	var id := "fedcba9876543210fedcba9876543210"
	if not accounts.exists(id):
		accounts.entries.append({"id": id, "name": "Isolated test account"})
	var executable := OS.get_environment("LOCALAPPDATA").path_join("Programs/antigravity/Antigravity.exe")
	var opened: Dictionary = await accounts.run("launch", id, executable)
	if not opened.get("ok", false):
		printerr("FAIL: " + str(opened.get("message", "launch")))
		quit(3)
		return
	assert(opened.get("workspace_shared", false), "Launched accounts must share the original workspace directories")
	await create_timer(2.0).timeout
	var result: Dictionary = await accounts.run("quota", id, executable)
	if not result.get("ok", false) or not result.get("logged_in", false):
		printerr("FAIL: " + str(result.get("message", "quota")))
		quit(4)
		return
	assert(accounts.selected == id and accounts.quotas.has(id))
	var loaded = load("res://scripts/modules/antigravity/antigravity_accounts.gd").new()
	root.add_child(loaded)
	loaded.initialize(storage)
	assert(loaded.selected == id and loaded.quotas.has(id))
	assert(loaded.entries.any(func(entry: Dictionary) -> bool: return entry.id == id and entry.get("logged_in", false)))
	print("PASS: actual profile reopen, native helper IPC, login recognition, quota read and persisted account metadata")
	quit(0)
