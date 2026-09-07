extends SceneTree

const ServiceScript = preload("res://scripts/modules/codex/codex_profile_service.gd")

class NativeService extends ServiceScript:
	func _helper_path() -> String:
		return _managed_root().path_join("runtime/helper.ps1")
	func _active_home() -> String:
		return _managed_root().path_join("active")

class TestService extends ServiceScript:
	var helper_calls: Array = []
	var helper_failure := ""
	var fake_usage := {"five_hour": 60, "weekly": 80, "updated_at": "2026-09-07T00:00:00Z"}
	var refuse_index := false
	var live_info := {"login_present": true, "email": "fake@example.invalid", "account_id": "fake-id"}

	func _helper_path() -> String:
		return _managed_root().path_join("runtime/helper.ps1")

	func _active_home() -> String:
		return _managed_root().path_join("active")

	func _write_index(path: String, selected: String) -> bool:
		if refuse_index:
			return false
		return super._write_index(path, selected)

	func _call_helper(action: String, parameters: Dictionary = {}) -> Dictionary:
		helper_calls.append({"action": action, "parameters": parameters.duplicate(true)})
		if helper_failure == action:
			return {"ok": false, "message": "simulated failure"}
		if action == "inspect":
			return {"ok": true, "installed": true, "running": false, "account": live_info.duplicate(true)}
		if action in ["prepare", "import", "capture"]:
			var path := str(parameters["CodexHome"])
			DirAccess.make_dir_recursive_absolute(path)
			var file := FileAccess.open(path.path_join("snapshot.json"), FileAccess.WRITE)
			file.store_string("{}")
			file.close()
			if action != "prepare":
				file = FileAccess.open(path.path_join("auth.json"), FileAccess.WRITE)
				file.store_string("{}")
				file.close()
			return {"ok": true, "account": live_info.duplicate(true)}
		if action == "switch":
			var index := str(parameters["IndexPath"])
			DirAccess.rename_absolute(str(parameters["PendingIndex"]), index)
			return {"ok": true, "running": true}
		if action == "usage":
			return {"ok": true, "usage": fake_usage.duplicate(true), "account": live_info.duplicate(true)}
		return {"ok": true, "running": true}

var checks := 0
var sandbox := ""

func _init() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		printerr("FAIL: " + message)
		quit(1)
		assert(condition, message)
	checks += 1

func new_service(label: String):
	var service = TestService.new()
	var base := sandbox.path_join(label)
	service.configure_storage(base, base.path_join("index.json"))
	root.add_child(service)
	service.initialize()
	return service

