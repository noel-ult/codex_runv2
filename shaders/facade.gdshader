shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Procedural building facade: brick / concrete panel / glass curtain wall, with
// framed windows, sills, randomly lit interiors (blinds, warm/cool light), ground floor
// storefronts with illuminated signage, grime and rain streaks. Roof faces get tar/gravel.

#include "res://shaders/common.gdshaderinc"

instance uniform vec4 wall_color : source_color = vec4(0.48, 0.27, 0.2, 1.0);
instance uniform float facade_style = 0.0; // 0 brick, 1 concrete panels, 2 glass curtain wall
instance uniform float seed = 0.0;
instance uniform float lit_ratio = 0.5;
instance uniform float base_y = 0.0;
instance uniform float top_y = 12.0;
instance uniform float storefront = 1.0;

uniform float floor_height = 3.4;
uniform float ground_floor_height = 4.2;
uniform float window_spacing = 2.7;
uniform float window_energy = 1.3;
// 1 = night, 0 = full daylight (driven by TimeOfDay).
global uniform float night_factor;

varying vec3 v_wpos;
varying vec3 v_wnrm;

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// Height field of the wall surface (1 = face, 0 = recessed). Used for bump + mortar.
float wall_height(vec2 p, float style, out vec2 cell) {
	if (style < 0.5) {
		vec2 q = p / vec2(0.25, 0.08);
		float row = floor(q.y);
		q.x += mod(row, 2.0) * 0.5;
		cell = floor(q);
		vec2 f = fract(q);
		float mx = smoothstep(0.0, 0.05, f.x) * smoothstep(0.0, 0.05, 1.0 - f.x);
		float my = smoothstep(0.0, 0.14, f.y) * smoothstep(0.0, 0.14, 1.0 - f.y);
		return mx * my;
	}
	vec2 q = p / vec2(1.8, 1.7);
	cell = floor(q);
	vec2 f = fract(q);
	float sx = smoothstep(0.0, 0.012, f.x) * smoothstep(0.0, 0.012, 1.0 - f.x);
	float sy = smoothstep(0.0, 0.012, f.y) * smoothstep(0.0, 0.012, 1.0 - f.y);
	return sx * sy;
}

