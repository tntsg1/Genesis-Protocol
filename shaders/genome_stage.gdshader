// The life designer's genome stage: a giant holographic DNA double helix
// across the lab, drawn per pixel in flat light (no volume). Graphite and
// steel; the only colour is the accent on the selected gene. Two backbones
// with a hot thread down the near one and data motes flowing along them,
// base pairs as fine grey rungs with atom nodes, gene segments between dashed
// brackets (the flanks are non-coding DNA, fainter), a scan beam, the lab
// grid. The strand travels along its axis (shift) to bring the selected
// gene to the middle, where a lens swells it (focus_x); its highlight wipes
// across it, and a level change flashes it (pulse) while the gene's stretch
// of DNA is cut out and peeled away and the new level's pressed in
// (backbone(), rungs()). The mouse is a second,
// smaller lens that lights the base pairs around it; a click sends a ripple
// along the strand; the room shifts a little with the mouse (parallax);
// while the strand runs, dust streaks show its speed. Labels are drawn on the CPU (scripts/ui/designer.gd),
// which mirrors lens(). Positions are screen pixels.
shader_type canvas_item;
render_mode blend_mix, unshaded;

uniform vec2 size = vec2(1920.0, 1080.0);
uniform vec2 center = vec2(946.0, 500.0);
uniform float len = 2600.0;    // the whole strand; its ends fade under the panels
uniform float coding = 2880.0; // the eight genes, in the middle
uniform float shift = 0.0;     // strand position at the view centre
uniform float amp = 150.0;
uniform float angle = -0.15;
uniform float wavelength = 250.0;
uniform float phase = 0.0;
uniform float reveal = 1.0;    // 0..1: the strand unrolls from the middle
// Each gene's base pairs: how many and which sequence (n_new, v_new), the
// set being pulled out by an edit (n_old, v_old), seconds since the edit.
uniform float n_new[8];
uniform float v_new[8];
uniform float n_old[8];
uniform float v_old[8];
uniform float edit_t[8];
uniform float pulse[8];        // 1 right after a level change, decays to 0
// Organ insertion sites right of the genes (designer.gd): how many, where
// they start, each one's width; per site the organ in it (Organs.LIST index,
// -1 empty), the one being lifted out, seconds since it changed.
uniform int organ_sites = 0;
uniform float organ_x0 = 1530.0;
uniform float organ_w = 260.0;
uniform float organ_id[4];
uniform float organ_old[4];
uniform float organ_t[4];
const float ORGAN_PAIRS = 8.0;
const float ORGAN_PAD = 34.0;
uniform int hover = -1;
uniform int sel = 0;
uniform float focus_x = 0.0;   // axis position the lens sits on
uniform float wipe = 1.0;      // 0..1: the selection sweeping across its gene
uniform float fade = 1.0;
uniform vec2 mouse = vec2(-9999.0);  // screen px
uniform float mouse_on = 0.0;        // eased 0..1 while over the strand
uniform float ripple_x = 0.0;        // strand x of the last click
uniform vec2 ripple_p = vec2(-9999.0);
uniform float ripple_t = 99.0;       // seconds since that click
uniform float speed = 0.0;           // 0..1, how fast the strand is running
uniform vec2 parallax = vec2(0.0);

const float GROOVE = 2.5;
const vec3 INK = vec3(0.17, 0.22, 0.26);
const vec3 STEEL = vec3(0.5, 0.56, 0.6);
const vec3 ACCENT = vec3(0.04, 0.62, 0.72);
const vec3 GLOW = vec3(0.1, 0.78, 0.9);
// A gene edit (timing mirrored in scripts/ui/designer.gd): both backbones
// are cut at the gene's ends, then the old stretch - backbones and base
// pairs - peels up and away from left to right like tape, and the new
// level's stretch presses in right behind it from below, overshooting a
// touch, and joins at the ends.
const float CUT = 0.08;  // the cut flashes before anything moves
const float STAG = 0.4;  // the peel's run from the gene's left end to its right
const float PULL = 0.3;  // one point of the old stretch lifting away
const float LEAD = 0.14; // the new stretch follows this far behind
const float INS = 0.3;   // one point of it pressing in
const float EDIT_END = CUT + LEAD + STAG + INS;

