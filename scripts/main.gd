extends Control

const CoreControllerScript = preload("res://scripts/core_controller.gd")
const TrafficGraphScript = preload("res://scripts/traffic_graph.gd")
const DesktopPetScript = preload("res://scripts/desktop_pet.gd")
const AquariumBackgroundScript = preload("res://scripts/aquarium_background.gd")

const TRAY_SHOW_MAIN := 1
const TRAY_SHOW_PET := 2
const TRAY_CONNECT := 3
const TRAY_AUTOSTART := 4
const TRAY_EXIT := 9

const BG := Color("dff8fb")
const SURFACE := Color("e9fbfbd4")
const SURFACE_2 := Color("d8f4f3dc")
const BORDER := Color("a8e8e8e8")
const TEXT := Color("12384a")
const MUTED := Color("527384")
const GREEN := Color("16866f")
const GREEN_DARK := Color("c5f1dfde")
const YELLOW := Color("b87918")
const RED := Color("c84d68")
const BLUE := Color("3478b8")
const OVERLAY_TEXT := Color("efffff")
const CRYSTAL_WHITE := Color("f7ffffdf")
const NODE_RENDER_BATCH_SIZE := 18

var controller: CoreController
var page_host: Control
var pages := {}
var nav_buttons := {}
var page_title: Label
var status_label: Label
var status_dot: Label
var connect_toggle: CheckButton
var proxy_toggle: CheckButton
var pet_speech: Label
var pet_texture: TextureRect
var profile_label: Label
var subscription_input: LineEdit
var v2_link_input: TextEdit
var subscription_list: VBoxContainer
var group_selector: OptionButton
var node_grid: GridContainer
var node_empty: Label
var traffic_graph: TrafficGraph
var download_speed_label: Label
var upload_speed_label: Label
var connections_label: Label
var total_label: Label
var log_view: RichTextLabel
var core_path_label: Label
var core_status_label: Label
var core_download_button: Button
var core_progress: ProgressBar
var core_progress_label: Label
var mode_buttons := {}
var desktop_pet_toggle: CheckButton
var close_to_tray_toggle: CheckButton
var autostart_toggle: CheckButton
var desktop_pet: Node
var tray_indicator: StatusIndicator
var tray_menu: PopupMenu
var app_settings := ConfigFile.new()
var proxy_groups: Array = []
var selected_group_index := 0
var delay_cache := {}
var _group_delay_pending: Array[String] = []
var previous_download := 0.0
var previous_upload := 0.0
var previous_sample_msec := 0
var _enable_proxy_when_online := false
var _refresh_tick := 0
var _close_to_tray := true
var _desktop_pet_enabled := true
var _quitting := false
var _current_node_name := ""
var _current_page_name := ""
var _node_rebuild_generation := 0

func _ready() -> void:
	controller = CoreControllerScript.new()
	add_child(controller)
	controller.status_changed.connect(_on_status_changed)
	controller.event_logged.connect(_append_log)
	controller.api_result.connect(_on_api_result)
	controller.download_progress.connect(_on_download_progress)
	controller.profile_changed.connect(_on_profile_changed)
	controller.subscriptions_changed.connect(_rebuild_subscription_list)
	controller.system_proxy_changed.connect(_on_system_proxy_changed)
	controller.system_proxy_busy_changed.connect(_on_system_proxy_busy_changed)
	controller.autostart_changed.connect(_on_autostart_changed)
	controller.autostart_busy_changed.connect(_on_autostart_busy_changed)
	_load_app_settings()
	_build_ui()
	_build_resident_features()
	controller.refresh_autostart_state()
	_show_page("dashboard")
	_on_status_changed(false, "代理未连接")
	_append_log("六角代理准备好了。")
	if not controller.has_core():
		_append_log("第一次使用：请到“设置”下载 Mihomo 内核。")
	var timer := Timer.new()
	timer.wait_time = 1.0
	timer.autostart = true
	timer.timeout.connect(_on_poll_timer)
	add_child(timer)
	get_tree().auto_accept_quit = false
	get_window().close_requested.connect(_on_main_window_close_requested)
	if "--tray-start" in OS.get_cmdline_user_args():
		call_deferred("_start_in_tray")

func _build_ui() -> void:
	var background: Control = AquariumBackgroundScript.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	move_child(background, 0)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	add_child(margin)
	var shell := HBoxContainer.new()
	shell.add_theme_constant_override("separation", 18)
	margin.add_child(shell)

	var sidebar := _panel(Color("e6fbf8dc"), Color("c7fffff2"), 22)
	sidebar.custom_minimum_size = Vector2(220, 0)
	shell.add_child(sidebar)
	var side_margin := _margin(16, 18, 16, 16)
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
	_add_nav(side, "settings", "⚙  设置")
	var side_spacer := Control.new()
	side_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(side_spacer)
	var side_note := Label.new()
	side_note.text = "HEXA NETWORK\nMihomo powered"
	side_note.add_theme_color_override("font_color", MUTED)
	side_note.add_theme_font_size_override("font_size", 11)
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
	pages["dashboard"] = _build_dashboard()
	pages["nodes"] = _build_nodes_page()
	pages["subscription"] = _build_subscription_page()
	pages["settings"] = _build_settings_page()
	for page in pages.values():
		page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		page_host.add_child(page)

func _build_brand(parent: Container) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	var icon_shell := _panel(Color("c9f4e3e8"), Color("8ddfc9"), 14)
	icon_shell.custom_minimum_size = Vector2(52, 52)
	row.add_child(icon_shell)
	var icon := TextureRect.new()
	icon.texture = _axolotl_texture()
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 7)
	icon_shell.add_child(icon)
	var names := VBoxContainer.new()
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(names)
	var title := _label("六角代理", 22, TEXT)
	title.add_theme_color_override("font_shadow_color", Color(1, 1, 1, 0.6))
	title.add_theme_constant_override("shadow_offset_x", 2)
	title.add_theme_constant_override("shadow_offset_y", 2)
	names.add_child(title)
	var sub := _label("HEXAGON PROXY", 10, GREEN)
	names.add_child(sub)