void fragment() {
	vec3 n = normalize(v_wnrm);
	float style = facade_style;

	// --- Roof -----------------------------------------------------------------
	if (n.y > 0.5) {
		vec2 p = v_wpos.xz;
		float g = fbm3(p * 2.5 + seed);
		float gravel = vnoise(p * 28.0);
		float puddle = smoothstep(0.62, 0.68, fbm3(p * 0.35 + seed * 3.0));
		vec3 c = vec3(0.13, 0.13, 0.14) * (0.75 + 0.45 * g) * (0.85 + 0.3 * gravel);
		ALBEDO = mix(c, c * 0.55, puddle);
		ROUGHNESS = mix(0.92, 0.08, puddle);
		SPECULAR = 0.4;
	} else if (n.y < -0.5) {
		ALBEDO = wall_color.rgb * 0.35;
		ROUGHNESS = 0.9;
	} else {
		// --- Vertical facade -----------------------------------------------------
		vec2 uv = facade_uv(v_wpos, n);
		vec3 tangent = facade_tangent(n);
		float fid = face_id(n);
		float h = v_wpos.y - base_y;
		float top_band = top_y - base_y - 0.9;

		vec3 albedo;
		float rough;
		float metal = 0.0;
		vec3 emission = vec3(0.0);
		vec2 grad = vec2(0.0);

		// Base wall material.
		vec2 cell;
		float e = 0.004;
		float hw = wall_height(uv, style, cell);
		vec2 tmp;
		grad.x = (wall_height(uv + vec2(e, 0.0), style, tmp) - hw) / e;
		grad.y = (wall_height(uv + vec2(0.0, e), style, tmp) - hw) / e;
		float lod = smoothstep(0.012, 0.05, length(fwidth(uv)));
		hw = mix(hw, 0.82, lod);
		grad *= 1.0 - lod;
		float stains = fbm3(uv * vec2(0.6, 0.25) + seed * 5.0);
		float streak = vnoise(vec2(uv.x * 2.2, uv.y * 0.12 + seed));
		if (style < 0.5) {
			float tone = hash12(cell + seed * 13.0);
			vec3 brick = wall_color.rgb * mix((0.72 + 0.5 * tone) * (0.9 + 0.2 * vnoise(uv * 40.0)), 0.97, lod);
			vec3 mortar = vec3(0.42, 0.4, 0.37);
			albedo = mix(mortar, brick, hw);
			rough = mix(0.95, 0.82, hw);
			grad *= 0.012;
		} else if (style < 1.5) {
			float tone = hash12(cell + seed * 7.0);
			albedo = wall_color.rgb * (0.88 + 0.18 * tone) * (0.85 + 0.3 * stains);
			albedo *= 1.0 - 0.25 * smoothstep(0.55, 0.9, streak);
			albedo = mix(albedo * 0.45, albedo, hw);
			rough = 0.88;
			grad *= 0.004;
		} else {
			albedo = vec3(0.05, 0.06, 0.07);
			rough = 0.1;
			metal = 0.5;
			grad = vec2(0.0);
		}

		// Ground grime.
		albedo *= 0.55 + 0.45 * smoothstep(0.0, 1.6, h + stains * 0.6);

		bool in_storefront = storefront > 0.5 && h < ground_floor_height;
		bool window_zone = h > ground_floor_height && h < top_band;
		if (storefront < 0.5) {
			window_zone = h > 0.6 && h < top_band;
		}

		if (in_storefront) {
			float cu = uv.x / 3.4;
			float ci = floor(cu);
			float fu = fract(cu);
			float shop = hash12(vec2(ci, fid + seed * 3.0));
			bool pillar = fu < 0.1 || fu > 0.9;
			if (!pillar && h > 0.3 && h < 3.0) {
				// Shop window: interior glow, mullion, reflection.
				float mull = step(abs(fu - 0.5), 0.008);
				float lit = step(shop, 0.78);
				vec3 interior = mix(vec3(1.0, 0.74, 0.48), vec3(0.7, 0.85, 1.0), step(0.65, hash12(vec2(ci, 9.0 + seed))));
				float depth = smoothstep(3.2, 0.4, h) * (0.55 + 0.45 * vnoise(vec2(uv.x * 3.0, h * 2.0) + ci));
				// Shelving / display silhouettes inside the shop.
				float shelves = step(0.5, fract(h * 1.6)) * step(0.35, vnoise(vec2(uv.x * 5.0, ci)));
				float displays = 1.0 - 0.75 * shelves * step(h, 2.2);
				albedo = mix(vec3(0.02, 0.025, 0.03), vec3(0.08), mull);
				rough = mix(0.04, 0.5, mull);
				metal = 0.3;
				emission = interior * depth * displays * lit * 0.42 * (1.0 - mull) * mix(0.45, 1.0, night_factor);
				grad = vec2(0.0);
			} else if (!pillar && h >= 3.1 && h < 3.85) {
				// Sign band: backlit lightbox with pixel-font lettering on some shops.
				float lit_sign = step(0.4, shop);
				vec3 sign_col = 0.55 + 0.45 * cos(6.2831 * (shop * 3.0 + vec3(0.0, 0.33, 0.67)));
				float sx = (fu - 0.1) / 0.8;
				float sy = (h - 3.1) / 0.75;
				float border = step(0.03, sx) * step(sx, 0.97) * step(0.08, sy) * step(sy, 0.92);
				float glyph_w = 0.3 / 3.4 / 0.8;
				float gx = (sx - 0.15) / glyph_w;
				float glyph = floor(gx);
				float in_text = step(0.0, gx) * step(gx, 7.0) * step(0.28, sy) * step(sy, 0.72);
				vec2 bit = floor(vec2(fract(gx) * 4.0, (sy - 0.28) / 0.44 * 5.0));
				float on = step(0.45, hash12(bit + vec2(glyph * 7.0, ci * 13.0 + seed))) * step(bit.x, 2.0);
				vec3 box = mix(vec3(0.9), sign_col, 0.75) * (0.8 + 0.2 * sy);
				albedo = vec3(0.06, 0.06, 0.065);
				rough = 0.4;
				emission = mix(box * 0.8, sign_col * 0.1, on * in_text) * border * lit_sign * mix(0.3, 1.0, night_factor);
				grad = vec2(0.0);
			} else if (!pillar && h <= 0.3) {
				albedo = vec3(0.06);
				rough = 0.6;
			}
		} else if (window_zone) {
			float cu = uv.x / window_spacing;
			float ci = floor(cu);
			float fu = fract(cu);
			float fl = (h - (storefront > 0.5 ? ground_floor_height : 0.0)) / floor_height;
			float fi = floor(fl);
			float fv = fract(fl);
			vec3 id = vec3(ci, fi, fid + seed * 11.0);
			float w0 = style > 1.5 ? 0.04 : 0.24;
			float w1 = style > 1.5 ? 0.96 : 0.76;
			float v0 = style > 1.5 ? 0.06 : 0.3;
			float v1 = style > 1.5 ? 0.96 : 0.86;
			bool in_win = fu > w0 && fu < w1 && fv > v0 && fv < v1;
			// Floor ledge band.
			if (style < 1.5 && fv < 0.05) {
				albedo = mix(albedo, vec3(0.5, 0.48, 0.45), 0.65);
				rough = 0.9;
				grad = vec2(0.0);
			}
			if (in_win) {
				float fw = 0.035 / (w1 - w0);
				float lu = (fu - w0) / (w1 - w0);
				float lv = (fv - v0) / (v1 - v0);
				bool frame = lu < fw || lu > 1.0 - fw || lv < fw * 1.4 || lv > 1.0 - fw * 1.4 || abs(lu - 0.5) < fw * 0.5;
				if (frame) {
					albedo = style > 1.5 ? vec3(0.2, 0.21, 0.23) : vec3(0.07, 0.07, 0.075);
					rough = 0.45;
					metal = 0.6;
					grad = vec2(0.0);
				} else {
					float r = hash13(id);
					float lit = step(r, lit_ratio * mix(0.18, 1.0, night_factor));
					vec3 warm = vec3(1.0, 0.76, 0.48);
					vec3 cool = vec3(0.62, 0.8, 1.0);
					vec3 tint = mix(warm, cool, step(0.72, hash13(id + 4.1)));
					float bright = 0.55 + 0.9 * hash13(id + 8.3);
					float ceiling = smoothstep(1.0, 0.55, lv) * 0.6 + 0.4;
					float blinds = hash13(id + 2.7) < 0.35 ? (0.55 + 0.45 * step(0.5, fract(lv * 16.0))) : 1.0;
					float half_shade = hash13(id + 6.6) < 0.25 ? step(lv, 0.55) : 1.0;
					float room = 0.75 + 0.25 * vnoise(vec2(lu * 4.0, lv * 3.0) + id.xy * 7.0);
					albedo = vec3(0.025, 0.03, 0.036);
					rough = 0.05;
					metal = 0.4;
					emission = tint * bright * ceiling * blinds * half_shade * room * lit * window_energy * mix(0.35, 1.0, night_factor);
					grad = vec2(0.0);
				}
			} else if (style < 1.5 && fu > w0 - 0.02 && fu < w1 + 0.02 && fv > v0 - 0.07 && fv <= v0) {
				// Window sill.
				albedo = vec3(0.6, 0.58, 0.55) * (0.8 + 0.2 * stains);
				rough = 0.8;
				grad = vec2(0.0);
			} else if (style < 1.5 && fu > w0 && fu < w1 && fv < v0) {
				// Rain streaks below windows.
				albedo *= 1.0 - 0.3 * smoothstep(0.4, 0.9, vnoise(vec2(uv.x * 9.0, h * 0.8))) * (1.0 - fv / v0);
			}
		} else if (h >= top_band) {
			// Cornice / parapet band.
			albedo = mix(albedo, vec3(0.5, 0.49, 0.47), 0.6) * (0.85 + 0.2 * stains);
			rough = 0.85;
		}

		ALBEDO = albedo;
		ROUGHNESS = rough;
		METALLIC = metal;
		EMISSION = emission;
		NORMAL = bumped_view_normal(n, tangent, grad, 1.0, VIEW_MATRIX);
	}
}
