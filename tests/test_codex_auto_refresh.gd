extends SceneTree

class FakeService extends Node:
	var calls: Array = []
	func is_busy() -> bool:
		return false
	func profiles() -> Array:
		return [{"id": "a", "login_present": true}, {"id": "b", "login_present": true}, {"id": "api", "login_present": true, "auth_kind": "api"}, {"id": "empty"}]
	func refresh_usage(id: String) -> Dictionary:
		calls.append(id)
		return {"ok": false}
	func view_state() -> Dictionary:
		return {}

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var coordinator = load("res://scripts/app/codex_profile_coordinator.gd").new()
	var service = FakeService.new()
	var panel = load("res://scripts/ui/codex_accounts_panel.gd").new()
	root.add_child(service)
	root.add_child(panel)
	root.add_child(coordinator)
	coordinator.service = service
	coordinator.panel = panel
	coordinator._active = true
	await coordinator._auto_refresh_usage()
	await coordinator._auto_refresh_usage()
	await coordinator._auto_refresh_usage()
	if service.calls != ["a", "b"]:
		printerr("FAIL: automatic refresh scheduling, API filtering or failure cooldown")
		quit(1)
		return
	coordinator._last_attempt["a"] = 0
	coordinator._working = true
	await coordinator._auto_refresh_usage()
	if service.calls.size() != 2:
		quit(2)
		return
	coordinator._working = false
	await coordinator._auto_refresh_usage()
	if service.calls != ["a", "b", "a"]:
		quit(3)
		return
	coordinator.shutdown()
	coordinator._last_attempt.clear()
	await coordinator._auto_refresh_usage()
	if service.calls.size() != 3:
		quit(4)
		return
	print("PASS: automatic quota refresh, cooldown, serialization and shutdown")
	quit(0)