func _build_topbar(parent: Container) -> void:
	var top := HBoxContainer.new()
	top.custom_minimum_size.y = 54
	parent.add_child(top)
	page_title = _label("网络总览", 26, OVERLAY_TEXT)
	page_title.add_theme_color_override("font_shadow_color", Color("06344da0"))
	page_title.add_theme_constant_override("shadow_offset_x", 2)
	page_title.add_theme_constant_override("shadow_offset_y", 2)
	page_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(page_title)
	var status_pill := _panel(Color("efffffe0"), Color("c9fffff0"), 16)
	status_pill.custom_minimum_size = Vector2(190, 40)
	top.add_child(status_pill)
	var status_row := HBoxContainer.new()
	status_row.alignment = BoxContainer.ALIGNMENT_CENTER
	status_row.add_theme_constant_override("separation", 8)
	status_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
	status_pill.add_child(status_row)
	status_dot = _label("●", 12, MUTED)
	status_row.add_child(status_dot)
	status_label = _label("代理未连接", 13, MUTED)
	status_row.add_child(status_label)

func _build_dashboard() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 14)
	var hero_row := HBoxContainer.new()
	hero_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hero_row.add_theme_constant_override("separation", 14)
	page.add_child(hero_row)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 14)
	hero_row.add_child(left)
	left.add_child(_build_connection_card())
	left.add_child(_build_stats_row())
	left.add_child(_build_graph_card())

	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 330
	right.add_theme_constant_override("separation", 14)
	hero_row.add_child(right)
	right.add_child(_build_pet_card())
	right.add_child(_build_log_card())
	return page

func _build_connection_card() -> PanelContainer:
	var card := _panel(SURFACE, BORDER, 20)
	card.custom_minimum_size.y = 158
	var margin := _margin(22, 18, 22, 18)
	card.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	var top := HBoxContainer.new()
	column.add_child(top)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(words)
	words.add_child(_label("网络守护", 13, MUTED))
	var headline := _label("让六角恐龙接管网络", 24, TEXT)
	words.add_child(headline)
	connect_toggle = CheckButton.new()
	connect_toggle.text = "一键连接"
	connect_toggle.add_theme_font_size_override("font_size", 15)
	_apply_crystal_toggle_theme(connect_toggle)
	connect_toggle.toggled.connect(_on_connect_toggled)
	top.add_child(connect_toggle)
	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 8)
	column.add_child(mode_row)
	mode_row.add_child(_label("代理模式", 12, MUTED))
	var group := ButtonGroup.new()
	for item in [["rule", "规则"], ["global", "全局"], ["direct", "直连"]]:
		var button := _small_choice_button(item[1])
		button.toggle_mode = true
		button.button_group = group
		button.pressed.connect(func() -> void: controller.set_mode(item[0]))
		mode_row.add_child(button)
		mode_buttons[item[0]] = button
	mode_buttons["rule"].button_pressed = true
	return card

func _build_stats_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	download_speed_label = _stat_card(row, "↓ 下载", "0 B/s", GREEN)
	upload_speed_label = _stat_card(row, "↑ 上传", "0 B/s", BLUE)
	connections_label = _stat_card(row, "◎ 连接", "0", YELLOW)
	total_label = _stat_card(row, "Σ 流量", "0 B", Color("cc8cff"))
	return row

func _build_graph_card() -> PanelContainer:
	var card := _panel(SURFACE, BORDER, 20)
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size.y = 170
	var margin := _margin(18, 14, 18, 16)
	card.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)
	var row := HBoxContainer.new()
	column.add_child(row)
	var title := _label("实时流量", 15, TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	row.add_child(_label("最近 44 秒", 11, MUTED))
	traffic_graph = TrafficGraphScript.new()
	traffic_graph.custom_minimum_size.y = 116
	traffic_graph.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(traffic_graph)
	return card

func _build_pet_card() -> PanelContainer:
	var card := _panel(Color("ecfbf5dc"), Color("b4eee1ef"), 22)
	card.custom_minimum_size.y = 350
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 10)
	var margin := _margin(20, 14, 20, 16)
	card.add_child(margin)
	margin.add_child(column)
	var screen := _panel(Color("c7d79d"), Color("6b7954"), 18)
	screen.custom_minimum_size = Vector2(0, 225)
	column.add_child(screen)
	var screen_content := Control.new()
	screen_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(screen_content)
	var scan := ColorRect.new()
	scan.color = Color("b8cb8e")
	scan.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 10)
	screen_content.add_child(scan)
	pet_texture = TextureRect.new()
	pet_texture.texture = _axolotl_texture()
	pet_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pet_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pet_texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pet_texture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 24)
	screen_content.add_child(pet_texture)
	pet_speech = _label("等待出发！", 14, Color("253325"))
	pet_speech.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pet_speech.set_anchors_preset(Control.PRESET_TOP_WIDE)
	pet_speech.offset_top = 10
	pet_speech.offset_bottom = 36
	screen_content.add_child(pet_speech)
	var pet_name := _label("六角恐龙 · 美西螈守护兽", 14, TEXT)
	pet_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(pet_name)
	profile_label = _label(controller.current_profile_name, 12, MUTED)
	profile_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(profile_label)
	return card

func _build_log_card() -> PanelContainer:
	var card := _panel(SURFACE, BORDER, 18)
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var margin := _margin(14, 12, 14, 12)
	card.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	margin.add_child(column)
	column.add_child(_label("运行记录", 14, TEXT))
	log_view = RichTextLabel.new()
	log_view.bbcode_enabled = true
	log_view.fit_content = false
	log_view.scroll_active = true
	log_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_view.add_theme_font_size_override("normal_font_size", 11)
	log_view.add_theme_color_override("default_color", MUTED)
	column.add_child(log_view)
	return card

func _build_nodes_page() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 14)
	var toolbar := _panel(SURFACE, BORDER, 18)
	toolbar.custom_minimum_size.y = 78
	page.add_child(toolbar)
	var margin := _margin(18, 14, 18, 14)
	toolbar.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	margin.add_child(row)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(words)
	words.add_child(_label("选择守护路线", 18, TEXT))
	words.add_child(_label("延迟越低，小恐龙跑得越快", 11, MUTED))
	group_selector = OptionButton.new()
	group_selector.custom_minimum_size = Vector2(190, 40)
	group_selector.add_theme_font_size_override("font_size", 13)
	_apply_crystal_option_theme(group_selector)
	group_selector.item_selected.connect(_on_group_selected)
	row.add_child(group_selector)
	var test_all := _button("全部测速", GREEN_DARK, GREEN)
	test_all.pressed.connect(_test_visible_nodes)
	row.add_child(test_all)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(scroll)
	var grid_margin := _margin(2, 2, 8, 8)
	grid_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid_margin)
	node_grid = GridContainer.new()
	node_grid.columns = 3
	node_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node_grid.add_theme_constant_override("h_separation", 12)
	node_grid.add_theme_constant_override("v_separation", 12)
	grid_margin.add_child(node_grid)
	node_empty = _label("连接后，这里会出现节点。", 15, MUTED)
	node_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	node_empty.custom_minimum_size.y = 180
	node_grid.add_child(node_empty)
	return page

