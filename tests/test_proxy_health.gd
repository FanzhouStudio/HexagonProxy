extends SceneTree

var service = preload("res://scripts/modules/network/proxy_health_service.gd").new()
var states: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func round_result(first: bool, second: bool) -> void:
	service._results.clear()
	for success in [first, second]:
		var request := HTTPRequest.new()
		service.add_child(request)
		service._requests.append(request)
		service._finish(request, service._generation, success)

func _run() -> void:
	root.add_child(service)
	service.checked.connect(func(state: String, _message: String) -> void: states.append(state))
	round_result(false, false)
	round_result(false, false)
	round_result(true, false)
	round_result(false, false)
	round_result(true, true)
	if states != ["checking", "failed", "partial", "checking", "healthy"]:
		push_error("Health failure threshold or recovery is incorrect: %s" % [states])
		quit(1)
		return
	var stale := HTTPRequest.new()
	service.add_child(stale)
	service._requests.append(stale)
	var generation: int = service._generation
	service.cancel()
	service._finish(stale, generation, true)
	if states.size() != 5 or not service._results.is_empty() or service._failures != 0:
		push_error("Cancelled health probe changed current status")
		quit(2)
		return
	print("PASS: proxy health failure threshold, partial reachability, recovery and stale callback isolation")
	quit(0)
