class_name AquariumBackground
extends Control

const BUBBLE_COUNT := 34
const WATER_TINT := Color(0.01, 0.09, 0.18, 0.22)

var _background: Texture2D = preload("res://assets/aquarium_bg.png")
var _bubbles: Array[Dictionary] = []
var _random := RandomNumberGenerator.new()
var _elapsed := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_random.seed = 0xA601071
	_reset_bubbles()
	resized.connect(_on_resized)

func _process(delta: float) -> void:
	_elapsed += delta
	for bubble in _bubbles:
		bubble["y"] = float(bubble["y"]) - float(bubble["speed"]) * delta
		if float(bubble["y"]) < -20.0:
			_reset_bubble(bubble, true)
	queue_redraw()

func _draw() -> void:
	if is_instance_valid(_background):
		var texture_size := _background.get_size()
		var texture_scale := maxf(size.x / texture_size.x, size.y / texture_size.y)
		var drawn_size := texture_size * texture_scale
		var offset := (size - drawn_size) * 0.5
		draw_texture_rect(_background, Rect2(offset, drawn_size), false)
	draw_rect(Rect2(Vector2.ZERO, size), WATER_TINT)
	for bubble in _bubbles:
		_draw_pixel_bubble(bubble)

func _draw_pixel_bubble(bubble: Dictionary) -> void:
	var drift := sin(_elapsed * float(bubble["drift_speed"]) + float(bubble["phase"])) * float(bubble["drift"])
	var bubble_position := Vector2(float(bubble["x"]) + drift, float(bubble["y"]))
	var pixel := float(bubble["pixel"])
	var alpha := float(bubble["alpha"])
	var edge := Color(0.46, 0.95, 1.0, alpha)
	var shine := Color(0.88, 1.0, 1.0, minf(alpha + 0.16, 0.72))
	var radius := pixel * 2.0
	# Square segments keep the bubbles visually consistent with the pixel artwork.
	draw_rect(Rect2(bubble_position + Vector2(-pixel, -radius), Vector2(pixel * 2.0, pixel)), edge)
	draw_rect(Rect2(bubble_position + Vector2(-pixel, radius - pixel), Vector2(pixel * 2.0, pixel)), edge)
	draw_rect(Rect2(bubble_position + Vector2(-radius, -pixel), Vector2(pixel, pixel * 2.0)), edge)
	draw_rect(Rect2(bubble_position + Vector2(radius - pixel, -pixel), Vector2(pixel, pixel * 2.0)), edge)
	draw_rect(Rect2(bubble_position + Vector2(-radius + pixel, -radius + pixel), Vector2(pixel, pixel)), shine)

func _reset_bubbles() -> void:
	_bubbles.clear()
	for index in BUBBLE_COUNT:
		var bubble := {}
		_bubbles.append(bubble)
		_reset_bubble(bubble, false)

func _reset_bubble(bubble: Dictionary, from_bottom: bool) -> void:
	bubble["x"] = _random.randf_range(18.0, maxf(size.x - 18.0, 19.0))
	bubble["y"] = size.y + _random.randf_range(8.0, 130.0) if from_bottom else _random.randf_range(0.0, maxf(size.y, 1.0))
	bubble["speed"] = _random.randf_range(16.0, 46.0)
	bubble["pixel"] = float(_random.randi_range(1, 3))
	bubble["alpha"] = _random.randf_range(0.18, 0.5)
	bubble["drift"] = _random.randf_range(2.0, 10.0)
	bubble["drift_speed"] = _random.randf_range(0.45, 1.1)
	bubble["phase"] = _random.randf_range(0.0, TAU)

func _on_resized() -> void:
	for bubble in _bubbles:
		bubble["x"] = clampf(float(bubble["x"]), 12.0, maxf(size.x - 12.0, 13.0))
