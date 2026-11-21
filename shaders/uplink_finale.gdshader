shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled, fog_disabled;

uniform float reach = 0.0;
uniform float beam_length = 1.0;
instance uniform float strength = 1.0;
varying float altitude;

void vertex() {
	altitude = clamp(VERTEX.y / beam_length + 0.5, 0.0, 1.0);
}

void fragment() {
	float edge = reach - altitude;
	float column = smoothstep(0.0, 0.014, edge);
	float head = exp(-abs(edge - 0.01) * 85.0) * (1.0 - smoothstep(0.95, 1.0, reach));
	float profile = pow(max(dot(normalize(NORMAL), VIEW), 0.0), 1.7);
	float haze = 1.0 - smoothstep(0.37, 1.0, altitude);
	float pulse = 0.85 + 0.15 * sin(altitude * 50.0 - TIME * 4.0);
	ALBEDO = mix(vec3(0.28, 1.8, 0.84), vec3(1.2, 2.3, 1.7), head);
	ALPHA = profile * haze * strength * (column * pulse + head * 0.65);
}
