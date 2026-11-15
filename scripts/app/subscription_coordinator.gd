class_name SubscriptionCoordinator
extends Node

## 订阅 UI 协调器
## 负责把 SubscriptionPanel 的用户意图路由到 SubscriptionService，
## 并把订阅库快照回写给 UI，避免面板直接依赖业务服务。

var subscription_service
var subscription_panel
var _active := false
var _control
var _timer: Timer

func setup(service, panel, control = null) -> void:
	_control = control
	if _control:
		_control.api_result.connect(_on_expiry_result)
		_control.state_changed.connect(func(online: bool, _starting: bool, _pid: int, _message: String) -> void:
			if online:
				_request_expiry()
		)
	subscription_service = service
	subscription_panel = panel
	subscription_panel.subscription_url_requested.connect(_on_subscription_url_requested)
	subscription_panel.v2_import_requested.connect(_on_v2_import_requested)
	subscription_panel.provider_refresh_requested.connect(_on_provider_refresh_requested)
	subscription_panel.subscription_activate_requested.connect(_on_subscription_activate_requested)
	subscription_panel.subscription_delete_requested.connect(_on_subscription_delete_requested)
	subscription_panel.local_profile_requested.connect(_on_local_profile_requested)
	subscription_service.subscriptions_changed.connect(_refresh_snapshot)

func start() -> void:
	if _active:
		return
	_active = true
	_refresh_snapshot()
	if _control:
		_timer = Timer.new()
		_timer.wait_time = 60
		_timer.timeout.connect(_request_expiry)
		add_child(_timer)
		_timer.start()
		_request_expiry()

func shutdown() -> void:
	_active = false
	if is_instance_valid(_timer):
		_timer.stop()

func _request_expiry() -> void:
	if not _active or _control == null or not _control.online:
		return
	var id: String = subscription_service.active_subscription_id()
	for entry in subscription_service.get_subscriptions():
		if str(entry.get("id", "")) == id and entry.get("type", "") == "http":
			_control.request("subscription_expiry:" + id, "/providers/proxies/hexagon-subscription", HTTPClient.METHOD_GET)
			return

func _on_expiry_result(action: String, ok: bool, payload: Variant) -> void:
	if not _active or not ok:
		return
	if action == "update_provider":
		_request_expiry()
	elif action.begins_with("subscription_expiry:") and payload is Dictionary:
		var id := action.trim_prefix("subscription_expiry:")
		if id == subscription_service.active_subscription_id():
			subscription_service.save_expiry(id, payload)
			_refresh_snapshot()
func _on_subscription_url_requested(url: String) -> void:
	if not _active:
		return
	if subscription_service.use_subscription_url(url):
		subscription_panel.clear_subscription_input()

func _on_v2_import_requested(content: String) -> void:
	if not _active:
		return
	if subscription_service.use_v2_share_links(content):
		subscription_panel.clear_v2_input()

func _on_provider_refresh_requested() -> void:
	if _active:
		subscription_service.update_provider()

func _on_subscription_activate_requested(entry_id: String) -> void:
	if _active:
		subscription_service.activate_subscription(entry_id)

func _on_subscription_delete_requested(entry_id: String) -> void:
	if _active:
		subscription_service.delete_subscription(entry_id)

func _on_local_profile_requested(path: String) -> void:
	if _active:
		subscription_service.import_local_profile(path)
func _refresh_snapshot() -> void:
	if not _active:
		return
	subscription_panel.set_subscriptions(
		subscription_service.get_subscriptions(),
		subscription_service.active_subscription_id()
	)
