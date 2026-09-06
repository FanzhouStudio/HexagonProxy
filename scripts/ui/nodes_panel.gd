class_name NodesPanel
extends Node

signal node_status_changed(node_name: String, delay: int)
signal proxy_select_requested(group_name: String, proxy_name: String)
signal proxy_delay_requested(proxy_name: String)
signal group_delay_requested(group_name: String)
signal global_group_requested(group_name: String)
signal runtime_refresh_requested
signal failover_enabled_changed(enabled: bool)
signal backup_toggle_requested(group_name: String, node_name: String, enabled: bool)

const SURFACE := Color("e9fbfbd4")
const BORDER := Color("a8e8e8e8")
const TEXT := Color("12384a")
const MUTED := Color("527384")
const GREEN := Color("16866f")
const GREEN_DARK := Color("c5f1dfde")
const YELLOW := Color("b87918")
const RED := Color("c84d68")
const NODE_RENDER_BATCH_SIZE := 18

var ui: UiFactory
var group_selector: OptionButton
var failover_toggle: CheckButton
var failover_status_label: Label
var node_grid: GridContainer
var proxy_groups: Array = []
var _failover_snapshot: Dictionary = {}
var selected_group_index := 0
var delay_cache := {}
var _group_delay_pending: Array[String] = []
var _current_node_name := ""
var _rebuild_generation := 0
var _rendered_structure_signature := ""
var _building_structure_signature := ""
var _node_views: Dictionary = {}
var _page_active := false
var _global_mode_active := false

func setup(factory: UiFactory) -> void:
	ui = factory
func build() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 14)
	var toolbar := ui.panel(SURFACE, BORDER, 18)
	toolbar.custom_minimum_size.y = 78
	page.add_child(toolbar)
	var margin := ui.margin(18, 14, 18, 14)
	toolbar.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	margin.add_child(row)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(words)
	words.add_child(ui.label("选择守护路线", 18, TEXT))
	words.add_child(ui.label("延迟越低，小恐龙跑得越快", 11, MUTED))
	var failover_box := VBoxContainer.new()
	failover_box.custom_minimum_size.x = 230
	failover_box.add_theme_constant_override("separation", 2)
	row.add_child(failover_box)
	failover_toggle = CheckButton.new()
	failover_toggle.text = "自动故障切换"
	ui.apply_crystal_toggle_theme(failover_toggle)
	failover_toggle.toggled.connect(func(value: bool) -> void: failover_enabled_changed.emit(value))
	failover_box.add_child(failover_toggle)
	failover_status_label = ui.label("等待节点数据", 10, MUTED)
	failover_status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	failover_status_label.tooltip_text = "连续探测失败后，自动切换到备选组中延迟最低的可用节点。"
	failover_box.add_child(failover_status_label)
	group_selector = OptionButton.new()
	group_selector.custom_minimum_size = Vector2(190, 40)
	group_selector.add_theme_font_size_override("font_size", 13)
	ui.apply_crystal_option_theme(group_selector)
	group_selector.item_selected.connect(_on_group_selected)
	row.add_child(group_selector)
	var test_all := ui.button("全部测速", GREEN_DARK, GREEN)
	test_all.pressed.connect(_test_visible_nodes)
	row.add_child(test_all)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(scroll)
	var grid_margin := ui.margin(2, 2, 8, 8)
	grid_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid_margin)
	node_grid = GridContainer.new()
	node_grid.columns = 3
	node_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node_grid.add_theme_constant_override("h_separation", 12)
	node_grid.add_theme_constant_override("v_separation", 12)
	grid_margin.add_child(node_grid)
	node_grid.add_child(ui.empty_message("连接后，这里会出现节点。"))
	return page

func set_active(value: bool) -> void:
	_page_active = value
	if not value:
		_rebuild_generation += 1
		_building_structure_signature = ""
		return
	_ensure_nodes_rendered()

func set_global_mode_active(value: bool) -> void:
	_global_mode_active = value

