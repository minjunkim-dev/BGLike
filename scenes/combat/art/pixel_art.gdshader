shader_type canvas_item;

#include "res://scenes/combat/art/pixel_art.gdshaderinc"

varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	COLOR = tint * SHARP_TEXTURE(TEXTURE, UV, 1.0 / TEXTURE_PIXEL_SIZE);
}
