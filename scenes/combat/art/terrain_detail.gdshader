shader_type canvas_item;

#include "res://scenes/combat/art/pixel_art.gdshaderinc"

uniform sampler2D detail_texture : source_color, filter_nearest, repeat_disable;
varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	COLOR = tint * SHARP_TEXTURE(detail_texture, UV, vec2(textureSize(detail_texture, 0)));
}