func _run() -> void:
	sandbox = OS.get_environment("TEMP").path_join("hexagon-codex-service-%d-%d" % [Time.get_ticks_usec(), randi()])
	var service = new_service("main")
	check(service.profiles().size() == 1, "default initialized")
	check(service.selected_id() == "default", "default selected")
	service.account_store.update("default", service.live_info)
	check(not bool((await service.create_profile("  ")).get("ok")), "empty label rejected")
	var created: Dictionary = await service.create_profile("测试账号")
	check(bool(created.get("ok")), "profile created")
	var id := str(created["profile_id"])
	var path: String = service.profile_path(id)
	check(DirAccess.dir_exists_absolute(path), "snapshot directory created")
	check(service.selected_id() == "default", "creation does not switch")
	var loaded = new_service("main")
	check(loaded.profiles().size() == 2, "index survives restart")
	loaded.free()
	service.helper_failure = "switch"
	var failed: Dictionary = await service.switch_profile(id)
	check(not bool(failed.get("ok")), "switch failure reported")
	check(service.selected_id() == "default", "failed switch keeps selection")
	check(not FileAccess.file_exists(sandbox.path_join("main/index.json.pending")), "pending file cleaned")
	service.helper_failure = ""
	service.refuse_index = true
	var calls: int = service.helper_calls.size()
	failed = await service.switch_profile(id)
	check(not bool(failed.get("ok")) and calls + 1 == service.helper_calls.size(), "index failure prevents switching after inspection")
	service.refuse_index = false
	var switched: Dictionary = await service.switch_profile(id)
	check(bool(switched.get("ok")) and service.selected_id() == id, "successful switch updates selection")
	loaded = new_service("main")
	check(loaded.selected_id() == id, "successful switch commits selection")
	loaded.free()
	check(not bool(service.forget_profile(id).get("ok")), "current account cannot be removed")
	check(not bool(service.forget_profile("default").get("ok")), "default cannot be removed")
	service.live_info = {"login_present": true, "email": "second@example.invalid", "account_id": "second-id"}
	service.account_store.update(id, service.live_info)
	await service.refresh_status()
	var usage_result: Dictionary = await service.refresh_usage(id)
	check(bool(usage_result.get("ok")), "real usage result accepted")
	var usage_call: Dictionary = service.helper_calls.back()
	check(str(usage_call["parameters"]["CodexHome"]).ends_with("/active"), "selected usage reads live credentials")
	service.helper_failure = "usage"
	failed = await service.refresh_usage(id)
	var cached: Dictionary = service.account_store.find(id).get("usage")
	check(not bool(failed.get("ok")) and cached["five_hour"] == 60, "failed refresh preserves cached quota")
	check(cached["updated_at"] == "2026-09-07T00:00:00Z", "failed refresh does not forge timestamp")
	service.helper_failure = ""
	await service.refresh_status()
	check(service.view_state()["selected_id"] == id, "view includes selection")
	check(service.profiles()[1].get("email") == "second@example.invalid", "safe live metadata displayed")
	var captured: Dictionary = await service.capture_current("新的备注")
	check(bool(captured.get("ok")) and service.profiles().size() == 2, "capture updates current account without duplication")
	check(service.account_store.find(id)["name"] == "新的备注", "capture can rename current label")
	await service.switch_profile("default")
	check(bool(service.forget_profile(id).get("ok")), "inactive profile removable")
	check(DirAccess.dir_exists_absolute(path), "remove retains snapshot files")
	var imported: Dictionary = await service.import_profile("fake.json")
	check(bool(imported.get("ok")), "import added")
	check(service.selected_id() == "default", "import never activates login")
	# External logins must not overwrite the selected row, even on refresh.
	var old_default: Dictionary = service.account_store.find("default").duplicate(true)
	service.live_info = {"login_present": true, "email": "third@example.invalid", "account_id": "third-id"}
	await service.refresh_status()
	check(service.account_store.find("default").get("account_id") == old_default.get("account_id"), "refresh never overwrites saved identity")
	check(service.profiles()[0].get("usage", {}).is_empty(), "different live identity never displays old quota")
	var distinct: Dictionary = await service.capture_current()
	check(bool(distinct.get("ok")) and str(distinct["profile_id"]) != "default", "new external login gets its own row")
	check(service.account_store.find("default").get("account_id") == old_default.get("account_id"), "capture preserves old default identity")
	check(service.account_store.find(str(distinct["profile_id"])).get("usage", {}).is_empty(), "new identity starts without inherited quota")
	var empty: Dictionary = await service.create_profile("指定账号")
	service.live_info = {"login_present": true, "email": "fourth@example.invalid", "account_id": "fourth-id"}
	var filled: Dictionary = await service.capture_current("", str(empty["profile_id"]))
	check(bool(filled.get("ok")) and filled["profile_id"] == empty["profile_id"], "explicit save fills chosen empty row")
	check(service.account_store.find(str(empty["profile_id"]))["name"] == "指定账号", "explicit save retains row label")
	service.live_info = {"login_present": true, "email": "fifth@example.invalid", "account_id": "fifth-id"}
	check(not bool((await service.capture_current("", str(empty["profile_id"]))).get("ok")), "different saved identity cannot be replaced")
	service.free()

	var migration_root := sandbox.path_join("migration")
	var old_home := migration_root.path_join("old/codex")
	DirAccess.make_dir_recursive_absolute(old_home)
	var auth := FileAccess.open(old_home.path_join("auth.json"), FileAccess.WRITE)
	auth.store_string("{\"tokens\":{\"access_token\":\"test-only\"}}")
	auth.close()
	var index := FileAccess.open(migration_root.path_join("index.json"), FileAccess.WRITE)
	index.store_string(JSON.stringify({"version": 1, "selected_id": "legacy",
		"profiles": [{"id": "legacy", "name": "旧账号", "codex_home": old_home, "electron_data": "unchanged"}]}))
	index.close()
	var migrated = new_service("migration")
	check(migrated.profiles().size() == 2 and migrated.selected_id() == "legacy", "legacy list and selection retained")
	check(FileAccess.file_exists(migrated.profile_path("legacy").path_join("auth.json")), "legacy auth copied to snapshot")
	check(FileAccess.file_exists(old_home.path_join("auth.json")), "legacy auth not removed")
	check(migrated._active_override == old_home, "legacy active home retained")
	migrated.free()

	var invalid_root := sandbox.path_join("invalid")
	DirAccess.make_dir_recursive_absolute(invalid_root)
	index = FileAccess.open(invalid_root.path_join("index.json"), FileAccess.WRITE)
	index.store_string("{broken")
	index.close()
	var invalid = new_service("invalid")
	check(not bool((await invalid.create_profile("拒绝")).get("ok")), "corrupt index blocks mutation")
	check(FileAccess.get_file_as_string(invalid_root.path_join("index.json")) == "{broken", "corrupt index never overwritten")
	invalid.free()

	# Exercise Godot -> background worker -> Windows PowerShell -> JSON without
	# real credentials, network requests, or desktop process control.
	var native = NativeService.new()
	var native_root := sandbox.path_join("native")
	native.configure_storage(native_root, native_root.path_join("index.json"))
	root.add_child(native)
	native.initialize()
	var native_created: Dictionary = await native.create_profile("原生测试")
	if not bool(native_created.get("ok")):
		printerr(native_created)
	check(bool(native_created.get("ok")), "native helper creates blank profile")
	var input := FileAccess.open(native_root.path_join("input.json"), FileAccess.WRITE)
	input.store_string(JSON.stringify({"OPENAI_API_KEY": "test-only-not-a-real-key"}))
	input.close()
	var native_imported: Dictionary = await native.import_profile(native_root.path_join("input.json"), "API 测试")
	check(bool(native_imported.get("ok")), "native helper imports fake API auth")
	var api_usage: Dictionary = await native.refresh_usage(str(native_imported.get("profile_id", "")))
	check(not bool(api_usage.get("ok")) and str(api_usage.get("message", "")).contains("API Key"), "API usage reports unsupported without network")
	check(not FileAccess.get_file_as_string(native_root.path_join("index.json")).contains("test-only-not-a-real-key"), "index contains no secret")
	check(not FileAccess.file_exists(native_root.path_join("active/auth.json")), "native import never modifies active login")
	native.dispose()
	native.free()
	print("PASS: %d Codex profile service checks" % checks)
	quit(0)