func selected_group() -> Dictionary:
	if selected_group_index >= 0 and selected_group_index < proxy_groups.size():
		return proxy_groups[selected_group_index]
	return {}
func current_node_name() -> String:
	return _current_node_name

func current_delay() -> int:
	return int(delay_cache.get(_current_node_name, 0))

func set_failover_snapshot(snapshot: Dictionary) -> void:
	var old_backup_signature := JSON.stringify(_failover_snapshot.get("backups", []))
	var old_route_group := str(_failover_snapshot.get("route_group", ""))
	_failover_snapshot = snapshot.duplicate(true)
	if is_instance_valid(failover_toggle):
		failover_toggle.set_pressed_no_signal(bool(snapshot.get("enabled", true)))
	if is_instance_valid(failover_status_label):
		var status := str(snapshot.get("status", "等待节点数据"))
		failover_status_label.text = status
		failover_status_label.tooltip_text = status
	var membership_changed := old_backup_signature != JSON.stringify(snapshot.get("backups", []))
	var route_changed := old_route_group != str(snapshot.get("route_group", ""))
	if membership_changed or route_changed:
		_refresh_visible_node_states()

func _is_backup(group_name: String, node_name: String) -> bool:
	var items: Variant = _failover_snapshot.get("backups", [])
	if not items is Array:
		return false
	for item in items:
		if item is Dictionary and str(item.get("group", "")) == group_name and str(item.get("node", "")) == node_name:
			return true
	return false

func handle_api_result(action: String, ok: bool, payload: Variant) -> bool:
	if action == "proxies":
		if ok and payload is Dictionary:
			_apply_proxies(payload)
		return true
	if action.begins_with("delay:"):
		var proxy_name := action.trim_prefix("delay:")
		delay_cache[proxy_name] = int(payload.get("delay", -1)) if ok and payload is Dictionary else -1
		_refresh_node_view(proxy_name)
		_emit_node_status()
		return true
	if action == "group_delay":
		_apply_group_delay(ok, payload)
		return true
	if action == "select_proxy":
		if ok:
			if _global_mode_active:
				global_group_requested.emit(str(selected_group().get("name", "六角选择")))
			runtime_refresh_requested.emit()
		return true
	return false
func _apply_group_delay(ok: bool, payload: Variant) -> void:
	if ok and payload is Dictionary:
		for proxy_name in _group_delay_pending:
			if not payload.has(proxy_name):
				delay_cache[proxy_name] = -1
		for proxy_name in payload:
			delay_cache[str(proxy_name)] = int(payload[proxy_name])
	else:
		for proxy_name in _group_delay_pending:
			delay_cache[proxy_name] = -1
	_group_delay_pending.clear()
	_refresh_visible_node_states()
	_emit_node_status()

func _apply_proxies(payload: Dictionary) -> void:
	var selected_name := ""
	if is_instance_valid(group_selector) and group_selector.item_count > 0 and selected_group_index < group_selector.item_count:
		selected_name = group_selector.get_item_text(selected_group_index)
	var proxy_map_value: Variant = payload.get("proxies", {})
	var proxy_map: Dictionary = proxy_map_value if proxy_map_value is Dictionary else {}
	var groups: Array = []
	for proxy_name in proxy_map:
		var data: Variant = proxy_map[proxy_name]
		if not data is Dictionary or str(proxy_name).to_upper() == "GLOBAL":
			continue
		var kind := str(data.get("type", ""))
		if kind in ["Selector", "URLTest", "Fallback", "LoadBalance"] and data.get("all", []) is Array:
			groups.append({"name": str(proxy_name), "type": kind, "now": str(data.get("now", "")), "all": data.get("all", [])})
	proxy_groups = groups
	var next_selected_index := -1
	var preferred_index := -1
	for index in proxy_groups.size():
		var group: Dictionary = proxy_groups[index]
		if str(group.get("name", "")) == selected_name:
			next_selected_index = index
		if str(group.get("name", "")) == "六角选择":
			preferred_index = index
	selected_group_index = next_selected_index if next_selected_index >= 0 else preferred_index if preferred_index >= 0 else 0
	if is_instance_valid(group_selector):
		var selector_changed := group_selector.item_count != proxy_groups.size()
		if not selector_changed:
			for index in proxy_groups.size():
				if group_selector.get_item_text(index) != str(proxy_groups[index].get("name", "")):
					selector_changed = true
					break
		if selector_changed:
			group_selector.clear()
			for group in proxy_groups:
				group_selector.add_item(str(group.get("name", "")))
		if group_selector.item_count > 0:
			group_selector.select(selected_group_index)
	_current_node_name = str(selected_group().get("now", ""))
	_ensure_nodes_rendered()
	_refresh_visible_node_states()
	_emit_node_status()

