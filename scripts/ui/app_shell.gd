class_name AppShell
extends Node

signal window_action_requested(action_id: String)

const AquariumBackgroundScript = preload("res://scripts/aquarium_background.gd")
const AntigravityProxyPanelScript = preload("res://scripts/ui/antigravity_proxy_panel.gd")
const WINDOW_ACTIONS := [
	{"id": "minimize", "text": "最小化", "tooltip": "最小化到任务栏", "width": 84},
	{"id": "close", "text": "关闭", "tooltip": "关闭主窗口并继续后台守护", "width": 72},
	{"id": "exit", "text": "退出", "tooltip": "安全退出 HexagonProxy", "width": 72, "danger": true}
]
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
var codex_accounts_panel: CodexAccountsPanel
var antigravity_proxy_panel: AntigravityProxyPanel
var settings_panel: SettingsPanel
var page_host: Control
var pages := {}
var nav_buttons := {}
var rail_buttons := {}
var window_action_buttons := {}
var page_title: Label
var aquarium_background: Control
var _current_page := ""

func setup(owner: Control, factory: UiFactory, dashboard: DashboardPanel, nodes: NodesPanel, subscription: SubscriptionPanel, routing: RoutingPanel, terminal: TerminalPanel, codex_accounts: CodexAccountsPanel, settings: SettingsPanel) -> void:
	host = owner
	ui = factory
	dashboard_panel = dashboard
	nodes_panel = nodes
	subscription_panel = subscription
	routing_panel = routing
	terminal_panel = terminal
	codex_accounts_panel = codex_accounts
	settings_panel = settings

func build(profile_name: String) -> void:
	var app_theme := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Segoe UI"])
	app_theme.default_font = font
	host.theme = app_theme
	host.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var background := ColorRect.new()
	background.color = Color.WHITE
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	aquarium_background = background
	ui.apply_background_theme(aquarium_background)
	aquarium_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.add_child(aquarium_background)
	host.move_child(aquarium_background, 0)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 0)
	margin.add_theme_constant_override("margin_top", 0)
	margin.add_theme_constant_override("margin_right", 0)
	margin.add_theme_constant_override("margin_bottom", 0)
	host.add_child(margin)
	var shell := HBoxContainer.new()
	shell.add_theme_constant_override("separation", 0)
	margin.add_child(shell)

	_build_rail(shell)
	var sidebar := ui.panel(Color("e6fbf8dc"), Color("c7fffff2"), 0)
	sidebar.custom_minimum_size = Vector2(210, 0)
	shell.add_child(sidebar)
	var side_margin := ui.margin(6, 20, 6, 20)
	sidebar.add_child(side_margin)
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 10)
	side_margin.add_child(side)
	_build_brand(side)
	var spacer_small := Control.new()
	spacer_small.custom_minimum_size.y = 14
	side.add_child(spacer_small)
	side.add_child(ui.label("工作台", 11, MUTED))
	_add_nav(side, "dashboard", "⌂  总览")
	_add_nav(side, "nodes", "⬡  节点")
	_add_nav(side, "subscription", "↻  订阅")
	_add_nav(side, "routing", "⇄  分流")
	_add_nav(side, "terminal", ">_  终端")
	_add_nav(side, "codex", "◈  Codex 账号")
	_add_nav(side, "antigravity", "↗  Antigravity")
	_add_nav(side, "settings", "⚙  设置")
	var side_spacer := Control.new()
	side_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(side_spacer)
	var side_note := ui.label("Mihomo powered", 11, MUTED)
	side.add_child(side_note)

	var content_margin := ui.margin(24, 14, 24, 24)
	content_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shell.add_child(content_margin)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	content_margin.add_child(body)
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
	pages["codex"] = codex_accounts_panel.build()
	antigravity_proxy_panel = AntigravityProxyPanelScript.new()
	add_child(antigravity_proxy_panel)
	antigravity_proxy_panel.setup(ui, host)
	pages["antigravity"] = antigravity_proxy_panel.build()
	pages["settings"] = settings_panel.build()
	for page in pages.values():
		page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		page_host.add_child(page)

