class_name ApplicationRoutingService
extends Node

## 应用分流服务 + RuntimeProfile transformer
## 规则数据独立持久化，启动前编译为 Mihomo PROCESS-NAME 规则。

signal rules_changed
signal event_logged(message: String)
signal restart_requested

const StoreScript = preload("res://scripts/modules/routing/application_routing_store.gd")
const BEGIN_MARKER := "  # HEXAGON-APP-ROUTING-BEGIN"
const END_MARKER := "  # HEXAGON-APP-ROUTING-END"

var store
var enabled := true
var rules: Array = []
var _initialized := false

func initialize() -> void:
	if _initialized:
		return
	_initialized = true
	store = StoreScript.new()
	var state: Dictionary = store.load_state()
	enabled = bool(state.get("enabled", true))
	rules = state.get("rules", [])

func snapshot() -> Dictionary:
	initialize()
	return {"enabled": enabled, "rules": rules.duplicate(true), "targets": target_catalog()}
func target_catalog() -> Array:
	return [
		{"id": "proxy", "label": "走代理", "policy": "六角选择"},
		{"id": "direct", "label": "直连", "policy": "DIRECT"}
	]

func set_enabled(value: bool) -> bool:
	initialize()
	if enabled == value:
		return true
	enabled = value
	return _commit("应用分流已%s。" % ("启用" if enabled else "关闭"))

func add_application(path: String) -> Dictionary:
	initialize()
	if not FileAccess.file_exists(path) or path.get_extension().to_lower() != "exe":
		return {"ok": false, "message": "请选择有效的 Windows .exe 程序。"}
	var process_name := path.get_file()
	if process_name.contains(","):
		return {"ok": false, "message": "程序文件名暂不支持逗号。"}
	for rule in rules:
		if str(rule.get("process_name", "")).to_lower() == process_name.to_lower():
			return {"ok": false, "message": "%s 已经在分流列表中。" % process_name}
	var rule := {
		"id": "%d-%s" % [Time.get_ticks_usec(), Crypto.new().generate_random_bytes(3).hex_encode()],
		"display_name": process_name.get_basename(),
		"path": path.replace("\\", "/"),
		"process_name": process_name,
		"target": "proxy",
		"enabled": true
	}
	rules.append(rule)
	if not _commit("已添加应用分流：%s" % process_name):
		rules.erase(rule)
		return {"ok": false, "message": "无法保存应用分流规则。"}
	return {"ok": true, "rule": rule.duplicate(true)}
func set_rule_target(rule_id: String, target: String) -> bool:
	initialize()
	if target not in ["proxy", "direct"]:
		return false
	var rule := _find_rule(rule_id)
	if rule.is_empty():
		return false
	rule["target"] = target
	return _commit("应用分流策略已更新。")

func set_rule_enabled(rule_id: String, value: bool) -> bool:
	initialize()
	var rule := _find_rule(rule_id)
	if rule.is_empty():
		return false
	rule["enabled"] = value
	return _commit("应用分流规则已%s。" % ("启用" if value else "停用"))

func delete_rule(rule_id: String) -> bool:
	initialize()
	for index in range(rules.size()):
		if str(rules[index].get("id", "")) == rule_id:
			var name := str(rules[index].get("display_name", "应用"))
			rules.remove_at(index)
			return _commit("已删除应用分流：%s" % name)
	return false

func _find_rule(rule_id: String) -> Dictionary:
	for rule in rules:
		if str(rule.get("id", "")) == rule_id:
			return rule
	return {}
func transform_profile(content: String, _context := {}) -> Dictionary:
	initialize()
	var cleaned := _remove_generated_block(content)
	if not enabled:
		return {"ok": true, "content": cleaned}
	var active_rules: Array[Dictionary] = []
	for rule in rules:
		if bool(rule.get("enabled", true)):
			active_rules.append(rule)
	if active_rules.is_empty():
		return {"ok": true, "content": cleaned}
	var proxy_policy := "六角选择" if cleaned.contains("name: 六角选择") else "GLOBAL"
	var generated: Array[String] = [BEGIN_MARKER]
	for rule in active_rules:
		var target := str(rule.get("target", "proxy"))
		var policy := "DIRECT" if target == "direct" else proxy_policy
		generated.append("  - PROCESS-NAME,%s,%s" % [str(rule.get("process_name", "")), policy])
	generated.append(END_MARKER)
	var with_process_mode := _ensure_process_mode(cleaned)
	return {"ok": true, "content": _insert_rule_block(with_process_mode, generated)}

func _ensure_process_mode(content: String) -> String:
	var expression := RegEx.new()
	if expression.compile("(?m)^find-process-mode\\s*:") == OK and expression.search(content) != null:
		return content
	return "find-process-mode: strict\n" + content
func _remove_generated_block(content: String) -> String:
	var normalized := content.replace("\r\n", "\n").replace("\r", "\n")
	var lines := normalized.split("\n")
	var result: Array[String] = []
	var skipping := false
	for raw_line in lines:
		var line := str(raw_line)
		if line.strip_edges() == BEGIN_MARKER.strip_edges():
			skipping = true
			continue
		if line.strip_edges() == END_MARKER.strip_edges():
			skipping = false
			continue
		if not skipping:
			result.append(line)
	return "\n".join(result)

func _insert_rule_block(content: String, generated: Array[String]) -> String:
	var lines: Array[String] = []
	for raw_line in content.split("\n"):
		lines.append(str(raw_line))
	var rules_index := -1
	for index in range(lines.size()):
		if lines[index].strip_edges() == "rules:":
			rules_index = index
			break
	if rules_index < 0:
		if not lines.is_empty() and not lines.back().is_empty():
			lines.append("")
		lines.append("rules:")
		rules_index = lines.size() - 1
	for index in range(generated.size() - 1, -1, -1):
		lines.insert(rules_index + 1, generated[index])
	return "\n".join(lines)
func _commit(message: String) -> bool:
	if store == null:
		store = StoreScript.new()
	if not store.save_state(enabled, rules):
		event_logged.emit("无法保存应用分流规则。")
		return false
	rules_changed.emit()
	event_logged.emit(message)
	restart_requested.emit()
	return true
