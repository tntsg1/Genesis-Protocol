shader_type canvas_item;
// A planet or moon for the end of Europa (scripts/ui/ending.gd), drawn on a
// square: lit from `light` (screen direction toward the sun), turning (`spin`),
// with a thin atmosphere at the limb. kind 0 Jupiter: belts and zones that
// shear into each other, the Great Red Spot; kind 1 Europa: pale ice crossed
// by the reddish-brown lineae; kind 2 planet one (chapter 6, arrival.gd): an
// ocean over the whole world, a few volcanic island arcs, long swirls of
// cloud, and a thin hazy air with no oxygen in it.

uniform int kind = 0;
uniform vec2 light = vec2(-0.7, -0.35);
uniform float spin = 0.0;
uniform float px = 0.004; // one screen pixel in units of the radius
uniform float pad = 1.15; // the square's half side in radii (room for the glow)

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int k = 0; k < 5; k++) {
		s += a * noise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return s;
}

vec3 jupiter(float lon, float lat) {
	// Belts and zones, each edge torn by turbulence.
	float warp = fbm(vec2(lon * 3.0, lat * 14.0)) - 0.5;
	float b = lat * 9.0 + warp * 1.4;
	float band = 0.5 + 0.5 * sin(b * 3.14159);
	vec3 zone = vec3(0.93, 0.88, 0.79);
	vec3 belt = vec3(0.76, 0.6, 0.47);
	vec3 col = mix(belt, zone, smoothstep(0.25, 0.75, band));
	// Darker brown at the strongest belts, bluish festoons at their edges.
	col = mix(col, vec3(0.6, 0.43, 0.32), smoothstep(0.08, 0.0, band) * 0.5);
	col = mix(col, vec3(0.55, 0.62, 0.7), smoothstep(0.03, 0.0, abs(band - 0.3)) * 0.25 * noise(vec2(lon * 20.0, lat * 30.0)));
	// Fine streaks along the latitudes.
	col *= 0.9 + 0.2 * fbm(vec2(lon * 12.0, lat * 60.0));
	// The Great Red Spot, a swirling oval in the southern belt.
	vec2 q = vec2((fract((lon - 0.7) / 6.2832 + 0.5) - 0.5) * 6.2832 * 0.55, (lat + 0.38) * 2.6);
	float spot = length(q);
	float swirl = fbm(q * 9.0 + vec2(spot * 4.0, 0.0));
	col = mix(col, mix(vec3(0.78, 0.42, 0.3), vec3(0.9, 0.62, 0.48), swirl), smoothstep(0.17, 0.12, spot));
	col = mix(col, vec3(0.92, 0.82, 0.7), smoothstep(0.2, 0.17, spot) * smoothstep(0.14, 0.17, spot) * 0.6);
	return col;
}

// Two octaves only: smooth, long curves for the cracks to follow.
float smooth2(vec2 p) {
	return noise(p) * 0.68 + noise(p * 2.1 + 5.0) * 0.32;
}

vec3 europa(float lon, float lat) {
	vec2 uv = vec2(lon * 1.6, lat * 2.2);
	// Bright ice, tan where salts stain the chaos terrain.
	vec3 ice = mix(vec3(0.94, 0.93, 0.9), vec3(0.78, 0.68, 0.56), smoothstep(0.45, 0.8, fbm(uv * 1.2 + 3.0)) * 0.8);
	// The lineae: long cracks across the whole face, a few finer ones.
	float lines = 0.0;
	for (int k = 0; k < 3; k++) {
		float n = smooth2(uv * (1.3 + float(k) * 1.1) + float(k) * 9.0);
		float w = 0.018 - float(k) * 0.004;
		lines = max(lines, smoothstep(w, w * 0.3, abs(n - 0.5)) * (1.0 - 0.25 * float(k)));
	}
	return mix(ice, vec3(0.6, 0.4, 0.3), lines * 0.7);
}

