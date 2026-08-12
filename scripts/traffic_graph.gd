class_name TrafficGraph
extends Control

var samples: Array[float] = []
var accent := Color("16866f")

func push_sample(value: float) -> void:
	samples.append(maxf(value, 0.0))
	if samples.size() > 44:
		samples.pop_front()
	queue_redraw()

func _draw() -> void:
	var bounds := Rect2(Vector2.ZERO, size)
	draw_style_box(_box(Color("f5ffffc9"), Color("b8ecebea"), 18), bounds)
	for index in range(1, 4):
		var y := size.y * float(index) / 4.0
		draw_line(Vector2(16, y), Vector2(size.x - 16, y), Color("3e7c8b32"), 1.0)
	if samples.size() < 2:
		return
	var peak: float = maxf(samples.max(), 1.0)
	var points := PackedVector2Array()
	for index in samples.size():
		var x := 16.0 + (size.x - 32.0) * float(index) / 43.0
		var y := size.y - 16.0 - (size.y - 32.0) * samples[index] / peak
		points.append(Vector2(x, y))
	if points.size() > 1:
		draw_polyline(points, accent, 3.0, true)
		for point in points:
			draw_circle(point, 2.2, Color("74ccb1"))

func _box(fill: Color, border: Color, radius: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(radius)
	return box
