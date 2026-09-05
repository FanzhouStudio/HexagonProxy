class_name PortProfileTransformer
extends RefCounted

## mixed-port 运行时注入器
## 作为 RuntimeProfilePipeline 的独立插件存在。

var proxy_config

func setup(config) -> void:
	proxy_config = config

func transform_profile(content: String, _context := {}) -> Dictionary:
	if proxy_config == null:
		return {"ok": false, "message": "端口配置尚未绑定。"}
	var expression := RegEx.new()
	if expression.compile("(?m)^mixed-port\\s*:\\s*\\d+\\s*(?:#.*)?$") != OK:
		return {"ok": false, "message": "无法创建 mixed-port 匹配规则。"}
	var replacement := "mixed-port: %d" % int(proxy_config.mixed_port())
	var updated := content
	if expression.search(content) != null:
		updated = expression.sub(content, replacement, true)
	else:
		updated = replacement + "\n" + content
	return {"ok": true, "content": updated}
