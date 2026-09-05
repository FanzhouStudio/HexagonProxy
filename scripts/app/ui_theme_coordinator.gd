class_name UiThemeCoordinator
extends Node

## 界面主题协调器
## 连接主题数据服务与 UI，不让 Panel 直接依赖 Service。

var theme_service
var ui_factory: UiFactory
var settings_panel
var _active := false

func setup(service, factory: UiFactory, settings) -> void:
	theme_service = service
	ui_factory = factory
	settings_panel = settings
	settings_panel.ui_theme_requested.connect(_on_theme_requested)
	theme_service.theme_changed.connect(_on_theme_changed)

func start() -> void:
	if _active:
		return
	_active = true
	settings_panel.set_theme_catalog(theme_service.catalog(), theme_service.current_theme_id())
	settings_panel.set_theme_state(theme_service.snapshot())

func shutdown() -> void:
	_active = false

func _on_theme_requested(theme_id: String) -> void:
	if not _active:
		return
	var result: Dictionary = theme_service.set_theme(theme_id)
	if not bool(result.get("ok", false)):
		settings_panel.show_theme_message(str(result.get("message", "无法切换界面主题。")), false)

func _on_theme_changed(snapshot: Dictionary) -> void:
	if not _active:
		return
	ui_factory.apply_theme(snapshot)
	settings_panel.set_theme_state(snapshot)
	settings_panel.show_theme_message("已切换为：%s" % str(snapshot.get("name", "界面主题")), true)
