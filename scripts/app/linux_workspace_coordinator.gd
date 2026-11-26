class_name LinuxWorkspaceCoordinator
extends Node

var service: LinuxWorkspaceService
var panel: LinuxWorkspacePanel

func setup(workspace: LinuxWorkspaceService, view: LinuxWorkspacePanel) -> void:
	service = workspace
	panel = view
	panel.start_requested.connect(service.start_workspace)
	panel.stop_requested.connect(service.stop_workspace)
	panel.open_requested.connect(service.open_workspace)
	panel.password_requested.connect(service.copy_password)
	panel.reset_requested.connect(service.reset_workspace)
	panel.folder_requested.connect(func() -> void: OS.shell_open(service.storage_dir()))
	service.state_changed.connect(panel.apply_state)
	panel.apply_state(service.snapshot())
