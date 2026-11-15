extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var source := OS.get_environment("HEXAGON_SHARED_SOURCE_HOME")
	var storage := OS.get_environment("HEXAGON_ANTIGRAVITY_TEST_ROOT")
	assert(not source.is_empty() and not storage.is_empty())
	var accounts = load("res://scripts/modules/antigravity/antigravity_accounts.gd").new()
	root.add_child(accounts)
	accounts.initialize(storage)
	accounts.workspace_home_override = source
	var id := "11223344556677881122334455667788"
	if not accounts.exists(id):
		accounts.entries.append({"id": id, "name": "Shared workspace test"})
	var executable := OS.get_environment("LOCALAPPDATA").path_join("Programs/antigravity/Antigravity.exe")
	var result: Dictionary = await accounts.run("launch", id, executable)
	if not result.get("ok", false):
		printerr("FAIL: " + str(result.get("message", "launch")))
		quit(1)
		return
	assert(result.get("workspace_shared", false))
	var root_path := storage.path_join(id).path_join("home/.gemini")
	var source_projects := DirAccess.get_files_at(source.path_join(".gemini/config/projects"))
	var target_projects := DirAccess.get_files_at(root_path.path_join("config/projects"))
	assert(not source_projects.is_empty() and source_projects == target_projects)
	assert(FileAccess.file_exists(root_path.path_join("antigravity/conversation_summaries.db")))
	assert(DirAccess.dir_exists_absolute(source.path_join(".gemini/antigravity/conversations")))
	var source_conversations := DirAccess.get_files_at(source.path_join(".gemini/antigravity/conversations"))
	var target_conversations := DirAccess.get_files_at(root_path.path_join("antigravity/conversations"))
	assert(not source_conversations.is_empty() and source_conversations == target_conversations)
	print("PASS: actual Antigravity launch shares existing project catalog, conversation files and conversation index")
	quit(0)