func _build_subscription_page() -> Control:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var page := VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 14)
	scroll.add_child(page)
	var intro := _panel(Color("e8faf5dc"), Color("b5eee0ef"), 20)
	intro.custom_minimum_size.y = 105
	page.add_child(intro)
	var intro_margin := _margin(22, 18, 22, 18)
	intro.add_child(intro_margin)
	var intro_row := HBoxContainer.new()
	intro_row.add_theme_constant_override("separation", 18)
	intro_margin.add_child(intro_row)
	var icon := TextureRect.new()
	icon.texture = _axolotl_texture()
	icon.custom_minimum_size = Vector2(92, 92)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	intro_row.add_child(icon)
	var words := VBoxContainer.new()
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	intro_row.add_child(words)
	words.add_child(_label("把路线交给六角恐龙", 22, TEXT))
	words.add_child(_label("支持 Clash / Mihomo 订阅，以及本地 YAML / YML 配置。", 13, MUTED))

	var url_card := _panel(SURFACE, BORDER, 20)
	url_card.custom_minimum_size.y = 165
	page.add_child(url_card)
	var url_margin := _margin(22, 18, 22, 18)
	url_card.add_child(url_margin)
	var url_column := VBoxContainer.new()
	url_column.add_theme_constant_override("separation", 12)
	url_margin.add_child(url_column)
	url_column.add_child(_label("订阅地址", 16, TEXT))
	url_column.add_child(_label("订阅地址可能包含凭据，只会写入本机 user://profiles。", 11, MUTED))
	var url_row := HBoxContainer.new()
	url_row.add_theme_constant_override("separation", 10)
	url_column.add_child(url_row)
	subscription_input = LineEdit.new()
	subscription_input.placeholder_text = "https://example.com/your-subscription"
	subscription_input.secret = true
	subscription_input.secret_character = "●"
	subscription_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	subscription_input.custom_minimum_size.y = 44
	subscription_input.add_theme_font_size_override("font_size", 13)
	subscription_input.add_theme_color_override("font_color", TEXT)
	subscription_input.add_theme_color_override("font_placeholder_color", MUTED)
	subscription_input.add_theme_stylebox_override("normal", _style(CRYSTAL_WHITE, BORDER, 12, 1))
	subscription_input.add_theme_stylebox_override("focus", _style(Color("f7fffff2"), GREEN, 12, 2))
	url_row.add_child(subscription_input)
	var add_button := _button("添加订阅", GREEN_DARK, GREEN)
	add_button.pressed.connect(func() -> void:
		if controller.use_subscription_url(subscription_input.text):
			subscription_input.clear()
	)
	url_row.add_child(add_button)

	var v2_card := _panel(Color("f3f4ffe0"), Color("d8d3f6f0"), 20)
	v2_card.custom_minimum_size.y = 185
	page.add_child(v2_card)
	var v2_margin := _margin(22, 14, 22, 14)
	v2_card.add_child(v2_margin)
	var v2_column := VBoxContainer.new()
	v2_column.add_theme_constant_override("separation", 8)
	v2_margin.add_child(v2_column)
	var v2_header := HBoxContainer.new()
	v2_column.add_child(v2_header)
	var v2_words := VBoxContainer.new()
	v2_words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v2_header.add_child(v2_words)
	v2_words.add_child(_label("V2 分享链接", 16, TEXT))
	v2_words.add_child(_label("支持 VLESS Reality、VMess、Hysteria2、Trojan、SS、TUIC；可一次粘贴多条。", 11, MUTED))
	var import_v2 := _button("导入 V2", Color("e8e2f8e8"), Color("765399"))
	import_v2.pressed.connect(func() -> void:
		if controller.use_v2_share_links(v2_link_input.text):
			v2_link_input.clear()
	)
	v2_header.add_child(import_v2)
	v2_link_input = TextEdit.new()
	v2_link_input.placeholder_text = "vless://...\nhysteria2://...\n也可粘贴 V2RayN Base64 订阅正文"
	v2_link_input.custom_minimum_size.y = 78
	v2_link_input.add_theme_font_size_override("font_size", 12)
	v2_link_input.add_theme_color_override("font_color", TEXT)
	v2_link_input.add_theme_color_override("font_placeholder_color", MUTED)
	v2_link_input.add_theme_stylebox_override("normal", _style(Color("faf8ffe8"), Color("d1c8ed"), 12, 1))
	v2_link_input.add_theme_stylebox_override("focus", _style(Color("fffafff2"), Color("9e7ac0"), 12, 2))
	v2_column.add_child(v2_link_input)

	var library_card := _panel(SURFACE, BORDER, 20)
	page.add_child(library_card)
	var library_margin := _margin(22, 16, 22, 16)
	library_card.add_child(library_margin)
	var library_column := VBoxContainer.new()
	library_column.add_theme_constant_override("separation", 10)
	library_margin.add_child(library_column)
	library_column.add_child(_label("已导入的订阅", 16, TEXT))
	library_column.add_child(_label("订阅会保存在本机；同一时间由一个 Mihomo 内核运行当前选中的配置。", 11, MUTED))
	subscription_list = VBoxContainer.new()
	subscription_list.add_theme_constant_override("separation", 8)
	library_column.add_child(subscription_list)
	_rebuild_subscription_list()

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 14)
	page.add_child(actions)
	var local_card := _action_card("导入本地配置", "使用完整的 Clash / Mihomo YAML", "选择文件")
	actions.add_child(local_card[0])
	local_card[1].pressed.connect(_open_profile_dialog)
	var refresh_card := _action_card("刷新订阅", "让内核立即拉取最新节点", "立即刷新")
	actions.add_child(refresh_card[0])
	refresh_card[1].pressed.connect(controller.update_provider)
	var hint := _panel(Color("f7f2ffe0"), Color("d7caeef0"), 16)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(hint)
	var hint_margin := _margin(16, 14, 16, 14)
	hint.add_child(hint_margin)
	var hint_text := _label("隐私提示\n六角代理不提供节点，也不会上传订阅。", 12, Color("72578c"))
	hint_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_margin.add_child(hint_text)
	return scroll

