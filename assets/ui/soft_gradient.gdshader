shader_type canvas_item;
render_mode unshaded;

uniform vec4 top_left : source_color;
uniform vec4 top_right : source_color;
uniform vec4 bottom_left : source_color;
uniform vec4 bottom_right : source_color;

void fragment() {
	vec4 top = mix(top_left, top_right, UV.x);
	vec4 bottom = mix(bottom_left, bottom_right, UV.x);
	COLOR = mix(top, bottom, UV.y);
}
