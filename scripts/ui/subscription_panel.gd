class_name SubscriptionPanel
extends Node

signal subscription_url_requested(url: String)
signal v2_import_requested(content: String)
signal provider_refresh_requested
signal subscription_activate_requested(entry_id: String)
signal subscription_delete_requested(entry_id: String)
signal local_profile_requested(path: String)

const ConfirmationPromptScript = preload("res://scripts/ui/confirmation_prompt.gd")

const SURFACE := Color("e9fbfbd4")
const BORDER := Color("a8e8e8e8")
const TEXT := Color("12384a")
const MUTED := Color("527384")
const GREEN := Color("16866f")
const GREEN_DARK := Color("c5f1dfde")
const RED := Color("c84d68")
const CRYSTAL_WHITE := Color("f7ffffdf")

var host: Control
var ui: UiFactory
var subscription_input: LineEdit
var v2_link_input: TextEdit
var subscription_list: VBoxContainer
var _subscriptions: Array = []
var _active_subscription_id := ""

func setup(owner: Control, factory: UiFactory) -> void:
	host = owner
	ui = factory

func build() -> Control:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var page := VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 14)
	scroll.add_child(page)
	var intro := ui.panel(Color("e8faf5dc"), Color("b5eee0ef"), 20)
	intro.custom_minimum_size.y = 105
	page.add_child(intro)
	var intro_margin := ui.margin(22, 18, 22, 18)
	intro.add_child(intro_margin)
	var intro_row := HBoxContainer.new()
	intro_row.add_theme_constant_override("separation", 18)
	intro_margin.add_child(intro_row)
	var icon := TextureRect.new()
	icon.texture = ui.axolotl_texture()
	icon.custom_minimum_size = Vector2(92, 92)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	intro_row.add_child(icon)
	var words := VBoxContainer.new()
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	intro_row.add_child(words)
	words.add_child(ui.label("把路线交给六角恐龙", 22, TEXT))
	words.add_child(ui.label("支持 Clash / Mihomo 订阅，以及本地 YAML / YML 配置。", 13, MUTED))

	var url_card := ui.panel(SURFACE, BORDER, 20)
	url_card.custom_minimum_size.y = 165
	page.add_child(url_card)
	var url_margin := ui.margin(22, 18, 22, 18)
	url_card.add_child(url_margin)
	var url_column := VBoxContainer.new()
	url_column.add_theme_constant_override("separation", 12)
	url_margin.add_child(url_column)
	url_column.add_child(ui.label("订阅地址", 16, TEXT))
	url_column.add_child(ui.label("订阅地址可能包含凭据，只会写入本机 user://profiles。", 11, MUTED))
	var url_row := HBoxContainer.new()
	url_row.add_theme_constant_override("separation", 10)
	url_column.add_child(url_row)
	subscription_input = LineEdit.new()
	subscription_input.placeholder_text = "https://example.com/your-subscription"
	subscription_input.secret = true
	subscription_input.secret_character = "●"
	subscription_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	subscription_input.custom_minimum_size.y = 48
	ui.apply_line_edit_theme(subscription_input, 13)
	url_row.add_child(subscription_input)
	var add_button := ui.button("添加订阅", GREEN_DARK, GREEN)
	add_button.pressed.connect(func() -> void:
		subscription_url_requested.emit(subscription_input.text)
	)
	url_row.add_child(add_button)

	var v2_card := ui.panel(Color("f3f4ffe0"), Color("d8d3f6f0"), 20)
	v2_card.custom_minimum_size.y = 185
	page.add_child(v2_card)
	var v2_margin := ui.margin(22, 14, 22, 14)
	v2_card.add_child(v2_margin)
	var v2_column := VBoxContainer.new()
	v2_column.add_theme_constant_override("separation", 8)
	v2_margin.add_child(v2_column)
	var v2_header := HBoxContainer.new()
	v2_column.add_child(v2_header)
	var v2_words := VBoxContainer.new()
	v2_words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v2_header.add_child(v2_words)
	v2_words.add_child(ui.label("V2 分享链接", 16, TEXT))
	v2_words.add_child(ui.label("支持 VLESS Reality、VMess、Hysteria2、Trojan、SS、TUIC；可一次粘贴多条。", 11, MUTED))
	var import_v2 := ui.button("导入 V2", Color("e8e2f8e8"), Color("765399"))
	import_v2.pressed.connect(func() -> void:
		v2_import_requested.emit(v2_link_input.text)
	)
	v2_header.add_child(import_v2)
	v2_link_input = TextEdit.new()
	v2_link_input.placeholder_text = "vless://...\nhysteria2://...\n也可粘贴 V2RayN Base64 订阅正文"
	v2_link_input.custom_minimum_size.y = 84
	ui.apply_text_edit_theme(v2_link_input, 12)
	v2_column.add_child(v2_link_input)

	var library_card := ui.panel(SURFACE, BORDER, 20)
	page.add_child(library_card)
	var library_margin := ui.margin(22, 16, 22, 16)
	library_card.add_child(library_margin)
	var library_column := VBoxContainer.new()
	library_column.add_theme_constant_override("separation", 10)
	library_margin.add_child(library_column)
	library_column.add_child(ui.label("已导入的订阅", 16, TEXT))
	library_column.add_child(ui.label("订阅会保存在本机；同一时间由一个 Mihomo 内核运行当前选中的配置。", 11, MUTED))
	subscription_list = VBoxContainer.new()
	subscription_list.add_theme_constant_override("separation", 8)
	library_column.add_child(subscription_list)
	_rebuild()

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 14)
	page.add_child(actions)
	var local_card := ui.action_card("导入本地配置", "使用完整的 Clash / Mihomo YAML", "选择文件")
	actions.add_child(local_card[0])
	local_card[1].pressed.connect(_open_profile_dialog)
	var refresh_card := ui.action_card("刷新订阅", "让内核立即拉取最新节点", "立即刷新")
	actions.add_child(refresh_card[0])
	refresh_card[1].pressed.connect(func() -> void: provider_refresh_requested.emit())
	var hint := ui.panel(Color("f7f2ffe0"), Color("d7caeef0"), 16)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(hint)
	var hint_margin := ui.margin(16, 14, 16, 14)
	hint.add_child(hint_margin)
	var hint_text := ui.label("隐私提示\nHexagonProxy 不提供节点，也不会上传订阅。", 12, Color("72578c"))
	hint_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_margin.add_child(hint_text)
	return scroll


