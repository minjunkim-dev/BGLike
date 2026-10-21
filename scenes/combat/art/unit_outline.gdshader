shader_type canvas_item;
render_mode unshaded;

uniform vec4 outline_color : source_color = vec4(1.0);

void fragment() {
	vec2 pixel = TEXTURE_PIXEL_SIZE;
	float alpha = texture(TEXTURE, UV).a;
	float edge = max(max(texture(TEXTURE, UV + vec2(pixel.x, 0.0)).a,
		texture(TEXTURE, UV - vec2(pixel.x, 0.0)).a),
		max(texture(TEXTURE, UV + vec2(0.0, pixel.y)).a,
		texture(TEXTURE, UV - vec2(0.0, pixel.y)).a));
	COLOR = vec4(outline_color.rgb, (1.0 - alpha) * edge * outline_color.a);
}
