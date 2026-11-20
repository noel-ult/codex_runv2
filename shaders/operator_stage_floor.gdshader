shader_type spatial;
render_mode unshaded;

uniform vec4 floor_color : source_color = vec4(0.039, 0.082, 0.102, 1.0);
uniform vec4 grid_color : source_color = vec4(0.116, 0.243, 0.263, 1.0);
varying vec2 floor_position;

void vertex() {
	floor_position = VERTEX.xz;
}

float line_grid(vec2 point, float spacing) {
	vec2 coordinates = point / spacing;
	vec2 distance_to_line = abs(fract(coordinates + 0.5) - 0.5);
	vec2 pixels = fwidth(coordinates);
	vec2 line_alpha = 1.0 - smoothstep(vec2(0.0), max(pixels, vec2(0.001)) * 1.4, distance_to_line);
	return max(line_alpha.x, line_alpha.y);
}

void fragment() {
	float radius = length(floor_position);
	float fade = 1.0 - smoothstep(0.55, 2.70, radius);
	float grid = max(line_grid(floor_position, 0.25) * 0.43, line_grid(floor_position, 1.0) * 0.8);
	ALBEDO = mix(floor_color.rgb, grid_color.rgb, grid * fade);
}
