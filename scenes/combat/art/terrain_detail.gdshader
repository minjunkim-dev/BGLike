shader_type canvas_item;

uniform sampler2D detail_texture : source_color, filter_nearest, repeat_disable;
varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	COLOR = tint * texture(detail_texture, UV);
}
