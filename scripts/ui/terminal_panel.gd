class_name TerminalPanel
extends Node

signal run_requested(shell_name: String, command: String)
signal stop_requested
signal working_directory_selected(path: String)
signal working_directory_reset_requested
signal preset_create_requested(name: String, shell_name: String, command: String)
signal preset_update_requested(preset_id: String, name: String, shell_name: String, command: String)
signal preset_delete_requested(preset_id: String)

const SURFACE := Color("e9fbfbd4")
const BORDER := Color("a8e8e8e8")
const TEXT := Color("12384a")
const MUTED := Color("527384")
const GREEN := Color("16866f")
const GREEN_DARK := Color("c5f1dfde")
const CONSOLE_BG := Color("102a35e8")
const CONSOLE_BORDER := Color("75cdb4b0")
const CONSOLE_TEXT := Color("d9fff3")

var ui: UiFactory
var shell_selector: OptionButton
var status_label: Label
var working_directory_edit: LineEdit
var choose_directory_button: Button
var reset_directory_button: Button
var directory_dialog: FileDialog
var output_view: RichTextLabel
var command_input: TextEdit
var preset_box: HBoxContainer
var preset_scroll: ScrollContainer
var preset_dialog: AcceptDialog
var preset_name_edit: LineEdit
var preset_shell_selector: OptionButton
var preset_command_edit: TextEdit
var preset_delete_dialog: ConfirmationDialog
var _editing_preset_id := ""
var _pending_delete_id := ""
var run_button: Button
var stop_button: Button

func setup(factory: UiFactory) -> void:
	ui = factory
func build() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 12)
	page.add_child(_build_toolbar())
	page.add_child(_build_working_directory_card())
	page.add_child(_build_output_card())
	page.add_child(_build_input_card())
	directory_dialog = FileDialog.new()
	directory_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	directory_dialog.access = FileDialog.ACCESS_FILESYSTEM
	directory_dialog.use_native_dialog = true
	directory_dialog.title = "选择终端运行目录"
	directory_dialog.dir_selected.connect(func(path: String) -> void: working_directory_selected.emit(path))
	page.add_child(directory_dialog)
	_build_preset_dialogs(page)
	return page

func _build_preset_dialogs(page: Control) -> void:
	preset_dialog = AcceptDialog.new()
	preset_dialog.title = "常用命令"
	preset_dialog.ok_button_text = "保存"
	preset_dialog.min_size = Vector2i(620, 390)
	preset_dialog.confirmed.connect(_submit_preset_dialog)
	var margin := ui.margin(18, 16, 18, 64)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preset_dialog.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	column.add_child(ui.label("自定义名称", 11, TEXT))
	preset_name_edit = LineEdit.new()
	preset_name_edit.placeholder_text = "例如：查看端口占用"
	preset_name_edit.custom_minimum_size.y = 42
	ui.apply_line_edit_theme(preset_name_edit, 12)
	column.add_child(preset_name_edit)
	column.add_child(ui.label("命令环境", 11, TEXT))
	preset_shell_selector = OptionButton.new()
	preset_shell_selector.add_item("PowerShell")
	preset_shell_selector.add_item("CMD")
	preset_shell_selector.custom_minimum_size.y = 38
	ui.apply_crystal_option_theme(preset_shell_selector)
	column.add_child(preset_shell_selector)
	column.add_child(ui.label("实际命令", 11, TEXT))
	preset_command_edit = TextEdit.new()
	preset_command_edit.placeholder_text = "输入实际执行的命令，可多行"
	preset_command_edit.custom_minimum_size.y = 125
	ui.apply_text_edit_theme(preset_command_edit, 12)
	column.add_child(preset_command_edit)
	page.add_child(preset_dialog)
	preset_delete_dialog = ConfirmationDialog.new()
	preset_delete_dialog.title = "删除常用命令"
	preset_delete_dialog.dialog_text = "确定删除这条常用命令吗？"
	preset_delete_dialog.ok_button_text = "删除"
	preset_delete_dialog.confirmed.connect(_confirm_preset_delete)
	page.add_child(preset_delete_dialog)

func _build_toolbar() -> PanelContainer:
	var card := ui.panel(SURFACE, BORDER, 18)
	card.custom_minimum_size.y = 70
	var margin := ui.margin(16, 12, 16, 12)
	card.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	margin.add_child(row)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(words)
	words.add_child(ui.label("内置命令行", 16, TEXT))
	words.add_child(ui.label("命令在本机执行 · 输出与输入区域相互独立", 10, MUTED))
	shell_selector = OptionButton.new()
	shell_selector.add_item("PowerShell")
	shell_selector.add_item("CMD")
	shell_selector.custom_minimum_size = Vector2(140, 38)
	ui.apply_crystal_option_theme(shell_selector)
	row.add_child(shell_selector)
	status_label = ui.label("就绪", 11, GREEN)
	status_label.custom_minimum_size.x = 180
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(status_label)
	return card