vec4 over(vec4 o, vec3 c, float a) {
	a = clamp(a, 0.0, 1.0);
	float out_a = a + o.a * (1.0 - a);
	vec3 rgb = (c * a + o.rgb * o.a * (1.0 - a)) / max(out_a, 1e-4);
	return vec4(rgb, out_a);
}

// Amplitude multiplier: the focused gene swells, the rest settles back.
float lens(float x) {
	float s = coding / 8.0;
	return 0.86 + 0.34 * exp(-pow((x - focus_x) / (s * 0.85), 2.0));
}

// The swell at x from the lens, the mouse and a passing ripple.
float swell(float x, float mx) {
	float m = 1.0 + 0.22 * mouse_on * exp(-pow((x - mx) / 150.0, 2.0));
	float rb = exp(-ripple_t * 2.2) * exp(-pow((abs(x - ripple_x) - ripple_t * 1100.0) / 70.0, 2.0));
	return lens(x) * m * (1.0 + 0.4 * rb);
}

// Progress of the peel (old) and the press (new) at fraction f of the gene.
float lift_u(float f, float t) {
	return clamp((t - CUT - f * STAG) / PULL, 0.0, 1.0);
}

float press_u(float f, float t) {
	return clamp((t - CUT - LEAD - f * STAG) / INS, 0.0, 1.0);
}

// Offsets across the strand: the old stretch lifts away (accelerating), the
// new comes up from below and settles with a slight overshoot.
float lift_off(float u) {
	return -amp * 2.2 * u * u;
}

float press_off(float u) {
	float v = u - 1.0;
	return -amp * 2.2 * (2.4 * v * v * v + 1.4 * v * v);
}

// One backbone at local x: th its helix angle, depth 0 far .. 1 near; off
// and off_d a stretch moved by an edit (offset across the strand and its
// slope), hot while it moves, a its opacity.
vec4 backbone(vec4 o, float x, float y, float th, float depth, float a_x, float k, float off, float off_d,
		float lit, float flash, float hot, float a, bool second) {
	if (a < 0.003) {
		return o;
	}
	float sy = a_x * sin(th) + off;
	float dy = a_x * k * cos(th) + off_d;
	float dist = abs(y - sy) / sqrt(1.0 + dy * dy);
	vec3 rim = mix(GLOW, ACCENT, lit);
	o = over(o, rim, (exp(-dist / 5.0) * (0.22 + 0.25 * lit + 0.3 * flash + 0.3 * hot) + exp(-dist / 18.0) * (0.04 + 0.05 * hot)) * a);
	vec3 core_c = mix(mix(mix(STEEL, INK, depth), ACCENT, lit * 0.85), GLOW, hot * 0.6);
	o = over(o, core_c, clamp(0.9 + 1.1 * depth - dist, 0.0, 1.0) * a);
	// A hot white thread down the middle of the near backbone.
	o = over(o, vec3(1.0), clamp(0.6 - dist, 0.0, 1.0) * depth * depth * 0.85 * a);
	// Data motes flowing along the backbones.
	float u = fract((x - TIME * 95.0 + (second ? 70.0 : 0.0)) / 190.0);
	float mote = clamp(3.2 - abs(u - 0.5) * 190.0, 0.0, 1.0) * clamp(2.6 - dist, 0.0, 1.0) * smoothstep(0.35, 0.8, depth);
	o = over(o, GLOW, mote * 0.9 * a);
	o = over(o, vec3(1.0), mote * 0.6 * a);
	return o;
}

