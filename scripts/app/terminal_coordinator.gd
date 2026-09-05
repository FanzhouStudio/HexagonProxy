class_name TerminalCoordinator
extends Node

## 内置终端协调器
## 负责把 TerminalPanel 的用户意图路由到 CommandConsoleService。

var command_service
var preset_service
var terminal_panel
var _active := false

func setup(service, presets, panel) -> void:
	command_service = service
	preset_service = presets
	terminal_panel = panel
	terminal_panel.run_requested.connect(_on_run_requested)
	terminal_panel.stop_requested.connect(_on_stop_requested)
	terminal_panel.working_directory_selected.connect(_on_working_directory_selected)
	terminal_panel.working_directory_reset_requested.connect(_on_working_directory_reset_requested)
	terminal_panel.preset_create_requested.connect(_on_preset_create_requested)
	terminal_panel.preset_update_requested.connect(_on_preset_update_requested)
	terminal_panel.preset_delete_requested.connect(_on_preset_delete_requested)
	preset_service.presets_changed.connect(_refresh_presets)
	command_service.output_appended.connect(_on_output_appended)
	command_service.state_changed.connect(_on_state_changed)
	command_service.finished.connect(_on_finished)

func start() -> void:
	_active = true
	terminal_panel.set_working_directory(command_service.working_directory())
	terminal_panel.set_running(command_service.is_running(), "运行中" if command_service.is_running() else "就绪")
	_refresh_presets()

func shutdown() -> void:
	_active = false
	if command_service.is_running():
		command_service.stop()
func _on_run_requested(shell_name: String, command: String) -> void:
	if _active:
		command_service.run_command(shell_name, command)

func _on_stop_requested() -> void:
	if _active:
		command_service.stop()

func _on_working_directory_selected(path: String) -> void:
	if not _active:
		return
	var result: Dictionary = command_service.set_working_directory(path)
	if bool(result.get("ok", false)):
		terminal_panel.set_working_directory(command_service.working_directory())
	terminal_panel.append_output("\n[系统] %s\n" % str(result.get("message", "无法修改运行目录。")))

func _on_working_directory_reset_requested() -> void:
	if not _active:
		return
	var result: Dictionary = command_service.reset_working_directory()
	if bool(result.get("ok", false)):
		terminal_panel.set_working_directory(command_service.working_directory())
	terminal_panel.append_output("\n[系统] %s\n" % str(result.get("message", "无法重置运行目录。")))

func _on_preset_create_requested(name: String, shell_name: String, command: String) -> void:
	if not _active:
		return
	var result: Dictionary = preset_service.add_preset(name, shell_name, command)
	terminal_panel.append_output("\n[系统] %s\n" % str(result.get("message", "无法保存常用命令。")))

func _on_preset_update_requested(preset_id: String, name: String, shell_name: String, command: String) -> void:
	if not _active:
		return
	var result: Dictionary = preset_service.update_preset(preset_id, name, shell_name, command)
	terminal_panel.append_output("\n[系统] %s\n" % str(result.get("message", "无法更新常用命令。")))

func _on_preset_delete_requested(preset_id: String) -> void:
	if not _active:
		return
	var result: Dictionary = preset_service.delete_preset(preset_id)
	terminal_panel.append_output("\n[系统] %s\n" % str(result.get("message", "无法删除常用命令。")))

func _refresh_presets() -> void:
	if _active:
		terminal_panel.set_presets(preset_service.list_presets())

func _on_output_appended(text: String) -> void:
	if _active:
		terminal_panel.append_output(text)

func _on_state_changed(running: bool, message: String) -> void:
	if _active:
		terminal_panel.set_running(running, message)

func _on_finished(exit_code: int, stopped: bool) -> void:
	if _active:
		terminal_panel.show_finished(exit_code, stopped)