func _on_group_selected(index: int) -> void:
	selected_group_index = index
	var group := selected_group()
	_current_node_name = str(group.get("now", ""))
	if _global_mode_active:
		global_group_requested.emit(str(group.get("name", "")))
	_ensure_nodes_rendered()
	_refresh_visible_node_states()
	_emit_node_status()

func _test_visible_nodes() -> void:
	var group := selected_group()
	if group.is_empty():
		return
	var nodes_value: Variant = group.get("all", [])
	var nodes: Array = nodes_value if nodes_value is Array else []
	_group_delay_pending.clear()
	for proxy_name_variant in nodes:
		var proxy_name := str(proxy_name_variant)
		_group_delay_pending.append(proxy_name)
		delay_cache[proxy_name] = -2
	_refresh_visible_node_states()
	group_delay_requested.emit(str(group.get("name", "")))

func _emit_node_status() -> void:
	node_status_changed.emit(_current_node_name, current_delay())

func _selected_structure_signature() -> String:
	var group := selected_group()
	if group.is_empty():
		return "__empty__"
	return "%s|%s" % [str(group.get("name", "")), JSON.stringify(group.get("all", []))]

func _ensure_nodes_rendered() -> void:
	if not _page_active or not is_instance_valid(node_grid):
		return
	var signature := _selected_structure_signature()
	if signature == _rendered_structure_signature:
		_refresh_visible_node_states()
		return
	if signature == _building_structure_signature:
		return
	_rebuild_nodes()

func _create_node_grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	return grid

func _rebuild_nodes() -> void:
	_rebuild_generation += 1
	var generation := _rebuild_generation
	if not _page_active or not is_instance_valid(node_grid):
		return
	var signature := _selected_structure_signature()
	_building_structure_signature = signature
	var host := node_grid.get_parent()
	if not is_instance_valid(host):
		_building_structure_signature = ""
		return
	var new_grid := _create_node_grid()
	var new_views: Dictionary = {}
	var group := selected_group()
	var nodes_value: Variant = group.get("all", []) if not group.is_empty() else []
	var nodes: Array = nodes_value if nodes_value is Array else []
	if group.is_empty():
		new_grid.add_child(ui.empty_message("连接后，这里会出现节点。"))
	elif nodes.is_empty():
		new_grid.add_child(ui.empty_message("这个策略组暂时没有节点。"))
	else:
		for index in nodes.size():
			if generation != _rebuild_generation or not _page_active:
				new_grid.free()
				if generation == _rebuild_generation:
					_building_structure_signature = ""
				return
			var proxy_name := str(nodes[index])
			new_grid.add_child(_node_card(str(group.get("name", "")), proxy_name, proxy_name == str(group.get("now", "")), new_views))
			if (index + 1) % NODE_RENDER_BATCH_SIZE == 0:
				await get_tree().process_frame
	if generation != _rebuild_generation or not _page_active:
		new_grid.free()
		if generation == _rebuild_generation:
			_building_structure_signature = ""
		return
	var old_grid := node_grid
	host.remove_child(old_grid)
	host.add_child(new_grid)
	node_grid = new_grid
	_node_views = new_views
	_rendered_structure_signature = signature
	_building_structure_signature = ""
	old_grid.queue_free()
	_refresh_visible_node_states()