func _build_working_directory_card() -> PanelContainer:
	var card := ui.panel(SURFACE, BORDER, 16)
	card.custom_minimum_size.y = 58
	var margin := ui.margin(14, 9, 14, 9)
	card.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	margin.add_child(row)
	row.add_child(ui.label("运行目录", 12, TEXT))
	working_directory_edit = LineEdit.new()
	working_directory_edit.editable = false
	working_directory_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	working_directory_edit.custom_minimum_size.y = 42
	ui.apply_line_edit_theme(working_directory_edit, 12)
	row.add_child(working_directory_edit)
	choose_directory_button = ui.small_choice_button("选择目录")
	choose_directory_button.custom_minimum_size.x = 82
	choose_directory_button.pressed.connect(_open_directory_dialog)
	row.add_child(choose_directory_button)
	reset_directory_button = ui.small_choice_button("重置")
	reset_directory_button.pressed.connect(func() -> void: working_directory_reset_requested.emit())
	row.add_child(reset_directory_button)
	return card

func _build_output_card() -> PanelContainer:
	var card := ui.panel(CONSOLE_BG, CONSOLE_BORDER, 18)
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size.y = 360
	var margin := ui.margin(14, 12, 14, 12)
	card.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)
	var title_row := HBoxContainer.new()
	column.add_child(title_row)
	var title := ui.label("输出", 13, CONSOLE_TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	var clear_button := ui.small_choice_button("清空")
	clear_button.pressed.connect(clear_output)
	title_row.add_child(clear_button)
	output_view = RichTextLabel.new()
	output_view.bbcode_enabled = false
	output_view.selection_enabled = true
	output_view.context_menu_enabled = true
	output_view.scroll_active = true
	output_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ui.apply_console_theme(output_view, 12)
	column.add_child(output_view)
	append_output("Hexagon Terminal · PowerShell 已就绪。\n")
	return card

func _build_input_card() -> PanelContainer:
	var card := ui.panel(SURFACE, BORDER, 18)
	card.custom_minimum_size.y = 220
	var margin := ui.margin(14, 12, 14, 12)
	card.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)
	var title_row := HBoxContainer.new()
	column.add_child(title_row)
	var input_title := ui.label("命令输入", 13, TEXT)
	input_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(input_title)
	var add_preset_button := ui.small_choice_button("＋ 添加常用命令")
	add_preset_button.pressed.connect(open_create_preset)
	title_row.add_child(add_preset_button)
	var preset_row := HBoxContainer.new()
	preset_row.add_theme_constant_override("separation", 8)
	column.add_child(preset_row)
	preset_row.add_child(ui.label("常用命令", 10, MUTED))
	preset_scroll = ScrollContainer.new()
	preset_scroll.custom_minimum_size.y = 38
	preset_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preset_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	preset_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	preset_row.add_child(preset_scroll)
	preset_box = HBoxContainer.new()
	preset_box.add_theme_constant_override("separation", 6)
	preset_scroll.add_child(preset_box)
	_set_empty_preset_hint()
	command_input = TextEdit.new()
	command_input.placeholder_text = "输入 PowerShell 或 CMD 命令，可输入多行脚本…"
	command_input.custom_minimum_size.y = 88
	command_input.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ui.apply_text_edit_theme(command_input, 12)
	column.add_child(command_input)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	column.add_child(actions)
	var hint := ui.label("支持多行命令；停止会终止当前命令进程树。", 10, MUTED)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(hint)
	var clear_input := ui.small_choice_button("清空输入")
	clear_input.custom_minimum_size.x = 82
	clear_input.pressed.connect(func() -> void: command_input.clear())
	actions.add_child(clear_input)
	run_button = ui.button("▶ 运行", GREEN_DARK, GREEN)
	run_button.custom_minimum_size.x = 92
	run_button.pressed.connect(_on_run_pressed)
	actions.add_child(run_button)
	stop_button = ui.button("■ 停止", Color("f3ddddc8"), Color("a84545"))
	stop_button.custom_minimum_size.x = 92
	stop_button.disabled = true
	stop_button.pressed.connect(func() -> void: stop_requested.emit())
	actions.add_child(stop_button)
	return card

func set_presets(presets: Array) -> void:
	if not is_instance_valid(preset_box):
		return
	for child in preset_box.get_children():
		preset_box.remove_child(child)
		child.queue_free()
	if presets.is_empty():
		_set_empty_preset_hint()
		return
	for item in presets:
		if item is Dictionary:
			preset_box.add_child(_build_preset_item(item))

func _set_empty_preset_hint() -> void:
	if not is_instance_valid(preset_box):
		return
	var hint := ui.label("暂无常用命令，点击右上角添加。", 10, MUTED)
	hint.custom_minimum_size.y = 34
	preset_box.add_child(hint)

