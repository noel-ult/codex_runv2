shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Clustered tree canopy: wind sway, leaf clumps, subsurface backlight.

#include "res://shaders/common.gdshaderinc"

uniform vec4 leaf_dark : source_color = vec4(0.15, 0.25, 0.11, 1.0);
uniform vec4 leaf_light : source_color = vec4(0.44, 0.54, 0.24, 1.0);

varying vec3 v_wpos;
varying vec3 v_wnrm;
varying float crown_height;

// Sample in three dimensions so the texture holds up on every side of a cluster.
float canopy_noise(vec3 point) {
	vec3 cell = floor(point);
	vec3 f = fract(point);
	vec3 weight = f * f * (3.0 - 2.0 * f);
	float lower = mix(
		mix(hash13(cell), hash13(cell + vec3(1, 0, 0)), weight.x),
		mix(hash13(cell + vec3(0, 1, 0)), hash13(cell + vec3(1, 1, 0)), weight.x),
		weight.y);
	float upper = mix(
		mix(hash13(cell + vec3(0, 0, 1)), hash13(cell + vec3(1, 0, 1)), weight.x),
		mix(hash13(cell + vec3(0, 1, 1)), hash13(cell + vec3(1, 1, 1)), weight.x),
		weight.y);
	return mix(lower, upper, weight.z);
}

void vertex() {
	vec3 center = MODEL_MATRIX[3].xyz;
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	crown_height = VERTEX.y;
	v_wpos = world;
	v_wnrm = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	float lobes = canopy_noise(world * 2.6) - 0.5;
	VERTEX += NORMAL * lobes * 0.26;
	float gust = sin(TIME * 1.45 + center.x * 0.31 + center.z * 0.22);
	float flutter = sin(TIME * 3.8 + world.y * 2.0 + world.x * 2.7);
	float flex = smoothstep(-0.75, 0.9, crown_height);
	VERTEX.x += (gust * 0.13 + flutter * 0.032) * flex;
	VERTEX.z += (gust * 0.08 - flutter * 0.022) * flex;
}

void fragment() {
	float clump = canopy_noise(v_wpos * 3.9);
	float detail = 1.0 - smoothstep(0.025, 0.1, length(fwidth(v_wpos)));
	float leaf = mix(0.5, canopy_noise(v_wpos * 24.0), detail);
	float canopy_light = clamp(0.55 * clump + 0.25 * crown_height + 0.30, 0.0, 1.0);
	vec3 col = mix(leaf_dark.rgb, leaf_light.rgb, canopy_light);
	col *= 0.67 + clump * 0.3 + leaf * 0.37;
	ALBEDO = col;
	ROUGHNESS = mix(0.9, 0.61, leaf);
	BACKLIGHT = col * 0.45;
	vec3 base_normal = normalize(v_wnrm);
	vec3 tangent = normalize(cross(abs(base_normal.y) < 0.9 ? vec3(0, 1, 0) : vec3(1, 0, 0), base_normal));
	vec3 bump = tangent * (leaf - 0.5) + cross(base_normal, tangent) * (clump - 0.5);
	NORMAL = normalize((VIEW_MATRIX * vec4(base_normal + 0.46 * bump, 0.0)).xyz);
}
