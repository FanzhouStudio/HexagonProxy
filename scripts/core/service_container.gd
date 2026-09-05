class_name ServiceContainer
extends Node

## 服务生命周期容器
## 负责服务注册、节点所有权、初始化和释放

var services: Dictionary = {}
var initialized := false

func register(name: String, service: Object) -> Object:
	if services.has(name):
		push_warning("Service already registered: %s" % name)
		return services[name]
	services[name] = service
	if service is Node:
		var node := service as Node
		if node.get_parent() == null:
			add_child(node)
	return service

func get_service(name: String) -> Object:
	return services.get(name)

func initialize_all() -> void:
	if initialized:
		return
	initialized = true
	for service in services.values():
		if service.has_method("initialize"):
			service.initialize()

func dispose_all() -> void:
	var list := services.values()
	list.reverse()
	for service in list:
		if service.has_method("dispose"):
			service.dispose()
		elif service.has_method("stop"):
			service.stop()
		if service is Node:
			var node := service as Node
			if is_instance_valid(node) and not node.is_queued_for_deletion():
				node.queue_free()
	services.clear()
	initialized = false