func _build_preset_item(preset: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	var shell_name := str(preset.get("shell", "powershell"))
	var command := str(preset.get("command", ""))
	var fill_button := ui.small_choice_button(str(preset.get("name", "常用命令")))
	fill_button.tooltip_text = "%s\n%s" % ["CMD" if shell_name == "cmd" else "PowerShell", command]
	fill_button.pressed.connect(func() -> void: fill_command(shell_name, command))
	row.add_child(fill_button)
	var edit_button := ui.small_choice_button("编辑")
	edit_button.pressed.connect(func() -> void: open_edit_preset(preset))
	row.add_child(edit_button)
	var delete_button := ui.small_choice_button("×")
	delete_button.tooltip_text = "删除"
	delete_button.custom_minimum_size.x = 34
	delete_button.pressed.connect(func() -> void: request_delete_preset(str(preset.get("id", ""))))
	row.add_child(delete_button)
	return row

func fill_command(shell_name: String, command: String) -> void:
	if is_instance_valid(shell_selector):
		shell_selector.select(1 if shell_name.to_lower() == "cmd" else 0)
	if is_instance_valid(command_input):
		command_input.text = command
		command_input.grab_focus()

func open_create_preset() -> void:
	_editing_preset_id = ""
	preset_dialog.title = "添加常用命令"
	preset_name_edit.clear()
	preset_shell_selector.select(shell_selector.selected if is_instance_valid(shell_selector) else 0)
	preset_command_edit.text = command_input.text if is_instance_valid(command_input) else ""
	preset_dialog.popup_centered()

func open_edit_preset(preset: Dictionary) -> void:
	_editing_preset_id = str(preset.get("id", ""))
	preset_dialog.title = "编辑常用命令"
	preset_name_edit.text = str(preset.get("name", ""))
	preset_shell_selector.select(1 if str(preset.get("shell", "powershell")) == "cmd" else 0)
	preset_command_edit.text = str(preset.get("command", ""))
	preset_dialog.popup_centered()

func request_delete_preset(preset_id: String) -> void:
	if preset_id.is_empty():
		return
	_pending_delete_id = preset_id
	preset_delete_dialog.popup_centered()

func _submit_preset_dialog() -> void:
	var shell_name := "cmd" if preset_shell_selector.selected == 1 else "powershell"
	if _editing_preset_id.is_empty():
		preset_create_requested.emit(preset_name_edit.text, shell_name, preset_command_edit.text)
	else:
		preset_update_requested.emit(_editing_preset_id, preset_name_edit.text, shell_name, preset_command_edit.text)

func _confirm_preset_delete() -> void:
	if _pending_delete_id.is_empty():
		return
	preset_delete_requested.emit(_pending_delete_id)
	_pending_delete_id = ""

func _open_directory_dialog() -> void:
	if not is_instance_valid(directory_dialog):
		return
	if is_instance_valid(working_directory_edit) and DirAccess.dir_exists_absolute(working_directory_edit.text):
		directory_dialog.current_dir = working_directory_edit.text
	directory_dialog.popup_centered_ratio(0.72)

func set_working_directory(path: String) -> void:
	if is_instance_valid(working_directory_edit):
		working_directory_edit.text = path
		working_directory_edit.tooltip_text = path

func _on_run_pressed() -> void:
	if not is_instance_valid(command_input):
		return
	var shell_name := "cmd" if shell_selector.selected == 1 else "powershell"
	var command := command_input.text
	append_output("\n> [%s]\n%s\n" % ["CMD" if shell_name == "cmd" else "PowerShell", command])
	run_requested.emit(shell_name, command)
func append_output(text: String) -> void:
	if not is_instance_valid(output_view) or text.is_empty():
		return
	output_view.append_text(text)
	output_view.scroll_to_line(maxi(output_view.get_line_count() - 1, 0))

func clear_output() -> void:
	if is_instance_valid(output_view):
		output_view.clear()

func set_running(running: bool, message: String) -> void:
	if is_instance_valid(run_button):
		run_button.disabled = running
	if is_instance_valid(stop_button):
		stop_button.disabled = not running
	if is_instance_valid(shell_selector):
		shell_selector.disabled = running
	if is_instance_valid(choose_directory_button):
		choose_directory_button.disabled = running
	if is_instance_valid(reset_directory_button):
		reset_directory_button.disabled = running
	if is_instance_valid(status_label):
		status_label.text = message
		status_label.add_theme_color_override("font_color", ui.green_color if not running else ui.warning_color)

func show_finished(exit_code: int, stopped: bool) -> void:
	append_output("\n[系统] %s\n" % ("命令已停止。" if stopped else "命令执行完成，退出码 %d。" % exit_code))
