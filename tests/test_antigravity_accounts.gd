extends SceneTree

const Accounts = preload("res://scripts/modules/antigravity/antigravity_accounts.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var path := ProjectSettings.globalize_path("user://accounts-test-%d" % Time.get_ticks_usec())
	var store := Accounts.new()
	root.add_child(store)
	store.initialize(path)
	assert(store.list().size() == 1)
	var unnamed: Dictionary = store.add(" ")
	assert(unnamed.ok, "Adding an account must work without a manual name")
	var added: Dictionary = store.add("工作账号")
	assert(added.ok and store.exists(added.id))
	assert(not store.add("工作账号").ok)
	assert(not store.exists("../outside"))
	store.selected = added.id
	store.quotas[added.id] = {"ok": true, "models": [{"name": "Fixture", "remaining": 0}]}
	assert(store.save())
	var reopened := Accounts.new()
	root.add_child(reopened)
	reopened.initialize(path)
	assert(reopened.selected == added.id and reopened.list().size() == 3)
	assert(reopened.quotas[added.id].models[0].remaining == 0)
	var rejected: Dictionary = await reopened.run("launch", "../outside", "invalid")
	assert(not rejected.ok)
	var native: Dictionary = await reopened.run("launch", "default", path.path_join("missing/Antigravity.exe"))
	assert(not native.ok and str(native.get("message", "")).contains("未找到 Antigravity"), "Real PowerShell bridge must return its Chinese error, not exit without JSON")
	var helper_bytes := FileAccess.get_file_as_bytes(path.path_join("helper.ps1"))
	assert(helper_bytes.slice(0, 3) == PackedByteArray([0xef, 0xbb, 0xbf]), "Materialized helper must preserve BOM bytes")
	store.queue_free()
	reopened.queue_free()
	print("PASS: account creation, persistence, quota cache, duplicate and invalid selection rejection")
	quit(0)