func _build_settings_page() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 14)
	var core_card := _panel(SURFACE, BORDER, 20)
	core_card.custom_minimum_size.y = 230
	page.add_child(core_card)
	var margin := _margin(22, 18, 22, 18)
	core_card.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	column.add_child(_label("Mihomo 内核", 18, TEXT))
	core_status_label = _label("已安装" if controller.has_core() else "尚未安装", 13, GREEN if controller.has_core() else YELLOW)
	column.add_child(core_status_label)
	core_path_label = _label(controller.core_path(), 11, MUTED)
	core_path_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(core_path_label)
	var core_row := HBoxContainer.new()
	core_row.add_theme_constant_override("separation", 10)
	column.add_child(core_row)
	core_download_button = _button("检查并下载最新内核", GREEN_DARK, GREEN)
	core_download_button.pressed.connect(controller.download_latest_core)
	core_row.add_child(core_download_button)
	var restart := _button("重启内核", SURFACE_2, TEXT)
	restart.pressed.connect(controller.restart_core)
	core_row.add_child(restart)
	core_progress = ProgressBar.new()
	core_progress.min_value = 0
	core_progress.max_value = 100
	core_progress.value = 0
	core_progress.show_percentage = false
	core_progress.custom_minimum_size.y = 8
	core_progress.visible = false
	column.add_child(core_progress)
	core_progress_label = _label("", 11, MUTED)
	column.add_child(core_progress_label)

	var behavior := _panel(SURFACE, BORDER, 20)
	behavior.custom_minimum_size.y = 330
	page.add_child(behavior)
	var behavior_margin := _margin(22, 18, 22, 18)
	behavior.add_child(behavior_margin)
	var behavior_column := VBoxContainer.new()
	behavior_column.add_theme_constant_override("separation", 12)
	behavior_margin.add_child(behavior_column)
	behavior_column.add_child(_label("连接设置", 18, TEXT))
	var proxy_row := HBoxContainer.new()
	behavior_column.add_child(proxy_row)
	var proxy_words := VBoxContainer.new()
	proxy_words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	proxy_row.add_child(proxy_words)
	proxy_words.add_child(_label("Windows 系统代理", 14, TEXT))
	proxy_words.add_child(_label("127.0.0.1:7890 · 退出时自动关闭", 11, MUTED))
	proxy_toggle = CheckButton.new()
	proxy_toggle.text = "启用"
	_apply_crystal_toggle_theme(proxy_toggle)
	proxy_toggle.toggled.connect(_on_system_proxy_toggled)
	proxy_row.add_child(proxy_toggle)
	var port_row := HBoxContainer.new()
	behavior_column.add_child(port_row)
	var port_label := _label("本地混合端口", 13, TEXT)
	port_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	port_row.add_child(port_label)
	port_row.add_child(_label("7890", 13, GREEN))
	var api_row := HBoxContainer.new()
	behavior_column.add_child(api_row)
	var api_label := _label("本地控制接口", 13, TEXT)
	api_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	api_row.add_child(api_label)
	api_row.add_child(_label("127.0.0.1:19090 · 密钥保护", 13, GREEN))
	var tray_row := HBoxContainer.new()
	behavior_column.add_child(tray_row)
	var tray_words := VBoxContainer.new()
	tray_words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tray_row.add_child(tray_words)
	tray_words.add_child(_label("关闭时驻留托盘", 13, TEXT))
	tray_words.add_child(_label("关闭主窗口后代理与桌宠继续运行", 10, MUTED))
	close_to_tray_toggle = CheckButton.new()
	close_to_tray_toggle.text = "启用"
	_apply_crystal_toggle_theme(close_to_tray_toggle)
	close_to_tray_toggle.set_pressed_no_signal(_close_to_tray)
	close_to_tray_toggle.toggled.connect(_on_close_to_tray_toggled)
	tray_row.add_child(close_to_tray_toggle)
	var pet_row := HBoxContainer.new()
	behavior_column.add_child(pet_row)
	var pet_words := VBoxContainer.new()
	pet_words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pet_row.add_child(pet_words)
	pet_words.add_child(_label("桌面宠物", 13, TEXT))
	pet_words.add_child(_label("透明置顶 · 可拖动 · 右键隐藏", 10, MUTED))
	desktop_pet_toggle = CheckButton.new()
	desktop_pet_toggle.text = "显示"
	_apply_crystal_toggle_theme(desktop_pet_toggle)
	desktop_pet_toggle.set_pressed_no_signal(_desktop_pet_enabled)
	desktop_pet_toggle.toggled.connect(_on_desktop_pet_toggled)
	pet_row.add_child(desktop_pet_toggle)
	var startup_row := HBoxContainer.new()
	behavior_column.add_child(startup_row)
	var startup_words := VBoxContainer.new()
	startup_words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	startup_row.add_child(startup_words)
	startup_words.add_child(_label("开机自启", 13, TEXT))
	startup_words.add_child(_label("登录 Windows 后从托盘启动", 10, MUTED))
	autostart_toggle = CheckButton.new()
	autostart_toggle.text = "启用"
	_apply_crystal_toggle_theme(autostart_toggle)
	autostart_toggle.set_pressed_no_signal(controller.is_autostart_enabled())
	autostart_toggle.toggled.connect(controller.set_autostart)
	startup_row.add_child(autostart_toggle)
	return page

func _on_poll_timer() -> void:
	_refresh_tick += 1
	if controller.online:
		if _refresh_tick % 2 == 0:
			controller.refresh_runtime()
		if _refresh_tick % 10 == 0:
			var group := _selected_group()
			if not group.is_empty():
				controller.test_group_delay(str(group.get("name", "")))
	else:
		traffic_graph.push_sample(0.0)
		if controller.starting or controller.core_pid > 0:
			controller.poll_status()

func _on_connect_toggled(enabled: bool) -> void:
	if enabled:
		_enable_proxy_when_online = true
		controller.start_core()
		if not controller.has_core():
			connect_toggle.set_pressed_no_signal(false)
			_show_page("settings")
	else:
		_enable_proxy_when_online = false
		controller.stop_core()

func _on_status_changed(is_online: bool, message: String) -> void:
	if not is_instance_valid(status_label):
		return
	status_label.text = message
	status_label.add_theme_color_override("font_color", GREEN if is_online else MUTED)
	status_dot.add_theme_color_override("font_color", GREEN if is_online else RED if controller.starting else MUTED)
	connect_toggle.set_pressed_no_signal(is_online or controller.starting)
	pet_speech.text = "路线畅通，出发！" if is_online else "正在热身…" if controller.starting else "等待出发！"
	pet_texture.modulate = Color.WHITE if is_online else Color(0.72, 0.76, 0.72, 1)
	if is_online and _enable_proxy_when_online and not controller.system_proxy_enabled:
		controller.set_system_proxy(true)
	if is_online:
		controller.refresh_runtime()
	_update_desktop_pet()
	_update_tray_menu()

func _on_system_proxy_changed(enabled: bool) -> void:
	if is_instance_valid(proxy_toggle):
		proxy_toggle.set_pressed_no_signal(enabled)

