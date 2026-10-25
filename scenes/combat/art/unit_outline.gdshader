shader_type canvas_item;
render_mode unshaded;

#include "res://scenes/combat/art/pixel_art.gdshaderinc"

uniform float fill_alpha = 0.0;
uniform vec4 outline_color : source_color = vec4(1.0);

void fragment() {
	// 텍셀이 화면 픽셀보다 작으면(640×360의 0.5배 그림) 1텍셀 윤곽은 픽셀 사이로 빠져 끊긴다. 최소 1화면 픽셀로 샘플한다.
	vec2 pixel = max(TEXTURE_PIXEL_SIZE, fwidth(UV));
	vec2 size = 1.0 / TEXTURE_PIXEL_SIZE;
	// 그림과 같은 sharp bilinear 알파로 윤곽 안쪽 경계를 그림 가장자리에 맞춘다(#264).
	float alpha = SHARP_TEXTURE(TEXTURE, UV, size).a;
	float edge = max(max(SHARP_TEXTURE(TEXTURE, UV + vec2(pixel.x, 0.0), size).a,
		SHARP_TEXTURE(TEXTURE, UV - vec2(pixel.x, 0.0), size).a),
		max(SHARP_TEXTURE(TEXTURE, UV + vec2(0.0, pixel.y), size).a,
		SHARP_TEXTURE(TEXTURE, UV - vec2(0.0, pixel.y), size).a));
	COLOR = vec4(outline_color.rgb, max((1.0 - alpha) * edge * outline_color.a, alpha * fill_alpha));
}
