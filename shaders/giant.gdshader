shader_type canvas_item;

#include "res://shaders/night.gdshaderinc"
// One giant virus (巨毒囊), drawn from distance fields: a six-sided capsid seen
// through a coat of fine fibres, the genome packed in the middle, and the
// star-shaped gate on one corner, where it opens inside a cell.
// INSTANCE_CUSTOM (arrives clamped to 0..1): x = its turn / TAU, y = how far
// the gate is open * 0.49, plus 0.5 with virophages caught in its fibres,
// z = 0..1 how far grown in, w = opacity / 2.

uniform float px = 0.1; // one screen pixel in world units
uniform vec3 ink = vec3(0.3, 0.2, 0.5);
uniform vec3 shell = vec3(0.72, 0.64, 0.88);
uniform vec3 hair = vec3(0.56, 0.47, 0.78);
uniform vec3 core = vec3(0.86, 0.17, 0.34);
uniform vec3 rider = vec3(0.08, 0.64, 0.6);

varying vec4 v_c;
varying vec2 v_q;
varying float v_side;

void vertex() {
	v_c = INSTANCE_CUSTOM;
	v_q = VERTEX;
	v_side = max(length(MODEL_MATRIX[0].xy), 1e-3);
}

float hexagon(vec2 p, float r) {
	p = abs(p);
	return max(p.x * 0.866025 + p.y * 0.5, p.y) - r;
}

float fill(float d, float k) {
	return clamp(0.5 - d / k, 0.0, 1.0);
}

vec4 over(vec4 o, vec3 c, float a) {
	float oa = a + o.a * (1.0 - a);
	return vec4((c * a + o.rgb * o.a * (1.0 - a)) / max(oa, 1e-4), oa);
}

float seg(vec2 p, vec2 a, vec2 b) {
	vec2 ab = b - a;
	return length(p - a - ab * clamp(dot(p - a, ab) / dot(ab, ab), 0.0, 1.0));
}

void fragment() {
	float k = px / v_side;
	float seed = fract(v_c.x * 7.13);
	float gate = mod(v_c.y, 0.5) * 2.04;
	float rode = step(0.5, v_c.y);
	float alpha = v_c.w * 2.0;
	float big = mix(0.55, 1.0, v_c.z);
	// It tumbles slowly in the water.
	float ang = v_c.x * 6.2832 + 0.7 * sin(TIME * (0.11 + 0.1 * seed) + seed * 40.0) + 0.3 * sin(TIME * (0.27 + 0.13 * seed) + seed * 17.0);
	vec2 n = vec2(cos(ang), sin(ang));
	vec2 p = vec2(dot(v_q, vec2(-n.y, n.x)), dot(v_q, n)) / big;
	k /= big;
	float w = max(k, 0.005);
	const float R = 0.27;
	float r = length(p);
	float a = atan(p.y, p.x);
	float hd = hexagon(p, R * 0.866025);
	vec4 o = vec4(0.0);

	// The fibre coat: thousands of hairs, a soft fringe from afar. Clumps
	// stir as it drifts.
	float tuft = 0.5 + 0.5 * sin(a * 11.0 + seed * 30.0 + 0.5 * sin(TIME * 0.4 + a * 3.0));
	float reach = 0.05 + 0.024 * tuft;
	float fringe = smoothstep(reach, reach * 0.35, hd) * step(-0.01, hd);
	float strand = 0.5 + 0.5 * sin(a * 96.0 + 3.0 * sin(a * 7.0 + seed * 20.0 + TIME * 0.25));
	float fine = smoothstep(0.02, 0.008, k);
	o = over(o, hair, fringe * mix(0.34, 0.2 + 0.5 * strand, fine));

	// Capsid: pale glass, each of its six faces catching the light differently.
	float face = 0.5 + 0.5 * cos(floor(a / 1.0472 + 0.5) * 1.0472 - 1.0);
	float body = fill(hd, k);
	// (From afar a thin glass would vanish among the algae: it fills in.)
	float far = smoothstep(0.012, 0.04, k);
	o = over(o, mix(shell * 0.84, min(shell * 1.2, vec3(1.0)), face), body * mix(0.2, 0.62, far));
	// A little brighter toward the rim, as glass is.
	o = over(o, min(shell * 1.3, vec3(1.0)), exp(hd * 26.0) * body * 0.3);
	// The genome, packed in the middle, turning faintly through the shell.
	float cd = r - 0.13 - 0.012 * sin(a * 5.0 + seed * 20.0 + TIME * 0.2);
	float coil = 0.5 + 0.5 * sin(p.x * 80.0 + sin(p.y * 60.0 + TIME * 0.2) * 2.6);
	float coil2 = 0.5 + 0.5 * sin(p.y * 96.0 - sin(p.x * 44.0) * 2.0);
	o = over(o, mix(core * 0.82, mix(core, vec3(1.0), 0.4), coil * coil2 * fine), smoothstep(0.02, -0.03, cd) * (0.22 + 0.2 * coil * fine) * (1.0 - gate));
	o = over(o, ink, fill(abs(cd + 0.012) - w * 0.25, k) * 0.2 * (1.0 - gate));
	// Ridges of the shell.
	float ridge = 1e3;
	for (int j = 0; j < 3; j++) {
		float f = float(j) * 1.0472 + 0.5236;
		vec2 v = vec2(cos(f), sin(f)) * R;
		ridge = min(ridge, seg(p, -v, v));
	}
	o = over(o, mix(shell * 1.5, vec3(1.0), 0.3), fill(ridge - w * 0.3, k) * body * 0.4);
	o = over(o, ink, fill(abs(hd) - w * 0.5, k) * 0.85);
	// The stargate: a five-pointed seam on one corner, opening like a flower.
	vec2 g = p - vec2(0.0, R * 0.62);
	float ga = atan(g.y, g.x);
	float star = (0.045 + 0.05 * gate) * (0.72 + 0.4 * cos(5.0 * ga));
	float sd = length(g) - star;
	o = over(o, ink, fill(abs(sd) - w * 0.4, k) * mix(0.6, 0.9, gate));
	o = over(o, core, fill(sd, k) * gate * 0.55);

	// Virophages caught in the fibres: little pale-green beads.
	if (rode > 0.5) {
		for (int j = 0; j < 7; j++) {
			float f = seed * 40.0 + float(j) * 2.399963;
			vec2 at = vec2(cos(f), sin(f)) * (R * 0.98 + 0.02 * sin(TIME * 0.7 + f));
			float bd = length(p - at) - 0.017;
			o = over(o, rider, fill(bd, k) * 0.9);
			o = over(o, ink, fill(abs(bd) - w * 0.3, k) * 0.4);
		}
	}
	if (night > 0.0) {
		// Night (深海荧光): lit from within in its own colour.
		o.rgb = mix(o.rgb, nt_lin(night_glow(nt_srgb(max(o.rgb, vec3(0.0))), nt_srgb(max(vec3(0.62, 0.5, 0.86), vec3(0.0))))), night);
		o.a = mix(o.a, min(1.0, o.a * 1.25), night);
	}
	COLOR = vec4(o.rgb, o.a * alpha);
}
