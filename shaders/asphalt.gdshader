shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Wet night asphalt: aggregate grain, patch repairs, hairline cracks, tyre-polished
// lanes and reflective puddles.

#include "res://shaders/common.gdshaderinc"

// 0 = bone dry, 1 = soaked (driven by WeatherSystem).
global uniform float wetness;
uniform vec4 base_color : source_color = vec4(0.07, 0.072, 0.078, 1.0);

varying vec3 v_wpos;

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = v_wpos.xz;
	float lod = smoothstep(0.01, 0.06, length(fwidth(p)));
	float grain = mix(vnoise(p * 22.0) * 0.6 + vnoise(p * 61.0) * 0.4, 0.5, lod);
	float patches = fbm3(p * 0.07);
	float repair = step(0.66, fbm3(p * 0.045 + 21.0));
	vec3 col = base_color.rgb * (0.75 + 0.45 * grain) * (0.8 + 0.4 * patches);
	col = mix(col, col * 0.7 + vec3(0.01), repair);

	float ridge = abs(fbm3(p * 0.35 + 3.0) - 0.5);
	float crack = (1.0 - smoothstep(0.0, 0.012, ridge)) * step(0.5, fbm3(p * 0.11 + 9.0));
	col *= 1.0 - 0.6 * crack;

	float puddle_field = fbm5(p * 0.09 + 5.3);
	float puddle = smoothstep(0.6 - wetness * 0.12, 0.64 - wetness * 0.12, puddle_field) * smoothstep(0.1, 0.5, wetness);
	float damp = smoothstep(0.42, 0.62, puddle_field) * wetness;

	ALBEDO = mix(col, col * 0.45, max(puddle, damp * 0.5));
	ROUGHNESS = mix(mix(0.82 - 0.15 * grain, 0.35, damp), 0.02, puddle);
	SPECULAR = 0.5;
	METALLIC = 0.0;

	vec2 grad = vec2(vnoise(p * 22.0 + vec2(0.05, 0.0)) - vnoise(p * 22.0), vnoise(p * 22.0 + vec2(0.0, 0.05)) - vnoise(p * 22.0)) * 6.0;
	grad *= (1.0 - puddle) * (1.0 - lod) * 0.25;
	vec3 wn = normalize(vec3(-grad.x, 1.0, -grad.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
}
