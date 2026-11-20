shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Worn thermoplastic road paint: cut-out wear holes, slightly glossy when wet.

#include "res://shaders/common.gdshaderinc"

instance uniform vec4 paint : source_color = vec4(0.85, 0.85, 0.8, 1.0);

varying vec3 v_wpos;

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = v_wpos.xz;
	float wear = fbm3(p * 4.0) * 0.7 + vnoise(p * 30.0) * 0.3;
	ALBEDO = paint.rgb * (0.75 + 0.25 * vnoise(p * 12.0));
	ROUGHNESS = 0.45;
	ALPHA = smoothstep(0.25, 0.35, wear);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
