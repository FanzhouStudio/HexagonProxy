class_name CodexAccount
extends RefCounted

var id: String = ""
var name: String = ""
var snapshot_path: String = ""
var created_at: String = ""
var usage: Dictionary = {
	"five_hour": -1,
	"weekly": -1,
	"updated_at": ""
}

func from_dictionary(data: Dictionary) -> void:
	id = str(data.get("id", ""))
	name = str(data.get("name", ""))
	snapshot_path = str(data.get("snapshot_path", ""))
	created_at = str(data.get("created_at", ""))
	usage = (data.get("usage", {}) as Dictionary).duplicate(true)

func to_dictionary() -> Dictionary:
	return {
		"id": id,
		"name": name,
		"snapshot_path": snapshot_path,
		"created_at": created_at,
		"usage": usage.duplicate(true)
	}
