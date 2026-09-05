class_name SubscriptionLegacyMigrator
extends RefCounted

## 旧版 active.yaml 识别与 provider 文件搬迁
## 返回迁移候选，订阅列表状态仍由 SubscriptionService 管理

var proxy_config
var store

func setup(config_value, store_value) -> void:
	proxy_config = config_value
	store = store_value

func prepare_candidate() -> Dictionary:
	var active_path: String = proxy_config.active_profile_path()
	if not FileAccess.file_exists(active_path):
		return {}
	var yaml := FileAccess.get_file_as_string(active_path)
	if yaml.contains("# HexagonProxy默认直连配置") or yaml.contains("# 六角代理默认直连配置"):
		return {}
	var kind := "local"
	var display_name := "迁移的本地配置"
	var provider_file := ""
	if yaml.contains("hexagon-subscription"):
		kind = "http"
		display_name = "HTTP 订阅（已迁移）"
	elif yaml.contains("hexagon-v2"):
		kind = "v2"
		display_name = "V2 分享链接（已迁移）"
		var legacy_provider: String = proxy_config.runtime_dir().path_join("providers").path_join("hexagon-v2.txt")
		if FileAccess.file_exists(legacy_provider):
			provider_file = "%s-v2.txt" % store.new_id()
			var provider_path: String = store.provider_dir().path_join(provider_file)
			if not store.write_text_atomic(provider_path, FileAccess.get_file_as_string(legacy_provider)):
				return {"error": "无法迁移旧版 V2 provider 文件。"}
			yaml = yaml.replace("./providers/hexagon-v2.txt", "./providers/library/%s" % provider_file)
	return {
		"yaml": yaml,
		"kind": kind,
		"display_name": display_name,
		"provider_file": provider_file
	}
