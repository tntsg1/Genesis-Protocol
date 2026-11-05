// Organisms in the culture dish: flat 2D line art, translucent bodies.
// Genes drive what you see, and detail fades in with zoom like turning up a
// microscope (LOD by how big a cell is on screen):
//   macro  outline and the species' colour, nothing else
//   group  translucent body, nucleus, cilia, organelles, jaws, eye, plates
//   micro  double membrane with its lipid grain, streaming cytoplasm, energy
//          flowing to the nucleus
// What it is doing is animated: swimming (cilia waves, a contraction running
// down the body), feeding (the membrane reaches round the food, energy
// streams in), hunting (jaws spread, the body lunges), biting (jaws snap),
// hurt (the membrane trembles, a dent, energy leaking), dividing (swell,
// nucleus parts, the waist pinches, two cells), and dying (shells: fade,
// crack, fall apart).
// Gene -> look:  speed  slender body, cilia ring, long flagellum
//                vision eye spot at the front
//                armor  segmented shell
//                attack mouth spikes; predators get jaws and tentacles
//                fertility round, plump body
//                efficiency more stored-energy organelles
//                cohesion faint signal dots around the body
// Instance data (SimCore.build_render_buffer, upright mode):
//   COLOR.rgb  species colour (sRGB, lineage-jittered)
//   COLOR.a    < 1 cell: (speed in 5 bits + 32 * lineage signature
//              + 1024 * stroke phase in 12 bits) / 2^22;
//              1..6 module type + 1; 7 envelope; 8 algae; 9 shell
//   CUSTOM.x   heading + 8 * phase bucket
//   cell:      .y energy + 2 * state (0 idle 1 eat 2 hunt 3 flee 4 bitten
//                 5 dividing 6 held inside its parent 7 engulfing (fraction =
//                 how far closed) 8 swallowed, being digested 9 digesting
//                 (fraction = how far digested))
//              .w diet + 2 cohesion + 16 bend + 256 growth + 4096 neural;
//                 while dividing: diet + 2 * round(progress * 4000)
//              .z six genes, 4 bits each; .w diet + 2 * cohesion level
//   module:    .y energy, .z speed fraction, .w index along the body
//   envelope:  .y body-wave phase, .z width/length + 2 * wave number * 100,
//              .w bitten + 2 * wave amplitude * 10000 (see SimCore)
shader_type canvas_item;
render_mode blend_mix, unshaded;

// Night (深海荧光, night.gdshaderinc): every body lit from within in its own
// colour (night_glow: the fill a soft translucent light, the membrane and the
// details brighter, blooming); shells dim; algae a green glow; light-eaters
// (the 光合膜 organ) with a warm halo round them.
#include "res://shaders/night.gdshaderinc"

// Analysis mode: organisms step back (lighter) so the diagram reads.
uniform float analysis = 0.0;
// The life designer draws its own big nucleus with chromosomes on top.
uniform float bare_nucleus = 0.0;
// View filter: 0 normal, 1 species (flat colours), 2 heat (ghosted).
uniform int view_mode = 0;
// Look 2: volume (a lamp highlight, light inside the membrane) and a soft
// glow on membranes (HDR, picked up by the environment's bloom).
uniform float look2 = 1.0;

// The pointer (DishPointer): the cell under it (hover) and the selected one
// (picked) light up. xy = the cell's centre (world), z = how near a quad's
// centre must be to count, w = amount 0..1.
uniform vec4 hover = vec4(-1e6, -1e6, 0.0, 0.0);
uniform vec4 picked = vec4(-1e6, -1e6, 0.0, 0.0);
// One screen pixel in world units (ripples are sized on screen).
uniform float ripple_px = 1.0;

// One species picked out (hovering its row in the HUD): its bodies light
// up, everything else steps back. Matched on the species colour's hue (the
// lineage jitter stays within `focus_tol`, set from the nearest other
// species so neighbours never match).
uniform vec4 focus_col = vec4(0.0);
uniform float focus_tol = 0.04;
uniform float focus_amt = 0.0;

varying vec4 v_custom;
varying vec4 v_color;
varying float v_focus; // 0 none, hover amount, or more when picked
varying float v_match; // 1 = the focused species
// Installed organs (scripts/organs.gd LIST order, one bit each), carried in
// the instance colour's red channel as r + 2 * mask (SimCore and the
// designer's specimen write it); 0 = none.
varying float v_organs;


// Integer hash on the float's bits (see dish.gdshader for why not sin-fract).
float hash(vec2 p) {
	uvec2 q = floatBitsToUint(p);
	uint h = (q.x * 1597334677u) ^ (q.y * 3812015801u);
	h ^= h >> 16u;
	h *= 2246822519u;
	h ^= h >> 13u;
	h *= 3266489917u;
	h ^= h >> 16u;
	return float(h) * (1.0 / 4294967295.0);
}

// Water ripples from the pointer (DishPointer): xy = centre (world),
// z = ring radius in screen pixels, w = amplitude in pixels. Visual only:
// the simulation never feels them, so experiments stay reproducible.
uniform vec4 ripples[10];
uniform int ripple_count = 0;


// Displacement (xy, world units) and light (z) of the ripples at w, where
// one screen pixel is px world units.
vec3 ripple_field(vec2 w, float px) {
	vec3 acc = vec3(0.0);
	for (int i = 0; i < 10; i++) {
		if (i >= ripple_count) {
			break;
		}
		vec4 rp = ripples[i];
		vec2 dv = w - rp.xy;
		float dp = length(dv) / px;
		float x = (dp - rp.z) / (5.0 + rp.z * 0.05);
		if (abs(x) > 3.0) {
			continue;
		}
		float env = exp(-x * x);
		acc.xy += dv / max(dp * px, 1e-4) * sin(x * 3.0) * env * rp.w * px;
		acc.z += cos(x * 3.0) * env * rp.w;
	}
	return acc;
}

float hue_of(vec3 c) {
	float mx = max(c.r, max(c.g, c.b));
	float mn = min(c.r, min(c.g, c.b));
	float d = mx - mn;
	if (d < 1e-4) {
		return 0.0;
	}
	float h;
	if (mx == c.r) {
		h = mod((c.g - c.b) / d, 6.0);
	} else if (mx == c.g) {
		h = (c.b - c.r) / d + 2.0;
	} else {
		h = (c.r - c.g) / d + 4.0;
	}
	return h / 6.0;
}

void vertex() {
	v_custom = INSTANCE_CUSTOM;
	v_color = COLOR;
	v_organs = floor(COLOR.r * 0.5);
	v_color.r = COLOR.r - 2.0 * v_organs;
	v_match = 0.0;
	if (focus_amt > 0.0 && COLOR.a < 7.5) {
		float dh = abs(hue_of(v_color.rgb) - hue_of(focus_col.rgb));
		dh = min(dh, 1.0 - dh);
		v_match = 1.0 - smoothstep(focus_tol * 0.8, focus_tol, dh);
	}
	// MODEL_MATRIX carries the instance's transform: its origin is the
	// cell's centre in the world.
	vec2 centre = MODEL_MATRIX[3].xy;
	float scale = max(length(MODEL_MATRIX[0].xy), 1e-3);
	v_focus = max(hover.w * step(length(centre - hover.xy), hover.z),
			picked.w * step(length(centre - picked.xy), picked.z) * 1.25);
	// Cells bob on the pointer's ripples (drawn only; the simulation does not
	// feel them).
	if (ripple_count > 0) {
		VERTEX += ripple_field(centre, ripple_px).xy / scale;
	}

}

float membrane(float ang, float ph, float base) {
	return base * (1.0 + 0.05 * sin(ang * 2.0 + TIME * 1.3 + ph)
			+ 0.035 * sin(ang * 3.0 - TIME * 1.9 + ph * 1.3)
			+ 0.02 * sin(ang * 5.0 + TIME * 2.7 + ph * 0.6));
}

vec4 over(vec4 dst, vec3 c, float a) {
	a = clamp(a, 0.0, 1.0);
	float oa = a + dst.a * (1.0 - a);
	vec3 oc = (c * a + dst.rgb * dst.a * (1.0 - a)) / max(oa, 1e-4);
	return vec4(oc, oa);
}

// Coverage of a line `dpx` pixels from its centre, `w` pixels wide.
float stroke(float dpx, float w) {
	return clamp(w * 0.5 - abs(dpx) + 0.5, 0.0, 1.0);
}

// Coverage of a filled disc (distance and radius in local units).
float disc(float d, float r, float ppu) {
	return clamp((r - d) * ppu + 0.5, 0.0, 1.0);
}

// Smooth minimum: two shapes melting into one.
float smin(float a, float b, float k) {
	if (k <= 1e-5) {
		return min(a, b);
	}
	float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
	return mix(b, a, h) - k * h * (1.0 - h);
}

vec3 rot_hue(vec3 c, float k) {
	// Cheap hue shift for organelle colours.
	const vec3 w = vec3(0.57735);
	float co = cos(k), si = sin(k);
	return c * co + cross(w, c) * si + w * dot(w, c) * (1.0 - co);
}

