shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

// Clustered tree canopy: wind sway, leaf clumps, subsurface backlight.

#include "res://shaders/common.gdshaderinc"

uniform vec4 leaf_dark : source_color = vec4(0.1, 0.19, 0.07, 1.0);
uniform vec4 leaf_light : source_color = vec4(0.32, 0.45, 0.16, 1.0);

varying vec3 v_wpos;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float sway = sin(TIME * 1.1 + world.x * 0.35 + world.z * 0.2) * 0.06 + sin(TIME * 2.7 + world.y * 1.3) * 0.02;
	VERTEX.x += sway * (VERTEX.y + 1.0);
	VERTEX.z += sway * 0.6 * (VERTEX.y + 1.0);
	v_wpos = world;
}

void fragment() {
	vec2 p = v_wpos.xy * 3.0 + v_wpos.zx * 2.0;
	float clump = fbm3(p);
	float leaf = vnoise(p * 6.0);
	vec3 col = mix(leaf_dark.rgb, leaf_light.rgb, smoothstep(0.3, 0.8, clump));
	col *= 0.7 + 0.5 * leaf;
	ALBEDO = col;
	ROUGHNESS = 0.75;
	BACKLIGHT = col * 0.9;
	float bump = (leaf - 0.5) * 0.6;
	NORMAL = normalize(NORMAL + vec3(bump, bump * 0.5, 0.0));
}
