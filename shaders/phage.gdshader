shader_type canvas_item;
// One phage (裂囊针), drawn from distance fields so it stays sharp at any zoom:
// a faceted head holding its DNA, a collar, a striped tail sheath over a thin
// tube, a base plate, and six jointed tail fibres. From afar it is a speck.
// INSTANCE_CUSTOM: x = direction the head points (radians), y = how far the
// sheath has contracted 0..1, z = how much of the DNA has left the head 0..1,
// w = opacity / 2, plus 0.5 when it is planted on a cell (legs down, no
// tumbling); instance data arrives clamped to 0..1.

uniform float px = 0.1; // one screen pixel in world units
// Being built inside a cell: custom y = how far the tail is on (fibres last),
// z = 1 - the DNA in the head, x + 20 = a loose tail with no head.
uniform bool inner = false;
// The shape of the virus (level 18): head and tail length, how crystalline
// the shell is, and how far the whole is drawn in so a big one still fits.
uniform float head = 1.0;
uniform float tail = 1.0;
uniform float legs = 1.0;
uniform float crystal = 0.0;
uniform float fit = 1.0;
uniform float bare = 0.0; // a virophage: the head alone, in the middle
// Glassy like the cells: thin coloured outlines over a pale, see-through body.
uniform vec3 ink = vec3(0.33, 0.26, 0.52);
uniform vec3 shell = vec3(0.74, 0.68, 0.88);
uniform vec3 dna = vec3(0.86, 0.17, 0.34);

varying vec4 v_c;
varying vec2 v_q;
varying float v_side;

void vertex() {
	v_c = INSTANCE_CUSTOM;
	v_q = VERTEX;
	v_side = max(length(MODEL_MATRIX[0].xy), 1e-3);
}

float seg(vec2 p, vec2 a, vec2 b) {
	vec2 ab = b - a;
	return length(p - a - ab * clamp(dot(p - a, ab) / dot(ab, ab), 0.0, 1.0));
}