func _on_system_proxy_toggled(enabled: bool) -> void:
	_enable_proxy_when_online = enabled
	controller.set_system_proxy(enabled)

func _on_system_proxy_busy_changed(busy: bool) -> void:
	if is_instance_valid(proxy_toggle):
		proxy_toggle.disabled = busy
		proxy_toggle.text = "处理中…" if busy else "启用"

func _on_profile_changed(display_name: String) -> void:
	profile_label.text = display_name
	_rebuild_subscription_list()

func _rebuild_subscription_list() -> void:
	if not is_instance_valid(subscription_list) or not is_instance_valid(controller):
		return
	for child in subscription_list.get_children():
		subscription_list.remove_child(child)
		child.queue_free()
	var entries := controller.get_subscriptions()
	if entries.is_empty():
		subscription_list.add_child(_empty_message("还没有保存的订阅。导入后会出现在这里。"))
		return
	var active_id := controller.active_subscription_id()
	for entry_variant in entries:
		if not entry_variant is Dictionary:
			continue
		var entry: Dictionary = entry_variant
		subscription_list.add_child(_subscription_row(entry, str(entry.get("id", "")) == active_id))

func _subscription_row(entry: Dictionary, active: bool) -> PanelContainer:
	var row_card := _panel(GREEN_DARK if active else CRYSTAL_WHITE, GREEN if active else BORDER, 14)
	var margin := _margin(14, 10, 12, 10)
	row_card.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	margin.add_child(row)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(words)
	var display_name := str(entry.get("name", "订阅"))
	words.add_child(_label(display_name, 13, TEXT))
	var type_names := {"http": "HTTP / Mihomo", "v2": "V2 分享链接", "local": "本地 YAML"}
	var detail := str(type_names.get(str(entry.get("type", "local")), "本地配置"))
	if active:
		detail += " · 当前使用"
	words.add_child(_label(detail, 10, GREEN if active else MUTED))
	var entry_id := str(entry.get("id", ""))
	var use_button := _small_choice_button("使用中" if active else "切换")
	use_button.disabled = active
	use_button.pressed.connect(func() -> void: controller.activate_subscription(entry_id))
	row.add_child(use_button)
	var delete_button := _small_choice_button("删除")
	delete_button.add_theme_color_override("font_color", RED)
	delete_button.pressed.connect(func() -> void: _confirm_delete_subscription(entry_id, display_name))
	row.add_child(delete_button)
	return row_card

func _confirm_delete_subscription(entry_id: String, display_name: String) -> void:
	var overlay := Control.new()
	overlay.z_index = 100
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	var veil := ColorRect.new()
	veil.color = Color("0a354552")
	veil.mouse_filter = Control.MOUSE_FILTER_STOP
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(veil)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var card := _panel(Color("f6fffff5"), Color("bfffffff"), 20)
	card.custom_minimum_size = Vector2(520, 220)
	center.add_child(card)
	var margin := _margin(28, 24, 28, 22)
	card.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)
	var title := _label("删除订阅", 20, TEXT)
	column.add_child(title)
	var message := _label("确定删除“%s”吗？\n本机保存的配置文件也会一起删除，此操作无法撤销。" % display_name, 13, MUTED)
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(message)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 10)
	column.add_child(actions)
	var cancel_button := _button("取消", Color("e3f3f3e8"), TEXT)
	cancel_button.custom_minimum_size.x = 92
	cancel_button.add_theme_color_override("font_focus_color", TEXT)
	cancel_button.add_theme_stylebox_override("focus", _style(Color("f4fffff2"), GREEN, 12, 2))
	var cancel_shortcut := Shortcut.new()
	var escape_event := InputEventKey.new()
	escape_event.keycode = KEY_ESCAPE
	cancel_shortcut.events = [escape_event]
	cancel_button.shortcut = cancel_shortcut
	cancel_button.pressed.connect(overlay.queue_free)
	actions.add_child(cancel_button)
	var confirm_button := _button("删除", Color("ffe3e8ef"), RED)
	confirm_button.custom_minimum_size.x = 92
	confirm_button.add_theme_color_override("font_hover_color", RED)
	confirm_button.add_theme_color_override("font_pressed_color", RED)
	confirm_button.add_theme_color_override("font_focus_color", RED)
	confirm_button.add_theme_stylebox_override("hover", _style(Color("ffd4ddef"), RED, 12, 2))
	confirm_button.add_theme_stylebox_override("focus", _style(Color("ffdce3f5"), RED, 12, 2))
	confirm_button.pressed.connect(func() -> void:
		controller.delete_subscription(entry_id)
		overlay.queue_free()
	)
	actions.add_child(confirm_button)
	confirm_button.grab_focus()

func _on_download_progress(progress: float, message: String) -> void:
	core_progress.visible = progress >= 0.0 and progress < 1.0
	core_progress.value = maxf(progress, 0.0) * 100.0
	core_progress_label.text = message
	core_progress_label.add_theme_color_override("font_color", RED if progress < 0.0 else GREEN if progress >= 1.0 else MUTED)
	core_download_button.disabled = progress >= 0.0 and progress < 1.0
	if progress >= 1.0:
		core_status_label.text = "已安装"
		core_status_label.add_theme_color_override("font_color", GREEN)

func _on_api_result(action: String, ok: bool, payload: Variant) -> void:
	if not ok:
		if action.begins_with("delay:"):
			delay_cache[action.trim_prefix("delay:")] = -1
			_rebuild_nodes()
			_update_desktop_pet()
		elif action == "group_delay":
			for proxy_name in _group_delay_pending:
				delay_cache[proxy_name] = -1
			_group_delay_pending.clear()
			_rebuild_nodes()
			_update_desktop_pet()
		return
	if action == "proxies" and payload is Dictionary:
		_apply_proxies(payload)
	elif action == "connections" and payload is Dictionary:
		_apply_connections(payload)
	elif action == "config" and payload is Dictionary:
		var mode := str(payload.get("mode", "rule")).to_lower()
		if mode_buttons.has(mode):
			mode_buttons[mode].set_pressed_no_signal(true)
	elif action.begins_with("delay:") and payload is Dictionary:
		var proxy_name := action.trim_prefix("delay:")
		delay_cache[proxy_name] = int(payload.get("delay", -1))
		_rebuild_nodes()
		_update_desktop_pet()
	elif action == "group_delay" and payload is Dictionary:
		for proxy_name in _group_delay_pending:
			if not payload.has(proxy_name):
				delay_cache[proxy_name] = -1
		for proxy_name in payload:
			delay_cache[str(proxy_name)] = int(payload[proxy_name])
		_group_delay_pending.clear()
		_rebuild_nodes()
		_update_desktop_pet()
	elif action in ["select_proxy", "update_provider", "set_mode"]:
		controller.refresh_runtime()

