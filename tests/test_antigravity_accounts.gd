extends SceneTree

const Accounts = preload("res://scripts/modules/antigravity/antigravity_accounts.gd")

class FailingStore extends Accounts:
	func save() -> bool:
		return false

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
	assert(not reopened.remove_account("default").ok, "Original account cannot be removed")
	assert(not reopened.remove_account("../outside").ok)
	reopened.busy = true
	assert(not reopened.remove_account(added.id).ok and reopened.exists(added.id), "An in-flight account operation blocks deletion")
	reopened.busy = false
	var failing := FailingStore.new()
	root.add_child(failing)
	failing.initialize(path)
	assert(not failing.set_default_account(added.id).ok and failing.default_account == "default", "Failed default save restores the original preference")
	failing.default_account = unnamed.id
	assert(not failing.remove_account("default").ok and failing.original_visible and failing.exists("default"), "Failed deletion restores the original account entry")
	assert(not failing.remove_account(added.id).ok)
	assert(failing.exists(added.id) and failing.selected == added.id and failing.quotas.has(added.id), "Save failures restore the entry, selection and quota")
	failing.queue_free()
	# A profile may link to the shared conversation tree; removal must never walk it.
	var profile_path := path.path_join(added.id).path_join("home/.gemini/antigravity")
	DirAccess.make_dir_recursive_absolute(profile_path)
	var history := FileAccess.open(profile_path.path_join("history-fixture.txt"), FileAccess.WRITE)
	history.store_string("preserve projects, login backups and conversations")
	history.close()
	assert(reopened.remove_account(added.id).ok)
	assert(not reopened.exists(added.id) and not reopened.quotas.has(added.id) and reopened.selected == "default")
	assert(FileAccess.get_file_as_string(profile_path.path_join("history-fixture.txt")) == "preserve projects, login backups and conversations")
	var after_removal := Accounts.new()
	root.add_child(after_removal)
	after_removal.initialize(path)
	assert(not after_removal.exists(added.id) and after_removal.exists(unnamed.id) and after_removal.selected == "default" and not after_removal.quotas.has(added.id), "Deletion persists without disturbing other accounts")
	assert(not after_removal.remove_account(added.id).ok, "Repeated deletion is rejected")
	after_removal.queue_free()
	var rejected: Dictionary = await reopened.run("launch", "../outside", "invalid")
	assert(not rejected.ok)
	var native: Dictionary = await reopened.run("launch", "default", path.path_join("missing/Antigravity.exe"))
	assert(not native.ok and str(native.get("message", "")).contains("未找到 Antigravity"), "Real PowerShell bridge must return its Chinese error, not exit without JSON")
	var helper_bytes := FileAccess.get_file_as_bytes(path.path_join("helper.ps1"))
	assert(helper_bytes.slice(0, 3) == PackedByteArray([0xef, 0xbb, 0xbf]), "Materialized helper must preserve BOM bytes")
	assert(reopened.set_default_account(unnamed.id).ok)
	assert(reopened.default_account == unnamed.id and reopened.selected == "default", "Default preference is independent of last opened account")
	assert(not reopened.remove_account(unnamed.id).ok, "The preferred account is protected until another is selected")
	assert(reopened.remove_account("default").ok and not reopened.exists("default") and reopened.selected == unnamed.id)
	var migrated := Accounts.new()
	root.add_child(migrated)
	migrated.initialize(path)
	assert(migrated.default_account == unnamed.id and migrated.selected == unnamed.id and migrated.list().size() == 1 and not migrated.exists("default"), "Original deletion and custom default persist across restart")
	assert(not migrated.set_default_account("default").ok and not migrated.remove_account(unnamed.id).ok)
	migrated.queue_free()
	store.queue_free()
	reopened.queue_free()
	print("PASS: account creation, deletion, rollback, persistence, quota cache and profile preservation")
	quit(0)