// Wavy line along -x starting at (x0, y0): returns the pixel distance to
// the curve measured perpendicular to it (a plain vertical distance makes
// steep parts of the wave thin out into a jagged zigzag), and in `t` how far
// along the line the point is (0 at the root, 1 at the tip).
// `phase` drives the beat (the kernel's stroke phase for cells, so it never
// jumps when the speed changes); the wave runs root to tip, swinging wider
// toward the tip with a little second harmonic, like a whip in water.
float wavy(vec2 p, float x0, float y0, float len, float amp, float freq, float phase, float ph, float ppu, out float t) {
	t = (x0 - p.x) / len;
	if (t < 0.0 || t > 1.0) {
		return 1e4;
	}
	float a = t * freq - phase + ph;
	float env = t * (1.5 - 0.5 * t);
	float wv = sin(a) + 0.18 * sin(2.0 * a - 0.7);
	float dw = cos(a) + 0.36 * cos(2.0 * a - 0.7);
	float y = y0 + wv * amp * env;
	float slope = amp * ((1.5 - t) * wv + env * freq * dw) / len;
	return abs(p.y - y) / sqrt(1.0 + slope * slope) * ppu;
}

const vec3 ORG0 = vec3(1.0, 0.62, 0.3);
const vec3 ORG1 = vec3(0.3, 0.82, 0.78);
const vec3 ORG2 = vec3(0.55, 0.82, 0.35);
const vec3 ORG3 = vec3(0.98, 0.55, 0.72);

// DNA seen through the loupe while a cell divides (the closest LOD): one
// copy of the molecule, a double helix along local y about c (half length
// hl). Behind the replication fork (fork, measured along y from c) the copy
// stands `side` x D off the old axis with its new strand built (cyan); past
// it the two old strands still pair up as the original molecule (copy A
// draws its rungs). side -1 keeps old strand one, +1 old strand two.
float dna_axis(float u, float cx, float side, float D, float fork, float ph) {
	return cx + side * D * smoothstep(0.0, 0.02, fork - u) + 0.006 * sin(u * 40.0 + ph);
}

vec4 dna_copy(vec4 o, vec2 p, vec2 c, float hl, float side, float D, float fork, float ph, float ppu, float a) {
	float u = p.y - c.y;
	if (abs(u) > hl + 0.012 || a < 0.003) {
		return o;
	}
	const float LAG = 0.01; // the polymerase's distance behind the fork
	float ax = dna_axis(u, c.x, side, D, fork, ph);
	float slope = (dna_axis(u + 0.001, c.x, side, D, fork, ph) - dna_axis(u - 0.001, c.x, side, D, fork, ph)) / 0.002;
	float v = p.x - ax;
	float A = 0.009;
	float k = 6.2832 / 0.032;
	float tw = TIME * 1.6 + ph; // the molecule turning slowly
	float th = k * u + tw;
	float ends = 1.0 - smoothstep(hl - 0.006, hl + 0.004, abs(u)); // the ends taper off
	float w = clamp(0.0022 * ppu, 1.0, 2.6);
	vec3 old_c = vec3(0.16, 0.2, 0.28);
	vec3 new_c = vec3(0.04, 0.66, 0.82);
	float built = 1.0 - smoothstep(fork - LAG - 0.003, fork - LAG, u);
	float paired = max(built, side < 0.0 ? smoothstep(fork, fork + 0.004, u) : 0.0);
	// Rungs (base pairs) between the strands, one every 6 nm-ish of axis.
	float sp = 0.006;
	float uj = (floor(u / sp) + 0.5) * sp;
	float y1 = A * sin(k * uj + tw);
	float y2 = A * sin(k * uj + tw + 2.5);
	float rung = clamp(w * 0.35 + 0.5 - abs(u - uj) * ppu, 0.0, 1.0)
		* clamp(min(v - min(y1, y2), max(y1, y2) - v) * ppu + 0.5, 0.0, 1.0);
	o = over(o, mix(vec3(0.55, 0.6, 0.66), new_c, 0.35 * built), rung * paired * ends * a * 0.75);
	// The two strands: old (graphite) and, where it is built, new (cyan).
	for (int s = 0; s < 2; s++) {
		float off = s == 0 ? 0.0 : 2.5;
		float sy = A * sin(th + off);
		float dy = A * k * cos(th + off) + slope;
		float dist = abs(v - sy) / sqrt(1.0 + dy * dy) * ppu;
		bool is_old = (s == 0) == (side < 0.0);
		float shown = is_old ? 1.0 : built;
		vec3 col = is_old ? old_c : new_c;
		float depth = 0.6 + 0.4 * cos(th + off);
		o = over(o, col, exp(-dist / 3.0) * 0.18 * shown * ends * a * (is_old ? 0.4 : 1.0));
		o = over(o, col, stroke(dist, w * (0.7 + 0.4 * depth)) * (0.55 + 0.45 * depth) * shown * ends * a);
	}
	return o;
}

// The organs (2026-10-29: "微生物也要长出对应的器官"), drawn on a cell in
// its own frame: p local (the cell faces +x), q = p over the body's axes,
// d its distance outside the membrane (local units), ang the angle in q.
// m is the organ mask. Out: spines, a glass shell, a long flagellum, dense
// cilia, receptor antennae, recognition marks; in: cnidocysts under the
// membrane, storage granules, a signal gland, a memory vesicle.
bool organ(int m, int k) {
	return ((m >> k) & 1) == 1;
}

vec4 organs_draw(vec4 o, int m, vec2 p, vec2 q, float d, float dpx, float ang, float rq, float ax, float ay,
		float R, float ppu, float detail, vec3 base, vec3 line, float ph, float swp, float inside, float kq) {
	if (m == 0 || detail <= 0.0) {
		return o;
	}
	vec3 glass = vec3(0.86, 0.97, 1.0);
	// 1 silica: a glass frustule just outside the membrane, in facets.
	if (organ(m, 1)) {
		float band = step(0.004, d) * step(d, 0.034);
		float fa = fract(ang / 6.2832 * 11.0 + 0.5);
		float ridge = clamp(1.2 - abs(fa - 0.5) * 2.0 / 11.0 * 6.2832 * rq * ppu, 0.0, 1.0);
		o = over(o, glass, band * 0.55 * detail);
		o = over(o, line, ridge * band * 0.45 * detail);
		o = over(o, line, stroke((d - 0.034) * ppu, 1.2) * 0.8 * detail);
		o = over(o, vec3(1.0), band * pow(max(0.0, sin(ang + 2.2)), 6.0) * 0.6 * detail);
	}
	// 2 spines: long thin spikes, tapering out from the membrane.
	if (organ(m, 2)) {
		float n = 14.0;
		float fa = fract(ang / 6.2832 * n + 0.25 + 0.15 * sin(ph));
		float off = abs(fa - 0.5) / n * 6.2832 * (rq * min(ax, ay));
		float len = 0.12 + 0.03 * sin(floor(ang / 6.2832 * n) * 2.7 + ph);
		float t = clamp(d / len, 0.0, 1.0);
		float w = mix(0.012, 0.0015, t);
		o = over(o, line, clamp((w - off) * ppu + 0.5, 0.0, 1.0) * step(-0.004, d) * step(d, len) * 0.9 * detail);
	}
	// 5 cilia: a dense coat of short hairs, beating round the body.
	if (organ(m, 5) && dpx > -1.0) {
		float n = 46.0;
		float L = 0.055 * ppu;
		float along = clamp(dpx / L, 0.0, 1.0);
		float fa = (ang / 6.2832) * n + 0.4 * sin(swp * 2.4 - ang * 8.0 + ph) * along;
		float hair = abs(fract(fa) - 0.5) / n * 6.2832 * rq * ppu;
		o = over(o, line, stroke(hair, 0.9) * step(0.0, dpx) * (1.0 - along) * 0.8 * detail);
	}
	// 4 flagellum: one long whip from the rear.
	if (organ(m, 4)) {
		float tt;
		float l = wavy(p, -R * 0.85 * ax, 0.0, 0.8, 0.13, 9.0, swp * 1.4, ph + 0.7, ppu, tt);
		o = over(o, line, stroke(l, 1.9 - 1.2 * tt) * 0.9 * detail);
	}
	// 7 chemoreceptor: two antennae at the front with sensing knobs.
	if (organ(m, 7)) {
		for (int s = 0; s < 2; s++) {
			float sd = s == 0 ? -1.0 : 1.0;
			float a0 = 0.45 * sd + 0.06 * sin(TIME * 1.7 + ph + sd);
			vec2 root = vec2(cos(a0) * R * ax, sin(a0) * R * ay);
			vec2 dir = normalize(vec2(cos(a0 * 1.4), sin(a0 * 1.4)));
			vec2 tip = root + dir * 0.11;
			vec2 pa = p - root;
			float h = clamp(dot(pa, tip - root) / dot(tip - root, tip - root), 0.0, 1.0);
			float dl = length(pa - (tip - root) * h) * ppu;
			o = over(o, line, stroke(dl, 1.3) * 0.85 * detail);
			o = over(o, mix(base, vec3(1.0), 0.3), disc(length(p - tip), 0.014, ppu) * detail);
			o = over(o, line, stroke((length(p - tip) - 0.014) * ppu, 1.0) * detail);
		}
	}
	// 8 recognition protein: little Y marks standing on the membrane.
	if (organ(m, 8)) {
		float n = 16.0;
		float fa = fract(ang / 6.2832 * n);
		float off = abs(fa - 0.5) / n * 6.2832 * (rq * min(ax, ay));
		float stalk = clamp((0.0035 - off) * ppu + 0.5, 0.0, 1.0) * step(0.0, d) * step(d, 0.016);
		float cup = clamp((0.009 - abs(off - (d - 0.016) * 0.8)) * ppu + 0.5, 0.0, 1.0) * step(0.016, d) * step(d, 0.028);
		o = over(o, mix(line, base, 0.3), (stalk + cup) * 0.85 * detail);
	}
	// 0 cnidocysts: capsules just under the membrane, each with its coiled
	// thread, the front ones with a barb poking out.
	if (organ(m, 0)) {
		float n = 13.0;
		float slot = floor(ang / 6.2832 * n + 0.5);
		float ac = slot / n * 6.2832;
		vec2 qc = vec2(cos(ac), sin(ac)) * 0.255;
		float dc = length(q - qc);
		o = over(o, mix(base, vec3(0.95, 0.9, 0.98), 0.5), disc(dc, 0.016, ppu) * inside * detail);
		o = over(o, line, stroke((dc - 0.016) * ppu, 0.9) * detail * inside);
		o = over(o, line, disc(dc, 0.005, ppu) * detail);
		if (cos(ac) > 0.3) {
			float barb = clamp((0.004 - abs(fract(ang / 6.2832 * n + 0.5) - 0.5) / n * 6.2832 * rq * min(ax, ay)) * ppu + 0.5, 0.0, 1.0);
			o = over(o, line, barb * step(0.0, d) * step(d, 0.03) * detail);
		}
	}
	// 3 storage granules: a dense cluster of small dark grains at the rear.
	if (organ(m, 3)) {
		for (int k = 0; k < 10; k++) {
			float fk = float(k);
			float a = hash(vec2(fk + 21.0, kq)) * 6.2832 + TIME * 0.08;
			vec2 c = vec2(-0.19, 0.05) + vec2(cos(a), sin(a)) * vec2(0.05, 0.08) * sqrt(hash(vec2(kq, fk + 5.0)));
			float dc = length(q - c);
			o = over(o, mix(base, vec3(0.25, 0.22, 0.3), 0.6), disc(dc, 0.013, ppu) * 0.85 * inside * detail);
			o = over(o, vec3(1.0), disc(length(q - c - vec2(0.004, 0.004)), 0.004, ppu) * 0.6 * inside * detail);
		}
	}
	// 6 signal gland: a vesicle on one flank, puffing signal motes out.
	if (organ(m, 6)) {
		vec2 gc = vec2(-0.06, 0.2);
		float dg = length((q - gc) / vec2(1.3, 1.0));
		float pump = 0.5 + 0.5 * sin(TIME * 2.2 + ph);
		o = over(o, mix(base, vec3(0.98, 0.8, 0.45), 0.7), disc(dg, 0.04 + 0.006 * pump, ppu) * 0.9 * inside * detail);
		o = over(o, line, stroke((dg - 0.04 - 0.006 * pump) * ppu, 1.0) * 0.8 * detail);
		for (int k = 0; k < 3; k++) {
			float t = fract(TIME * 0.5 + float(k) / 3.0 + ph);
			vec2 mp = vec2(-0.03, R * ay + 0.02) + vec2(0.04 * sin(float(k) * 2.1 + ph), 0.14 * t);
			o = over(o, vec3(0.98, 0.78, 0.4), disc(length(p - mp), 0.008 * (1.0 - t), ppu) * (1.0 - t) * detail);
		}
	}
	// 9 memory vesicle: a bright bubble with rings, glowing softly.
	if (organ(m, 9)) {
		vec2 mc = vec2(0.15, -0.15);
		float dm = length(q - mc);
		float beat = 0.5 + 0.5 * sin(TIME * 1.3 + ph);
		o = over(o, mix(base, vec3(0.75, 0.95, 1.0), 0.7), disc(dm, 0.04, ppu) * 0.7 * inside * detail);
		o = over(o, line, stroke((dm - 0.04) * ppu, 1.0) * 0.8 * detail);
		o = over(o, vec3(1.0), stroke((dm - 0.022 - 0.008 * beat) * ppu, 0.8) * 0.8 * detail);
	}
	return o;
}

