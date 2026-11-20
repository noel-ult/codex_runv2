shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Concrete paving slabs with recessed joints, per-slab tone, chewing-gum spots and damp patches.

#include "res://shaders/common.gdshaderinc"

uniform vec4 slab_color : source_color = vec4(0.40, 0.39, 0.38, 1.0);
uniform float slab_size = 1.2;
global uniform float wetness;

varying vec3 v_wpos;
varying vec3 v_wnrm;

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(v_wnrm);
	vec2 p = abs(n.y) > 0.5 ? v_wpos.xz : facade_uv(v_wpos, n);
	vec2 q = p / slab_size;
	vec2 cell = floor(q);
	vec2 f = fract(q);
	float joint = smoothstep(0.0, 0.025, f.x) * smoothstep(0.0, 0.025, 1.0 - f.x) * smoothstep(0.0, 0.025, f.y) * smoothstep(0.0, 0.025, 1.0 - f.y);
	float tone = hash12(cell);
	float speck = vnoise(p * 30.0);
	float stain = fbm3(p * 0.3);
	float aggregate = vnoise(p * 10.0 + 4.7);
	float gum = step(0.985, hash12(floor(p * 6.0)));
	vec3 col = slab_color.rgb * (0.74 + 0.38 * tone) * (0.82 + 0.32 * speck) * (0.78 + 0.4 * stain) * (0.9 + 0.2 * aggregate);
	col = mix(col * 0.35, col, joint);
	col = mix(col, vec3(0.08), gum * 0.6);
	float damp = smoothstep(0.58, 0.7, fbm3(p * 0.15 + 2.0)) * clamp(wetness * 1.4, 0.0, 1.0);
	ALBEDO = mix(col, col * 0.76, damp);
	ROUGHNESS = mix(0.88, 0.38, damp);
}
