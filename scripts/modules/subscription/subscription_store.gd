class_name SubscriptionStore
extends RefCounted

## 订阅持久化仓储
## 只负责订阅索引、配置文件与 provider 文件的磁盘读写

var profile_root: String
var runtime_root: String

func setup(profile_dir: String, runtime_dir: String) -> void:
	profile_root = profile_dir
	runtime_root = runtime_dir

func library_dir() -> String:
	return profile_root.path_join("library")

func index_path() -> String:
	return library_dir().path_join("index.json")

func provider_dir() -> String:
	return runtime_root.path_join("providers").path_join("library")

func new_id() -> String:
	return "%d-%s" % [Time.get_ticks_usec(), Crypto.new().generate_random_bytes(4).hex_encode()]

func load_index() -> Dictionary:
	DirAccess.make_dir_recursive_absolute(library_dir())
	if not FileAccess.file_exists(index_path()):
		return {"subscriptions": [], "active_id": ""}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(index_path()))
	if not parsed is Dictionary:
		return {"subscriptions": [], "active_id": ""}
	var subscriptions: Array = []
	var items: Variant = parsed.get("subscriptions", [])
	if items is Array:
		for item in items:
			if item is Dictionary and not str(item.get("id", "")).is_empty():
				subscriptions.append(item)
	return {
		"subscriptions": subscriptions,
		"active_id": str(parsed.get("active_id", ""))
	}

func save_index(subscriptions: Array, active_id: String) -> bool:
	var data := {
		"version": 1,
		"active_id": active_id,
		"subscriptions": subscriptions
	}
	return write_text_atomic(index_path(), JSON.stringify(data, "  "))

func create_entry(entry_id: String, display_name: String, kind: String, yaml: String, provider_file := "", extra := {}) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(library_dir())
	var config_file := "%s.yaml" % entry_id
	if not write_text_atomic(library_dir().path_join(config_file), yaml):
		return {}
	var entry := {
		"id": entry_id,
		"name": display_name,
		"type": kind,
		"config_file": config_file,
		"provider_file": provider_file,
		"created_at": int(Time.get_unix_time_from_system())
	}
	for key in extra:
		entry[key] = extra[key]
	return entry

func remove_entry_config(entry: Dictionary) -> void:
	var config_file := str(entry.get("config_file", ""))
	if not config_file.is_empty():
		var config_path := library_dir().path_join(config_file)
		if FileAccess.file_exists(config_path):
			DirAccess.remove_absolute(config_path)

func delete_entry_files(entry: Dictionary) -> void:
	remove_entry_config(entry)
	var provider_files := [
		str(entry.get("provider_file", "")),
		str(entry.get("hy2_provider_file", ""))
	]
	for provider_file in provider_files:
		if provider_file.is_empty():
			continue
		for path in [provider_dir().path_join(provider_file), library_dir().path_join(provider_file)]:
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(path)

func read_entry_config(entry: Dictionary) -> String:
	var path := library_dir().path_join(str(entry.get("config_file", "")))
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)

func write_text_atomic(path: String, content: String) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var temp_path := path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(content)
	file.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	return DirAccess.rename_absolute(temp_path, path) == OK
