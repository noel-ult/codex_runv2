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

// Rounded masonry edges in world metres. Screen coverage softens the color seam;
// the sharper physical edge contributes to the normal only while it can resolve.
float masonry(vec2 p, bool brick, float footprint, out vec2 cell, out vec2 slope) {
	vec2 tile = brick ? vec2(0.25, 0.08) : vec2(1.8, 1.7);
	vec2 q = p / tile;
	q.x += brick ? mod(floor(q.y), 2.0) * 0.5 : 0.0;
	cell = floor(q);
	vec2 f = fract(q);
	vec2 edge = min(f, 1.0 - f) * tile;
	float width = brick ? 0.011 : 0.032;
	vec2 t = clamp(edge / width, vec2(0.0), vec2(1.0));
	vec2 rounded = t * t * (3.0 - 2.0 * t);
	slope = 6.0 * t * (1.0 - t) * rounded.yx * sign(0.5 - f) / width;
	slope *= (brick ? 0.008 : 0.012) * (1.0 - smoothstep(width * 0.55, width * 2.0, footprint));
	vec2 face = smoothstep(vec2(0.0), vec2(width + min(footprint, width) * 0.3), edge);
	float lod = smoothstep(tile.y * 0.20, tile.y * 0.75, footprint);
	return mix(face.x * face.y, brick ? 0.82 : 0.97, lod);
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

		// Large stains survive far down the street. Fine surface grain fades before
		// it can shimmer, while the lower frequency mottling stays visible.
		float footprint = max(length(dFdx(uv)), length(dFdy(uv)));
		float grain_weight = 1.0 - smoothstep(0.01, 0.045, footprint);
		float stains = fbm3(uv * vec2(0.6, 0.25) + seed * 5.0);
		float streak = vnoise(vec2(uv.x * 2.2, uv.y * 0.12 + seed));
		if (style < 1.5) {
			bool brick = style < 0.5;
			vec2 cell;
			float face = masonry(uv, brick, footprint, cell, grad);
			float tone = hash12(cell + seed * 13.0);
			float grains = (vnoise(uv * 32.0 + seed) - 0.5) * grain_weight;
			float mottling = vnoise(uv * 6.0 + seed);
			if (brick) {
				float variation = mix(tone, 0.5, smoothstep(0.02, 0.065, footprint));
				vec3 clay = wall_color.rgb * mix(vec3(0.74, 0.71, 0.7), vec3(1.18, 1.26, 1.29), variation);
				clay *= (0.84 + 0.32 * mottling + 0.25 * grains) * (0.82 + 0.36 * stains);
				vec3 mortar = vec3(0.29, 0.26, 0.22) * (0.78 + 0.38 * mottling);
				albedo = mix(mortar, clay, face);
				rough = mix(0.96, 0.73 + 0.16 * mottling, face);
			} else {
				albedo = wall_color.rgb * (0.81 + 0.36 * tone) * (0.82 + 0.36 * stains);
				albedo *= 0.89 + 0.23 * mottling + 0.20 * grains;
				albedo *= 1.0 - 0.28 * smoothstep(0.55, 0.9, streak);
				albedo = mix(albedo * 0.44, albedo, face);
				rough = 0.78 + 0.17 * mottling;
			}
		} else {
			albedo = wall_color.rgb * (0.2 + 0.12 * stains);
			rough = 0.28;
			metal = 0.38;
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
				float depth = (1.0 - smoothstep(0.4, 3.2, h)) * (0.55 + 0.45 * vnoise(vec2(uv.x * 3.0, h * 2.0) + ci));
				// Shelving / display silhouettes inside the shop.
				float shelves = step(0.5, fract(h * 1.6)) * step(0.35, vnoise(vec2(uv.x * 5.0, ci)));
				float displays = 1.0 - 0.75 * shelves * step(h, 2.2);
				float reflected_sky = smoothstep(0.5, 2.8, h + (shop - 0.5) * 0.65);
				vec3 shop_glass = mix(vec3(0.023, 0.03, 0.033), vec3(0.07, 0.11, 0.135), reflected_sky);
				albedo = mix(shop_glass, vec3(0.08), mull);
				rough = mix(0.12 + 0.08 * streak, 0.5, mull);
				metal = 0.27;
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
					float ceiling = 1.0 - 0.6 * smoothstep(0.55, 1.0, lv);
					float slat = lv * 16.0;
					float slat_visibility = 1.0 - smoothstep(0.18, 0.6, footprint * 16.0 / (floor_height * (v1 - v0)));
					float blinds = hash13(id + 2.7) < 0.35 ? 0.78 + (step(0.5, fract(slat)) - 0.5) * 0.45 * slat_visibility : 1.0;
					float half_shade = hash13(id + 6.6) < 0.25 ? step(lv, 0.55) : 1.0;
					float room = 0.75 + 0.25 * vnoise(vec2(lu * 4.0, lv * 3.0) + id.xy * 7.0);
					// Each pane bends the sky colors differently. The softly darker bottom
					// and reveal give unlit windows a sense of depth, even on overcast days.
					float glass_tone = hash13(id + 12.7);
					float horizon = smoothstep(0.12, 0.88, lv + (glass_tone - 0.5) * 0.4);
					float edge = min(min(lu, 1.0 - lu), min(lv, 1.0 - lv));
					float reveal = mix(0.65, 1.0, smoothstep(0.025, 0.15, edge));
					vec3 glass = mix(vec3(0.027, 0.038, 0.052), vec3(0.11, 0.16, 0.21), horizon);
					float glazing = style > 1.5 ? 1.0 : 0.72;
					albedo = glass * (0.78 + 0.52 * glass_tone) * reveal * glazing;
					rough = mix(0.11, 0.30, glass_tone) + 0.08 * streak;
					metal = 0.20 + 0.18 * glazing;
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