func _apply_proxies(payload: Dictionary) -> void:
	var proxy_map_value: Variant = payload.get("proxies", {})
	var proxy_map: Dictionary = proxy_map_value if proxy_map_value is Dictionary else {}
	var groups: Array = []
	for proxy_name in proxy_map:
		var data: Variant = proxy_map[proxy_name]
		if not data is Dictionary:
			continue
		# GLOBAL is Mihomo's synthetic mode group. Its entries are policies such as
		# DIRECT/REJECT rather than imported subscription nodes.
		if str(proxy_name).to_upper() == "GLOBAL":
			continue
		var kind := str(data.get("type", ""))
		if kind in ["Selector", "URLTest", "Fallback", "LoadBalance"] and data.get("all", []) is Array:
			groups.append({
				"name": str(proxy_name),
				"type": kind,
				"now": str(data.get("now", "")),
				"all": data.get("all", [])
			})
	proxy_groups = groups
	var selected_name := ""
	if group_selector.item_count > 0 and selected_group_index < group_selector.item_count:
		selected_name = group_selector.get_item_text(selected_group_index)
	group_selector.clear()
	var next_selected_index := -1
	var preferred_index := -1
	for index in proxy_groups.size():
		group_selector.add_item(proxy_groups[index]["name"])
		if proxy_groups[index]["name"] == selected_name:
			next_selected_index = index
		if proxy_groups[index]["name"] == "六角选择":
			preferred_index = index
	selected_group_index = next_selected_index if next_selected_index >= 0 else preferred_index if preferred_index >= 0 else 0
	if group_selector.item_count > 0:
		group_selector.select(selected_group_index)
	var current_group := _selected_group()
	_current_node_name = str(current_group.get("now", ""))
	_rebuild_nodes()
	_update_desktop_pet()

func _apply_connections(payload: Dictionary) -> void:
	var download := float(payload.get("downloadTotal", 0.0))
	var upload := float(payload.get("uploadTotal", 0.0))
	var now := Time.get_ticks_msec()
	var elapsed := maxf(float(now - previous_sample_msec) / 1000.0, 0.2) if previous_sample_msec > 0 else 1.0
	var down_speed := maxf((download - previous_download) / elapsed, 0.0) if previous_sample_msec > 0 else 0.0
	var up_speed := maxf((upload - previous_upload) / elapsed, 0.0) if previous_sample_msec > 0 else 0.0
	previous_download = download
	previous_upload = upload
	previous_sample_msec = now
	download_speed_label.text = _format_bytes(down_speed) + "/s"
	upload_speed_label.text = _format_bytes(up_speed) + "/s"
	var connections_value: Variant = payload.get("connections", [])
	var connections: Array = connections_value if connections_value is Array else []
	connections_label.text = str(connections.size())
	total_label.text = _format_bytes(download + upload)
	traffic_graph.push_sample(down_speed + up_speed)

func _on_group_selected(index: int) -> void:
	selected_group_index = index
	var group := _selected_group()
	_current_node_name = str(group.get("now", ""))
	_rebuild_nodes()
	_update_desktop_pet()

func _rebuild_nodes() -> void:
	_node_rebuild_generation += 1
	var generation := _node_rebuild_generation
	if not is_instance_valid(node_grid):
		return
	if _current_page_name != "nodes":
		return
	for child in node_grid.get_children():
		node_grid.remove_child(child)
		child.queue_free()
	if proxy_groups.is_empty() or selected_group_index >= proxy_groups.size():
		node_grid.add_child(_empty_message("连接后，这里会出现节点。"))
		return
	var group: Dictionary = proxy_groups[selected_group_index]
	var nodes_value: Variant = group.get("all", [])
	var nodes: Array = nodes_value if nodes_value is Array else []
	if nodes.is_empty():
		node_grid.add_child(_empty_message("这个策略组暂时没有节点。"))
		return
	for index in nodes.size():
		if generation != _node_rebuild_generation or _current_page_name != "nodes":
			return
		var proxy_name_variant: Variant = nodes[index]
		var proxy_name := str(proxy_name_variant)
		node_grid.add_child(_node_card(group["name"], proxy_name, proxy_name == group.get("now", "")))
		if (index + 1) % NODE_RENDER_BATCH_SIZE == 0:
			await get_tree().process_frame

func _node_card(group_name: String, proxy_name: String, selected: bool) -> PanelContainer:
	var card := _panel(GREEN_DARK if selected else SURFACE, GREEN if selected else BORDER, 16)
	card.custom_minimum_size = Vector2(245, 112)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var margin := _margin(14, 12, 14, 12)
	card.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)
	var name_label := _label(proxy_name, 14, TEXT)
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.tooltip_text = proxy_name
	column.add_child(name_label)
	var bottom := HBoxContainer.new()
	column.add_child(bottom)
	var delay: int = int(delay_cache.get(proxy_name, 0))
	var delay_text := "测速" if delay == 0 else "测速中…" if delay == -2 else "失败" if delay < 0 else "%d ms" % delay
	var delay_label := _label(delay_text, 12, MUTED if delay in [0, -2] else RED if delay < 0 else GREEN if delay < 180 else YELLOW)
	delay_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(delay_label)
	var test := _small_choice_button("测")
	test.pressed.connect(func() -> void:
		delay_cache[proxy_name] = -2
		_rebuild_nodes()
		controller.test_proxy_delay(proxy_name)
	)
	bottom.add_child(test)
	var choose := _small_choice_button("已选" if selected else "选择")
	choose.disabled = selected
	choose.pressed.connect(func() -> void: controller.select_proxy(group_name, proxy_name))
	bottom.add_child(choose)
	return card

func _test_visible_nodes() -> void:
	if proxy_groups.is_empty() or selected_group_index >= proxy_groups.size():
		return
	var group: Dictionary = proxy_groups[selected_group_index]
	var nodes_value: Variant = group.get("all", [])
	var nodes: Array = nodes_value if nodes_value is Array else []
	_group_delay_pending.clear()
	for proxy_name_variant in nodes:
		var proxy_name := str(proxy_name_variant)
		_group_delay_pending.append(proxy_name)
		delay_cache[proxy_name] = -2
	_rebuild_nodes()
	controller.test_group_delay(str(group.get("name", "")))

func _selected_group() -> Dictionary:
	if selected_group_index >= 0 and selected_group_index < proxy_groups.size():
		return proxy_groups[selected_group_index]
	return {}