func show_page(page_id: String) -> void:
	if _current_page == page_id:
		return
	_current_page = page_id
	var titles := {
		"dashboard": "网络总览",
		"nodes": "节点路线",
		"subscription": "订阅管理",
		"routing": "应用分流",
		"terminal": "内置终端",
		"codex": "Codex 账号",
		"antigravity": "Antigravity",
		"settings": "偏好设置"
	}
	for page_name in pages:
		pages[page_name].visible = page_name == page_id
	if is_instance_valid(dashboard_panel):
		dashboard_panel.set_dashboard_active(page_id == 'dashboard')
	for nav_name in nav_buttons:
		var active: bool = str(nav_name) == page_id
		var button: Button = nav_buttons[nav_name]
		ui.apply_nav_button(button, active)
	for page_name in rail_buttons:
		ui.apply_rail_button(rail_buttons[page_name], str(page_name) == page_id)
	if is_instance_valid(page_title):
		page_title.text = titles.get(page_id, "HexagonProxy")
	nodes_panel.set_active(page_id == "nodes")

func _build_brand(parent: Container) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	var icon := TextureRect.new()
	icon.texture = ui.axolotl_texture()
	icon.custom_minimum_size = Vector2(32, 32)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	row.add_child(icon)
	var title := ui.label("HexagonProxy", 15, Color("12384a"))
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(title)

func _build_topbar(parent: Container) -> void:
	var top := HBoxContainer.new()
	top.custom_minimum_size.y = 54
	parent.add_child(top)
	page_title = ui.label("网络总览", 20, OVERLAY_TEXT)
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
	status_label.custom_minimum_size.x = 230
	status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_row.add_child(status_label)
	dashboard_panel.bind_status_controls(status_label, status_dot)
	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 6)
	top.add_child(action_row)
	_build_window_actions(action_row)

func _build_window_actions(parent: HBoxContainer) -> void:
	window_action_buttons.clear()
	for action in WINDOW_ACTIONS:
		if not action is Dictionary:
			continue
		var action_id := str(action.get("id", ""))
		var action_color := ui.danger_color if bool(action.get("danger", false)) else Color.TRANSPARENT
		var button := ui.small_choice_button(str(action.get("text", action_id)), action_color)
		button.custom_minimum_size = Vector2(float(action.get("width", 72)), 34)
		button.tooltip_text = str(action.get("tooltip", ""))
		button.pressed.connect(_on_window_action.bind(action_id))
		parent.add_child(button)
		window_action_buttons[action_id] = button

func _on_window_action(action_id: String) -> void:
	window_action_requested.emit(action_id)

func _add_nav(parent: Container, page_name: String, text: String) -> void:
	var button := ui.button(text, Color("f4ffffa8"), MUTED)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size.y = 52
	button.pressed.connect(func() -> void: show_page(page_name))
	parent.add_child(button)
	nav_buttons[page_name] = button

func _build_rail(parent: Container) -> void:
	var rail := ui.panel(ui.color("rail", ui.console_bg_color), Color.TRANSPARENT, 0)
	rail.custom_minimum_size.x = 64
	parent.add_child(rail)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	rail.add_child(column)
	for item in [["⌂", "dashboard", "总览"], ["⬡", "nodes", "节点"], ["◈", "codex", "Codex 账号"], ["↗", "antigravity", "Antigravity"]]:
		var button := ui.small_choice_button(item[0])
		button.custom_minimum_size = Vector2(40, 44)
		ui.apply_rail_button(button, false)
		button.tooltip_text = item[2]
		button.pressed.connect(func() -> void: show_page(item[1]))
		column.add_child(button)
		rail_buttons[item[1]] = button
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)
	var settings := ui.small_choice_button("⚙")
	settings.tooltip_text = "偏好设置"
	ui.apply_rail_button(settings, false)
	settings.pressed.connect(func() -> void: show_page("settings"))
	column.add_child(settings)
	rail_buttons["settings"] = settings
