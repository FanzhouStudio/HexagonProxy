class_name NodeFailoverPolicy
extends RefCounted

## 节点故障切换纯策略
## 不持久化、不发请求，只根据候选与延迟选择目标。

func choose_best(
	group_name: String,
	backups: Array,
	delays: Dictionary,
	current_node: String,
	attempted: Dictionary,
	max_delay_ms: int
) -> Dictionary:
	var best_name := ""
	var best_delay := 2147483647
	for item in backups:
		if not item is Dictionary:
			continue
		if str(item.get("group", "")) != group_name:
			continue
		var node := str(item.get("node", ""))
		if node.is_empty() or node == current_node or attempted.has(node):
			continue
		var delay := int(delays.get(node, -1))
		if delay <= 0 or delay > max_delay_ms:
			continue
		if delay < best_delay:
			best_delay = delay
			best_name = node
	return {"node": best_name, "delay": best_delay if not best_name.is_empty() else -1}
