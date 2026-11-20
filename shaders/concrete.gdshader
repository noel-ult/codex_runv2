shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Cast-in-place concrete: formwork panel seams, tie-holes, water stains and moss at the base.

#include "res://shaders/common.gdshaderinc"

instance uniform vec4 tint : source_color = vec4(0.5, 0.5, 0.49, 1.0);

varying vec3 v_wpos;
varying vec3 v_wnrm;

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(v_wnrm);
	vec2 p = abs(n.y) > 0.5 ? v_wpos.xz : facade_uv(v_wpos, n);
	vec2 q = p / vec2(2.4, 1.2);
	vec2 f = fract(q);
	float seam = smoothstep(0.0, 0.006, f.x) * smoothstep(0.0, 0.006, 1.0 - f.x) * smoothstep(0.0, 0.012, f.y) * smoothstep(0.0, 0.012, 1.0 - f.y);
	vec2 tie = fract(q * vec2(2.0, 2.0)) - 0.5;
	float hole = 1.0 - smoothstep(0.015, 0.03, length(tie * vec2(2.4, 1.2)));
	float stain = fbm3(p * vec2(0.5, 0.2));
	float streak = smoothstep(0.55, 0.95, vnoise(vec2(p.x * 3.0, p.y * 0.1)));
	float base_damp = abs(n.y) > 0.5 ? 0.0 : 1.0 - smoothstep(0.0, 1.2, v_wpos.y + stain * 0.8);
	vec3 col = tint.rgb * (0.8 + 0.25 * vnoise(p * 12.0)) * (0.82 + 0.3 * stain);
	col *= 1.0 - 0.3 * streak;
	col = mix(col, col * 0.4, 1.0 - seam);
	col = mix(col, vec3(0.05), hole * 0.8);
	col = mix(col, col * vec3(0.55, 0.65, 0.5), base_damp * 0.7);
	ALBEDO = col;
	ROUGHNESS = 0.9 - base_damp * 0.3;
}