float box(vec2 p, vec2 c, vec2 h) {
	vec2 d = abs(p - c) - h;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// A long hexagon, pointed at both ends (the head seen side on).
float capsid(vec2 p, float hw, float hh) {
	p = abs(p);
	vec2 n = normalize(vec2(hw * 0.62, hw));
	return max(p.x - hw, dot(p - vec2(0.0, hh), n));
}

float fill(float d, float k) {
	return clamp(0.5 - d / k, 0.0, 1.0);
}

vec4 over(vec4 o, vec3 c, float a) {
	float oa = a + o.a * (1.0 - a);
	return vec4((c * a + o.rgb * o.a * (1.0 - a)) / max(oa, 1e-4), oa);
}

void fragment() {
	float k = px / v_side; // one screen pixel, in quad units
	float k0 = k;
	float seed0 = fract(v_c.x * 7.13);
	float planted0 = inner ? 1.0 : step(0.5, v_c.w);
	// Free ones drift in and out of the focal plane: softer and paler.
	float depth = (1.0 - planted0) * (0.5 + 0.5 * sin(TIME * (0.17 + 0.16 * seed0) + seed0 * 60.0));
	k *= 1.0 + 2.2 * depth * depth;
	float planted = inner ? 0.0 : step(0.5, v_c.w);
	float alpha = (v_c.w - 0.5 * planted) * 2.0;
	// Too small to read: a speck in the water, and none of the rest is worked
	// out (thousands of these fill a dish seen from afar).
	float small = inner ? 0.0 : 1.0 - smoothstep(14.0, 26.0, 1.0 / (k * fit));
	vec4 o = vec4(0.0);
	if (small < 1.0) {
	float loose = inner ? step(10.0, v_c.x) : 0.0;
	float tail_on = inner ? v_c.y : 1.0;
	float tail_a = (inner ? smoothstep(0.0, 0.3, tail_on) : 1.0) * (1.0 - bare); // the tail comes up to the head
	float leg_a = (inner ? smoothstep(0.7, 1.0, tail_on) * (1.0 - loose) : 1.0) * (1.0 - bare);
	float head_a = 1.0 - loose;
	float seed = fract(v_c.x * 7.13);
	float s2 = fract(v_c.x * 3.71 + 0.37);
	// Free ones are jostled, not spun: the heading wanders back and forth.
	float ang = v_c.x - 20.0 * loose + (inner ? 0.0 : 1.0 - planted) * (1.0 - 0.7 * crystal) * (1.3 * sin(TIME * (0.19 + 0.2 * seed) + seed * 40.0) + 0.7 * sin(TIME * (0.41 + 0.3 * s2) + s2 * 40.0));
	vec2 n = vec2(cos(ang), sin(ang));
	vec2 p = vec2(dot(v_q, vec2(-n.y, n.x)), dot(v_q, n)) * fit;
	k *= fit;
	float c = inner ? 0.0 : v_c.y;
	float e = v_c.z;
	vec2 hp0 = p;
	p.y += (1.0 - tail_on) * 0.14 * (1.0 - loose); // (the tail parts only: the head uses hp0)

	const float BASE = -0.36;
	float top = BASE + 0.34 * tail - 0.2 * c; // the head drops as the sheath shortens
	float hc = mix(top + 0.022 + 0.205 * head, 0.0, bare);
	float w = max(k, 0.0065);

	// Tail fibres: free they trail and stir; planted they stand on the membrane.
	for (int j = 0; j < 3; j++) {
		float f = float(j) - 1.0;
		for (int s = -1; s <= 1; s += 2) {
			float sx = float(s);
			// Free, the long fibres lie folded back along the tail and only now
			// and then a few swing out, each in its own time; planted, all down.
			float own = seed * 31.0 + f * 2.1 + sx * 1.3;
			float out_a = max(planted, smoothstep(0.35, 0.95, sin(TIME * (0.23 + 0.17 * s2) + own)));
			vec2 hip = vec2(sx * (0.05 + 0.012 * f), BASE + 0.005);
			vec2 knee = mix(vec2(sx * (0.058 + 0.006 * f), top - 0.03 - 0.03 * f), vec2(sx * (0.2 + 0.035 * f) * legs, BASE + 0.13), out_a);
			vec2 foot = mix(vec2(sx * (0.066 + 0.008 * f), BASE + 0.02 + 0.03 * f), vec2(sx * (0.33 + 0.045 * f) * legs, mix(BASE - 0.03, BASE - 0.005, planted)), out_a);
			float d = min(seg(p, hip, knee), seg(p, knee, foot)) - w * mix(0.55, 1.0 - 0.18 * abs(f), out_a);
			o = over(o, ink, fill(d, k) * (0.72 - 0.2 * abs(f)) * mix(0.3, 1.0, out_a) * leg_a);
		}
	}
	// Tube: it stays the same length, so contraction drives it through the plate.
	float tube = seg(p, vec2(0.0, top), vec2(0.0, top - 0.34 * tail)) - w * 1.1;
	o = over(o, ink, fill(tube, k) * 0.75 * tail_a);
	// Sheath: rings, shorter and fatter when fired.
	float sw = mix(0.04, 0.07, c);
	float sh = (top - BASE) * 0.5;
	float sd = box(p, vec2(0.0, BASE + sh), vec2(sw, sh));
	float rings = 0.5 + 0.5 * sin((p.y - BASE) * mix(150.0, 260.0, c));
	o = over(o, shell, fill(sd, k) * 0.34 * tail_a);
	o = over(o, ink, fill(sd, k) * rings * 0.3 * smoothstep(0.0, 8.0, 1.0 / k * 0.02) * tail_a);
	o = over(o, ink, fill(abs(sd) - w * 0.35, k) * 0.75 * tail_a);
	// Base plate and collar.
	o = over(o, ink, fill(box(p, vec2(0.0, BASE), vec2(0.08, 0.016)), k) * 0.7 * tail_a);
	o = over(o, ink, fill(box(p, vec2(0.0, top + 0.008), vec2(0.06, 0.013)), k) * 0.7 * tail_a);
	// Head: facets catch the light; the DNA packed inside drains away.
	vec2 hp = hp0 - vec2(0.0, hc);
	float hd = capsid(hp, mix(0.125, 0.17, bare) * head, mix(0.205, 0.195, bare) * head);
	float a = atan(hp.y, hp.x);
	float facet = 0.5 + 0.5 * cos(floor(a / 1.0472 + 0.5) * 1.0472 - 1.0);
	o = over(o, shell, exp(-max(hd, 0.0) * 42.0) * (1.0 - fill(hd, k)) * 0.28 * head_a);
	o = over(o, mix(shell * 0.86, min(shell * 1.18, vec3(1.0)), facet), fill(hd, k) * mix(0.42, 0.2, e) * head_a);
	float pack = (1.0 - e) * smoothstep(0.015, -0.02, hd + 0.03);
	float coil = 0.5 + 0.5 * sin(hp.x * 110.0 + sin(hp.y * 80.0) * 2.0);
	o = over(o, mix(dna * 0.8, mix(dna, vec3(1.0), 0.3), coil), pack * 0.55 * head_a);
	float ridge = min(min(abs(hp.y - abs(hp.x) * 0.62 - 0.08), abs(hp.y + abs(hp.x) * 0.62 + 0.08)), abs(hp.x) + 0.06);
	o = over(o, mix(shell * 1.5, vec3(1.0), 0.3), fill(ridge - w * 0.3, k) * fill(hd + 0.012, k) * 0.45 * (1.0 - e * 0.6) * head_a);
	o = over(o, ink, fill(abs(hd) - w * 0.42, k) * 0.85 * head_a);
	// A crystalline shell: a second hard edge and cold glints on the facets.
	if (crystal > 0.0) {
		o = over(o, ink, fill(abs(hd + 0.024) - w * 0.4, k) * crystal * head_a);
		o = over(o, ink, fill(abs(hd - 0.012) - w * 0.3, k) * crystal * 0.7 * head_a);
		// Cut facets: the head's hexagon fans out from its middle.
		float fan = abs(fract(atan(hp.y, hp.x) / 1.0472) - 0.5);
		o = over(o, vec3(1.0), smoothstep(0.03, 0.0, fan) * fill(hd + 0.03, k) * crystal * 0.8 * head_a);
		float glint = smoothstep(0.82, 1.0, sin(hp.x * 60.0 + hp.y * 34.0 + TIME * 0.7 + seed * 9.0));
		o = over(o, vec3(1.0), glint * fill(hd + 0.02, k) * crystal * 0.6 * head_a);
	}

	}
	if (small > 0.0) {
		// (Round whatever the focus: k0, or the blur reaches the quad's edge and it shows square.)
		float r = min(0.34, max(0.11, 1.5 * k0));
		float dot_a = fill(length(v_q) - r, k0 * 1.5 * (1.0 + depth));
		o = mix(o, vec4(mix(ink, dna, 0.34), dot_a * 0.7), small);
	}
	COLOR = vec4(o.rgb, o.a * alpha * (1.0 - 0.45 * depth));
}
