class_name RuntimeProfilePipeline
extends RefCounted

## 运行配置处理管线
## 启动 Mihomo 前按优先级执行可插拔 transformer，不让 ProxyService 知道具体规则类型。

var _entries: Array[Dictionary] = []

func register_transformer(id: String, transformer, priority := 100) -> void:
	unregister_transformer(id)
	_entries.append({"id": id, "transformer": transformer, "priority": int(priority)})
	_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("priority", 100)) < int(b.get("priority", 100))
	)

func unregister_transformer(id: String) -> void:
	for index in range(_entries.size() - 1, -1, -1):
		if str(_entries[index].get("id", "")) == id:
			_entries.remove_at(index)

func apply(profile_path: String, context := {}) -> Dictionary:
	if not FileAccess.file_exists(profile_path):
		return {"ok": false, "message": "活动配置不存在。"}
	var original := FileAccess.get_file_as_string(profile_path)
	var content := original
	for entry in _entries:
		var transformer = entry.get("transformer")
		if transformer == null or not transformer.has_method("transform_profile"):
			continue
		var result: Dictionary = transformer.transform_profile(content, context)
		if not bool(result.get("ok", false)):
			return {"ok": false, "message": str(result.get("message", "运行配置处理失败。")), "transformer": str(entry.get("id", ""))}
		content = str(result.get("content", content))
	if content == original:
		return {"ok": true, "changed": false}
	return _write_atomic(profile_path, content)
func _write_atomic(path: String, content: String) -> Dictionary:
	var temporary := path + ".pipeline.tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "message": "无法写入运行配置临时文件。"}
	file.store_string(content)
	file.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	if DirAccess.rename_absolute(temporary, path) != OK:
		DirAccess.remove_absolute(temporary)
		return {"ok": false, "message": "无法替换运行配置。"}
	return {"ok": true, "changed": true}
