shader_type canvas_item;
// CRT overlay: scanlines, rolling refresh band, flicker, vignette and phosphor grain.

uniform float intensity : hint_range(0.0, 1.0) = 0.6;

float rand(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	float scan = 0.5 + 0.5 * sin(uv.y * 900.0);
	float band = smoothstep(0.0, 0.04, abs(fract(uv.y - TIME * 0.12) - 0.5));
	vec2 centered = uv - 0.5;
	float vignette = smoothstep(0.75, 0.25, length(centered * vec2(1.0, 1.25)));
	float grain = rand(uv * 600.0 + TIME) * 0.06;
	float flicker = 0.97 + 0.03 * sin(TIME * 60.0);
	float dark = (1.0 - scan) * 0.22 + (1.0 - band) * 0.05 + (1.0 - vignette) * 0.65;
	COLOR = vec4(0.0, 0.02, 0.0, clamp(dark * intensity * flicker + grain * intensity, 0.0, 1.0));
}
