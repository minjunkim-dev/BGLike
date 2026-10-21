shader_type canvas_item;
render_mode unshaded;

uniform vec4 outline_color : source_color = vec4(1.0);

void fragment() {
	// 텍셀이 화면 픽셀보다 작으면(640×360의 0.5배 그림) 1텍셀 윤곽은 픽셀 사이로 빠져 끊긴다. 최소 1화면 픽셀로 샘플한다.
	vec2 pixel = max(TEXTURE_PIXEL_SIZE, fwidth(UV));
	float alpha = texture(TEXTURE, UV).a;
	float edge = max(max(texture(TEXTURE, UV + vec2(pixel.x, 0.0)).a,
		texture(TEXTURE, UV - vec2(pixel.x, 0.0)).a),
		max(texture(TEXTURE, UV + vec2(0.0, pixel.y)).a,
		texture(TEXTURE, UV - vec2(0.0, pixel.y)).a));
	COLOR = vec4(outline_color.rgb, (1.0 - alpha) * edge * outline_color.a);
}
