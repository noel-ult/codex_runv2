shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Cast-in-place concrete: formwork panel seams, tie-holes, water stains and moss at the base.

#include "res://shaders/common.gdshaderinc"

instance uniform vec4 tint : source_color = vec4(0.5, 0.5, 0.49, 1.0);
global uniform float wetness;

varying vec3 v_wpos;
varying vec3 v_wnrm;

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(v_wnrm);
	bool horizontal = abs(n.y) > 0.5;
	vec2 p = horizontal ? v_wpos.xz : facade_uv(v_wpos, n);
	vec2 panel = vec2(2.4, 1.2);
	vec2 q = p / panel;
	vec2 f = fract(q);
	float footprint = max(length(dFdx(p)), length(dFdy(p)));
	vec2 edge = min(f, 1.0 - f) * panel;
	vec2 panel_face = smoothstep(vec2(0.004), vec2(0.024 + min(footprint, 0.02) * 0.25), edge);
	float seam = (1.0 - panel_face.x * panel_face.y) * (1.0 - smoothstep(0.03, 0.11, footprint));
	vec2 tie = vec2(fract(q.x * 2.0) - 0.5, f.y - 0.52) * vec2(panel.x * 0.5, panel.y);
	float tie_distance = length(tie);
	float tie_weight = horizontal ? 0.0 : 1.0 - smoothstep(0.026, 0.08, footprint);
	float hole = (1.0 - smoothstep(0.014, 0.031, tie_distance)) * tie_weight;
	float tie_rim = (1.0 - smoothstep(0.029, 0.048, tie_distance)) * tie_weight - hole;

	float stain = fbm3(p * vec2(0.5, 0.24));
	float streak = smoothstep(0.53, 0.87, vnoise(p * vec2(3.6, 0.22)));
	float aggregate = vnoise(p * 8.0);
	float grain_weight = 1.0 - smoothstep(0.012, 0.049, footprint);
	vec2 grain_pos = p * 32.0;
	float grain = 0.5;
	vec2 grain_slope = vec2(0.0);
	if (grain_weight > 0.0) {
		grain = vnoise(grain_pos);
		grain_slope = vec2(vnoise(grain_pos + vec2(0.2, 0.0)) - grain,
				vnoise(grain_pos + vec2(0.0, 0.2)) - grain);
	}
	float base_damp = horizontal ? 0.0 : (1.0 - smoothstep(0.0, 1.25, v_wpos.y + stain * 0.9));
	float damp = max(base_damp * 0.55, wetness * smoothstep(0.42, 0.80, stain) * 0.58);
	float pour_tone = mix(hash12(floor(q)), 0.5, smoothstep(0.18, 0.5, footprint));
	vec3 col = tint.rgb * (0.84 + 0.29 * pour_tone) * (0.80 + 0.38 * stain);
	col *= 0.83 + 0.34 * aggregate + (grain - 0.5) * grain_weight * 0.26;
	col *= 1.0 - (0.21 + wetness * 0.1) * streak;
	col *= (1.0 - 0.52 * seam) * (1.0 - 0.35 * damp);
	col = mix(col * (1.0 + 0.16 * tie_rim), col * 0.19, hole);
	col = mix(col, col * vec3(0.73, 0.84, 0.67), base_damp * 0.52);

	// Formwork joints and sand grains catch grazing light on the actual wall normal.
	vec2 t = clamp((edge - 0.004) / 0.024, vec2(0.0), vec2(1.0));
	vec2 slope = 1.4 * t * (1.0 - t) * panel_face.yx * sign(0.5 - f);
	slope *= 1.0 - smoothstep(0.013, 0.047, footprint);
	slope += grain_slope * (0.35 * grain_weight);
	vec3 axis_u = horizontal ? vec3(1.0, 0.0, 0.0) : facade_tangent(n);
	vec3 axis_v = horizontal ? vec3(0.0, 0.0, 1.0) : vec3(0.0, 1.0, 0.0);
	NORMAL = normalize((VIEW_MATRIX * vec4(n - slope.x * axis_u - slope.y * axis_v, 0.0)).xyz);
	ALBEDO = col;
	ROUGHNESS = clamp(0.83 + 0.14 * aggregate - 0.33 * damp, 0.0, 1.0);
}
