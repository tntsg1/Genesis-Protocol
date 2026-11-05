shader_type canvas_item;
// Europa's ice seen from the surface, for the end (scripts/ui/ending.gd): a
// plain running to the horizon in perspective, crossed by the lineae, a ridge
// or two, low sunlight glinting; Jupiter's light from above. UV.y = 0 is the
// horizon.

uniform float t = 0.0;
uniform float glare_x = 0.3;

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

void fragment() {
	float y = UV.y;
	float depth = 1.0 / (y + 0.04);
	vec2 w = vec2((UV.x - 0.5) * depth * 1.6, depth);
	// Night ice under Jupiter's light: blue-grey, not snow-white.
	vec3 ice = mix(vec3(0.5, 0.58, 0.64), vec3(0.4, 0.44, 0.48), smoothstep(0.3, 0.8, fbm(w * 0.35)));
	// The lineae, long cracks, reddish; doubled ridges along them.
	float n = fbm(w * vec2(0.5, 0.25) + vec2(3.0, 0.0));
	float line = smoothstep(0.025, 0.0, abs(n - 0.5)) + 0.6 * smoothstep(0.012, 0.0, abs(n - 0.53));
	float n2 = fbm(w * vec2(0.18, 0.6) + vec2(11.0, 2.0));
	line = max(line, 0.8 * smoothstep(0.02, 0.0, abs(n2 - 0.48)));
	// (Thinner with distance, so the far plain stays clean.)
	line *= smoothstep(0.0, 0.25, y);
	ice = mix(ice, vec3(0.42, 0.3, 0.26), line * 0.65);
	// Shading from the low sun: frost bright on the near side of every bump.
	float bump = fbm(w * 1.2) - fbm(w * 1.2 + vec2(0.05, 0.0));
	ice *= 0.94 + clamp(bump * 2.0, -0.12, 0.12);
	// A glint along the line to the sun.
	float glint = exp(-abs(UV.x - glare_x) * 6.0) * smoothstep(0.6, 0.0, y) * 0.35;
	ice += vec3(1.0, 0.95, 0.85) * glint * (0.6 + 0.4 * noise(w * 8.0 + t));
	// Haze toward the horizon, the sky's colour.
	vec3 haze = vec3(0.22, 0.3, 0.36);
	ice = mix(ice, haze, exp(-y * 9.0) * 0.7);
	// The bright limb: the far edge of the plain catching the light.
	ice += vec3(0.6, 0.85, 0.9) * exp(-y * 140.0) * 0.5;
	// Darker toward the viewer, a vignette into the lower bar.
	ice *= mix(1.0, 0.62, smoothstep(0.3, 1.0, y));
	COLOR = vec4(ice, 1.0);
}
