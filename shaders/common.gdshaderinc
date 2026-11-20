// Shared procedural noise + helpers for Codex Run materials.

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
			mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm3(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 3; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(17.1, 9.2);
		a *= 0.5;
	}
	return v / 0.875;
}

float fbm5(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(17.1, 9.2);
		a *= 0.5;
	}
	return v / 0.96875;
}

// Facade coordinates for a vertical face: x = horizontal run along the face, y = world height.
vec2 facade_uv(vec3 wpos, vec3 n) {
	if (abs(n.x) > abs(n.z)) {
		return vec2(wpos.z * sign(n.x), wpos.y);
	}
	return vec2(-wpos.x * sign(n.z), wpos.y);
}

vec3 facade_tangent(vec3 n) {
	if (abs(n.x) > abs(n.z)) {
		return vec3(0.0, 0.0, sign(n.x));
	}
	return vec3(-sign(n.z), 0.0, 0.0);
}

float face_id(vec3 n) {
	if (abs(n.x) > abs(n.z)) {
		return n.x > 0.0 ? 1.0 : 2.0;
	}
	return n.z > 0.0 ? 3.0 : 4.0;
}

// Converts a world-space gradient bump into a view-space normal.
vec3 bumped_view_normal(vec3 wn, vec3 tangent, vec2 grad, float strength, mat4 view_matrix) {
	vec3 bitangent = vec3(0.0, 1.0, 0.0);
	vec3 n = normalize(wn - (tangent * grad.x + bitangent * grad.y) * strength);
	return normalize((view_matrix * vec4(n, 0.0)).xyz);
}
