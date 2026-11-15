class_name UiThemeCoordinator
extends Node

## 界面主题协调器
## 连接主题数据服务与 UI，不让 Panel 直接依赖 Service。

var theme_service
var ui_factory: UiFactory
var settings_panel
var _active := false
var _font_debounce: Timer
var _pending_font_percent := -1

func setup(service, factory: UiFactory, settings) -> void:
	theme_service = service
	ui_factory = factory
	settings_panel = settings
	settings_panel.ui_theme_requested.connect(_on_theme_requested)
	settings_panel.font_size_requested.connect(_on_font_size_requested)
	settings_panel.font_size_adjustment_finished.connect(_apply_pending_font_size)
	theme_service.theme_changed.connect(_on_theme_changed)
	_font_debounce = Timer.new()
	_font_debounce.one_shot = true
	_font_debounce.wait_time = 0.08
	_font_debounce.timeout.connect(_apply_pending_font_size)
	add_child(_font_debounce)

func start() -> void:
	if _active:
		return
	_active = true
	settings_panel.set_theme_catalog(theme_service.catalog(), theme_service.current_theme_id())
	settings_panel.set_theme_state(theme_service.snapshot())

func shutdown() -> void:
	if _active and _pending_font_percent >= 100:
		_apply_pending_font_size()
	_active = false
	_font_debounce.stop()

func _on_font_size_requested(percent: int) -> void:
	if not _active:
		return
	_pending_font_percent = percent
	if _font_debounce.is_stopped():
		_font_debounce.start()

func _apply_pending_font_size() -> void:
	_font_debounce.stop()
	if not _active or _pending_font_percent < 100:
		return
	var percent := _pending_font_percent
	_pending_font_percent = -1
	var result: Dictionary = theme_service.set_font_size_percent(percent)
	if not bool(result.get("ok", false)):
		settings_panel.set_theme_state(theme_service.snapshot())
		settings_panel.show_theme_message(str(result.get("message", "无法更改字号。")), false)

func _on_theme_requested(theme_id: String) -> void:
	if not _active:
		return
	_apply_pending_font_size()
	var result: Dictionary = theme_service.set_theme(theme_id)
	if not bool(result.get("ok", false)):
		settings_panel.show_theme_message(str(result.get("message", "无法切换界面主题。")), false)

func _on_theme_changed(snapshot: Dictionary) -> void:
	if not _active:
		return
	ui_factory.apply_theme(snapshot)
	settings_panel.set_theme_state(snapshot)
	settings_panel.show_theme_message("已应用：%s · 字号 %d%%" % [str(snapshot.get("name", "界面主题")), int(snapshot.get("font_size_percent", 100))], true)
