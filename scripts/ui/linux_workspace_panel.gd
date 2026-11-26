class_name LinuxWorkspacePanel
extends Node

signal start_requested(capacity_gb: int)
signal stop_requested
signal open_requested
signal password_requested
signal folder_requested
signal reset_requested

var ui: UiFactory
var disk_slider: HSlider
var disk_label: Label
var status_label: Label
var usage_label: Label
var message_label: Label
var start_button: Button
var stop_button: Button
var open_button: Button
var password_button: Button
var reset_button: Button
var _host: Control
var _state: Dictionary = {}

func setup(factory: UiFactory) -> void:
	ui = factory

func build() -> Control:
	var scroll := ScrollContainer.new()
	_host = scroll
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 18)
	scroll.add_child(column)
	column.add_child(ui.label("Linux 工作区", 24, ui.text_color))
	var description := ui.label("独立运行的 Tuxee 文件管理与持久终端。内置 QEMU，无需安装 WSL 或 Docker。", 13, ui.muted_color)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(description)
	var card := ui.panel(ui.surface_color, ui.border_color, 12)
	column.add_child(card)
	var margin := ui.margin(24, 22, 24, 22)
	card.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 18)
	margin.add_child(content)
	status_label = ui.label("尚未安装", 18, ui.text_color)
	content.add_child(status_label)
	disk_label = ui.label("系统盘上限：10 GB", 14, ui.text_color)
	content.add_child(disk_label)
	disk_slider = HSlider.new()
	disk_slider.min_value = 1
	disk_slider.max_value = 10
	disk_slider.step = 1
	disk_slider.value = 10
	disk_slider.custom_minimum_size.y = 32
	ui.apply_slider_theme(disk_slider)
	disk_slider.value_changed.connect(func(value: float) -> void: disk_label.text = "系统盘上限：%d GB" % int(value))
	content.add_child(disk_slider)
	usage_label = ui.label("", 12, ui.muted_color)
	content.add_child(usage_label)
	var note := ui.label("容量 1～10 GB，按实际数据增长，包含 Linux 系统、Tuxee、工作文件及磁盘元数据。1 GB 适合基础终端；停止后可以扩容，已有系统盘不支持缩小。", 12, ui.muted_color)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(note)
	var actions := HFlowContainer.new()
	actions.add_theme_constant_override("h_separation", 10)
	actions.add_theme_constant_override("v_separation", 10)
	content.add_child(actions)
	start_button = _button(actions, "安装并启动", func() -> void: start_requested.emit(int(disk_slider.value)))
	ui.primary_button(start_button)
	stop_button = _button(actions, "停止工作区", func() -> void: stop_requested.emit())
	open_button = _button(actions, "打开工作区", func() -> void: open_requested.emit())
	password_button = _button(actions, "复制登录密码", func() -> void: password_requested.emit())
	_button(actions, "打开数据目录", func() -> void: folder_requested.emit())
	reset_button = _button(actions, "重建系统盘", _confirm_reset)
	message_label = ui.label("", 12, ui.danger_color)
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(message_label)
	var login := ui.label("工作区在默认浏览器中打开，登录用户为 root，密码由本机随机生成。关闭浏览器不会结束终端；停止工作区会关闭其中的程序，磁盘文件保留。", 12, ui.muted_color)
	login.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(login)
	var resources := ui.label("运行时使用 512 MB 内存、2 个虚拟 CPU，采用软件模拟。QEMU 和启动资源单独随程序提供，不计入系统盘容量。", 12, ui.muted_color)
	resources.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(resources)
	return scroll

func apply_state(state: Dictionary) -> void:
	if state == _state:
		return
	var first := _state.is_empty()
	_state = state.duplicate()
	status_label.text = str(state.get("status", "尚未安装"))
	var running := bool(state.get("running", false))
	var busy := bool(state.get("busy", false))
	var installed := bool(state.get("installed", false))
	if first or running:
		disk_slider.set_value_no_signal(int(state.get("disk_gb", 10)))
		disk_label.text = "系统盘上限：%d GB" % int(disk_slider.value)
	disk_slider.editable = not busy and not running
	start_button.text = "启动 / 应用扩容" if installed else "安装并启动"
	start_button.disabled = busy or running
	stop_button.disabled = not running or (busy and str(state.get("status", "")).begins_with("正在保存"))
	open_button.disabled = not bool(state.get("ready", false))
	password_button.disabled = not installed
	reset_button.disabled = busy or running or not installed
	usage_label.text = "镜像文件：%.1f MB · 数据目录：%s" % [float(state.get("disk_bytes", 0)) / 1048576.0, str(state.get("path", ""))]
	usage_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message_label.text = str(state.get("error", ""))

func _confirm_reset() -> void:
	var prompt := preload("res://scripts/ui/confirmation_prompt.gd").new()
	_host.get_tree().root.add_child(prompt)
	prompt.setup(ui, "重建 Linux 系统盘", "这会删除 Linux 工作区中的所有文件、程序和登录信息。HexagonProxy 的其他数据不受影响。", "删除系统盘", true)
	prompt.confirmed.connect(func() -> void: reset_requested.emit())

func _button(parent: Container, text: String, action: Callable) -> Button:
	var button := ui.small_choice_button(text)
	button.pressed.connect(action)
	parent.add_child(button)
	return button
