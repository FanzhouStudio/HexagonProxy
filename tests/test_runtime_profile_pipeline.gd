extends SceneTree

const PipelineScript = preload("res://scripts/modules/proxy/runtime_profile_pipeline.gd")

class FakeTransformer:
	var marker: String
	func _init(value: String) -> void: marker = value
	func transform_profile(content: String, _context := {}) -> Dictionary:
		return {"ok": true, "content": content + marker}

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var path := ProjectSettings.globalize_path("user://pipeline-test.yaml")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail("无法创建 Pipeline 测试文件", 2)
		return
	file.store_string("base")
	file.close()
	var pipeline = PipelineScript.new()
	pipeline.register_transformer("late", FakeTransformer.new("-late"), 100)
	pipeline.register_transformer("early", FakeTransformer.new("-early"), 10)
	var result: Dictionary = pipeline.apply(path)
	if not bool(result.get("ok", false)) or FileAccess.get_file_as_string(path) != "base-early-late":
		_fail("Transformer 没有按优先级执行", 3)
		return
	pipeline.register_transformer("late", FakeTransformer.new("-replaced"), 50)
	pipeline.unregister_transformer("early")
	file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail("无法重置 Pipeline 测试文件", 4)
		return
	file.store_string("base")
	file.close()
	result = pipeline.apply(path)
	if not bool(result.get("ok", false)) or FileAccess.get_file_as_string(path) != "base-replaced":
		_fail("Transformer 替换/卸载契约失败", 5)
		return
	print("PASS: RuntimeProfilePipeline 注册、优先级、替换与卸载")
	quit(0)

func _fail(message: String, code: int) -> void:
	printerr("FAIL: %s" % message)
	quit(code)
