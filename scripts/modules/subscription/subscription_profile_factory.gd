class_name SubscriptionProfileFactory
extends RefCounted

## HexagonProxy生成配置模板
## 集中维护固定路由规则、rule provider 与基础订阅 YAML

const LocalNetworkCatalogScript = preload("res://scripts/modules/network/local_network_catalog.gd")

var local_network_catalog = LocalNetworkCatalogScript.new()

const GENERATED_RULE_PROVIDERS := """rule-providers:
  hexagon-cn-domain:
    type: file
    behavior: domain
    format: mrs
    path: ./rules/geosite-cn.mrs
  hexagon-cn-ip:
    type: file
    behavior: ipcidr
    format: mrs
    path: ./rules/geoip-cn.mrs
"""

func http_profile_yaml(url: String) -> String:
	var escaped := url.replace("'", "''")
	return """# HexagonProxy生成的订阅配置
mixed-port: 7890
allow-lan: false
mode: rule
log-level: info
ipv6: false
unified-delay: true
tcp-concurrent: true
profile:
  store-selected: true
  store-fake-ip: true
%s
proxy-providers:
  hexagon-subscription:
    type: http
    url: '%s'
    path: ./providers/hexagon-subscription.yaml
    interval: 3600
    header:
      User-Agent:
        - 'mihomo'
    health-check:
      enable: true
      url: https://www.gstatic.com/generate_204
      interval: 600
proxy-groups:
  - name: 六角选择
    type: select
    use:
      - hexagon-subscription
  - name: 自动优选
    type: url-test
    use:
      - hexagon-subscription
    url: https://www.gstatic.com/generate_204
    interval: 300
    tolerance: 80
%s""" % [GENERATED_RULE_PROVIDERS, escaped, generated_routing_rules()]

func default_profile_yaml() -> String:
	return """# HexagonProxy默认直连配置
mixed-port: 7890
allow-lan: false
mode: rule
log-level: info
ipv6: false
profile:
  store-selected: true
%s
proxies: []
proxy-groups:
  - name: 六角选择
    type: select
    proxies:
      - DIRECT
%s""" % [GENERATED_RULE_PROVIDERS, generated_routing_rules()]

func v2_profile_yaml(parser, provider_name: String, hy2_provider_name := "") -> String:
	return parser.v2_profile_yaml(
		provider_name,
		hy2_provider_name,
		GENERATED_RULE_PROVIDERS,
		generated_routing_rules()
	)

func generated_routing_rules() -> String:
	var lines := PackedStringArray(["rules:"])
	lines.append_array(local_network_catalog.mihomo_direct_rules())
	lines.append("  - RULE-SET,hexagon-cn-domain,DIRECT")
	lines.append("  - RULE-SET,hexagon-cn-ip,DIRECT,no-resolve")
	lines.append("  - MATCH,六角选择")
	return "\n".join(lines) + "\n"

func generated_rule_providers() -> String:
	return GENERATED_RULE_PROVIDERS