func _refresh_visible_node_states() -> void:
	for proxy_name in _node_views.keys():
		_refresh_node_view(str(proxy_name))

func _refresh_node_view(proxy_name: String) -> void:
	var raw: Variant = _node_views.get(proxy_name, {})
	if not raw is Dictionary:
		return
	var view: Dictionary = raw
	var group_name := str(view.get("group", ""))
	var group := selected_group()
	var selected := group_name == str(group.get("name", "")) and proxy_name == str(group.get("now", ""))
	var card: PanelContainer = view.get("card")
	ui.update_panel_style(card, GREEN_DARK if selected else SURFACE, GREEN if selected else BORDER, 16)
	var delay := int(delay_cache.get(proxy_name, 0))
	var delay_label: Label = view.get("delay_label")
	if is_instance_valid(delay_label):
		delay_label.text = "测速" if delay == 0 else "测速中…" if delay == -2 else "失败" if delay < 0 else "%d ms" % delay
		ui.update_label_color(delay_label, MUTED if delay in [0, -2] else RED if delay < 0 else GREEN if delay < 180 else YELLOW)
	var backup: Button = view.get("backup_button")
	if is_instance_valid(backup):
		var backup_enabled := _is_backup(group_name, proxy_name)
		var route_group := str(_failover_snapshot.get("route_group", ""))
		backup.text = "★ 备选" if backup_enabled else "☆ 备选"
		backup.disabled = not route_group.is_empty() and route_group != group_name
		backup.tooltip_text = "当前自动守护组为：%s" % route_group if backup.disabled else "移出自动故障切换备选组" if backup_enabled else "加入自动故障切换备选组"
	var choose: Button = view.get("choose_button")
	if is_instance_valid(choose):
		choose.text = "已选" if selected else "选择"
		choose.disabled = selected

func _node_card(group_name: String, proxy_name: String, selected: bool, views: Dictionary) -> PanelContainer:
	var card := ui.panel(GREEN_DARK if selected else SURFACE, GREEN if selected else BORDER, 16)
	card.custom_minimum_size = Vector2(245, 112)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var margin := ui.margin(14, 12, 14, 12)
	card.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)
	var name_label := ui.label(proxy_name, 14, TEXT)
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.tooltip_text = proxy_name
	column.add_child(name_label)
	var bottom := HBoxContainer.new()
	column.add_child(bottom)
	var delay := int(delay_cache.get(proxy_name, 0))
	var delay_text := "测速" if delay == 0 else "测速中…" if delay == -2 else "失败" if delay < 0 else "%d ms" % delay
	var delay_color := MUTED if delay in [0, -2] else RED if delay < 0 else GREEN if delay < 180 else YELLOW
	var delay_label := ui.label(delay_text, 12, delay_color)
	delay_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(delay_label)
	var test := ui.small_choice_button("测")
	test.pressed.connect(func() -> void:
		delay_cache[proxy_name] = -2
		_refresh_node_view(proxy_name)
		proxy_delay_requested.emit(proxy_name)
	)
	bottom.add_child(test)
	var backup_enabled := _is_backup(group_name, proxy_name)
	var backup := ui.small_choice_button("★ 备选" if backup_enabled else "☆ 备选")
	backup.pressed.connect(func() -> void: backup_toggle_requested.emit(group_name, proxy_name, not _is_backup(group_name, proxy_name)))
	bottom.add_child(backup)
	var choose := ui.small_choice_button("已选" if selected else "选择")
	choose.disabled = selected
	choose.pressed.connect(func() -> void: proxy_select_requested.emit(group_name, proxy_name))
	bottom.add_child(choose)
	views[proxy_name] = {"group": group_name, "card": card, "delay_label": delay_label, "backup_button": backup, "choose_button": choose}
	return card