// One set of base pairs over a segment [x0, x0 + seg_w]: n pairs of
// sequence version ver. mode 0 sits still, 1 peels away, 2 presses in; t
// is the time since the gene's edit. Rungs with atom nodes at the ends.
vec4 rungs(vec4 o, float x, float y, float mx, float my, int gi, float x0, float seg_w, float in_coding,
		float n, float ver, int mode, float t, float is_sel, float flash, float sx, float vis) {
	n = max(n, 1.0);
	float jf = clamp(floor((x - x0) / seg_w * n), 0.0, n - 1.0);
	float xj = x0 + seg_w * (jf + 0.5) / n;
	float aj = amp * swell(xj, mx);
	float thj = 6.2832 / wavelength * xj + phase;
	float y1 = aj * sin(thj);
	float y2 = aj * sin(thj + GROOVE);
	float dj = 0.5 + 0.5 * cos(thj + GROOVE * 0.5);
	// The edit slides the rung along its own line, out past a backbone.
	float off = 0.0;
	float shown = 1.0;
	float hot = 0.0;
	float lock = 0.0;
	// The pair rides its stretch of backbone.
	float fj = (xj - x0) / seg_w;
	if (mode == 1) {
		float u = lift_u(fj, t);
		off = lift_off(u);
		shown = 1.0 - smoothstep(0.4, 1.0, u);
		hot = step(0.001, u);
	} else if (mode == 2) {
		float u = press_u(fj, t);
		off = press_off(u);
		shown = smoothstep(0.0, 0.3, u);
		hot = 1.0 - u;
		float since = t - CUT - LEAD - fj * STAG - INS;
		lock = step(0.0, since) * exp(-since / 0.14);
	}
	if (shown < 0.004) {
		return o;
	}
	float e1 = y1 + off;
	float e2 = y2 + off;
	float mid = (e1 + e2) * 0.5;
	float pair_lit = is_sel * step(xj, x0 + seg_w * wipe);
	float w = 0.6 + 0.5 * dj + 0.5 * pair_lit + 0.6 * flash + 0.6 * hot;
	float cov = clamp(w + 0.5 - abs(x - xj), 0.0, 1.0)
		* clamp(min(y - min(e1, e2), max(e1, e2) - y) + 0.5, 0.0, 1.0);
	// Tone by base (A–T light, G–C dark), as on the CPU (GenomeArt.base_of).
	uint h = in_coding > 0.5 ? (uint(gi) * 73856093u) ^ (uint(int(jf)) * 19349663u) ^ (uint(int(ver)) * 83492791u)
		: uint(int(x0 / 18.0) + 100000) * 2654435761u >> 7u;
	h = (h ^ (h >> 16u)) * 0x45d9f3bu;
	h ^= h >> 16u;
	int b = int(h & 3u);
	bool near_y1 = (y - mid) * (e1 - mid) > 0.0;
	float tone = (b < 2) == near_y1 ? 0.0 : 1.0;
	vec3 rc = mix(mix(STEEL, INK, 0.25 + 0.5 * tone), mix(ACCENT, GLOW, tone * 0.5), pair_lit);
	rc = mix(rc, GLOW, max(flash * 0.6, max(hot * 0.75, lock)));
	float near_beam = exp(-abs(xj - sx) / 18.0);
	float prox = mouse_on * exp(-length(vec2(xj - mx, mid - my)) / 85.0);
	rc = mix(rc, GLOW, prox * 0.75);
	pair_lit = max(pair_lit, max(prox * 0.8, max(hot, lock)));
	float ra = (0.35 + 0.55 * dj) * (0.6 + 0.4 * max(pair_lit, flash)) * (0.4 + 0.6 * in_coding) + 0.45 * near_beam + 0.5 * prox;
	o = over(o, rc, cov * ra * vis * shown);
	// A moving pin glows, with a short trail behind it (both sets move up).
	if (hot > 0.001) {
		float lo = min(e1, e2);
		float hi = max(e1, e2);
		float tail = 60.0;
		float along_pin = step(lo, y) * (y < hi ? 1.0 : clamp(1.0 - (y - hi) / tail, 0.0, 1.0));
		o = over(o, GLOW, exp(-abs(x - xj) / 4.0) * along_pin * hot * 0.45 * vis * shown);
	}
	// Atom nodes where the pair meets a backbone (they travel with a pulled
	// pin and flare as a new one locks in).
	float r = 1.5 + 1.1 * dj + 0.7 * pair_lit + 2.0 * lock;
	for (int e = 0; e < 2; e++) {
		float nd = length(vec2(x, y) - vec2(xj, e == 0 ? e1 : e2));
		float na = vis * shown * (0.45 + 0.55 * dj);
		o = over(o, mix(GLOW, ACCENT, pair_lit), exp(-nd / (3.0 + 5.0 * lock)) * (0.25 + 0.3 * pair_lit + 0.5 * lock) * na);
		o = over(o, mix(INK, ACCENT, pair_lit), clamp(r + 1.3 - nd, 0.0, 1.0) * na);
		o = over(o, vec3(1.0), clamp(r - 0.2 - nd, 0.0, 1.0) * na);
	}
	return o;
}