func _update_desktop_pet() -> void:
	var delay := int(delay_cache.get(_current_node_name, 0))
	if is_instance_valid(desktop_pet):
		desktop_pet.set_node_status(_current_node_name, delay, controller.online)
	if is_instance_valid(tray_indicator):
		if not controller.online:
			tray_indicator.tooltip = "六角代理 · 未连接"
		elif _current_node_name.is_empty():
			tray_indicator.tooltip = "六角代理 · 已连接"
		else:
			var delay_text := "测速中" if delay <= 0 else "%d ms" % delay
			tray_indicator.tooltip = "六角代理 · %s · %s" % [_current_node_name, delay_text]

func _open_profile_dialog() -> void:
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.use_native_dialog = true
	dialog.filters = PackedStringArray(["*.yaml, *.yml ; Mihomo / Clash 配置"])
	dialog.file_selected.connect(func(path: String) -> void:
		controller.import_local_profile(path)
		dialog.queue_free()
	)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered_ratio(0.7)

func _build_resident_features() -> void:
	if DisplayServer.get_name() == "headless":
		return
	tray_menu = PopupMenu.new()
	tray_menu.name = "TrayMenu"
	tray_menu.prefer_native_menu = true
	tray_menu.add_item("显示六角代理", TRAY_SHOW_MAIN)
	tray_menu.add_check_item("显示桌面宠物", TRAY_SHOW_PET)
	tray_menu.add_check_item("连接代理", TRAY_CONNECT)
	tray_menu.add_separator()
	tray_menu.add_check_item("开机自启", TRAY_AUTOSTART)
	tray_menu.add_separator()
	tray_menu.add_item("退出六角代理", TRAY_EXIT)
	tray_menu.id_pressed.connect(_on_tray_menu_pressed)
	add_child(tray_menu)
	tray_indicator = StatusIndicator.new()
	tray_indicator.name = "TrayIndicator"
	tray_indicator.icon = _axolotl_texture()
	tray_indicator.tooltip = "六角代理 · 未连接"
	add_child(tray_indicator)
	tray_indicator.menu = tray_indicator.get_path_to(tray_menu)

	desktop_pet = DesktopPetScript.new()
	add_child(desktop_pet)
	desktop_pet.main_requested.connect(_show_main_window)
	desktop_pet.hidden_by_user.connect(_on_pet_hidden_by_user)
	var stored_position := Vector2i(
		int(app_settings.get_value("desktop_pet", "x", -10000)),
		int(app_settings.get_value("desktop_pet", "y", -10000))
	)
	desktop_pet.create_pet(stored_position, _desktop_pet_enabled)
	desktop_pet.set_node_status("", 0, false)
	_update_tray_menu()

func _load_app_settings() -> void:
	app_settings.load("user://settings.cfg")
	_close_to_tray = bool(app_settings.get_value("resident", "close_to_tray", true))
	_desktop_pet_enabled = bool(app_settings.get_value("desktop_pet", "visible", true))

func _save_app_settings() -> void:
	app_settings.set_value("resident", "close_to_tray", _close_to_tray)
	app_settings.set_value("desktop_pet", "visible", _desktop_pet_enabled)
	if is_instance_valid(desktop_pet):
		var pet_position: Vector2i = desktop_pet.get_pet_position()
		app_settings.set_value("desktop_pet", "x", pet_position.x)
		app_settings.set_value("desktop_pet", "y", pet_position.y)
	app_settings.save("user://settings.cfg")

func _on_main_window_close_requested() -> void:
	if _quitting:
		return
	if _close_to_tray and is_instance_valid(tray_indicator):
		get_window().hide()
		_append_log("主窗口已隐藏到托盘。")
	else:
		_quit_application()

func _show_main_window() -> void:
	var main_window := get_window()
	main_window.show()
	if main_window.mode == Window.MODE_MINIMIZED:
		main_window.mode = Window.MODE_WINDOWED
	main_window.grab_focus()

func _start_in_tray() -> void:
	get_window().hide()
	_enable_proxy_when_online = true
	controller.start_core()

func _on_tray_menu_pressed(id: int) -> void:
	match id:
		TRAY_SHOW_MAIN:
			_show_main_window()
		TRAY_SHOW_PET:
			_set_desktop_pet_visible(not _desktop_pet_enabled)
		TRAY_CONNECT:
			var enable := not (controller.online or controller.starting)
			connect_toggle.set_pressed_no_signal(enable)
			_on_connect_toggled(enable)
		TRAY_AUTOSTART:
			controller.set_autostart(not controller.is_autostart_enabled())
		TRAY_EXIT:
			_quit_application()

func _on_close_to_tray_toggled(enabled: bool) -> void:
	_close_to_tray = enabled
	_save_app_settings()

func _on_desktop_pet_toggled(enabled: bool) -> void:
	_set_desktop_pet_visible(enabled)

func _set_desktop_pet_visible(enabled: bool) -> void:
	_desktop_pet_enabled = enabled
	if is_instance_valid(desktop_pet):
		desktop_pet.set_pet_visible(enabled)
	if is_instance_valid(desktop_pet_toggle):
		desktop_pet_toggle.set_pressed_no_signal(enabled)
	_save_app_settings()
	_update_tray_menu()

func _on_pet_hidden_by_user() -> void:
	_set_desktop_pet_visible(false)

func _on_autostart_changed(enabled: bool) -> void:
	if is_instance_valid(autostart_toggle):
		autostart_toggle.set_pressed_no_signal(enabled)
	_update_tray_menu()

func _on_autostart_busy_changed(busy: bool) -> void:
	if is_instance_valid(autostart_toggle):
		autostart_toggle.disabled = busy
		autostart_toggle.text = "处理中…" if busy else "启用"

func _update_tray_menu() -> void:
	if not is_instance_valid(tray_menu):
		return
	var pet_index := tray_menu.get_item_index(TRAY_SHOW_PET)
	var connect_index := tray_menu.get_item_index(TRAY_CONNECT)
	var startup_index := tray_menu.get_item_index(TRAY_AUTOSTART)
	tray_menu.set_item_checked(pet_index, _desktop_pet_enabled)
	tray_menu.set_item_checked(connect_index, controller.online or controller.starting)
	tray_menu.set_item_text(connect_index, "断开代理" if controller.online or controller.starting else "连接代理")
	tray_menu.set_item_checked(startup_index, controller.is_autostart_enabled())

func _quit_application() -> void:
	if _quitting:
		return
	_quitting = true
	_save_app_settings()
	if is_instance_valid(tray_indicator):
		tray_indicator.visible = false
	controller.stop_core()
	get_tree().quit()

