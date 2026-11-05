shader_type canvas_item;
// The seed vault for the end (scripts/ui/ending.gd): a glass capsule between
// two metal caps, filling with a green, lit medium as the lives go in (bubbles
// rising), a ring of light running round it when it seals. Drawn on a rect,
// UV across it; `aspect` = height / width.

uniform float fill = 0.0;
uniform float seal = 0.0;
uniform float aspect = 2.6;
uniform float t = 0.0;
uniform float px = 0.004;

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float sd_round_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

vec4 over(vec4 o, vec3 c, float a) {
	float oa = a + o.a * (1.0 - a);
	return vec4((c * a + o.rgb * o.a * (1.0 - a)) / max(oa, 1e-4), oa);
}

void fragment() {
	vec2 p = (UV - 0.5) * vec2(1.0, aspect) * 2.0; // x in -1..1
	float half_h = aspect;
	float cap = 0.32;
	vec4 o = vec4(0.0);
	// The glass tube.
	float d = sd_round_box(p, vec2(0.82, half_h - cap), 0.82);
	float inside = clamp(-d / px + 0.5, 0.0, 1.0);
	float x = p.x / 0.82;
	// Glass: faintly tinted, thick at the sides (seen edge-on).
	float side = pow(abs(x), 6.0);
	o = over(o, vec3(0.7, 0.9, 0.95), inside * (0.06 + 0.35 * side));
	// The medium, up to `fill`, lit from within, its surface a bright line.
	// (p.y grows downward: the surface rises from the bottom as it fills.)
	float top = mix(half_h - cap + 0.85, -(half_h - cap) - 0.6, fill);
	top += 0.02 * sin(p.x * 8.0 + t * 2.0);
	float wet = step(top, p.y) * inside;
	vec3 med = mix(vec3(0.2, 0.55, 0.38), vec3(0.55, 0.95, 0.7), 0.5 + 0.5 * (1.0 - abs(x)));
	o = over(o, med, wet * 0.34);
	// Caustics: light wavering through the medium.
	float caus = sin(p.x * 14.0 + sin(p.y * 6.0 + t * 1.3) * 2.0) * sin(p.y * 11.0 - t * 0.9 + p.x * 3.0);
	o = over(o, vec3(0.75, 1.0, 0.85), wet * smoothstep(0.55, 1.0, caus) * 0.18);
	o = over(o, vec3(0.8, 1.0, 0.9), clamp(1.0 - abs(p.y - top) / (px * 2.0), 0.0, 1.0) * inside * step(0.01, fill) * 0.8);
	// Bubbles rising in it.
	for (int k = 0; k < 9; k++) {
		float fk = float(k);
		vec2 c = vec2((hash(vec2(fk, 1.0)) - 0.5) * 1.2, half_h - mod(t * (0.4 + hash(vec2(fk, 2.0)) * 0.5) + hash(vec2(fk, 3.0)) * 6.0, half_h * 2.0));
		float rb = 0.025 + 0.03 * hash(vec2(fk, 4.0));
		float db = abs(length(p - c) - rb);
		o = over(o, vec3(0.9, 1.0, 0.95), clamp(1.0 - db / (px * 1.5), 0.0, 1.0) * 0.6 * step(top, c.y) * wet);
	}
	// Highlights: a long bright stripe on the left, a fainter one on the right.
	o = over(o, vec3(1.0), smoothstep(0.08, 0.0, abs(x + 0.55)) * inside * 0.55);
	o = over(o, vec3(1.0), smoothstep(0.05, 0.0, abs(x - 0.62)) * inside * 0.25);
	o = over(o, vec3(0.85, 0.97, 1.0), clamp(1.0 - abs(d) / (px * 1.6), 0.0, 1.0) * 0.85);
	// The caps: brushed metal bands top and bottom.
	for (int s = 0; s < 2; s++) {
		float sy = s == 0 ? -1.0 : 1.0;
		vec2 q = p - vec2(0.0, sy * (half_h - cap * 0.5));
		float dc = sd_round_box(q, vec2(0.92, cap * 0.5), 0.08);
		float m = clamp(-dc / px + 0.5, 0.0, 1.0);
		float sheen = 0.55 + 0.35 * (1.0 - abs(q.x + 0.3)) + 0.06 * sin(q.x * 60.0);
		// Frosted glass-steel: dark, with a cold edge catching the light.
		vec3 metal = vec3(0.2, 0.26, 0.29) * sheen;
		metal = mix(metal, vec3(0.1, 0.13, 0.15), smoothstep(0.0, 1.0, abs(q.y) / (cap * 0.5)) * 0.5);
		o = over(o, metal, m * 0.92);
		o = over(o, vec3(0.6, 0.92, 0.95), clamp(1.0 - abs(dc) / (px * 1.4), 0.0, 1.0) * 0.6);
		// A status light on the lower cap, green once it is sealed.
		if (s == 1) {
			float dl = length(q - vec2(0.55, 0.0)) - 0.045;
			o = over(o, mix(vec3(0.9, 0.6, 0.2), vec3(0.4, 1.0, 0.6), step(0.99, seal)), clamp(-dl / px + 0.5, 0.0, 1.0));
		}
	}
	// Sealed: a ring of light running down it.
	if (seal > 0.0 && seal < 1.0) {
		float ry = mix(half_h, -half_h, seal);
		o = over(o, vec3(0.7, 1.0, 0.9), exp(-abs(p.y - ry) * 18.0) * clamp(-d / px + 0.5, 0.0, 1.0) * 0.8);
	}
	COLOR = o;
}
