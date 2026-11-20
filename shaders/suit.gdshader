shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Clothing / under-armour fabric for skinned characters. UV.x runs around the limb
// (0.75 = front for the torso), UV.y along it. Draws woven micro-normal, seams, a front
// zipper, cuffs and glowing Codex veins whose colour/intensity are per-instance.

#include "res://shaders/common.gdshaderinc"

uniform vec4 base_color : source_color = vec4(0.16, 0.19, 0.17, 1.0);
uniform vec4 panel_color : source_color = vec4(0.3, 0.31, 0.29, 1.0);
uniform float pattern = 0.0; // 0 techwear jacket, 1 hunter undersuit (hex weave), 2 plain cloth
uniform float roughness_value = 0.86;
uniform float uv_scale_v = 6.0;
instance uniform vec4 accent_color : source_color = vec4(0.2, 0.9, 1.0, 1.0);
instance uniform float accent_energy = 1.0;
instance uniform float vein_mask = 1.0;

void fragment() {
	vec2 uv = UV;
	float around = uv.x;
	float along = uv.y;
	vec3 col = base_color.rgb;
	float rough = roughness_value;
	vec3 emission = vec3(0.0);

	if (pattern < 0.5) {
		// Techwear: contrasting side panels, front zipper, cuffs, seam lines.
		float side = smoothstep(0.06, 0.05, abs(fract(around + 0.0) - 0.0)) + smoothstep(0.06, 0.05, abs(around - 0.5));
		float panel = step(0.38, fract(along * 2.0 + 0.1)) * step(fract(along * 2.0 + 0.1), 0.62) * step(abs(around - 0.25), 0.12);
		col = mix(col, panel_color.rgb, clamp(side + panel * 0.8, 0.0, 1.0));
		float seam = smoothstep(0.006, 0.0, abs(fract(along * 3.0) - 0.5) - 0.0) * 0.6;
		col *= 1.0 - seam * 0.35;
		float zipper = smoothstep(0.012, 0.004, abs(around - 0.75));
		col = mix(col, vec3(0.05), zipper * 0.9);
		float vein = smoothstep(0.01, 0.0, abs(around - 0.75) - 0.008) * (1.0 - zipper * 0.4);
		vein += smoothstep(0.008, 0.0, abs(abs(around - 0.5) - 0.18) - 0.003) * step(0.2, fract(along * 1.5));
		float flow = 0.65 + 0.35 * sin(TIME * 3.0 - along * 18.0);
		emission = accent_color.rgb * accent_energy * clamp(vein, 0.0, 1.0) * flow * vein_mask;
	} else if (pattern < 1.5) {
		// Hunter undersuit: hex/ballistic weave + thin glowing circuit traces.
		vec2 hex = vec2(around * 40.0, along * uv_scale_v * 4.0);
		hex.x += mod(floor(hex.y), 2.0) * 0.5;
		vec2 hf = fract(hex) - 0.5;
		float cell = smoothstep(0.42, 0.48, max(abs(hf.x) * 1.15 + abs(hf.y) * 0.6, abs(hf.y) * 1.2));
		col = mix(col, col * 0.55, cell);
		rough = 0.7;
		float trace = smoothstep(0.006, 0.0, abs(around - 0.5) - 0.004) + smoothstep(0.006, 0.0, abs(around) - 0.004);
		emission = accent_color.rgb * accent_energy * 0.6 * trace * vein_mask;
	} else {
		// Plain cloth with subtle stitched seams.
		float seam = smoothstep(0.01, 0.0, abs(around - 0.5) - 0.002) + smoothstep(0.01, 0.0, abs(around) - 0.002);
		col *= 1.0 - 0.25 * seam;
	}

	// Keep broad folds visible at gameplay distance and fade the weave as its threads become subpixel.
	vec2 weave_uv = vec2(around * 44.0, along * uv_scale_v * 8.0);
	vec2 thread_angle = weave_uv * 6.283185;
	float weave_detail = 1.0 - smoothstep(0.22, 0.75, length(fwidth(weave_uv)));
	float weave = sin(thread_angle.x) * sin(thread_angle.y) * weave_detail;
	float fold_angle = (around * 5.0 + along * 0.62 + 0.11 * sin(along * 13.0)) * 6.283185;
	float folds = sin(fold_angle) * 0.7 + sin(fold_angle * 2.0 + along * 18.0) * 0.3;
	col *= 1.0 + folds * 0.075 + weave * 0.075;
	rough += folds * 0.05;

	// Cuff / hem darkening at the ends of each part.
	float hem = smoothstep(0.04, 0.0, along) + smoothstep(0.96, 1.0, along);
	col *= 1.0 - 0.3 * hem;

	ALBEDO = col;
	ROUGHNESS = rough;
	EMISSION = emission;
	vec2 weave_slope = vec2(cos(thread_angle.x) * sin(thread_angle.y), sin(thread_angle.x) * cos(thread_angle.y));
	vec2 fabric_slope = weave_slope * weave_detail * 0.19 + vec2(cos(fold_angle), cos(fold_angle + along * 4.0) * 0.4) * 0.10;
	NORMAL_MAP = normalize(vec3(fabric_slope, 1.0)) * 0.5 + 0.5;
}