func _add_nav(parent: Container, page_name: String, text: String) -> void:
	var button := _button(text, Color("f4ffffa8"), MUTED)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size.y = 44
	button.pressed.connect(func() -> void: _show_page(page_name))
	parent.add_child(button)
	nav_buttons[page_name] = button

func _show_page(page_id: String) -> void:
	_current_page_name = page_id
	var titles := {
		"dashboard": "网络总览",
		"nodes": "节点路线",
		"subscription": "订阅管理",
		"settings": "偏好设置"
	}
	for page_name in pages:
		pages[page_name].visible = page_name == page_id
	for nav_name in nav_buttons:
		var active: bool = str(nav_name) == page_id
		var button: Button = nav_buttons[nav_name]
		button.add_theme_color_override("font_color", GREEN if active else MUTED)
		button.add_theme_stylebox_override("normal", _style(GREEN_DARK if active else Color("f4ffffa8"), Color("75cdb4") if active else Color("ffffff80"), 12, 1))
	if is_instance_valid(page_title):
		page_title.text = titles.get(page_id, "六角代理")
	if page_id == "nodes":
		_rebuild_nodes()

func _append_log(message: String) -> void:
	if not is_instance_valid(log_view):
		return
	var time := Time.get_time_string_from_system()
	log_view.append_text("[color=#527384]%s[/color]  %s\n" % [time, message])
	log_view.scroll_to_line(maxi(log_view.get_line_count() - 1, 0))

func _format_bytes(value: float) -> String:
	if value < 1024.0:
		return "%d B" % int(value)
	if value < 1024.0 * 1024.0:
		return "%.1f KB" % (value / 1024.0)
	if value < 1024.0 * 1024.0 * 1024.0:
		return "%.1f MB" % (value / 1024.0 / 1024.0)
	return "%.2f GB" % (value / 1024.0 / 1024.0 / 1024.0)

func _panel(fill: Color, border: Color, radius: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style(fill, border, radius, 1))
	return panel

func _style(fill: Color, border: Color, radius: int, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	style.shadow_color = Color("3eb9c42d")
	style.shadow_size = 7
	style.shadow_offset = Vector2(0, 3)
	style.anti_aliasing = true
	return style

func _margin(left: int, top: int, right: int, bottom: int) -> MarginContainer:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", left)
	margin.add_theme_constant_override("margin_top", top)
	margin.add_theme_constant_override("margin_right", right)
	margin.add_theme_constant_override("margin_bottom", bottom)
	return margin

func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

func _button(text: String, fill: Color, color: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 40
	button.add_theme_font_size_override("font_size", 13)
	button.add_theme_color_override("font_color", color)
	button.add_theme_color_override("font_hover_color", TEXT)
	button.add_theme_color_override("font_pressed_color", TEXT)
	button.add_theme_stylebox_override("normal", _style(fill, Color.TRANSPARENT, 12, 1))
	button.add_theme_stylebox_override("hover", _style(fill.lightened(0.08), BORDER, 12, 1))
	button.add_theme_stylebox_override("pressed", _style(fill.darkened(0.08), GREEN, 12, 1))
	button.add_theme_stylebox_override("disabled", _style(Color("d5e9e8b8"), Color("ffffff70"), 12, 1))
	return button

func _small_choice_button(text: String) -> Button:
	var button := _button(text, SURFACE_2, MUTED)
	button.custom_minimum_size = Vector2(58, 32)
	button.add_theme_font_size_override("font_size", 12)
	button.add_theme_stylebox_override("pressed", _style(GREEN_DARK, GREEN, 10, 1))
	button.add_theme_color_override("font_pressed_color", GREEN)
	return button

func _apply_crystal_toggle_theme(toggle: CheckButton) -> void:
	toggle.add_theme_color_override("font_color", TEXT)
	toggle.add_theme_color_override("font_hover_color", GREEN)
	toggle.add_theme_color_override("font_pressed_color", GREEN)
	toggle.add_theme_color_override("font_focus_color", TEXT)
	toggle.add_theme_color_override("font_disabled_color", Color("78909a"))

func _apply_crystal_option_theme(option: OptionButton) -> void:
	option.add_theme_color_override("font_color", TEXT)
	option.add_theme_color_override("font_hover_color", GREEN)
	option.add_theme_color_override("font_pressed_color", GREEN)
	option.add_theme_color_override("font_focus_color", TEXT)
	option.add_theme_stylebox_override("normal", _style(CRYSTAL_WHITE, BORDER, 12, 1))
	option.add_theme_stylebox_override("hover", _style(Color("f8ffffef"), Color("7ed8d2"), 12, 2))
	option.add_theme_stylebox_override("pressed", _style(Color("d9f4eee8"), GREEN, 12, 2))
	option.add_theme_stylebox_override("focus", _style(Color("f8ffffef"), GREEN, 12, 2))
	var popup := option.get_popup()
	popup.add_theme_color_override("font_color", TEXT)
	popup.add_theme_color_override("font_hover_color", GREEN)
	popup.add_theme_color_override("font_accelerator_color", MUTED)
	popup.add_theme_stylebox_override("panel", _style(Color("f4fffff5"), BORDER, 12, 1))
	popup.add_theme_stylebox_override("hover", _style(Color("d4f3e8ee"), Color("8ddfc9"), 8, 1))

func _stat_card(parent: Container, title: String, value: String, color: Color) -> Label:
	var card := _panel(SURFACE, BORDER, 16)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size.y = 82
	parent.add_child(card)
	var margin := _margin(13, 10, 13, 10)
	card.add_child(margin)
	var column := VBoxContainer.new()
	margin.add_child(column)
	column.add_child(_label(title, 11, MUTED))
	var value_label := _label(value, 18, color)
	column.add_child(value_label)
	return value_label

func _action_card(title: String, description: String, action: String) -> Array:
	var card := _panel(SURFACE, BORDER, 16)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var margin := _margin(16, 14, 16, 14)
	card.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 7)
	margin.add_child(column)
	column.add_child(_label(title, 14, TEXT))
	var desc := _label(description, 11, MUTED)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(desc)
	var button := _small_choice_button(action)
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	column.add_child(button)
	return [card, button]

func _empty_message(text: String) -> Label:
	var label := _label(text, 15, MUTED)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(760, 180)
	return label

func _axolotl_texture() -> AtlasTexture:
	var texture := AtlasTexture.new()
	texture.atlas = load("res://assets/axolotl.png")
	texture.region = Rect2(24, 44, 112, 72)
	return texture
