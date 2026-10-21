// 도트 아트용 sharp bilinear 샘플(#264). 텍셀 안쪽은 Nearest와 같고, 텍셀 경계만 화면 1픽셀(fwidth) 폭으로 섞는다.
// 정수 배율에서는 모든 화면 픽셀이 한 텍셀 안에 들어가 Nearest와 같다. 1920×1080(1텍셀=1.5px)에서는 도트 크기가 고르게 보인다.
// sampler는 Nearest여도 된다. 네 텍셀을 직접 읽고 알파를 곱한 색으로 섞어 투명 가장자리가 어둡게 번지지 않는다.
// 내장 TEXTURE는 함수 인자로 넘기면 headless 셰이더 컴파일이 오류를 내므로 텍셀 읽기는 매크로로 둔다.

// 텍셀이 화면 픽셀보다 클 때(확대)만 섞는다. 1텍셀이 1화면 픽셀 이하면(글꼴 글리프, 1280×720의 유닛 그림) Nearest 그대로다.
bool sharp_magnified(vec2 pixel) {
	vec2 footprint = fwidth(pixel);
	return max(footprint.x, footprint.y) < 0.9;
}

vec2 sharp_weight(vec2 pixel) {
	vec2 seam = floor(pixel + 0.5);
	return clamp((pixel - seam) / max(fwidth(pixel), vec2(1e-4)) + 0.5, 0.0, 1.0);
}

vec4 sharp_mix(vec4 top_left, vec4 top_right, vec4 bottom_left, vec4 bottom_right, vec2 weight) {
	top_left.rgb *= top_left.a;
	top_right.rgb *= top_right.a;
	bottom_left.rgb *= bottom_left.a;
	bottom_right.rgb *= bottom_right.a;
	vec4 color = mix(mix(top_left, top_right, weight.x), mix(bottom_left, bottom_right, weight.x), weight.y);
	return color.a > 0.0 ? vec4(color.rgb / color.a, color.a) : vec4(0.0);
}

// tex의 텍셀 경계 seam 주변 텍셀 하나를 읽는다. size는 tex의 텍셀 수다.
#define SHARP_FETCH(tex, uv, size, dx, dy) texture(tex, (floor((uv) * (size) + 0.5) + vec2(dx, dy)) / (size))
// 분기 없이 mix로 고른다. fwidth가 균일한 흐름에서만 계산되고, 확대가 아니면 원래 샘플과 정확히 같다.
#define SHARP_TEXTURE(tex, uv, size) mix(texture(tex, uv), sharp_mix(SHARP_FETCH(tex, uv, size, -0.5, -0.5), SHARP_FETCH(tex, uv, size, 0.5, -0.5), SHARP_FETCH(tex, uv, size, -0.5, 0.5), SHARP_FETCH(tex, uv, size, 0.5, 0.5), sharp_weight((uv) * (size))), float(sharp_magnified((uv) * (size))))