void fragment() {
	vec2 p = UV * size;
	float t = TIME;
	vec2 d = p - center;
	float ca = cos(angle);
	float sa = sin(angle);
	// Local frame: x along the helix axis, y across it.
	float vx = d.x * ca + d.y * sa; // along the axis, from the view centre
	float x = vx + shift;           // along the strand
	float y = -d.x * sa + d.y * ca;
	vec4 o = vec4(0.0);
	vec2 dm = mouse - center;
	float mx = dm.x * ca + dm.y * sa + shift;
	float my = -dm.x * sa + dm.y * ca;

	// The room: scanlines, lab grid (a little parallax with the mouse).
	o = over(o, GLOW, step(0.5, fract(p.y / 3.0)) * 0.012);
	vec2 pg = p + parallax * 0.5;
	vec2 g = abs(fract(pg / 40.0 - 0.5) - 0.5) * 40.0;
	vec2 gm = abs(fract(pg / 200.0 - 0.5) - 0.5) * 200.0;
	o = over(o, INK, clamp(1.0 - min(g.x, g.y), 0.0, 1.0) * 0.035 + clamp(1.3 - min(gm.x, gm.y), 0.0, 1.0) * 0.06);

	float half_len = len * 0.5;
	float shown = reveal * 1150.0; // unrolls across the view
	float rv = smoothstep(shown + 2.0, shown - 30.0, abs(vx)) * step(0.001, reveal)
		* smoothstep(half_len, half_len - 400.0, abs(x));
	float a_x = amp * swell(x, mx);
	float haze = exp(-pow(y / (a_x * 1.5), 2.0)) * exp(-pow((x - focus_x) / 520.0, 2.0));
	o = over(o, GLOW, haze * 0.07 * rv);

	float inside = step(abs(x), half_len);
	float half_c = coding * 0.5;
	float in_coding = step(abs(x), half_c);
	float seg = coding / 8.0;
	int gi = clamp(int(floor((x + half_c) / seg)), 0, 7);
	float x0 = in_coding > 0.5 ? -half_c + seg * float(gi) : floor(x / 18.0) * 18.0;
	float seg_w = in_coding > 0.5 ? seg : 18.0;
	float flash = pulse[gi] * in_coding;
	// Selection: the gene, and how far its highlight has wiped across.
	float is_sel = (sel == gi ? 1.0 : 0.0) * in_coding;
	float lit = is_sel * smoothstep(x0 + seg * wipe + 2.0, x0 + seg * wipe - 24.0, x);
	float hov = (hover == gi ? 1.0 : 0.0) * in_coding * (1.0 - is_sel);

	// Gene segments: a faint band on the selected / hovered one, solid accent
	// edges on the selected, dashed brackets between genes, a faint axis.
	float band = in_coding * smoothstep(a_x * 1.32, a_x * 1.25, abs(y));
	float soft = in_coding * exp(-pow(y / (a_x * 0.95), 2.0));
	o = over(o, GLOW, soft * (lit * 0.1 + hov * 0.06 + flash * 0.16) * rv);
	float edge = clamp(1.4 - min(abs(x - x0), abs(x0 + seg - x)), 0.0, 1.0);
	o = over(o, ACCENT, edge * band * is_sel * 0.9 * rv);
	float m = abs(fract((x + half_c) / seg + 0.5) - 0.5) * seg;
	float bracket = clamp(1.2 - m, 0.0, 1.0) * step(abs(y), a_x * 1.45) * step(0.45, fract(y / 7.0)) * step(abs(x), half_c + 1.0);
	o = over(o, INK, bracket * 0.35 * rv);
	o = over(o, INK, clamp(1.0 - abs(y), 0.0, 1.0) * 0.12 * inside * rv);

	// Speed streaks while the strand runs: dust anchored to the strand.
	float row = floor(y / 9.0);
	float rh = fract(sin(row * 91.7) * 43758.5);
	float su = fract(x * 0.0021 + rh * 7.0);
	float streak = step(0.8, rh) * smoothstep(0.0, 0.5, su) * (1.0 - smoothstep(0.5, 0.56, su))
		* clamp(1.0 - abs(fract(y / 9.0) - 0.5) * 4.0, 0.0, 1.0) * smoothstep(340.0, 180.0, abs(y));
	o = over(o, GLOW, streak * speed * 0.35 * rv);
	// The click ripple's ring.
	float rr = length(p - ripple_p) - ripple_t * 520.0;
	o = over(o, GLOW, exp(-abs(rr) / 3.0) * exp(-ripple_t * 3.0) * 0.6);

	// The scan beam, sweeping along the strand.
	float sx = shift - 700.0 + fract(t * 0.12) * 1400.0;
	float beam = exp(-abs(x - sx) / 5.0) * smoothstep(a_x * 1.7, a_x * 1.2, abs(y)) * inside;
	o = over(o, GLOW, beam * 0.3 * rv);

	float k = 6.2832 / wavelength;
	float th0 = k * x + phase;
	float dep0 = 0.5 + 0.5 * cos(th0);
	float dep1 = 0.5 + 0.5 * cos(th0 + GROOVE);
	// An edit in this gene: its time, and where along the gene this column is.
	float te = in_coding > 0.5 ? edit_t[gi] : 99.0;
	float fx = clamp((x - x0) / seg_w, 0.0, 1.0);
	bool editing = te < EDIT_END;
	float u_old = lift_u(fx, te);
	float u_new = press_u(fx, te);
	// The moving stretches' slope, from their offsets a pixel either side.
	float fd = 1.0 / seg_w;
	float d_old = (lift_off(lift_u(fx + fd, te)) - lift_off(lift_u(fx - fd, te))) * 0.5;
	float d_new = (press_off(press_u(fx + fd, te)) - press_off(press_u(fx - fd, te))) * 0.5;
	for (int s = 0; s < 2; s++) {
		bool second = (dep0 < dep1) == (s == 0);
		float th = th0 + (second ? GROOVE : 0.0);
		float depth = second ? dep1 : dep0;
		float a = (0.25 + 0.75 * depth) * inside * rv;
		if (!editing) {
			o = backbone(o, x, y, th, depth, a_x, k, 0.0, 0.0, lit, flash, 0.0, a, second);
		} else {
			if (u_old < 1.0) {
				o = backbone(o, x, y, th, depth, a_x, k, lift_off(u_old), d_old, lit, flash,
					step(0.001, u_old), a * (1.0 - smoothstep(0.4, 1.0, u_old)), second);
			}
			o = backbone(o, x, y, th, depth, a_x, k, press_off(u_new), d_new, lit, flash,
				1.0 - u_new, a * smoothstep(0.0, 0.3, u_new), second);
		}
		if (s == 0) {
			// Base pairs sit between the backbones: after the far one. A
			// gene being edited draws the set going out and the set coming in.
			float vis = inside * rv;
			if (in_coding > 0.5) {
				if (te < CUT + STAG + PULL) {
					o = rungs(o, x, y, mx, my, gi, x0, seg_w, in_coding, n_old[gi], v_old[gi], 1, te, is_sel, flash, sx, vis);
				}
				o = rungs(o, x, y, mx, my, gi, x0, seg_w, in_coding, n_new[gi], v_new[gi], 2, te, is_sel, flash, sx, vis);
			} else {
				// An organ site: its organ's pairs (in the accent) or a gap,
				// framed; the flanks keep the plain non-coding rungs.
				float sf = (x - organ_x0) / organ_w;
				int si = clamp(int(floor(sf)), 0, 3);
				bool site = organ_sites > 0 && sf >= 0.0 && si < organ_sites;
				float sx0 = organ_x0 + organ_w * float(si) + ORGAN_PAD;
				float sw = organ_w - 2.0 * ORGAN_PAD;
				bool inner = site && x >= sx0 && x <= sx0 + sw;
				if (inner) {
					float te = organ_t[si];
					float now_id = organ_id[si];
					float was_id = organ_old[si];
					if (was_id >= 0.0 && te < CUT + STAG + PULL) {
						o = rungs(o, x, y, mx, my, 8 + si, sx0, sw, 1.0, ORGAN_PAIRS, was_id * 7.0 + 3.0, 1, te, 1.0, 0.0, sx, vis);
					}
					if (now_id >= 0.0) {
						o = rungs(o, x, y, mx, my, 8 + si, sx0, sw, 1.0, ORGAN_PAIRS, now_id * 7.0 + 3.0, 2, te, 1.0, 0.0, sx, vis);
					}
					// The site's frame: brackets at its ends, a faint band; an
					// empty one dashed down the middle, waiting.
					float a_s = amp * swell(x, mx);
					float edge = clamp(1.4 - min(abs(x - sx0), abs(sx0 + sw - x)), 0.0, 1.0);
					float tall = step(abs(y), a_s * 1.35);
					o = over(o, ACCENT, edge * tall * step(0.4, fract(y / 6.0)) * (now_id >= 0.0 ? 0.8 : 0.5) * vis);
					o = over(o, GLOW, tall * (now_id >= 0.0 ? 0.035 : 0.02) * vis);
					if (now_id < 0.0) {
						float dash = step(0.5, fract(x / 10.0)) * clamp(1.2 - abs(y), 0.0, 1.0);
						o = over(o, ACCENT, dash * 0.45 * vis);
					}
				} else {
					o = rungs(o, x, y, mx, my, gi, x0, seg_w, in_coding, 1.0, 0.0, 0, 99.0, is_sel, flash, sx, vis);
				}
			}
		}
	}
	// The cuts and joins: a flare on both backbones at the gene boundary
	// nearest this pixel, for an edit of the gene on either side of it.
	if (abs(x) < half_c + 60.0) {
		float bi = clamp(floor((x + half_c) / seg + 0.5), 0.0, 8.0);
		float xb = -half_c + seg * bi;
		float fl = 0.0;
		for (int side = 0; side < 2; side++) {
			// The gene this boundary is the right end of (side 0) / left end of (side 1).
			int gb = int(bi) - 1 + side;
			if (gb < 0 || gb > 7) {
				continue;
			}
			float tb = edit_t[gb];
			float cut = exp(-tb / 0.1) * step(tb, EDIT_END);
			float tj = CUT + LEAD + INS + (side == 0 ? STAG : 0.0);
			float join = step(tj, tb) * exp(-(tb - tj) / 0.12);
			fl = max(fl, max(cut, join));
		}
		if (fl > 0.003) {
			float ab = amp * swell(xb, mx);
			float thb = k * xb + phase;
			for (int e = 0; e < 2; e++) {
				float yb = ab * sin(thb + (e == 1 ? GROOVE : 0.0));
				float nd = length(vec2(x - xb, y - yb));
				o = over(o, GLOW, exp(-nd / 9.0) * fl * 0.8 * rv);
				o = over(o, vec3(1.0), clamp(4.0 * fl - nd, 0.0, 1.0) * fl * rv);
			}
		}
	}

	// Data motes drifting up through the room.
	vec2 cell = vec2(56.0);
	vec2 pc = p + parallax * 1.4 + vec2(0.0, t * 11.0);
	vec2 id = floor(pc / cell);
	uvec2 q = uvec2(ivec2(id) + 4096) * uvec2(1597334673u, 3812015801u);
	float hsh = float((q.x ^ q.y) * 1597334673u) / 4294967296.0;
	if (hsh < 0.2) {
		vec2 mp = (id + vec2(fract(hsh * 37.0), fract(hsh * 91.0))) * cell;
		float md = length(pc - mp);
		float tw = 0.5 + 0.5 * sin(t * 2.0 + hsh * 40.0);
		o = over(o, GLOW, clamp(1.4 - md, 0.0, 1.0) * (0.3 + 0.3 * tw));
	}
	COLOR = vec4(pow(o.rgb, vec3(2.2)), o.a * fade * COLOR.a);
}
