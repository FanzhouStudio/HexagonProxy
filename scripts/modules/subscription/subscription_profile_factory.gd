class_name SubscriptionProfileFactory
extends RefCounted

## HexagonProxy生成配置模板
## 集中维护固定路由规则、rule provider 与基础订阅 YAML

const GENERATED_ROUTING_RULES := """rules:
  - DOMAIN,localhost,DIRECT
  - DOMAIN-SUFFIX,localhost,DIRECT
  - IP-CIDR,127.0.0.0/8,DIRECT,no-resolve
  - IP-CIDR,10.0.0.0/8,DIRECT,no-resolve
  - IP-CIDR,100.64.0.0/10,DIRECT,no-resolve
  - IP-CIDR,169.254.0.0/16,DIRECT,no-resolve
  - IP-CIDR,172.16.0.0/12,DIRECT,no-resolve
  - IP-CIDR,192.168.0.0/16,DIRECT,no-resolve
  - IP-CIDR6,::1/128,DIRECT,no-resolve
  - IP-CIDR6,fc00::/7,DIRECT,no-resolve
  - IP-CIDR6,fe80::/10,DIRECT,no-resolve
  - RULE-SET,hexagon-cn-domain,DIRECT
  - RULE-SET,hexagon-cn-ip,DIRECT,no-resolve
  - MATCH,六角选择
"""

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
%s""" % [GENERATED_RULE_PROVIDERS, escaped, GENERATED_ROUTING_RULES]

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
%s""" % [GENERATED_RULE_PROVIDERS, GENERATED_ROUTING_RULES]

func v2_profile_yaml(parser, provider_name: String, hy2_provider_name := "") -> String:
	return parser.v2_profile_yaml(
		provider_name,
		hy2_provider_name,
		GENERATED_RULE_PROVIDERS,
		GENERATED_ROUTING_RULES
	)
func generated_routing_rules() -> String:
	return GENERATED_ROUTING_RULES

func generated_rule_providers() -> String:
	return GENERATED_RULE_PROVIDERS