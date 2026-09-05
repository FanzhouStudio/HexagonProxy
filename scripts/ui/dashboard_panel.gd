class_name DashboardPanel
extends Node

signal connect_requested(enabled: bool)
signal mode_requested(mode: String)

const TrafficGraphScript = preload("res://scripts/traffic_graph.gd")
const SURFACE := Color("e9fbfbd4")
const BORDER := Color("a8e8e8e8")
const TEXT := Color("12384a")
const MUTED := Color("527384")
const GREEN := Color("16866f")
const GREEN_DARK := Color("c5f1dfde")
const YELLOW := Color("b87918")
const RED := Color("c84d68")
const BLUE := Color("3478b8")

var ui: UiFactory
var status_label: Label
var status_dot: Label
var connect_toggle: CheckButton
var pet_speech: Label
var pet_texture: TextureRect
var profile_label: Label
var traffic_graph: TrafficGraph
var download_speed_label: Label
var upload_speed_label: Label
var connections_label: Label
var total_label: Label
var log_view: RichTextLabel
var mode_buttons := {}
var previous_download := 0.0
var previous_upload := 0.0
var previous_sample_msec := 0

func setup(factory: UiFactory) -> void:
	ui = factory

func bind_status_controls(label_control: Label, dot_control: Label) -> void:
	status_label = label_control
	status_dot = dot_control

func build(profile_name: String) -> Control:
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
	right.add_child(_build_pet_card(profile_name))
	right.add_child(_build_log_card())
	return page
func _build_connection_card() -> PanelContainer:
	var card := ui.panel(SURFACE, BORDER, 20)
	card.custom_minimum_size.y = 158
	var content_margin := ui.margin(22, 18, 22, 18)
	card.add_child(content_margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	content_margin.add_child(column)
	var top := HBoxContainer.new()
	column.add_child(top)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(words)
	words.add_child(ui.label("网络守护", 13, MUTED))
	words.add_child(ui.label("让六角恐龙接管网络", 24, TEXT))
	connect_toggle = CheckButton.new()
	connect_toggle.text = "一键连接"
	connect_toggle.add_theme_font_size_override("font_size", 15)
	ui.apply_crystal_toggle_theme(connect_toggle)
	connect_toggle.toggled.connect(func(value: bool) -> void: connect_requested.emit(value))
	top.add_child(connect_toggle)
	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 8)
	column.add_child(mode_row)
	mode_row.add_child(ui.label("代理模式", 12, MUTED))
	var group := ButtonGroup.new()
	for item in [["rule", "规则"], ["global", "全局"], ["direct", "直连"]]:
		var button := ui.small_choice_button(item[1])
		button.toggle_mode = true
		button.button_group = group
		button.pressed.connect(func() -> void: mode_requested.emit(str(item[0])))
		mode_row.add_child(button)
		mode_buttons[str(item[0])] = button
	mode_buttons["rule"].button_pressed = true
	return card

func _build_stats_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	download_speed_label = ui.stat_card(row, "↓ 下载", "0 B/s", GREEN)
	upload_speed_label = ui.stat_card(row, "↑ 上传", "0 B/s", BLUE)
	connections_label = ui.stat_card(row, "◎ 连接", "0", YELLOW)
	total_label = ui.stat_card(row, "Σ 流量", "0 B", Color("cc8cff"))
	return row

func _build_graph_card() -> PanelContainer:
	var card := ui.panel(SURFACE, BORDER, 20)
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size.y = 170
	var content_margin := ui.margin(18, 14, 18, 16)
	card.add_child(content_margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	content_margin.add_child(column)
	var row := HBoxContainer.new()
	column.add_child(row)
	var title := ui.label("实时流量", 15, TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	row.add_child(ui.label("最近 44 秒", 11, MUTED))
	traffic_graph = TrafficGraphScript.new()
	traffic_graph.custom_minimum_size.y = 116
	traffic_graph.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(traffic_graph)
	return card

func _build_pet_card(profile_name: String) -> PanelContainer:
	var card := ui.panel(Color("ecfbf5dc"), Color("b4eee1ef"), 22)
	card.custom_minimum_size.y = 350
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 10)
	var content_margin := ui.margin(20, 14, 20, 16)
	card.add_child(content_margin)
	content_margin.add_child(column)
	var screen := ui.panel(Color("c7d79d"), Color("6b7954"), 18)
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
	pet_texture.texture = ui.axolotl_texture()
	pet_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pet_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pet_texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pet_texture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 24)
	screen_content.add_child(pet_texture)
	pet_speech = ui.label("等待出发！", 14, Color("253325"))
	pet_speech.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pet_speech.set_anchors_preset(Control.PRESET_TOP_WIDE)
	pet_speech.offset_top = 10
	pet_speech.offset_bottom = 36
	screen_content.add_child(pet_speech)
	var pet_name := ui.label("六角恐龙 · 美西螈守护兽", 14, TEXT)
	pet_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(pet_name)
	profile_label = ui.label(profile_name, 12, MUTED)
	profile_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(profile_label)
	return card

func _build_log_card() -> PanelContainer:
	var card := ui.panel(SURFACE, BORDER, 18)
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var content_margin := ui.margin(14, 12, 14, 12)
	card.add_child(content_margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	content_margin.add_child(column)
	column.add_child(ui.label("运行记录", 14, TEXT))
	log_view = RichTextLabel.new()
	log_view.bbcode_enabled = true
	log_view.fit_content = false
	log_view.scroll_active = true
	log_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ui.apply_console_theme(log_view, 11)
	column.add_child(log_view)
	return card
func set_status(online: bool, starting: bool, message: String) -> void:
	if not is_instance_valid(status_label):
		return
	status_label.text = message
	status_label.add_theme_color_override("font_color", ui.green_color if online else ui.muted_color)
	status_dot.add_theme_color_override("font_color", ui.green_color if online else ui.danger_color if starting else ui.muted_color)
	connect_toggle.set_pressed_no_signal(online or starting)
	pet_speech.text = "路线畅通，出发！" if online else "正在热身…" if starting else "等待出发！"
	pet_texture.modulate = Color.WHITE if online else Color(0.72, 0.76, 0.72, 1)

func set_connect_pressed(value: bool) -> void:
	if is_instance_valid(connect_toggle):
		connect_toggle.set_pressed_no_signal(value)

func set_mode(mode: String) -> void:
	if mode_buttons.has(mode):
		mode_buttons[mode].set_pressed_no_signal(true)

func set_profile_name(display_name: String) -> void:
	if is_instance_valid(profile_label):
		profile_label.text = display_name

func append_log(message: String) -> void:
	if not is_instance_valid(log_view):
		return
	var time := Time.get_time_string_from_system()
	log_view.append_text("[color=#%s]%s[/color]  %s\n" % [ui.muted_color.to_html(false), time, message])
	log_view.scroll_to_line(maxi(log_view.get_line_count() - 1, 0))
func apply_connections(payload: Dictionary) -> void:
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

func push_zero_sample() -> void:
	if is_instance_valid(traffic_graph):
		traffic_graph.push_sample(0.0)

func _format_bytes(value: float) -> String:
	if value < 1024.0:
		return "%d B" % int(value)
	if value < 1024.0 * 1024.0:
		return "%.1f KB" % (value / 1024.0)
	if value < 1024.0 * 1024.0 * 1024.0:
		return "%.1f MB" % (value / 1024.0 / 1024.0)
	return "%.2f GB" % (value / 1024.0 / 1024.0 / 1024.0)
