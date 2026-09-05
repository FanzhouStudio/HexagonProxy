class_name RoutingPanel
extends Node

signal application_add_requested(path: String)
signal master_enabled_changed(enabled: bool)
signal rule_target_changed(rule_id: String, target: String)
signal rule_enabled_changed(rule_id: String, enabled: bool)
signal rule_delete_requested(rule_id: String)

const SURFACE := Color("e9fbfbd4")
const BORDER := Color("a8e8e8e8")
const TEXT := Color("12384a")
const MUTED := Color("527384")
const GREEN := Color("16866f")
const GREEN_DARK := Color("c5f1dfde")

var ui: UiFactory
var master_toggle: CheckButton
var message_label: Label
var rules_box: VBoxContainer
var empty_label: Label
var exe_dialog: FileDialog
var _targets: Array = []

func setup(factory: UiFactory) -> void:
	ui = factory

func build() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 14)
	page.add_child(_build_intro_card())
	page.add_child(_build_rules_card())
	exe_dialog = FileDialog.new()
	exe_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	exe_dialog.access = FileDialog.ACCESS_FILESYSTEM
	exe_dialog.filters = PackedStringArray(["*.exe ; Windows 程序"])
	exe_dialog.use_native_dialog = true
	exe_dialog.title = "选择要分流的应用"
	exe_dialog.file_selected.connect(func(path: String) -> void: application_add_requested.emit(path))
	page.add_child(exe_dialog)
	return page

func _build_intro_card() -> PanelContainer:
	var card := ui.panel(SURFACE, BORDER, 18)
	card.custom_minimum_size.y = 120
	var margin := ui.margin(18, 14, 18, 14)
	card.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	margin.add_child(row)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_theme_constant_override("separation", 5)
	row.add_child(words)
	words.add_child(ui.label("应用分流", 18, TEXT))
	var desc := ui.label("按 Windows 程序决定直连或走代理。当前仅对进入 HexagonProxy 的流量生效；忽略系统代理的游戏等程序后续需要 TUN 模式。", 11, MUTED)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.add_child(desc)
	message_label = ui.label("选择一个 .exe 后即可创建规则。", 10, MUTED)
	words.add_child(message_label)
	master_toggle = CheckButton.new()
	master_toggle.text = "启用"
	ui.apply_crystal_toggle_theme(master_toggle)
	master_toggle.toggled.connect(func(value: bool) -> void: master_enabled_changed.emit(value))
	row.add_child(master_toggle)
	var add_button := ui.button("＋ 添加应用", GREEN_DARK, GREEN)
	add_button.custom_minimum_size.x = 120
	add_button.pressed.connect(_open_exe_dialog)
	row.add_child(add_button)
	return card
func _build_rules_card() -> PanelContainer:
	var card := ui.panel(SURFACE, BORDER, 18)
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var margin := ui.margin(16, 14, 16, 14)
	card.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	var title_row := HBoxContainer.new()
	column.add_child(title_row)
	var title := ui.label("应用规则", 16, TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	title_row.add_child(ui.label("应用规则优先于域名/IP规则 · 当前按进程名匹配", 10, MUTED))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	rules_box = VBoxContainer.new()
	rules_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rules_box.add_theme_constant_override("separation", 8)
	scroll.add_child(rules_box)
	empty_label = ui.empty_message("还没有应用规则\n点击“添加应用”选择一个 .exe 程序")
	rules_box.add_child(empty_label)
	return card

func set_snapshot(snapshot: Dictionary) -> void:
	_targets = snapshot.get("targets", [])
	if is_instance_valid(master_toggle):
		master_toggle.set_pressed_no_signal(bool(snapshot.get("enabled", true)))
	_rebuild_rules(snapshot.get("rules", []))
func _rebuild_rules(rules: Array) -> void:
	if not is_instance_valid(rules_box):
		return
	for child in rules_box.get_children():
		child.queue_free()
	if rules.is_empty():
		empty_label = ui.empty_message("还没有应用规则\n点击“添加应用”选择一个 .exe 程序")
		rules_box.add_child(empty_label)
		return
	for rule in rules:
		rules_box.add_child(_build_rule_row(rule))

func _build_rule_row(rule: Dictionary) -> PanelContainer:
	var card := ui.panel(Color("f7ffffc8"), Color("ffffff90"), 14)
	var margin := ui.margin(14, 10, 14, 10)
	card.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	margin.add_child(row)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(words)
	words.add_child(ui.label(str(rule.get("display_name", "应用")), 14, TEXT))
	var process_name := str(rule.get("process_name", ""))
	var path := str(rule.get("path", ""))
	var detail := ui.label("%s  ·  %s" % [process_name, path], 10, MUTED)
	detail.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	detail.tooltip_text = path
	words.add_child(detail)
	var target_selector := OptionButton.new()
	target_selector.custom_minimum_size = Vector2(150, 36)
	ui.apply_crystal_option_theme(target_selector)
	var selected_index := 0
	for index in range(_targets.size()):
		var target: Dictionary = _targets[index]
		target_selector.add_item(str(target.get("label", target.get("id", "策略"))))
		target_selector.set_item_metadata(index, str(target.get("id", "proxy")))
		if str(target.get("id", "")) == str(rule.get("target", "proxy")):
			selected_index = index
	target_selector.select(selected_index)
	var rule_id := str(rule.get("id", ""))
	target_selector.item_selected.connect(func(index: int) -> void:
		rule_target_changed.emit(rule_id, str(target_selector.get_item_metadata(index)))
	)
	row.add_child(target_selector)
	var enabled_toggle := CheckButton.new()
	enabled_toggle.text = "启用"
	ui.apply_crystal_toggle_theme(enabled_toggle)
	enabled_toggle.set_pressed_no_signal(bool(rule.get("enabled", true)))
	enabled_toggle.toggled.connect(func(value: bool) -> void: rule_enabled_changed.emit(rule_id, value))
	row.add_child(enabled_toggle)
	var delete_button := ui.small_choice_button("删除")
	delete_button.pressed.connect(func() -> void: rule_delete_requested.emit(rule_id))
	row.add_child(delete_button)
	return card

func _open_exe_dialog() -> void:
	if is_instance_valid(exe_dialog):
		exe_dialog.popup_centered_ratio(0.72)

func show_message(message: String, success: bool) -> void:
	if is_instance_valid(message_label):
		message_label.text = message
		message_label.add_theme_color_override("font_color", ui.green_color if success else ui.danger_color)