func set_subscriptions(entries: Array, active_id: String) -> void:
	_subscriptions = entries.duplicate(true)
	_active_subscription_id = active_id
	_rebuild()

func clear_subscription_input() -> void:
	if is_instance_valid(subscription_input):
		subscription_input.clear()

func clear_v2_input() -> void:
	if is_instance_valid(v2_link_input):
		v2_link_input.clear()

func _rebuild() -> void:
	if not is_instance_valid(subscription_list):
		return
	for child in subscription_list.get_children():
		subscription_list.remove_child(child)
		child.queue_free()
	if _subscriptions.is_empty():
		subscription_list.add_child(ui.empty_message("还没有保存的订阅。导入后会出现在这里。"))
		return
	for entry_variant in _subscriptions:
		if not entry_variant is Dictionary:
			continue
		var entry: Dictionary = entry_variant
		subscription_list.add_child(_subscription_row(entry, str(entry.get("id", "")) == _active_subscription_id))

func _subscription_row(entry: Dictionary, active: bool) -> PanelContainer:
	var row_card := ui.panel(GREEN_DARK if active else CRYSTAL_WHITE, GREEN if active else BORDER, 14)
	var margin := ui.margin(14, 10, 12, 10)
	row_card.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	margin.add_child(row)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(words)
	var display_name := str(entry.get("name", "订阅"))
	words.add_child(ui.label(display_name, 13, TEXT))
	var type_names := {"http": "HTTP / Mihomo", "v2": "V2 分享链接", "local": "本地 YAML"}
	var detail := str(type_names.get(str(entry.get("type", "local")), "本地配置"))
	if active:
		detail += " · 当前使用"
	words.add_child(ui.label(detail, 10, GREEN if active else MUTED))
	var entry_id := str(entry.get("id", ""))
	var use_button := ui.small_choice_button("使用中" if active else "切换")
	use_button.disabled = active
	use_button.pressed.connect(func() -> void: subscription_activate_requested.emit(entry_id))
	row.add_child(use_button)
	var delete_button := ui.small_choice_button("删除")
	delete_button.add_theme_color_override("font_color", ui.danger_color)
	delete_button.pressed.connect(func() -> void: _confirm_delete_subscription(entry_id, display_name))
	row.add_child(delete_button)
	return row_card

func _confirm_delete_subscription(entry_id: String, display_name: String) -> void:
	var prompt = ConfirmationPromptScript.new()
	host.add_child(prompt)
	prompt.setup(
		ui,
		"删除订阅",
		"确定删除“%s”吗？\n本机保存的配置文件也会一起删除，此操作无法撤销。" % display_name,
		"删除",
		true
	)
	prompt.confirmed.connect(func() -> void:
		subscription_delete_requested.emit(entry_id)
	)


func _open_profile_dialog() -> void:
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.use_native_dialog = true
	dialog.filters = PackedStringArray(["*.yaml, *.yml ; Mihomo / Clash 配置"])
	dialog.file_selected.connect(func(path: String) -> void:
		local_profile_requested.emit(path)
		dialog.queue_free()
	)
	dialog.canceled.connect(dialog.queue_free)
	host.add_child(dialog)
	dialog.popup_centered_ratio(0.7)
