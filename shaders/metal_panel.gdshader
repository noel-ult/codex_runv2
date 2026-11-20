shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Painted industrial steel: panel seams, rivets, brushed grain, edge wear and optional hazard stripes.

#include "res://shaders/common.gdshaderinc"

instance uniform vec4 paint_color : source_color = vec4(0.22, 0.25, 0.27, 1.0);
instance uniform float hazard = 0.0;
uniform vec2 panel_size = vec2(1.6, 1.2);
uniform float wear = 0.25;

varying vec3 v_wpos;
varying vec3 v_wnrm;

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(v_wnrm);
	vec2 p = abs(n.y) > 0.5 ? v_wpos.xz : facade_uv(v_wpos, n);
	vec2 q = p / panel_size;
	vec2 f = fract(q);
	float seam = smoothstep(0.0, 0.01, f.x) * smoothstep(0.0, 0.01, 1.0 - f.x) * smoothstep(0.0, 0.014, f.y) * smoothstep(0.0, 0.014, 1.0 - f.y);
	vec2 rv = (f - vec2(0.04)) * panel_size;
	vec2 rv2 = (vec2(1.0) - f - vec2(0.04)) * panel_size;
	float rivet = max(max(1.0 - smoothstep(0.012, 0.02, length(rv)), 1.0 - smoothstep(0.012, 0.02, length(rv2))),
			max(1.0 - smoothstep(0.012, 0.02, length(vec2(rv.x, rv2.y))), 1.0 - smoothstep(0.012, 0.02, length(vec2(rv2.x, rv.y)))));
	vec3 paint = paint_color.rgb;
	if (hazard > 0.5) {
		float stripe = step(0.5, fract((p.x + p.y) * 1.4));
		paint = mix(vec3(0.03), vec3(0.85, 0.62, 0.05), stripe);
	}
	float brushed = vnoise(vec2(p.x * 2.0, p.y * 140.0));
	float chip = smoothstep(0.78, 0.84, fbm3(p * 7.0) + (1.0 - seam) * 0.35) * wear;
	float grime = fbm3(p * vec2(0.8, 0.3)) * 0.25;
	vec3 col = paint * (0.85 + 0.15 * brushed) * (1.0 - grime);
	vec3 bare = vec3(0.45, 0.45, 0.47) * (0.8 + 0.2 * brushed);
	col = mix(col, bare, chip);
	col = mix(col * 0.35, col, seam);
	col = mix(col, bare * 0.9, rivet);
	ALBEDO = col;
	METALLIC = mix(0.25, 0.9, max(chip, rivet));
	ROUGHNESS = mix(0.55, 0.3, max(chip, rivet)) + 0.1 * brushed;
}
