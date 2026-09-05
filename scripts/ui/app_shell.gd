class_name AppShell
extends Node

const AquariumBackgroundScript = preload("res://scripts/aquarium_background.gd")
const MUTED := Color("527384")
const GREEN := Color("16866f")
const GREEN_DARK := Color("c5f1dfde")
const OVERLAY_TEXT := Color("efffff")

var host: Control
var ui: UiFactory
var dashboard_panel: DashboardPanel
var nodes_panel: NodesPanel
var subscription_panel: SubscriptionPanel
var routing_panel: RoutingPanel
var terminal_panel: TerminalPanel
var settings_panel: SettingsPanel
var page_host: Control
var pages := {}
var nav_buttons := {}
var page_title: Label
var aquarium_background: Control

func setup(owner: Control, factory: UiFactory, dashboard: DashboardPanel, nodes: NodesPanel, subscription: SubscriptionPanel, routing: RoutingPanel, terminal: TerminalPanel, settings: SettingsPanel) -> void:
	host = owner
	ui = factory
	dashboard_panel = dashboard
	nodes_panel = nodes
	subscription_panel = subscription
	routing_panel = routing
	terminal_panel = terminal
	settings_panel = settings

func build(profile_name: String) -> void:
	aquarium_background = AquariumBackgroundScript.new()
	aquarium_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.apply_background_theme(aquarium_background)
	host.add_child(aquarium_background)
	host.move_child(aquarium_background, 0)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	host.add_child(margin)
	var shell := HBoxContainer.new()
	shell.add_theme_constant_override("separation", 18)
	margin.add_child(shell)

	var sidebar := ui.panel(Color("e6fbf8dc"), Color("c7fffff2"), 22)
	sidebar.custom_minimum_size = Vector2(250, 0)
	shell.add_child(sidebar)
	var side_margin := ui.margin(16, 18, 16, 16)
	sidebar.add_child(side_margin)
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 10)
	side_margin.add_child(side)
	_build_brand(side)
	var spacer_small := Control.new()
	spacer_small.custom_minimum_size.y = 14
	side.add_child(spacer_small)
	_add_nav(side, "dashboard", "⌂  总览")
	_add_nav(side, "nodes", "⬡  节点")
	_add_nav(side, "subscription", "↻  订阅")
	_add_nav(side, "routing", "⇄  分流")
	_add_nav(side, "terminal", ">_  终端")
	_add_nav(side, "settings", "⚙  设置")
	var side_spacer := Control.new()
	side_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(side_spacer)
	var side_note := ui.label("Mihomo powered", 11, MUTED)
	side.add_child(side_note)

	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	shell.add_child(body)
	_build_topbar(body)
	page_host = Control.new()
	page_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(page_host)
	pages["dashboard"] = dashboard_panel.build(profile_name)
	pages["nodes"] = nodes_panel.build()
	pages["subscription"] = subscription_panel.build()
	pages["routing"] = routing_panel.build()
	pages["terminal"] = terminal_panel.build()
	pages["settings"] = settings_panel.build()
	for page in pages.values():
		page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		page_host.add_child(page)

func show_page(page_id: String) -> void:
	var titles := {
		"dashboard": "网络总览",
		"nodes": "节点路线",
		"subscription": "订阅管理",
		"routing": "应用分流",
		"terminal": "内置终端",
		"settings": "偏好设置"
	}
	for page_name in pages:
		pages[page_name].visible = page_name == page_id
	for nav_name in nav_buttons:
		var active: bool = str(nav_name) == page_id
		var button: Button = nav_buttons[nav_name]
		ui.apply_nav_button(button, active)
	if is_instance_valid(page_title):
		page_title.text = titles.get(page_id, "HexagonProxy")
	nodes_panel.set_active(page_id == "nodes")

func _build_brand(parent: Container) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	var icon := TextureRect.new()
	icon.texture = load("res://assets/app_icon.png")
	icon.custom_minimum_size = Vector2(58, 58)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	row.add_child(icon)
	var title := ui.label("HexagonProxy", 22, Color("12384a"))
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_shadow_color", Color(1, 1, 1, 0.6))
	title.add_theme_constant_override("shadow_offset_x", 2)
	title.add_theme_constant_override("shadow_offset_y", 2)
	row.add_child(title)

func _build_topbar(parent: Container) -> void:
	var top := HBoxContainer.new()
	top.custom_minimum_size.y = 54
	parent.add_child(top)
	page_title = ui.label("网络总览", 26, OVERLAY_TEXT)
	page_title.add_theme_color_override("font_shadow_color", Color("06344da0"))
	page_title.add_theme_constant_override("shadow_offset_x", 2)
	page_title.add_theme_constant_override("shadow_offset_y", 2)
	page_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(page_title)
	var status_pill := ui.panel(Color("f7ffffdf"), Color("a8e8e8e8"), 16)
	status_pill.custom_minimum_size = Vector2(190, 40)
	top.add_child(status_pill)
	var status_row := HBoxContainer.new()
	status_row.alignment = BoxContainer.ALIGNMENT_CENTER
	status_row.add_theme_constant_override("separation", 8)
	status_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
	status_pill.add_child(status_row)
	var status_dot := ui.label("●", 12, MUTED)
	status_row.add_child(status_dot)
	var status_label := ui.label("代理未连接", 13, MUTED)
	status_row.add_child(status_label)
	dashboard_panel.bind_status_controls(status_label, status_dot)

func _add_nav(parent: Container, page_name: String, text: String) -> void:
	var button := ui.button(text, Color("f4ffffa8"), MUTED)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size.y = 44
	button.pressed.connect(func() -> void: show_page(page_name))
	parent.add_child(button)
	nav_buttons[page_name] = button