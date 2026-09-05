class_name SubscriptionCatalog
extends RefCounted

## 订阅列表与活动项状态
## 负责索引的内存表示和持久化，不处理配置文件内容

var store
var entries: Array = []
var active_id := ""

func setup(store_value) -> void:
	store = store_value

func load() -> void:
	var loaded: Dictionary = store.load_index()
	entries = loaded.get("subscriptions", [])
	active_id = str(loaded.get("active_id", ""))

func save() -> bool:
	return store.save_index(entries, active_id)

func list() -> Array:
	return entries.duplicate(true)

func is_empty() -> bool:
	return entries.is_empty()

func size() -> int:
	return entries.size()
func index_of(entry_id: String) -> int:
	for index in entries.size():
		var entry: Dictionary = entries[index]
		if str(entry.get("id", "")) == entry_id:
			return index
	return -1

func entry_at(index: int) -> Dictionary:
	if index < 0 or index >= entries.size():
		return {}
	return entries[index]

func append(entry: Dictionary) -> void:
	entries.append(entry)

func insert_at(index: int, entry: Dictionary) -> void:
	entries.insert(clampi(index, 0, entries.size()), entry)

func pop_back() -> Dictionary:
	if entries.is_empty():
		return {}
	return entries.pop_back()

func remove_at(index: int) -> Dictionary:
	if index < 0 or index >= entries.size():
		return {}
	var entry: Dictionary = entries[index]
	entries.remove_at(index)
	return entry

func set_entry(index: int, entry: Dictionary) -> void:
	if index >= 0 and index < entries.size():
		entries[index] = entry
func set_active(entry_id: String) -> void:
	active_id = entry_id

func clear_active() -> void:
	active_id = ""

func new_id() -> String:
	return store.new_id()