vec3 organelle_color(float h) {
	return h < 0.25 ? ORG0 : (h < 0.5 ? ORG1 : (h < 0.75 ? ORG2 : ORG3));
}

void fragment() {
	// QuadMesh is a 3D primitive: its UV.y runs bottom-to-top on a 2D canvas
	// (where +y is down). Flip it, or every body is drawn mirrored about its
	// heading and turns the opposite way to how it moves.
	// (Measured by tests/orient_check.gd: a heading of 45° must point down-right.)
	vec2 ps = vec2(UV.x - 0.5, 0.5 - UV.y) * 2.0;
	float packed = v_custom.x;
	float kq = floor((packed + 4.0) / 8.0);
	float hd = packed - 8.0 * kq;
	float ph = kq * 1.37;
	vec2 p = vec2(ps.x * cos(hd) + ps.y * sin(hd), -ps.x * sin(hd) + ps.y * cos(hd));
	vec3 base = v_color.rgb;
	float kind = v_color.a;
	float ppu = 1.0 / max(fwidth(ps.x), 1e-5); // pixels per local unit
	vec3 line = mix(base * 0.8, vec3(0.32, 0.45, 0.52), 0.2);
	vec3 tint = mix(base, vec3(1.0), 0.45);
	vec4 o = vec4(0.0);
	float glow = 0.0; // how much this pixel blooms (look 2)

	if (kind < 1.0) {
		// ---------------------------------------------------------------- cell
		float kv = kind * 4194304.0 + 0.5;
		float low = mod(floor(kv), 1024.0);
		float speed = mod(low, 32.0) / 31.0;
		float sig = floor(low / 32.0); // 0..31: this lineage's own look
		float swp = floor(kv / 1024.0) / 4096.0 * 6.2831853; // stroke phase
		float s1 = fract(sig * 0.6180339);
		float s2 = fract(sig * 0.3819660 + 0.27);
		float s3 = fract(sig * 0.7548776 + 0.61);
		float state = floor(v_custom.y * 0.5);
		float energy = v_custom.y - state * 2.0;
		if (state == 6.0) {
			// Still held inside its parent: the parent draws both halves.
			COLOR = vec4(0.0);
		} else if (state == 8.0) {
			// ------------------------------------------- being digested
			// Swallowed prey inside its predator (drawn first, so the
			// predator's body lies over it): held in a food vacuole, its
			// membrane breaking up and its colour draining as it shrinks,
			// nutrients seeping out into the host.
			float gdig = energy;
			float R = 0.3;
			float rpx = R * ppu;
			float mid = smoothstep(2.0, 4.5, rpx);
			float detail = smoothstep(7.0, 12.0, rpx);
			float ang = atan(p.y, p.x);
			float soft = 1.0 - smoothstep(0.7, 1.0, gdig);
			float wob = 0.03 * sin(ang * 3.0 + TIME * 1.5 + ph) + 0.06 * gdig * sin(ang * 6.0 - TIME * 0.8 + ph);
			float d = length(p / vec2(1.1, 0.88)) - R * (1.0 + wob);
			float dpx = d * ppu;
			float inside = clamp(0.5 - dpx, 0.0, 1.0);
			vec3 dig = mix(base, vec3(0.86, 0.8, 0.6), 0.65 * smoothstep(0.0, 0.7, gdig));
			float dv = length(p) - R * 1.3;
			o = over(o, vec3(0.9, 0.95, 0.97), clamp(0.5 - dv * ppu, 0.0, 1.0) * 0.3 * soft);
			o = over(o, line, stroke(dv * ppu, 1.0) * 0.6 * soft * mid);
			o = over(o, dig, inside * (0.7 - 0.3 * gdig) * soft);
			float seg = abs(fract(ang / 6.2832 * 9.0 + hash(vec2(kq, 2.0))) - 0.5);
			float gaps = smoothstep(0.5 - 0.35 * gdig, 0.45 - 0.35 * gdig, seg);
			o = over(o, dig * 0.6, stroke(dpx, 1.6) * mix(1.0, gaps, smoothstep(0.1, 0.5, gdig)) * soft);
			o = over(o, mix(dig, vec3(0.45, 0.4, 0.7), 0.3), disc(length(p - vec2(-0.03, 0.0)), 0.07 * (1.0 - gdig), ppu) * 0.5 * (1.0 - smoothstep(0.2, 0.6, gdig)));
			for (int k = 0; k < 5; k++) {
				float fk = float(k);
				float a = hash(vec2(fk, kq)) * 6.2832 + TIME * 0.3;
				vec2 c = vec2(cos(a), sin(a)) * R * (0.3 + 0.5 * hash(vec2(kq, fk))) * (1.0 + 0.4 * gdig);
				o = over(o, dig * 0.9, disc(length(p - c), 0.022, ppu) * 0.6 * soft * detail);
			}
			if (detail > 0.0) {
				for (int k = 0; k < 4; k++) {
					float t = fract(TIME * 0.7 + float(k) * 0.25 + ph);
					float a = float(k) * 1.7 + ph;
					vec2 c = vec2(cos(a), sin(a)) * R * (0.9 + 0.9 * t);
					o = over(o, vec3(1.0, 0.88, 0.5), disc(length(p - c), 0.018 * (1.0 - t), ppu) * (1.0 - t) * 0.8 * detail * soft);
				}
			}
		} else if (state == 5.0) {
			// ---------------------------------------------------- division
			// The signature moment. The parent swells and stretches, its
			// chromosomes condense and the nucleus parts in two along spindle
			// fibres, the waist pinches in, and two cells draw apart (the child
			// steps out ahead, at +x). This quad is drawn 1.5x the usual size so
			// both halves fit; local units are rescaled to match a normal cell.
			p *= 1.5;
			ppu /= 1.5;
			uint g = uint(v_custom.z + 0.5);
			float g_speed = float(g & 15u) / 15.0;
			float g_fert = float((g >> 16u) & 15u) / 15.0;
			float g_eff = float((g >> 20u) & 15u) / 15.0;
			float split = floor(v_custom.w / 2.0) / 4000.0;
			float diet = mod(v_custom.w, 2.0);
			float R = 0.3;
			float rpx = R * ppu;
			float detail = smoothstep(7.0, 12.0, rpx);
			float mid = smoothstep(2.0, 4.5, rpx);
			float ax = (1.0 + 0.35 * g_speed - 0.1 * g_fert) * (0.95 + 0.1 * s1);
			float ay = (1.0 - 0.18 * g_speed + 0.14 * g_fert) * (0.96 + 0.08 * s2);
			// Stages: swell 0..0.25, stretch and pinch 0.15..0.8, part 0.8..1.
			float sep = smoothstep(0.08, 0.95, split);
			// Fully parted, the two bodies just touch end to end (the kernel
			// holds the child at the same distance: the two half lengths).
			float sx = 2.08 * R * ax * sep;
			float mx = sx * 0.5;
			float swell = 1.0 + 0.12 * smoothstep(0.0, 0.25, split) * (1.0 - smoothstep(0.55, 1.0, split));
			float ry = R * ay * swell * (1.0 - 0.1 * sep * (1.0 - sep) * 4.0);
			float rx = R * ax * swell;
			vec2 pp = p;
			pp.y *= 1.0 + 0.04 * sin(swp + p.x * 9.0);
			float da = length(pp / vec2(rx, ry)) - 1.0;
			float db = length((pp - vec2(sx, 0.0)) / vec2(rx, ry)) - 1.0;
			float k = 0.9 * (1.0 - smoothstep(0.45, 0.97, split));
			float dd = smin(da, db, k) * min(rx, ry);
			float waist = exp(-pow((p.x - mx) / (0.04 + 0.1 * (1.0 - sep)), 2.0));
			float pinch = smoothstep(0.2, 0.85, split) * (1.0 - smoothstep(0.92, 1.0, split));
			dd += waist * 0.09 * pinch * smoothstep(0.0, 0.2, ry - abs(p.y) * 0.5);
			float ang = atan(p.y, p.x - mx);
			float side = step(mx, p.x);
			vec2 lc = vec2(side * sx, 0.0); // the lobe this pixel belongs to
			float la = atan(p.y - lc.y, p.x - lc.x);
			dd += R * 0.03 * sin(la * 3.0 - TIME * 1.9 + ph * 1.3);
			float dpx = dd * ppu;
			float inside = clamp(0.5 - dpx, 0.0, 1.0);
			float lw = clamp(rpx * 0.08, 0.9, 2.0);
			// A soft glow while it works, brighter at the furrow.
			float aura = exp(-max(dd, 0.0) * 13.0) * (1.0 - inside);
			o = over(o, mix(base, vec3(1.0), 0.35), aura * (0.2 + 0.08 * sin(TIME * 5.0) + 0.25 * waist * pinch) * mid);
			// Cilia keep beating round both halves.
			if (detail > 0.0 && g_speed > 0.15 && dpx > -1.0) {
				float n = floor(10.0 + 26.0 * g_speed + 6.0 * s2);
				float L = (0.04 + 0.05 * g_speed) * ppu;
				float bend = 0.35 * sin(swp * 2.0 - la * n * 0.25 + ph);
				float along = clamp(dpx / L, 0.0, 1.0);
				float fa = (la / 6.2832) * n + bend * along;
				float hair = abs(fract(fa) - 0.5) / n * 6.2832 * length(p - lc) * ppu;
				o = over(o, line, stroke(hair, 0.9) * step(0.0, dpx) * (1.0 - along) * 0.75 * detail * (1.0 - waist * pinch));
			}
			// The parent keeps its tail (or tentacles) beating behind it.
			if (detail > 0.0 && dpx > -0.5) {
				if (diet > 0.5) {
					for (int k3 = 0; k3 < 3; k3++) {
						float fk = float(k3) - 1.0;
						float tt;
						float l = wavy(p, -rx * 0.75, fk * R * 0.35, 0.55 + 0.1 * fk * fk, 0.12, 8.0, swp * 0.8, ph + fk * 1.7, ppu, tt);
						o = over(o, line, stroke(l, 1.6 - 0.9 * tt) * 0.7 * detail);
					}
				} else if (g_speed > 0.45) {
					float tt;
					float l = wavy(p, -rx * 0.85, 0.0, (0.3 + 0.35 * g_speed) * (0.8 + 0.4 * s1), 0.1, 11.0, swp * 1.6, ph, ppu, tt);
					o = over(o, line, stroke(l, 1.4 - 0.8 * tt) * 0.8 * detail);
				}
			}
			o = over(o, tint, inside * (0.28 + 0.12 * energy));
			o = over(o, base, inside * smoothstep(-0.06, 0.0, dd) * 0.22);
			o = over(o, line, stroke(dpx, lw) * 0.95);
			float micro = smoothstep(16.0, 26.0, rpx);
			o = over(o, line, stroke(dpx + 0.016 * ppu, 0.6) * 0.35 * micro);
			// The cleavage furrow: a bright ring tightening round the waist.
			o = over(o, vec3(1.0), stroke(dpx, lw * 2.2) * waist * pinch * 0.6);
			// Nucleus: chromosomes condense in it (0.1..0.3), it stretches,
			// then two daughter nuclei are pulled apart along the spindle.
			vec3 ncol = mix(base, vec3(0.45, 0.4, 0.7), 0.4);
			vec3 chrom = mix(base, vec3(0.22, 0.18, 0.48), 0.78);
			float part = smoothstep(0.32, 0.72, split);
			float condense = smoothstep(0.08, 0.28, split);
			vec2 n0 = vec2(mix(-0.04, mx, smoothstep(0.0, 0.3, split)), 0.0);
			float stretch = 1.0 + 0.9 * smoothstep(0.15, 0.32, split) * (1.0 - part);
			// Through the loupe: the DNA itself. A helicase runs along the
			// molecule unzipping it (0.04..0.26), polymerases behind it build
			// each old strand a new partner, the two copies coil up a little,
			// ride the spindle to the poles and settle into the new nuclei.
			float ultra = smoothstep(70.0, 115.0, rpx);
			float nuc_d = 9.0; // distance to the nearest nucleus (local units)
			// The loupe looks into the nucleus: drawn twice the size there, and
			// the DNA in its own frame, sc times larger than the cell's.
			float sc = mix(1.0, 2.0, ultra);
			float dna_a = ultra * smoothstep(0.0, 0.05, split) * (1.0 - smoothstep(0.86, 1.0, split));
			float hl = 0.055 * (1.0 - 0.3 * smoothstep(0.26, 0.4, split) * (1.0 - smoothstep(0.72, 0.95, split)));
			float rep = smoothstep(0.04, 0.26, split);
			float fork = mix(-hl - 0.02, hl + 0.04, rep);
			if (part < 0.02) {
				vec2 rq = (p - n0) / vec2(mix(stretch, 1.0 + 0.25 * (stretch - 1.0), ultra), 1.0);
				float dn = length(rq) - 0.07 * sc * (1.0 + 0.3 * condense);
				nuc_d = dn;
				o = over(o, ncol, clamp(0.5 - dn * ppu, 0.0, 1.0) * 0.45 * mid);
				o = over(o, line, stroke(dn * ppu, 0.8) * 0.5 * detail * (1.0 - condense * 0.6));
				// Condensed chromosomes: short bars lining up across the middle.
				for (int c = 0; c < 4; c++) {
					float fc = float(c);
					vec2 cc = n0 + vec2(0.0, (fc - 1.5) * 0.034 * (1.0 + 0.3 * condense))
						+ vec2(0.02 * sin(fc * 2.3 + ph) * (1.0 - condense), 0.0);
					vec2 dv = p - cc;
					float bar = length(vec2(max(abs(dv.x) - 0.028, 0.0), dv.y)) - 0.009;
					o = over(o, chrom, clamp(0.5 - bar * ppu, 0.0, 1.0) * condense * detail * 0.9 * (1.0 - ultra));
				}
				if (dna_a > 0.003) {
					vec2 q = n0 + (p - n0) / sc;
					float qpu = ppu * sc;
					o = dna_copy(o, q, n0, hl, -1.0, 0.024, fork, ph, qpu, dna_a);
					o = dna_copy(o, q, n0, hl, 1.0, 0.024, fork, ph, qpu, dna_a);
					// The helicase at the fork (a bright clamp opening the
					// strands) and a polymerase on each copy just behind it.
					float working = smoothstep(0.03, 0.06, split) * (1.0 - smoothstep(0.24, 0.28, split)) * dna_a;
					if (working > 0.003) {
						vec2 hp = vec2(dna_axis(fork, n0.x, 0.0, 0.0, fork, ph), n0.y + fork);
						float hd = length((q - hp) / vec2(1.0, 0.6));
						o = over(o, vec3(0.1, 0.78, 0.9), exp(-hd * qpu / 9.0) * 0.6 * working);
						o = over(o, vec3(0.04, 0.55, 0.7), stroke((hd - 0.011) * qpu, 2.2) * working);
						o = over(o, vec3(1.0), disc(hd, 0.005, qpu) * working);
						for (int s = 0; s < 2; s++) {
							float sd = s == 0 ? -1.0 : 1.0;
							float up = fork - 0.012;
							vec2 pp2 = vec2(dna_axis(up, n0.x, sd, 0.024, fork, ph), n0.y + up);
							float pd = length(q - pp2);
							o = over(o, vec3(0.1, 0.78, 0.9), exp(-pd * qpu / 6.0) * 0.5 * working);
							o = over(o, vec3(1.0), disc(pd, 0.0045, qpu) * working);
							o = over(o, vec3(0.04, 0.55, 0.7), stroke((pd - 0.0065) * qpu, 1.2) * working);
						}
					}
				}
			} else {
				vec2 na = vec2(mix(mx, -0.04, part), 0.0);
				vec2 nb = vec2(mix(mx, sx - 0.04, part), 0.0);
				for (int n = 0; n < 2; n++) {
					vec2 nc = n == 0 ? na : nb;
					float r = mix(0.05, 0.075, part) * sc;
					float dn = length(p - nc) - r;
					nuc_d = min(nuc_d, length(p - nc) - r);
					o = over(o, ncol, clamp(0.5 - dn * ppu, 0.0, 1.0) * 0.45 * mid);
					o = over(o, line, stroke(dn * ppu, 0.8) * 0.5 * detail * part);
					// The chromosome sets riding with each nucleus, unwinding.
					for (int c = 0; c < 4; c++) {
						float fc = float(c);
						vec2 cc = nc + vec2(0.0, (fc - 1.5) * 0.026 * (1.0 - part * 0.5));
						vec2 dv = p - cc;
						float bar = length(vec2(max(abs(dv.x) - 0.012, 0.0), dv.y)) - 0.008;
						o = over(o, chrom, clamp(0.5 - bar * ppu, 0.0, 1.0) * (1.0 - part) * detail * 0.9 * (1.0 - ultra));
					}
				}
				// The two finished copies, each riding its nucleus out to a pole.
				if (dna_a > 0.003) {
					vec2 ca = na - vec2(0.024 * sc * (1.0 - part), 0.0);
					vec2 cb = nb + vec2(0.024 * sc * (1.0 - part), 0.0);
					o = dna_copy(o, ca + (p - ca) / sc, ca, hl, -1.0, 0.0, 9.0, ph, ppu * sc, dna_a);
					o = dna_copy(o, cb + (p - cb) / sc, cb, hl, 1.0, 0.0, 9.0, ph, ppu * sc, dna_a);
				}
				// Spindle fibres from pole to pole while they part.
				float poles = 1.0 - smoothstep(0.7, 0.9, split);
				if (detail > 0.0 && poles > 0.0 && p.x > na.x && p.x < nb.x) {
					float u = (p.x - na.x) / max(nb.x - na.x, 1e-3);
					for (int f = 0; f < 5; f++) {
						float bow = (float(f) - 2.0) * 0.03 * sin(u * 3.1416);
						o = over(o, ncol, stroke(abs(p.y - bow) * ppu, 0.7) * 0.45 * detail * poles);
					}
				}
			}
			// Organelles shared out between the halves, drifting across.
			if (detail > 0.0) {
				int count = 2 + int(g_eff * 4.0 + 0.5);
				for (int k2 = 0; k2 < 6; k2++) {
					if (k2 >= count) {
						break;
					}
					float fk = float(k2);
					float h = hash(vec2(fk, kq));
					float a = h * 6.2832 + TIME * (0.15 + 0.1 * hash(vec2(kq, fk)));
					vec2 c = vec2(cos(a) * 0.62, sin(a) * 0.55) * R * (0.45 + 0.4 * hash(vec2(fk + 7.0, kq)));
					c.x += mod(fk, 2.0) * sx * smoothstep(0.2, 0.8, split);
					float r = 0.03 + 0.03 * hash(vec2(fk + 3.0, kq));
					vec3 oc = organelle_color(hash(vec2(fk + 11.0, kq)));
					float dc = length(p - c);
					// Through the loupe they keep out of the nucleus, off the DNA.
					float clear = mix(1.0, 0.15 + 0.85 * smoothstep(-0.005, 0.015, nuc_d), ultra);
					o = over(o, oc, disc(dc, r, ppu) * (0.35 + 0.45 * energy) * inside * detail * clear);
					o = over(o, mix(oc, vec3(1.0), 0.6), disc(dc, r * 0.4, ppu) * 0.6 * inside * detail * clear);
				}
			}
			// Predators grow the child's jaws as it parts.
			if (diet > 0.5) {
				vec2 jp = p - vec2(sx, 0.0);
				float a = abs(atan(jp.y, jp.x));
				float jr = length(jp);
				o = over(o, line, stroke((a - 0.35) * jr * ppu, 1.6) * step(rx * 0.85, jr) * step(jr, rx + 0.12) * step(0.0, jp.x) * sep);
			}
		} else {
		uint g = uint(v_custom.z + 0.5);
		float g_speed = float(g & 15u) / 15.0;
		float g_vision = float((g >> 4u) & 15u) / 15.0;
		float g_armor = float((g >> 8u) & 15u) / 15.0;
		float g_attack = float((g >> 12u) & 15u) / 15.0;
		float g_fert = float((g >> 16u) & 15u) / 15.0;
		float g_eff = float((g >> 20u) & 15u) / 15.0;
		float social = mod(v_custom.w, 16.0);
		float diet = mod(social, 2.0);
		float cohesion = floor(social * 0.5) / 7.0;
		float bend = mod(floor(v_custom.w / 16.0), 16.0) / 15.0 * 2.0 - 1.0; // -1..1, turning
		// Newborns swell into shape with a soft elastic overshoot, and their
		// membrane is brighter for a moment (division just happened).
		float grown = mod(floor(v_custom.w / 256.0), 16.0) / 15.0;
		float neural = floor(v_custom.w / 4096.0) / 15.0; // 0..1, gene 1..5
		float swell = 1.0 - exp(-5.0 * grown) * cos(grown * 9.0);
		p /= max(mix(0.5, 1.0, swell), 0.3);

		float R = 0.3;
		float rpx = R * ppu;
		float detail = smoothstep(7.0, 12.0, rpx);
		float mid = smoothstep(2.0, 4.5, rpx);

		// Swimming: rock side to side with each stroke, stretch on the surge.
		// No whole-body yaw: the stroke shows in the body wave and the tail;
		// turning is the kernel's (the cilia turn the body, with inertia).
		float rock = 0.0;
		p = vec2(p.x * cos(rock) - p.y * sin(rock), p.x * sin(rock) + p.y * cos(rock));
		// Body proportions from genes: fast = slender, fertile = round.
		float ax = (1.0 + 0.35 * g_speed - 0.1 * g_fert + 0.15 * speed) * (0.95 + 0.1 * s1);
		float ay = (1.0 - 0.18 * g_speed + 0.14 * g_fert - 0.06 * speed) * (0.96 + 0.08 * s2);
		// Swimming: a contraction runs down the body with each stroke.
		ay *= 1.0 + 0.05 * sin(swp + p.x * 9.0) * (0.3 + speed);
		// Hunting: every so often the body gathers and lunges forward.
		float lunge = state == 2.0 ? pow(max(0.0, sin(TIME * 2.4 + ph)), 8.0) : 0.0;
		ax *= 1.0 + 0.2 * lunge;
		ay *= 1.0 - 0.1 * lunge;
		if (state == 9.0) {
			// Digesting a meal: round and full, easing back as it goes down.
			float full = 1.0 - smoothstep(0.15, 1.0, energy);
			ay *= 1.0 + 0.2 * full;
			ax *= 1.0 + 0.05 * full;
		}
		// Soft body: it curves into turns and a travelling wave runs from
		// head to tail, so the cell flexes with the water instead of gliding
		// as a rigid shape.
		p.y -= bend * (0.9 * p.x * p.x - 0.06);
		p.y += sin(p.x * 9.0 + swp) * 0.018 * (0.45 + speed) * smoothstep(0.35, -0.2, p.x);
		p.x *= 1.0 + 0.04 * sin(TIME * 2.3 + ph * 0.7);
		vec2 q = p / vec2(ax, ay);
		if (diet > 0.5) { // predators: a pointed front
			q.y *= 1.0 + 0.35 * smoothstep(0.0, 0.3, p.x);
		}
		float ang = atan(q.y, q.x);
		float rq = length(q);
		float Rm = membrane(ang, ph, R);
		if (state == 7.0) {
			// Engulfing: the front opens into a cup whose arms reach round
			// the prey and close over it as the bite goes on.
			float close = energy;
			float aa = abs(ang);
			float arm_at = mix(0.95, 0.45, close);
			Rm += R * (0.18 + 0.55 * close) * exp(-pow((aa - arm_at) / 0.3, 2.0));
			Rm -= R * 0.22 * (1.0 - 0.6 * close) * exp(-aa * aa / 0.06);
			Rm += R * 0.02 * sin(ang * 7.0 + TIME * 6.0);
		}
		if (state == 9.0) {
			Rm += R * 0.025 * sin(ang * 2.0 - TIME * 2.0 + ph); // slow churning
		}
		if (state == 1.0) {
			// Feeding: the membrane reaches forward round the food.
			Rm += R * 0.14 * pow(max(cos(ang), 0.0), 5.0) * (0.65 + 0.35 * sin(TIME * 4.0 + ph));
		}
		// Hurt: the membrane trembles and caves in where it was bitten.
		float hurt_a = hash(vec2(ph, floor(TIME * 0.5))) * 6.2832 - 3.1416;
		if (state == 4.0) {
			Rm += R * 0.025 * sin(ang * 11.0 + TIME * 45.0);
			float da = abs(mod(ang - hurt_a + 3.1416, 6.2832) - 3.1416);
			Rm -= R * 0.06 * exp(-da * da / 0.12);
		}
		float d = (rq - Rm) * min(ax, ay);
		float dpx = d * ppu;
		float inside = clamp(0.5 - dpx, 0.0, 1.0);

		if (mid < 0.01) {
			// Macro: the cell's outline in its species' colour, nothing more.
			o = over(o, mix(base, vec3(1.0), 0.25), inside * 0.6);
			o = over(o, base * 0.75, stroke(dpx, 1.1) * 0.95);
			o = over(o, base, exp(-max(d, 0.0) * 22.0) * (1.0 - inside) * 0.35);
			if (v_focus > 0.0) {
				float halo = exp(-max(d, 0.0) * 9.0) * (1.0 - inside);
				o = over(o, mix(base, vec3(1.0), 0.35), halo * 0.55 * min(v_focus, 1.0));
				o = over(o, mix(base, vec3(1.0), 0.5), stroke(dpx, 1.8) * min(v_focus, 1.0));
				glow = max(glow, (halo * 0.8 + stroke(dpx, 2.0)) * v_focus);
			}
		} else {
			float pulse = state == 3.0 ? 0.5 + 0.5 * sin(TIME * 18.0 + ph) : 0.0;
			float aura = exp(-max(d, 0.0) * 13.0) * (1.0 - inside);
			o = over(o, mix(base, vec3(1.0), 0.3), aura * (0.16 + 0.14 * pulse));
			// Wake.
			if (p.x < -R * 0.5) {
				float t = clamp((-p.x - R * 0.5) / (0.95 - R * 0.5), 0.0, 1.0);
				float spread = R * (0.55 + 0.9 * t);
				float band = 1.0 - smoothstep(spread * 0.6, spread, abs(p.y));
				o = over(o, vec3(1.0), band * (1.0 - t) * speed * 0.4);
			}
			if (lunge > 0.05 && p.x < -R * 0.6) {
				float lane = abs(fract(p.y / 0.07 + 0.5) - 0.5) * 0.07 * ppu;
				float len_s = smoothstep(-R * 0.6 - 0.4 * lunge, -R * 0.6, p.x);
				o = over(o, mix(base, vec3(1.0), 0.5), stroke(lane, 1.0) * len_s * step(abs(p.y), R * 0.7) * lunge * 0.55);
			}
			// Tentacles (predators) or a flagellum (fast swimmers).
			if (detail > 0.0) {
				if (diet > 0.5) {
					for (int k = 0; k < 3; k++) {
						float fk = float(k) - 1.0;
						float tt;
						vec2 pf = p + vec2(0.0, bend * 0.2 * clamp((-R * 0.75 * ax - p.x) / 0.55, 0.0, 1.0));
						float l = wavy(pf, -R * 0.75 * ax, fk * R * 0.35, 0.55 + 0.1 * fk * fk, 0.12, 8.0, swp * 0.8, ph + fk * 1.7, ppu, tt);
						o = over(o, line, stroke(l, 1.6 - 0.9 * tt) * 0.7 * detail);
					}
				} else if (g_speed > 0.45) {
					float tt;
					// In a turn the tail sweeps out to the far side: it is what
					// swings the body round.
					vec2 pf = p + vec2(0.0, bend * 0.2 * clamp((-R * 0.85 * ax - p.x) / 0.45, 0.0, 1.0));
					float l = wavy(pf, -R * 0.85 * ax, 0.0, (0.3 + 0.35 * g_speed) * (0.8 + 0.4 * s1), 0.1, 11.0, swp * 1.6, ph, ppu, tt);
					o = over(o, line, stroke(l, 1.4 - 0.8 * tt) * 0.8 * detail);
				}
			}
			if (mid > 0.0 && detail < 1.0 && diet < 0.5) {
				// Mid LOD: a short simple tail.
				float tt;
				float l = wavy(p, -R * 0.85 * ax, 0.0, 0.3, 0.06, 12.0, swp * 1.6, ph, ppu, tt);
				o = over(o, line, stroke(l, 1.0) * 0.6 * (1.0 - detail));
			}
			// Cilia: a ring of fine hairs whose beat travels around the body.
			if (detail > 0.0 && g_speed > 0.15 && dpx > -1.0) {
				float n = floor(10.0 + 26.0 * g_speed + 6.0 * s2);
				float L = (0.04 + 0.05 * g_speed) * ppu;
				float bend = 0.35 * sin(swp * 2.0 - ang * n * 0.25 + ph);
				float fa = (ang / 6.2832) * n + bend * clamp(dpx / L, 0.0, 1.0);
				float hair = abs(fract(fa) - 0.5) / n * 6.2832 * rq * ppu;
				float along = clamp(dpx / L, 0.0, 1.0);
				o = over(o, line, stroke(hair, 0.9) * step(0.0, dpx) * (1.0 - along) * 0.75 * detail);
			}
			// Mouth spikes (attack) on non-predators.
			if (diet < 0.5 && g_attack > 0.2 && d > 0.0) {
				float fan = smoothstep(0.3, 0.8, cos(ang));
				float ray = smoothstep(0.75, 1.0, cos(ang * 9.0));
				o = over(o, line, fan * ray * clamp(0.5 - (d - 0.03 - 0.08 * g_attack) * ppu, 0.0, 1.0) * 0.8);
			}
			// Predator jaws: two curved mandibles that open and close.
			if (diet > 0.5 && p.x > 0.0) {
				float open = 0.3 + 0.12 * sin(TIME * 4.0 + ph);
				if (state == 2.0) {
					open = 0.5 + 0.1 * lunge; // spread wide on the chase
				} else if (state == 7.0) {
					open = 0.55; // held wide while the body closes round
				}
				float a = abs(atan(p.y, p.x));
				float r = length(p);
				float blade = abs(a - open * (1.0 - (r - R * ax) * 2.5)) * r * ppu;
				// Rooted on the membrane itself, so they never float free of a
				// pointed or stretched front.
				float on = step(-0.008, d) * step(d, 0.1 + 0.07 * g_attack);
				o = over(o, line, stroke(blade, 2.0) * on * (state == 7.0 ? 1.0 - 0.85 * energy : 1.0));
			}
			// Body.
			o = over(o, tint, inside * (0.28 + 0.12 * energy));
			o = over(o, base, inside * smoothstep(-0.06, 0.0, d) * 0.22);
			// Shell: thick segmented plates.
			if (g_armor > 0.3) {
				float band = smoothstep(-0.05 - 0.04 * g_armor, -0.03, d) * inside;
				float seg = abs(fract(ang / 6.2832 * (8.0 + floor(s3 * 5.0)) + 0.5) - 0.5);
				float gap = smoothstep(0.02, 0.05, seg);
				o = over(o, mix(base, vec3(0.96, 0.9, 0.78), 0.55), band * gap * g_armor * 0.7);
				o = over(o, line, stroke(dpx + (0.04 + 0.04 * g_armor) * ppu, 1.0) * g_armor * 0.5 * mid);
			}
			float lw = clamp(rpx * 0.08, 0.9, 2.0) * (state == 2.0 ? 1.35 : 1.0);
			o = over(o, line, stroke(dpx, lw) * 0.95);
			if (look2 > 0.0) {
				// Light caught inside the membrane, and the lamp's highlight
				// on the upper side of the body: the cell reads as a volume.
				float band = smoothstep(-0.075, -0.004, d) * inside;
				o = over(o, mix(base, vec3(1.0), 0.6), band * 0.38 * look2);
				float hl = clamp(dot(normalize(ps + vec2(1e-4)), vec2(-0.55, 0.83)), 0.0, 1.0);
				o = over(o, vec3(1.0), inside * pow(hl, 4.0) * smoothstep(-0.14, -0.03, d) * 0.32 * look2);
				glow = max(glow, stroke(dpx, lw * 2.2) * 0.9 * look2 * mid);
			}
			if (v_focus > 0.0) {
				// In focus (hovered / selected): a soft halo in the species'
				// colour and a lit membrane; both bloom.
				float f = min(v_focus, 1.0);
				float halo = exp(-max(d, 0.0) * 8.0) * (1.0 - inside);
				o = over(o, mix(base, vec3(1.0), 0.3), halo * 0.42 * f);
				o = over(o, mix(base, vec3(1.0), 0.65), stroke(dpx, lw * 1.7) * 0.9 * f);
				o = over(o, mix(base, vec3(1.0), 0.8), inside * smoothstep(-0.09, 0.0, d) * 0.25 * f);
				glow = max(glow, (halo * 0.7 + stroke(dpx, lw * 2.4)) * v_focus);
			}
			if (grown < 1.0) {
				o = over(o, vec3(1.0), stroke(dpx, lw * 2.5) * (1.0 - grown) * 0.6);
			}
			// Insides: nucleus, then stored-energy organelles and a vacuole.
			vec2 nc = vec2(-0.04, 0.015 * sin(TIME + ph));
			float own_nucleus = 1.0 - bare_nucleus;
			o = over(o, mix(base, vec3(0.45, 0.4, 0.7), 0.4), disc(length(q - nc), 0.07, ppu) * 0.45 * mid * own_nucleus);
			if (detail > 0.0) {
				o = over(o, line, stroke((length(q - nc) - 0.07) * ppu, 0.8) * 0.5 * detail * own_nucleus);
				int count = 2 + int(g_eff * 4.0 + 0.5);
				for (int k = 0; k < 6; k++) {
					if (k >= count) {
						break;
					}
					float fk = float(k);
					float h = hash(vec2(fk, kq));
					float a = h * 6.2832 + TIME * (0.15 + 0.1 * hash(vec2(kq, fk)));
					vec2 c = vec2(cos(a) * 0.62, sin(a) * 0.55) * R * (0.45 + 0.4 * hash(vec2(fk + 7.0, kq)));
					float r = 0.03 + 0.03 * hash(vec2(fk + 3.0, kq));
					vec3 oc = organelle_color(hash(vec2(fk + 11.0, kq)));
					float dc = length(q - c);
					o = over(o, oc, disc(dc, r, ppu) * (0.35 + 0.45 * energy) * inside * detail);
					o = over(o, mix(oc, vec3(1.0), 0.6), disc(dc, r * 0.4, ppu) * 0.6 * inside * detail);
				}
				o = organs_draw(o, int(v_organs + 0.5), p, q, d, dpx, ang, rq, ax, ay, R, ppu, detail, base, line, ph, swp, inside, kq);
				// Neural capacity: a ring of ganglia around the nucleus,
				// more of them for a bigger brain, joined by a fine arc.
				float ng = 2.0 + floor(neural * 6.0 + 0.5);
				float gr = 0.11;
				float ga = atan(q.y - nc.y, q.x - nc.x);
				float gd = length(q - nc);
				float slot = (ga / 6.2832 + 0.5) * ng;
				vec2 gc = nc + vec2(cos((floor(slot) + 0.5) / ng * 6.2832 - 3.1416), sin((floor(slot) + 0.5) / ng * 6.2832 - 3.1416)) * gr;
				o = over(o, mix(base, vec3(0.45, 0.4, 0.75), 0.55), disc(length(q - gc), 0.016, ppu) * 0.75 * detail * own_nucleus);
				o = over(o, mix(base, vec3(0.45, 0.4, 0.75), 0.4), stroke((gd - gr) * ppu, 0.7) * 0.3 * detail * step(0.2, neural) * own_nucleus);
				vec2 vc = vec2(0.08, -0.06);
				o = over(o, line, stroke((length(q - vc) - 0.045) * ppu, 0.8) * 0.35 * inside * detail);
			}
			// Eye spot.
			if (g_vision > 0.3) {
				vec2 ec = vec2(R * 0.62, R * 0.15);
				o = over(o, vec3(0.9, 0.35, 0.25), disc(length(q - ec), 0.018 + 0.022 * g_vision, ppu) * 0.85 * mid);
			}
			// Social cells broadcast: faint signal dots around them.
			if (cohesion > 0.3 && detail > 0.0 && d > 0.02) {
				float sa = ang * 6.0 + TIME * 0.8;
				float sr = 0.07 + 0.03 * sin(TIME * 2.0 + ph);
				float dotd = length(vec2(fract(sa / 6.2832) - 0.5, (d - sr) * 6.0)) * 0.6;
				o = over(o, mix(base, vec3(1.0), 0.3), disc(dotd, 0.02, ppu) * cohesion * 0.6 * detail);
			}
			// Feeding: a morsel is taken in at the front, carried in a food
			// vacuole toward the nucleus and digested away.
			if (state == 1.0 && mid > 0.0) {
				float t = fract(TIME * 0.45 + ph * 0.1);
				vec2 c = mix(vec2(R * 0.8, 0.02), nc + vec2(0.06, -0.03), smoothstep(0.0, 0.6, t));
				float rv = 0.05 * (1.0 - 0.75 * smoothstep(0.35, 1.0, t));
				float dv = length(q - c);
				o = over(o, vec3(0.55, 0.8, 0.42), disc(dv, rv, ppu) * 0.75 * inside);
				o = over(o, vec3(0.92, 0.97, 0.88), stroke((dv - rv - 0.012) * ppu, 0.8) * 0.5 * inside * mid);
			}
			// Bright motes stream in from the food (or the prey) to the nucleus.
			if ((state == 1.0 || state == 7.0) && detail > 0.0) {
				for (int k3 = 0; k3 < 4; k3++) {
					float t = fract(TIME * 0.8 + float(k3) * 0.25 + ph);
					vec2 c = mix(vec2(R * 0.95, 0.0), nc, t) + vec2(0.0, sin(t * 6.0 + float(k3)) * 0.03);
					o = over(o, mix(vec3(0.62, 0.86, 0.45), vec3(1.0, 0.86, 0.5), t), disc(length(q - c), 0.02, ppu) * (1.0 - t * 0.6) * detail);
				}
			}
			// Hurt: a pale flinch and energy leaking out of the wound.
			if (state == 4.0) {
				o = over(o, vec3(1.0), inside * (0.12 + 0.12 * sin(TIME * 30.0 + ph)));
				for (int k4 = 0; k4 < 4; k4++) {
					float t = fract(TIME * 1.6 + float(k4) * 0.25);
					float a = hurt_a + (float(k4) - 1.5) * 0.25;
					vec2 c = vec2(cos(a), sin(a)) * R * (1.0 + 0.45 * t);
					o = over(o, mix(base, vec3(1.0, 0.9, 0.6), 0.5), disc(length(q - c), 0.022 * (1.0 - t), ppu) * (1.0 - t) * mid);
				}
			}
			// Micro tier: the double membrane and its lipid grain, the
			// cytoplasm streaming round, energy flowing in to the nucleus.
			float micro = smoothstep(16.0, 26.0, rpx);
			if (micro > 0.0) {
				o = over(o, line, stroke(dpx + 0.016 * ppu, 0.6) * 0.35 * micro);
				float grain = abs(fract(ang / 6.2832 * 64.0) - 0.5);
				float band = step(-0.016 * ppu, dpx) * step(dpx, 0.0);
				o = over(o, mix(base, vec3(1.0), 0.5), band * smoothstep(0.32, 0.12, grain) * 0.45 * micro);
				for (int k5 = 0; k5 < 10; k5++) {
					float fk = float(k5);
					float rr = R * (0.32 + 0.45 * hash(vec2(fk + 21.0, kq)));
					float a = TIME * (0.35 + 0.25 * hash(vec2(kq, fk + 5.0))) + fk * 0.63;
					vec2 c = nc + vec2(cos(a) * rr * 0.9, sin(a) * rr * 0.7);
					o = over(o, mix(base, vec3(1.0), 0.6), disc(length(q - c), 0.008, ppu) * inside * 0.7 * micro);
				}
				float flow = fract(length(q - nc) * 9.0 - TIME * 0.9);
				o = over(o, mix(vec3(1.0, 0.9, 0.55), base, 0.4), smoothstep(0.08, 0.0, abs(flow - 0.5) - 0.42) * inside * smoothstep(0.07, 0.12, length(q - nc)) * energy * 0.18 * micro);
			}
		}
		}
	} else if (kind > 8.5) {
		// ---------------------------------------------------------- empty shell
		// Left by starvation or old age: a pale, deflating skin that fades as
		// it decomposes. Gentle, never grim.
		// Death as a process, run by how far it has decomposed (life 0..1):
		// stillness and colour draining away, then the membrane cracks, then
		// its pieces drift apart and dissolve with what was inside.
		float fade = v_custom.y;
		float life = 1.0 - fade;
		float drain = smoothstep(0.0, 0.18, life);
		float crack = smoothstep(0.15, 0.45, life);
		float apart = smoothstep(0.42, 1.0, life);
		float ang = atan(p.y, p.x);
		float R = 0.3 * (1.0 - 0.15 * crack);
		vec3 pale = mix(base, vec3(0.78, 0.82, 0.84), 0.55 * drain + 0.15);
		// The membrane in pieces: each piece drifts out a little on its own.
		float nseg = 7.0;
		float fs = ang / 6.2832 * nseg + hash(vec2(kq, 3.0)) * nseg;
		float piece = floor(fs);
		float in_piece = abs(fract(fs) - 0.5);
		float drift = apart * (0.06 + 0.1 * hash(vec2(piece, kq)));
		float rr = length(p);
		float wrinkle = crack * 0.05 * sin(ang * 7.0 + ph) + 0.02 * sin(ang * 3.0 + ph * 2.0);
		float d = rr - R * (1.0 + wrinkle) - drift;
		float dpx = d * ppu;
		float gap = smoothstep(0.5 - 0.22 * crack, 0.5 - 0.22 * crack - 0.05, in_piece);
		float inside = clamp(0.5 - dpx, 0.0, 1.0);
		float alive_a = 1.0 - apart;
		o = over(o, pale, inside * (0.28 * (1.0 - drain) + 0.1) * alive_a);
		o = over(o, pale * 0.8, stroke(dpx, clamp(R * ppu * 0.06, 0.8, 1.6)) * gap * (0.35 + 0.5 * fade) * (1.0 - apart * 0.7));
		// The nucleus shrinks and fades; granules spill out as it falls apart.
		o = over(o, mix(pale, vec3(0.45, 0.4, 0.7), 0.3 * (1.0 - drain)), disc(length(p - vec2(-0.03, 0.02)), 0.06 * (1.0 - crack * 0.7), ppu) * 0.45 * alive_a);
		for (int k = 0; k < 6; k++) {
			float fk = float(k);
			float a = hash(vec2(fk, kq)) * 6.2832;
			vec2 c = vec2(cos(a), sin(a)) * (0.08 + 0.12 * hash(vec2(kq, fk)) + 0.25 * apart);
			o = over(o, pale * 0.85, disc(length(p - c), 0.02 * (1.0 - apart * 0.6), ppu) * 0.5 * fade);
		}
	} else if (kind > 7.5) {
		// ---------------------------------------------------------- algae clump
		// A few small green balls; how many and how big follows its energy.
		float e = v_custom.y;
		float rpx = 0.4 * ppu;
		if (rpx < 3.0) {
			o = over(o, vec3(0.6, 0.82, 0.45), exp(-length(p) * 7.0) * 0.8);
		} else {
			int balls = 3 + int(e * 4.0);
			float spread = 0.12 + 0.14 * e;
			for (int k = 0; k < 7; k++) {
				if (k >= balls) {
					break;
				}
				float fk = float(k);
				float a = hash(vec2(fk, kq)) * 6.2832;
				vec2 c = k == 0 ? vec2(0.0) : vec2(cos(a), sin(a)) * spread * (0.6 + 0.4 * hash(vec2(kq, fk)));
				c += 0.012 * vec2(sin(TIME * 0.9 + fk + ph), cos(TIME * 0.7 + fk * 1.3));
				float br = (0.06 + 0.05 * hash(vec2(fk + 2.0, kq))) * (0.6 + 0.4 * e);
				float dd = length(p - c);
				o = over(o, vec3(0.72, 0.88, 0.56), disc(dd, br, ppu) * 0.85);
				o = over(o, vec3(0.42, 0.64, 0.36), stroke((dd - br) * ppu, 1.0) * 0.75);
				o = over(o, vec3(0.9, 0.97, 0.8), disc(length(p - c + vec2(br * 0.35, br * 0.35)), br * 0.3, ppu) * 0.6);
			}
		}
	} else if (kind > 6.5) {
		// ------------------------------------------------------------ envelope
		// Packed by SimCore: y = wave phase, z = aspect + 2 * k * 100,
		// w = bitten + 2 * amplitude * 10000. The skin follows the same
		// travelling wave as the modules inside it.
		float aspect = mod(v_custom.z, 2.0);
		float wave_k = floor(v_custom.z / 2.0) / 100.0;
		float wave_amp = floor(v_custom.w / 2.0) / 10000.0;
		float bitten_env = mod(v_custom.w, 2.0);
		p.y -= sin(v_custom.y + wave_k * p.x) * wave_amp;
		vec2 q = p / vec2(0.7, 0.7 * aspect);
		float rq = length(q);
		float ang = atan(q.y, q.x);
		float d = (rq - membrane(ang, ph, 1.0)) * 0.7 * min(1.0, aspect);
		float dpx = d * ppu;
		float inside = clamp(0.5 - dpx, 0.0, 1.0);
		float detail = smoothstep(80.0, 140.0, 0.7 * ppu);
		float aura = exp(-max(d, 0.0) * 9.0) * (1.0 - inside);
		o = over(o, mix(base, vec3(1.0), 0.3), aura * 0.14);
		// A fringe of cilia all round the giant.
		if (detail > 0.0 && dpx > -1.0) {
			float n = 70.0;
			float L = 0.045 * ppu;
			float bend = 0.4 * sin(TIME * 9.0 - ang * 12.0 + ph);
			float fa = (ang / 6.2832) * n + bend * clamp(dpx / L, 0.0, 1.0);
			float hair = abs(fract(fa) - 0.5) / n * 6.2832 * rq * 0.7 * ppu;
			o = over(o, line, stroke(hair, 1.0) * step(0.0, dpx) * (1.0 - clamp(dpx / L, 0.0, 1.0)) * 0.7 * detail);
		}
		o = over(o, tint, inside * 0.12);
		o = over(o, base, inside * smoothstep(-0.05, 0.0, d) * 0.1);
		o = over(o, line, stroke(dpx, 1.6) * 0.8);
		if (bitten_env > 0.5) {
			o = over(o, vec3(1.0), inside * 0.3);
		}
	} else {
		// -------------------------------------------------------------- module
		int type = int(kind - 1.0 + 0.5);
		float energy = v_custom.y;
		float speed = v_custom.z;
		float qs = type == 1 ? 3.0 : (type == 3 ? 1.6 : 1.0);
		float R = (type == 2 ? 0.34 : 0.31) / qs;
		float rr = length(p);
		float ang = atan(p.y, p.x);
		float d = rr - membrane(ang, ph, R);
		float dpx = d * ppu;
		float inside = clamp(0.5 - dpx, 0.0, 1.0);
		float detail = smoothstep(7.0, 12.0, R * ppu);
		if (type == 1 && p.x < -0.34) {
			// A long whip rooted at the back edge of the envelope (0.22 local
			// units behind the module), a slow travelling wave tapering to a
			// fine tip, so it never runs across the body.
			float tt;
			float l = wavy(p, -0.34, 0.0, 0.6, 0.12, 9.0, TIME * 6.0, ph, ppu, tt);
			// Fade in over the first stretch, so the root never reads as a
			// line through the body even where the envelope is narrow.
			o = over(o, line, stroke(l, 2.2 - 1.6 * tt) * 0.85 * smoothstep(0.08, 0.3, tt));
		}
		if (type == 3 && p.x > 0.0 && d > -0.01) {
			// A pair of short curved mandibles just ahead of the module.
			float open = 0.4 + 0.18 * sin(TIME * 4.0 + ph);
			float a = abs(atan(p.y, p.x));
			float tip = clamp(d / 0.14, 0.0, 1.0);
			float blade = abs(a - open * (1.0 - tip * 0.6)) * rr * ppu;
			o = over(o, line, stroke(blade, 3.0 - 1.8 * tip) * step(d, 0.14));
		}
		o = over(o, tint, inside * (0.3 + 0.12 * energy));
		o = over(o, base, inside * smoothstep(-0.06, 0.0, d) * 0.22);
		if (type == 2) {
			vec2 a2 = abs(p);
			float hex = max(a2.x * 0.866 + a2.y * 0.5, a2.y) - R * 0.78;
			o = over(o, mix(base, vec3(0.96, 0.9, 0.78), 0.55), clamp(0.5 - hex * ppu, 0.0, 1.0) * inside * 0.35);
			o = over(o, line, stroke(hex * ppu, 1.0) * 0.7);
		}
		o = over(o, line, stroke(dpx, clamp(R * ppu * 0.08, 0.9, 2.0)) * 0.95);
		if (type == 0) {
			o = over(o, mix(base, vec3(0.45, 0.4, 0.7), 0.4), disc(rr, R * 0.4, ppu) * 0.5);
			o = over(o, line, stroke((rr - R * 0.4) * ppu, 0.9) * 0.5 * detail);
		} else if (type == 4) {
			o = over(o, vec3(0.9, 0.35, 0.25), disc(rr, R * 0.28, ppu) * 0.85);
		} else if (type == 5) {
			for (int k = 0; k < 4; k++) {
				float fk = float(k);
				vec2 c = vec2(cos(fk * 1.6 + ph + TIME * 0.2), sin(fk * 1.6 + ph + TIME * 0.2)) * R * 0.45;
				vec3 oc = organelle_color(hash(vec2(fk + 11.0, kq)));
				o = over(o, oc, disc(length(p - c), R * 0.16, ppu) * (0.4 + 0.4 * energy) * inside);
			}
		}
	}

	o.a *= smoothstep(1.0, 0.85, max(abs(ps.x), abs(ps.y)));
	o.a *= 1.0 - 0.45 * analysis;
	if (view_mode == 1) {
		// Species: every body in its species' colour, plainly.
		if (kind < 7.5) {
			o.rgb = mix(o.rgb, v_color.rgb, 0.65 * step(0.01, o.a));
			o.a = min(1.0, o.a * 1.25);
		} else {
			o.a *= 0.25; // algae and shells step back
		}
	} else if (view_mode == 2) {
		o.a *= 0.14; // the heat map is the picture
	}
	if (focus_amt > 0.0) {
		float f = focus_amt;
		float grey = dot(o.rgb, vec3(0.3, 0.55, 0.15));
		// The rest: greyed and thinned, not washed toward white (that read
		// as overexposure). The picked species: its own colour, a little
		// deeper, and only a touch of bloom.
		o.rgb = mix(o.rgb, vec3(grey) * vec3(0.92, 0.97, 1.0), f * (1.0 - v_match) * 0.75);
		o.a *= mix(1.0, mix(0.32, 1.0, v_match), f);
		o.rgb = mix(o.rgb, mix(o.rgb, v_color.rgb * 0.82, 0.45), f * v_match);
		o.a = mix(o.a, min(1.0, o.a * 1.2), f * v_match);
		glow += 0.12 * f * v_match * step(0.01, o.a);
	}
	if (night > 0.0 && o.a > 0.0) {
		bool algae = kind > 7.5 && kind < 8.5;
		vec3 nrgb = night_glow(o.rgb, algae ? vec3(0.55, 0.85, 0.4) : base);
		float na = min(1.0, o.a * 1.3);
		if (kind > 8.5) {
			nrgb *= 0.5;
			na = o.a * 0.7;
		}
		o.rgb = mix(o.rgb, nrgb, night);
		o.a = mix(o.a, na, night);
		glow += 0.5 * night;
	}
	if (night > 0.0 && kind < 1.0 && ((int(v_organs + 0.5) >> 12) & 1) == 1) {
		// Light-eaters: a warm halo under the body.
		float r = length(ps);
		float ha = exp(-max(r - 0.3, 0.0) / 0.13) * 0.42 * (1.0 - smoothstep(0.8, 1.0, r)) * (1.0 - o.a) * night;
		vec3 hc = vec3(1.0, 0.66, 0.36);
		float oa = o.a + ha;
		o.rgb = (o.rgb * o.a + hc * ha) / max(oa, 1e-4);
		o.a = oa;
	}
	vec3 lin = pow(o.rgb, vec3(2.2));
	lin *= 1.0 + glow * 0.6; // above 1: blooms
	COLOR = vec4(lin, o.a);
}
