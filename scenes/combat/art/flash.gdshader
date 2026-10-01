shader_type canvas_item;
// 피격 시 스프라이트를 흰색으로 잠깐 번쩍이게 한다. flash 0 = 원래 색, 1 = 흰색.
uniform float flash : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	COLOR.rgb = mix(COLOR.rgb, vec3(1.0), flash);
}