vec3 ocean(float lon, float lat) {
	vec2 uv = vec2(lon * 1.4, lat * 2.0);
	float depth = fbm(uv * 1.6 + 7.0);
	vec3 sea = mix(vec3(0.1, 0.36, 0.5), vec3(0.2, 0.56, 0.62), smoothstep(0.35, 0.7, depth));
	// Island arcs: chains of small dark specks with a pale shallow ring.
	float arc = abs(smooth2(uv * 1.1 + 3.0) - 0.5);
	float isle = smoothstep(0.03, 0.0, arc) * smoothstep(0.55, 0.75, noise(uv * 14.0));
	sea = mix(sea, vec3(0.5, 0.78, 0.76), smoothstep(0.06, 0.0, arc) * 0.35);
	sea = mix(sea, vec3(0.32, 0.26, 0.22), isle);
	// Clouds, sheared along the latitudes.
	float c = fbm(vec2(lon * 2.2 + fbm(uv * 2.0) * 1.5, lat * 6.0));
	sea = mix(sea, vec3(0.95, 0.96, 0.94), smoothstep(0.55, 0.78, c) * 0.85);
	return sea;
}

void fragment() {
	vec2 p = (UV * 2.0 - 1.0) * pad;
	float r2 = dot(p, p);
	vec3 l = normalize(vec3(light, 0.55));
	// The atmosphere's glow just past the limb, on the lit side.
	float out_r = max(sqrt(r2) - 1.0, 0.0);
	float lit_side = clamp(dot(normalize(p), normalize(light)) * 0.8 + 0.4, 0.0, 1.0);
	float halo = exp(-out_r * (kind == 0 ? 28.0 : (kind == 2 ? 34.0 : 60.0))) * lit_side * (kind == 0 ? 0.45 : (kind == 2 ? 0.4 : 0.2));
	vec3 halo_col = kind == 0 ? vec3(0.95, 0.85, 0.7) : (kind == 2 ? vec3(0.85, 0.9, 0.82) : vec3(0.8, 0.9, 1.0));
	float z = sqrt(max(1.0 - r2, 0.0));
	vec3 n = vec3(p, z);
	float lat = asin(clamp(p.y, -1.0, 1.0));
	float lon = atan(p.x, z) + spin;
	vec3 col = kind == 0 ? jupiter(lon, lat) : (kind == 2 ? ocean(lon, lat) : europa(lon, lat));
	float d = dot(n, l);
	float shade = smoothstep(-0.03, 0.14, d) * (0.55 + 0.45 * max(d, 0.0));
	// Limb darkening, and a thin haze at the edge.
	shade *= mix(0.55, 1.0, pow(z, 0.35));
	// The game's grade: colours held back toward a cool grey, so the space
	// shots sit with the dark-field dish (true colours, quieter).
	float lum = dot(col, vec3(0.3, 0.55, 0.15));
	col = mix(col, vec3(lum) * vec3(0.9, 0.98, 1.04), kind == 2 ? 0.2 : 0.4) * 0.86;
	// Night side: Europa faintly lit by Jupiter (jupitershine).
	float night = kind == 1 ? 0.07 : 0.015;
	col *= night + (1.0 - night) * shade;
	col += (kind == 0 ? vec3(0.9, 0.82, 0.7) : vec3(0.7, 0.8, 0.95)) * pow(1.0 - z, 4.0) * 0.45 * smoothstep(-0.2, 0.3, d);
	// A thin cold rim of light at the lit limb, the dish's glass edge again.
	col += vec3(0.55, 0.9, 0.95) * smoothstep(0.82, 1.0, 1.0 - z) * smoothstep(0.0, 0.4, d) * 0.35;
	float cover = clamp((1.0 - sqrt(r2)) / px + 0.5, 0.0, 1.0);
	float a = cover + halo * (1.0 - cover);
	COLOR = vec4((col * cover + halo_col * halo * (1.0 - cover)) / max(a, 1e-4), a);
}
