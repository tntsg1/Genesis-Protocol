shader_type canvas_item;
// One block of a colony (level 21, Volvox), or a grain of grit. A flagellum
// block is a patch of small cells with a pair of whips on each open side,
// beating in a wave along the rim; walled in, they lie still and pale. A germ
// block is one big cell, a gonidium; once it starts, it grows a new colony the
// way Volvox carteri does (see embryo() below): eleven cleavages, the sixth of
// them setting aside 16 big gonidia, into a hollow ball with a cross-shaped
// opening; the ball turns itself inside out through it; then the young one
// grows, its whips outside, turning in its pocket. Level 22 (tardigrade): an
// armour block is cuticle, translucent plates laid over each other, thickest
// on its open sides, a bite leaving a dent that heals; a store block is a cell
// packed with oil droplets that shrink away, and it with them, as it is drawn on.
// COLOR.a = how hard the body swims. INSTANCE_CUSTOM (arrives clamped to 0..1):
// x = (kind + 8 * open sides) / 128 (kind 0 flagella, 1 germ, 2 grit, 3 armour,
// 4 store; sides: bit 0 front, 1 back, 2 +y, 3 -y), y = phase, z = the germ's
// embryo 0..1 / the armour's fresh bite / how full the store is, w = how far
// gone the shell is (0 = alive). Level 23: a live block's harm rides in w
// instead (0.5..0.74 armour cracked, 0.75..1 broken and regrowing, 1 = just
// broken), a ghost's fade being 0..0.49; a regeneration block (kind 5) is a
// pack of stem cells (neoblasts), and a broken block grows back out of a pale
// bud (a blastema) on the wound, as a planarian's does.

uniform float px = 0.1; // one screen pixel in world units
uniform float dark = 0.0; // 1 on the bench's darkfield: edges scatter light
uniform vec4 seeds[126]; // Colony.embryo_seeds(): the cells, cleavage by cleavage
uniform vec3 gon[16]; // Colony.embryo_gonidia()

varying vec4 v_c;
varying vec4 v_col;
varying vec2 v_q;
varying float v_side;
varying vec4 v_i0; // the inverting sheet (see inversion()), worked out per block
varying vec4 v_i1;
varying float v_cy;

const float B = 0.4545; // half a block in quad units (a quad is 2.2 blocks)

// The embryo's clock (custom z): cleavage to E_CLEAVE, inversion to
// E_INVERT, then growing until it hatches.
const float E_CLEAVE = 0.5;
const float E_INVERT = 0.7;
const float R_GERM = 0.3; // the gonidium's radius, quad units
const float R_INV = 0.28; // a unit of the inverting sheet, quad units
const float R_GROWN = 0.41;
const float K_SHEET = 2.2; // how much light a unit of cell sheet takes
const float H_SHEET = 0.07; // the cell sheet's thickness once cleaved, unit sphere
const float R_GON = 0.2; // a gonidium's angular radius on the sphere

// The inverting sheet, seen cut along its axis: arc length from the posterior
// pole (on the axis, heading out) to the lip of the opening, LM on the unit
// sphere. Three arcs: the part not yet turned (curving one way), the fold
// (WB of sheet bent right over, outwards) and the part already turned
// (curving the other way). The lips curl out and back until they meet behind
// the posterior half (at TM); that half, shrunk, is then pulled through the
// ring, which closes over it. The constants make the two stages meet:
// SBM = (LM - WB) / (1 + CPM (1 + 2 WB / (PI RIM))), A1M = SBM CPM / RIM,
// ROM = (LM - SBM - WB) / A1M.
const float LM = 2.9415927;
const float WB = 0.4;
const float TM = 0.55;
const float RIM = 0.6; // the unturned half's radius when the lips meet
const float CPM = 0.78; // and how far it has drawn together
const float SBM = 1.2039516;
const float A1M = 1.5651370;
const float ROM = 0.8546479;
const int N_UN = 36; // steps along each arc
const int N_FOLD = 16;
const int N_TURNED = 40;

vec2 arc(float a, float l, float k) {
	float h = 0.5 * k * l;
	float sc = abs(h) < 1e-3 ? 1.0 : sin(h) / h;
	return l * sc * vec2(cos(a + h), sin(a + h));
}

// tau 0..1 -> (length, curvature) of the unturned part and the fold in i0,
// of the turned part in i1.xy; i1.zw = how much sheet the first two hold.
void inversion(float tau, out vec4 i0, out vec4 i1) {
	if (tau <= TM) {
		float u = tau / TM;
		float sb = LM - (LM - SBM) * u;
		float m = sin(1.5707963 * u);
		float ri = 1.0 - (1.0 - RIM) * m;
		float cp = 1.0 - (1.0 - CPM) * m;
		float bl = WB * min(1.0, (LM - sb) / WB);
		float ro = 1.0 + (ROM - 1.0) * u;
		i0 = vec4(sb * cp, 1.0 / ri, bl, -PI / WB);
		i1 = vec4(max(0.0, LM - sb - WB), -1.0 / ro, sb, bl);
	} else {
		float u = (tau - TM) / (1.0 - TM);
		float a1 = A1M * pow(1.0 - u, 1.2);
		float ri = RIM + (1.0 - RIM) * u;
		float wl = WB * (1.0 - u);
		float sb = SBM * (1.0 - u);
		float lp = LM - sb - wl;
		// The ring where the turned part starts: just where it closes on the axis.
		float lo = 1e-4;
		float hi = PI - 1e-4;
		for (int k = 0; k < 18; k++) {
			float al = 0.5 * (lo + hi);
			float f = lp * sin(al) / (PI - al) - ri * sin(a1) - wl * (sin(al) + sin(a1)) / max(al + a1, 1e-5);
			if (f > 0.0) {
				hi = al;
			} else {
				lo = al;
			}
		}
		float al = 0.5 * (lo + hi);
		i0 = vec4(ri * a1, 1.0 / ri, wl, (-al - a1) / max(wl, 1e-4));
		i1 = vec4(lp, -(PI - al) / lp, sb, wl);
	}
}

void vertex() {
	v_c = INSTANCE_CUSTOM;
	v_col = COLOR;
	v_q = VERTEX;
	v_side = max(length(MODEL_MATRIX[0].xy), 1e-3);
	vec4 i0 = vec4(0.0);
	vec4 i1 = vec4(0.0);
	float cy = 0.0;
	float e = INSTANCE_CUSTOM.z;
	if ((int(round(INSTANCE_CUSTOM.x * 128.0)) & 7) == 1 && (INSTANCE_CUSTOM.w < 0.01 || INSTANCE_CUSTOM.w >= 0.5) && e >= E_CLEAVE && e < E_INVERT) {
		inversion((e - E_CLEAVE) / (E_INVERT - E_CLEAVE), i0, i1);
		// Centre the shape: walk it once, coarsely.
		vec2 P = vec2(0.0);
		float a = 0.0;
		float lo = 0.0;
		float hi = 0.0;
		for (int k = 0; k < 30; k++) {
			float l = k < 10 ? i0.x / 10.0 : (k < 16 ? i0.z / 6.0 : i1.x / 14.0);
			float kap = k < 10 ? i0.y : (k < 16 ? i0.w : i1.y);
			P += arc(a, l, kap);
			a += kap * l;
			lo = min(lo, P.y);
			hi = max(hi, P.y);
		}
		cy = 0.5 * (lo + hi);
	}
	v_i0 = i0;
	v_i1 = i1;
	v_cy = cy;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec3 hash3(vec3 p) {
	p = vec3(dot(p, vec3(127.1, 311.7, 74.7)), dot(p, vec3(269.5, 183.3, 246.1)), dot(p, vec3(113.5, 271.9, 124.6)));
	return fract(sin(p) * 43758.5453);
}

vec4 over(vec4 o, vec3 c, float a) {
	float oa = a + o.a * (1.0 - a);
	return vec4((c * a + o.rgb * o.a * (1.0 - a)) / max(oa, 1e-4), oa);
}

mat2 rot(float a) {
	return mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a)));
}

// One whip, rooted at x = 0 on the block's edge, reaching out along +x.
float whip(vec2 q, float y0, float beat, float ppu, float swim) {
	float l = 0.46;
	float t = q.x / l;
	if (t < 0.0 || t > 1.0) {
		return 0.0;
	}
	float amp = (0.03 + 0.08 * swim) * t;
	float y = y0 + amp * sin(9.0 * t - beat) + 0.03 * t * t * sin(beat * 0.5);
	float d = abs(q.y - y) * ppu;
	return clamp(mix(1.25, 0.45, t) + 0.5 - d, 0.0, 1.0) * (1.0 - t * t);
}

// How far M is past the plane between cells s1 and s2 (unit vectors), on s1's side.
float split(vec3 M, vec3 s1, vec3 s2) {
	vec3 d = s1 - s2;
	float l = length(d);
	return l < 1e-4 ? 9.0 : dot(M, d) / l;
}

// The two nearest of a jittered lattice's points pushed onto the sphere: about
// 4 PI F^2 / 1.6 cells; jit = how far the points stray from the lattice.
void worley(vec3 M, float F, float jit, out vec3 s1, out vec3 s2) {
	vec3 X = M * F;
	vec3 i0 = floor(X);
	float b1 = -2.0;
	float b2 = -2.0;
	s1 = M;
	s2 = -M;
	for (int z = -1; z <= 1; z++) {
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec3 id = i0 + vec3(float(x), float(y), float(z));
				vec3 s = normalize(id + 0.5 + jit * (hash3(id) - 0.5));
				float d = dot(M, s);
				if (d > b1) {
					b2 = b1;
					s2 = s1;
					b1 = d;
					s1 = s;
				} else if (d > b2) {
					b2 = d;
					s2 = s;
				}
			}
		}
	}
}

float lattice(int n) {
	return sqrt(1.6 * pow(2.0, float(n)) / (4.0 * PI));
}

// The listed cells of level n <= 6 (see cells()).
void listed(vec3 M, int n, float sep, out vec3 own, out vec3 sis, out vec3 other, out vec3 mother) {
	int c = 1 << n;
	int o = c - 2;
	int op = (c >> 1) - 2;
	float b1 = -9.0;
	float b2 = -9.0;
	float b3 = -9.0;
	int i1 = 0;
	int i2 = 0;
	int i3 = 0;
	for (int j = 0; j < 64; j++) {
		if (j >= c) {
			break;
		}
		vec3 s = seeds[o + j].xyz;
		if (n > 1) {
			s = normalize(mix(seeds[op + (j >> 1)].xyz, s, sep));
		}
		float d = dot(M, s);
		if (d > b1) {
			b3 = b2;
			i3 = i2;
			b2 = b1;
			i2 = i1;
			b1 = d;
			i1 = j;
		} else if (d > b2) {
			b3 = b2;
			i3 = i2;
			b2 = d;
			i2 = j;
		} else if (d > b3) {
			b3 = d;
			i3 = j;
		}
	}
	int io = (i2 ^ 1) == i1 ? i3 : i2;
	int is = i1 ^ 1;
	if (n > 1) {
		mother = seeds[op + (i1 >> 1)].xyz;
		own = normalize(mix(mother, seeds[o + i1].xyz, sep));
		sis = normalize(mix(mother, seeds[o + is].xyz, sep));
		other = normalize(mix(seeds[op + (io >> 1)].xyz, seeds[o + io].xyz, sep));
	} else {
		own = seeds[i1].xyz;
		sis = seeds[is].xyz;
		other = -own;
		mother = vec3(0.0, 1.0, 0.0);
	}
}

// A cell of the cleaving ball at level n (2^n cells; 0 = the gonidium), the
// daughters of round n parted by sep: the seed it lies in, its sister's and the
// nearest other cell's. Level 7 and on are too many to list: a lattice stands
// in (mother and other then being the level before's), the 16 gonidia on top.
void cells(vec3 M, int n, float sep, out vec3 own, out vec3 sis, out vec3 other, out vec3 mother) {
	own = M;
	sis = M;
	other = -M;
	mother = M;
	if (n <= 0) {
		return;
	}
	if (n >= 7) {
		vec3 s1;
		vec3 s2;
		worley(M, lattice(n), 0.7, s1, s2);
		own = s1;
		sis = s2;
		if (n == 7) {
			vec3 a;
			vec3 b;
			listed(M, 6, 1.0, mother, a, other, b);
		} else {
			worley(M, lattice(n - 1), 0.7, mother, other);
		}
		return;
	}
	listed(M, n, sep, own, sis, other, mother);
}


// The nearest gonidium: (angle to its centre, its radius) once round 6 has
// set them aside.
vec2 gonidium(vec3 M, float grown) {
	float best = -2.0;
	for (int k = 0; k < 16; k++) {
		best = max(best, dot(M, gon[k]));
	}
	return vec2(acos(clamp(best, -1.0, 1.0)), R_GON * grown);
}

// A cell's face, a little dome: lit from the upper left, a groove where the
// cells part, a faint nucleus. M on the sphere, own = the cell's centre, r its
// radius (angles), d = how far to its edge, Rv takes the screen to M, edge =
// the groove's strength, upx = screen pixels per angle, inner = seen from inside.
vec3 cell_face(vec3 M, vec3 own, float r, float d, mat3 Rv, vec3 L, vec3 green, vec3 ink, float edge, float upx, float nuc, bool inner) {
	vec3 t = M - own * dot(M, own);
	vec3 n = normalize(M + t * (1.1 / max(r, 0.02)));
	vec3 ns = transpose(Rv) * n;
	if (inner) {
		ns = -ns;
	}
	float lit = clamp(dot(ns, L), 0.0, 1.0);
	vec3 c = green * (0.55 + 0.55 * lit) + vec3(0.1, 0.12, 0.08) * pow(lit, 10.0);
	// Big cells part along a deep groove, small ones along a line.
	c = mix(c, ink, clamp(1.4 + 0.025 * r * upx - d * upx, 0.0, 1.0) * edge * mix(0.7, 0.9, smoothstep(0.3, 1.0, r)));
	c = mix(c, green * 0.55, (1.0 - smoothstep(0.0, 0.3 * r, d)) * edge * 0.5);
	// The first big cells pale, like the gonidium they came from.
	c = mix(c, vec3(0.74, 0.88, 0.78), 0.3 * smoothstep(0.3, 1.2, r));
	return mix(c, vec3(0.8, 0.92, 0.72), nuc);
}

// The cleaving ball, radius 1 in q. rt = rounds done (fractional; < 0 before
// the first), rpx = its radius in screen pixels.
vec4 cleaving(vec2 q, float rt, float rpx, float ph, vec3 L, vec3 green, vec3 ink) {
	vec4 o = vec4(0.0);
	int n = rt < 0.0 ? 0 : min(int(floor(rt)) + 1, 11);
	float f = rt < 0.0 ? 0.0 : (n == 11 && rt >= 11.0 ? 1.0 : fract(rt));
	float sep = smoothstep(0.1, 0.7, f);
	float fur = smoothstep(0.05, 0.6, f);
	float rc = 2.0 / sqrt(pow(2.0, float(max(n, 1)) - 1.0 + sep)); // a cell's angular radius
	if (n == 0) {
		rc = 2.0;
	}
	float uc = rt < 0.0 ? 0.0 : clamp(rt / 11.0, 0.0, 1.0);
	// It sits a little tipped, the opening towards us, and comes upright to turn.
	float tilt = -0.5 * (1.0 - smoothstep(0.82, 1.0, uc));
	float spin = -0.7853982 + (0.3 * sin(ph * 3.0) + 0.25 * uc) * (1.0 - smoothstep(0.82, 1.0, uc));
	mat3 Rv = mat3(vec3(cos(spin), 0.0, -sin(spin)), vec3(0.0, 1.0, 0.0), vec3(sin(spin), 0.0, cos(spin)))
		* mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, cos(tilt), sin(tilt)), vec3(0.0, -sin(tilt), cos(tilt)));
	float rho = length(q);
	// The rim bulges a little over each cell.
	float bulge = 1.0;
	if (n >= 1 && rho > 0.72 && rho < 1.2) {
		vec3 Ml = Rv * vec3(q / rho, 0.0);
		vec3 own;
		vec3 sis;
		vec3 other;
		vec3 mother;
		cells(Ml, min(n, 6), n <= 6 ? sep : 1.0, own, sis, other, mother);
		float d = min(split(Ml, own, other), mix(1.0, split(Ml, own, sis), fur));
		float amp = min(0.11, 0.075 * rc) * smoothstep(0.72, 0.95, rho);
		bulge = 1.0 + amp * (smoothstep(0.0, 0.7 * rc, d) - 0.55);
		if (n >= 6) {
			// The gonidia stand out from the sheet.
			vec2 g = gonidium(Ml, n == 6 ? sep : 1.0);
			if (g.x < g.y) {
				bulge += 0.05 * g.y / R_GON * sqrt(1.0 - g.x * g.x / (g.y * g.y)) * smoothstep(0.85, 0.97, rho);
			}
		}
	}
	float rq = rho / bulge;
	float aa = 1.2 / rpx;
	float cover = clamp((1.0 - rq) / aa + 0.5, 0.0, 1.0);
	if (cover <= 0.0) {
		return o;
	}
	rq = min(rq, 0.9999);
	vec2 qq = q / bulge;
	float h = n == 0 ? 1.0 : clamp(1.6 * rc, H_SHEET, 1.0);
	float path = 2.0 * sqrt(1.0 - rq * rq) - 2.0 * sqrt(max(0.0, (1.0 - h) * (1.0 - h) - rq * rq));
	// Glassy like the rest of the body, never quite solid.
	float total = (1.0 - exp(-K_SHEET * max(path, 0.06))) * mix(0.66, 1.0, smoothstep(3.0, 7.0, rt));
	float each = 1.0 - sqrt(1.0 - total);
	float upx = rpx; // screen pixels per radian, at the centre
	float detail = smoothstep(2.0, 5.0, rc * rpx);
	for (int side = 0; side < 2; side++) {
		float z = sqrt(1.0 - rq * rq) * (side == 0 ? -1.0 : 1.0);
		vec3 P = vec3(qq, z);
		vec3 M = Rv * P;
		vec3 own;
		vec3 sis;
		vec3 other;
		vec3 mother;
		cells(M, n, sep, own, sis, other, mother);
		if (n == 0) {
			own = Rv * normalize(vec3(-0.15, 0.12, 0.98));
		}
		// The opening-to-be: a cross where the first two furrows meet at the
		// pole, the cells there never quite closing up.
		// From 8 cells to 64 the embryo is a cup, open at this pole, closing
		// up into the cross.
		float cup = 1.05 * smoothstep(2.3, 3.2, rt) * (1.0 - smoothstep(4.2, 6.3, rt));
		float lip = 9.0;
		if (cup > 0.0) {
			lip = (acos(clamp(M.y, -1.0, 1.0)) - cup) * upx / max(abs(z), 0.3);
			if (lip < 0.0) {
				continue;
			}
		}
		float cross_w = 0.03 * smoothstep(4.0, 9.0, rt);
		float groove = 0.0;
		if (cross_w > 0.0 && M.y > 0.92) {
			float arm = min(abs(M.x), abs(M.z)) - cross_w * smoothstep(0.92, 0.985, M.y);
			groove = (1.0 - smoothstep(-cross_w, 1.5 / upx, arm)) * float(side);
		}
		float d;
		float edge = detail;
		if (n == 0) {
			d = 9.0;
		} else if (n >= 7) {
			// Rounds too fine to list: the new walls come in as the old ones go.
			float dn = split(M, own, sis);
			float dold = split(M, mother, other);
			d = mix(min(dold, 9.0), dn, fur);
			edge *= 0.8;
		} else {
			float dn = split(M, own, other);
			float ds = split(M, own, sis);
			// The furrow cuts in from the cell's sides.
			float ingress = n == 1 ? 1.0 : smoothstep((1.0 - fur) * rc * 1.05 - 0.04, (1.0 - fur) * rc * 1.05, acos(clamp(dot(M, mother), -1.0, 1.0)));
			d = min(dn, ds < 9.0 && fur * ingress > 0.02 ? ds / max(fur * ingress, 0.02) : 9.0);
		}
		// Seen at a slant the walls crowd together.
		float slant = max(abs(z), 0.18);
		float rn = n == 0 ? 0.3 : 0.11 * rc;
		float nuc = n <= 5 && side == 1 ? (1.0 - smoothstep(rn * 0.6, rn * 1.15, acos(clamp(dot(M, own), -1.0, 1.0)))) * (n == 0 ? 0.42 : 0.25) * detail : 0.0;
		vec3 c = cell_face(M, own, rc, d, Rv, L, green, ink, edge, upx / slant, nuc, side == 0);
		float a = each * (side == 0 ? 0.75 : 1.0);
		if (n >= 6) {
			// The gonidia: big, dark green, standing proud of the sheet.
			vec2 g = gonidium(M, n == 6 ? sep : 1.0);
			if (g.x < g.y) {
				vec3 gcen = M;
				for (int k = 0; k < 16; k++) {
					if (acos(clamp(dot(M, gon[k]), -1.0, 1.0)) <= g.x + 1e-4) {
						gcen = gon[k];
					}
				}
				c = cell_face(M, gcen, g.y * 0.8, g.y - g.x, Rv, L, green * vec3(0.84, 1.0, 0.8), ink, detail, upx / slant, 0.0, side == 0);
				a = max(a, mix(0.4, 0.7, float(side)) * smoothstep(0.0, 0.03, g.y - g.x));
			}
		}
		// The cup's rim: the sheet cut, seen end on.
		float rim = clamp(1.0 - (lip - 1.0) / 2.5, 0.0, 1.0);
		c = mix(c, ink, rim * 0.55);
		a = mix(a, max(a, 0.75), rim);
		// The opening-to-be: a sunken cross where the first two furrows meet.
		c = mix(c, ink * 0.8, groove * 0.75);
		a = mix(a, max(a, 0.8), groove);
		o = over(o, c * (side == 0 ? 0.8 : 1.0), a * cover);
	}
	// The gonidium's membrane, fading as it parts into cells.
	o = over(o, ink, clamp(1.1 - abs(rq - 1.0) * rpx, 0.0, 1.0) * 0.4 * (1.0 - smoothstep(0.0, 3.0, rt)));
	return o;
}

// The sheet turning inside out, cut along its axis (see inversion()). q in
// units of the original ball, the axis up, the opening at the top to begin.
vec4 inverting(vec2 q, float tau, float rpx, vec3 green, vec3 ink) {
	vec4 o = vec4(0.0);
	float x = q.x;
	float y = q.y + v_cy;
	float rr = abs(x);
	vec2 Q = vec2(rr, y);
	// The four lips part as they curl, and seal again behind.
	float open = smoothstep(0.0, 0.12, tau) * (1.0 - smoothstep(0.45, 0.62, tau));
	float cs = sqrt(4.0 * PI / 2048.0); // a somatic cell, unit sphere
	float detail = smoothstep(3.0, 6.0, cs * rpx);
	vec2 P = vec2(0.0);
	float a = 0.0;
	float s = 0.0;
	float bd = 99.0; // the nearest point of the cut sheet
	float bs = 0.0;
	float ba = 0.0;
	float bsd = 0.0;
	for (int k = 0; k < N_UN + N_FOLD + N_TURNED; k++) {
		float l;
		float kap;
		float dm;
		if (k < N_UN) {
			l = v_i0.x / float(N_UN);
			kap = v_i0.y;
			dm = v_i1.z / float(N_UN);
		} else if (k < N_UN + N_FOLD) {
			l = v_i0.z / float(N_FOLD);
			kap = v_i0.w;
			dm = v_i1.w / float(N_FOLD);
		} else {
			l = v_i1.x / float(N_TURNED);
			kap = v_i1.y;
			dm = max(0.0, LM - v_i1.z - v_i1.w) / float(N_TURNED);
		}
		if (l <= 1e-6) {
			continue;
		}
		vec2 P1 = P + arc(a, l, kap);
		float am = a + 0.5 * kap * l;
		vec2 seg = P1 - P;
		float t = clamp(dot(Q - P, seg) / max(dot(seg, seg), 1e-8), 0.0, 1.0);
		vec2 near = P + seg * t;
		float d = length(Q - near);
		if (d < bd) {
			bd = d;
			bs = s + dm * t;
			ba = am;
			bsd = dot(Q - near, vec2(sin(am), -cos(am)));
		}
		// The faces: where this ring of sheet crosses the line of sight.
		if ((y - P.y) * (y - P1.y) <= 0.0 && abs(P1.y - P.y) > 1e-6) {
			float tc = (y - P.y) / (P1.y - P.y);
			float rc = mix(P.x, P1.x, tc);
			if (rc > rr + 1e-4) {
				float sm = s + dm * tc;
				float th = PI - sm;
				float sinp = sqrt(max(0.0, 1.0 - x * x / (rc * rc)));
				float slant = abs(sin(am)) * sinp;
				// (Faint mid-turn, so the cut carries the shape; as the ball had them at both ends.)
				float faint = mix(1.0, 0.5, smoothstep(0.0, 0.15, tau) * (1.0 - smoothstep(0.85, 1.0, tau)));
				float af = 0.65 * faint * (1.0 - exp(-K_SHEET * H_SHEET / max(slant, 0.35)));
				for (int side = 0; side < 2; side++) {
					// (The ball came upright turned an eighth, its cross off the rim.)
					float phi = atan(side == 0 ? -sinp : sinp, x / rc) + 0.7853982;
					vec3 M = vec3(sin(th) * cos(phi), cos(th), sin(th) * sin(phi));
					// The lips, parted along the cross.
					float slit = 0.55 * smoothstep(LM - 0.9, LM, sm) * open;
					float dphi = abs(mod(phi + 0.7853982, 1.5707963) - 0.7853982);
					float cut = (dphi - slit * 0.5) * sin(th) * rpx / max(sinp, 0.2);
					if (slit > 0.0 && cut < 0.0) {
						continue;
					}
					vec3 c = green * (side == 0 ? 0.72 : 0.92);
					float aa = af * (side == 0 ? 0.7 : 1.0);
					float torn = smoothstep(0.5, 2.0, slit * sin(th) * rpx);
					if (torn > 0.0 && cut < 1.6) {
						// The torn edge, seen end on.
						c = mix(c, ink, 0.3 * torn);
						aa = mix(aa, max(aa, 0.3), torn);
					}
					if (detail > 0.0) {
						vec3 s1;
						vec3 s2;
						worley(M, lattice(11), 0.7, s1, s2);
						float dd = split(M, s1, s2);
						c = mix(c, ink, clamp(1.2 - dd * rpx / max(slant, 0.2), 0.0, 1.0) * 0.5 * detail);
					}
					vec2 g = gonidium(M, 1.0);
					if (g.x < g.y) {
						float gs = sqrt(max(0.0, 1.0 - g.x * g.x / (g.y * g.y)));
						c = green * vec3(0.84, 1.0, 0.8) * (0.5 + 0.55 * gs);
						c = mix(c, ink, clamp(1.3 - (g.y - g.x) * rpx, 0.0, 1.0) * 0.5);
						aa = max(aa, mix(0.4, 0.7, float(side)) * smoothstep(0.0, 0.03, g.y - g.x));
					}
					o = over(o, c, aa);
				}
			}
		}
		P = P1;
		a += kap * l;
		s += dm;
	}
	// The cut through the sheet: a band of cells, gonidia bulging on its
	// outer face.
	float phi0 = (x >= 0.0 ? 0.0 : PI) + 0.7853982;
	float th = PI - bs;
	vec3 Mb = vec3(sin(th) * cos(phi0), cos(th), sin(th) * sin(phi0));
	vec2 g = gonidium(Mb, 1.0);
	float bump = g.x < g.y ? 0.05 * sqrt(max(0.0, 1.0 - g.x * g.x / (g.y * g.y))) : 0.0;
	// Cells wedge as they bend: the sheet thickens through the fold.
	float fold = smoothstep(0.0, 0.08, bs - v_i1.z) * (1.0 - smoothstep(v_i1.w - 0.08, v_i1.w, bs - v_i1.z)) * step(0.001, v_i1.w);
	float lo = -0.5 * H_SHEET * (1.0 + 0.25 * fold);
	float hi = 0.5 * H_SHEET * (1.0 + 0.25 * fold) + bump;
	float inside = clamp(min(min(bsd - lo, hi - bsd), hi - bd) * rpx + 0.5, 0.0, 1.0);
	if (bd > 0.5 * H_SHEET + 0.25) {
		inside = 0.0;
	}
	if (inside > 0.0) {
		float across = clamp((bsd - lo) / (hi - lo), 0.0, 1.0);
		vec3 c = mix(mix(green, vec3(0.74, 0.88, 0.78), 0.35), green * 0.85, across);
		if (bump > 0.0 && bsd > 0.5 * H_SHEET - 0.02) {
			// A gonidium in section, round and dark.
			float up = clamp((bsd - 0.5 * H_SHEET) / bump, 0.0, 1.0);
			c = green * vec3(0.84, 1.0, 0.8) * (1.05 - 0.45 * up);
			c = mix(c, ink, clamp(1.3 - (hi - bsd) * rpx, 0.0, 1.0) * 0.5);
			inside = min(1.0, inside * 1.1);
		}
		float tick = abs(fract(bs / cs + 0.5) - 0.5) * cs * rpx;
		// (Coming in from the ball's own rim, the section firms up.)
		float firm = smoothstep(0.0, 0.15, tau);
		c = mix(c, ink, clamp(1.0 - tick, 0.0, 1.0) * 0.3 * detail * firm * (bsd < 0.5 * H_SHEET ? 1.0 : 0.0));
		o = over(o, c, inside * mix(0.4, 0.66, firm));
	}
	return o;
}

// The young colony, radius 1 in q: a thin ball of small cells drawn apart
// as it swells, its whips now outside, its own 16 gonidia within, turning.
vec4 juvenile(vec2 q, float ug, float rpx, float ph, vec3 L, vec3 green, vec3 ink) {
	vec4 o = vec4(0.0);
	float rho = length(q);
	// It came out of the turn as the turn left it, and starts to roll.
	float spin = -0.7853982 + ug * 5.0;
	float tilt = 0.4 * sin(ug * 3.0) * sin(ph * 2.0 + 1.0);
	mat3 Rv = mat3(vec3(cos(spin), 0.0, -sin(spin)), vec3(0.0, 1.0, 0.0), vec3(sin(spin), 0.0, cos(spin)))
		* mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, cos(tilt), sin(tilt)), vec3(0.0, -sin(tilt), cos(tilt)));
	// Whips round the rim, two to a cell, beating.
	float fl = 0.12 * smoothstep(0.0, 0.6, ug);
	if (rho > 0.98 && rho < 1.0 + 1.3 * fl && rpx > 22.0) {
		float nf = 72.0;
		float ang = atan(q.y, q.x);
		float idx = floor(ang / TAU * nf + 0.5);
		// Each whip its own length and lean.
		float t = (rho - 1.0) / (fl * (0.7 + 0.6 * hash(vec2(idx, 3.1))));
		float lat = (ang - idx * TAU / nf) * rho;
		float beat = TIME * 11.0 + idx * 0.9;
		float w = 0.012 * t * sin(5.0 * t - beat) + 0.02 * t * (hash(vec2(idx, 7.3)) - 0.5);
		float d = abs(lat - w) * rpx;
		float alpha = clamp(1.0 - d * 0.9, 0.0, 1.0) * clamp(1.0 - t * t, 0.0, 1.0) * smoothstep(-0.02, 0.0, t) * 0.45 * smoothstep(22.0, 40.0, rpx);
		o = over(o, ink, alpha);
	}
	if (rho >= 1.0 + 1.0 / rpx) {
		return o;
	}
	float cover = clamp((1.0 - rho) * rpx + 0.5, 0.0, 1.0);
	float rq = min(rho, 0.9999);
	float h = H_SHEET * mix(1.0, 0.7, ug);
	float path = 2.0 * sqrt(1.0 - rq * rq) - 2.0 * sqrt(max(0.0, (1.0 - h) * (1.0 - h) - rq * rq));
	float total = 1.0 - exp(-K_SHEET * max(path, 0.04));
	float each = 1.0 - sqrt(1.0 - total);
	float cs = sqrt(4.0 * PI / 2048.0);
	float detail = smoothstep(3.0, 6.0, cs * rpx);
	// Behind: the far wall, then the gonidia inside, then the near wall.
	for (int side = 0; side < 2; side++) {
		float z = sqrt(1.0 - rq * rq) * (side == 0 ? -1.0 : 1.0);
		vec3 P = vec3(q, z);
		vec3 M = Rv * P;
		vec3 c = mix(green * 0.85, vec3(0.74, 0.86, 0.76), 0.25);
		float a = each;
		if (detail > 0.0) {
			// The cells themselves, drawn apart as the jelly between them swells.
			vec3 s1;
			vec3 s2;
			worley(M, lattice(11), 0.7, s1, s2);
			float dc = acos(clamp(dot(M, s1), -1.0, 1.0));
			float dot_r = cs * 0.26;
			float slope = rpx / max(abs(z), 0.25);
			float grow = smoothstep(0.0, 0.4, ug);
			float in_dot = clamp((dot_r - dc) * slope + 0.5, 0.0, 1.0) * detail * grow;
			// Clear jelly round each one; the far wall's cells fainter through it.
			c = mix(c, green * 0.62 + vec3(0.02, 0.05, 0.02), in_dot);
			a = mix(a * 0.6, max(a, side == 0 ? 0.3 : 0.6), in_dot);
		}
		o = over(o, c * (side == 0 ? 0.85 : 1.0), a * cover * (side == 0 ? 0.8 : 1.0));
		// Just out of the turn the gonidia still lie in the sheet, as it left them.
		float lying = 1.0 - smoothstep(0.0, 0.2, ug);
		if (lying > 0.0) {
			vec2 g = gonidium(vec3(M.x, -M.y, M.z), 1.0);
			if (g.x < g.y) {
				float gs = sqrt(max(0.0, 1.0 - g.x * g.x / (g.y * g.y)));
				vec3 gc = green * vec3(0.84, 1.0, 0.8) * (0.5 + 0.55 * gs);
				gc = mix(gc, ink, clamp(1.3 - (g.y - g.x) * rpx, 0.0, 1.0) * 0.5);
				o = over(o, gc, mix(0.4, 0.7, float(side)) * smoothstep(0.0, 0.03, g.y - g.x) * lying * cover);
			}
		}
		if (side == 0) {
			for (int k = 0; k < 16; k++) {
				// Turned inside out, its own gonidia face in; they sink into the ball.
				vec3 g = transpose(Rv) * (vec3(gon[k].x, -gon[k].y, gon[k].z) * mix(1.0, 0.84, smoothstep(0.0, 0.5, ug)));
				float rb = mix(0.17, 0.16, ug);
				float dg = length(q - g.xy);
				if (dg < rb + 2.0 / rpx) {
					float in_g = clamp((rb - dg) * rpx + 0.5, 0.0, 1.0);
					float shade = sqrt(max(0.0, 1.0 - dg * dg / (rb * rb)));
					float glit = clamp(dot(vec3((q - g.xy) / rb, shade), L), 0.0, 1.0);
					vec3 gc = green * vec3(0.84, 1.0, 0.8) * (0.55 + 0.5 * glit) + vec3(0.08, 0.1, 0.06) * pow(glit, 10.0);
					gc = mix(gc, ink, clamp(1.1 - abs(dg - rb) * rpx, 0.0, 1.0) * 0.5);
					o = over(o, gc, in_g * 0.65 * mix(0.6, 1.0, step(0.0, g.z)) * smoothstep(0.0, 0.2, ug));
				}
			}
		}
	}
	// The rim: the sheet seen edge on, as the turn left it.
	float across = (1.0 - rho) / H_SHEET;
	if (across < 1.0) {
		float band = clamp(min(1.0 - rho, H_SHEET - (1.0 - rho)) * rpx + 0.5, 0.0, 1.0) * cover;
		o = over(o, mix(green * 0.7, green * 1.15, clamp(across, 0.0, 1.0)), band * 0.82 * mix(1.0, 0.55, smoothstep(0.2, 1.0, ug)));
	}
	float lit = pow(max(dot(vec3(q, sqrt(1.0 - rq * rq)), L), 0.0), 18.0);
	o = over(o, vec3(0.9, 1.0, 0.92), lit * 0.25 * cover);
	return o;
}

// A gonidium becoming a colony, e = 0..1 of the way (0 = not begun).
vec4 embryo(vec2 p, float e, float ph, float ppu, vec3 green, vec3 ink) {
	float axis = ph;
	vec2 lxy = rot(-axis) * vec2(-0.45, -0.55);
	vec3 L = normalize(vec3(lxy, 0.7));
	if (e < E_CLEAVE) {
		float uc = e / E_CLEAVE;
		// Rounds 1-5 at 0.095 each, the sixth (the gonidia set aside) 0.13, the rest 0.07.
		float rt = e <= 0.0 ? -1.0 : (uc < 0.515 ? (uc - 0.04) / 0.095 : (uc < 0.645 ? 5.0 + (uc - 0.515) / 0.13 : 6.0 + (uc - 0.645) / 0.071));
		vec2 q = rot(-axis) * p / R_GERM;
		return cleaving(q, rt, R_GERM * ppu, ph, L, green, ink);
	}
	if (e < E_INVERT) {
		float tau = (e - E_CLEAVE) / (E_INVERT - E_CLEAVE);
		float r = mix(R_GERM, R_INV, smoothstep(0.0, 0.3, tau));
		vec2 q = rot(-axis) * p / r;
		return inverting(q, tau, r * ppu, green, ink);
	}
	float ug = (e - E_INVERT) / (1.0 - E_INVERT);
	float r = mix(R_INV * LM / PI, R_GROWN, smoothstep(0.0, 1.0, ug));
	float sway = 0.25 * sin(TIME * 0.31 + ph * 2.0) * smoothstep(0.0, 0.3, ug);
	vec2 q = rot(-axis - sway) * p / r;
	return juvenile(q, ug, r * ppu, ph, L, green, ink);
}

float sd_box(vec2 p, vec2 half, float r) {
	vec2 q = abs(p) - half + r;
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
}

// Level 22: cuticle, as on an armoured tardigrade (Echiniscus): a plate of
// chitin and protein, amber and translucent, pitted with pores, its layers
// showing where it meets open water. bite = a fresh dent (1) healing away (0).
vec4 armour(vec2 p, int open, float ph, float bite, float crack, float ppu, vec3 tint, vec3 ink) {
	vec4 o = vec4(0.0);
	// A round plate, a little domed, like a tardigrade's dorsal plates.
	float R = B * 0.97;
	float d = length(p) - R;
	float inside = clamp(0.5 - d * ppu, 0.0, 1.0);
	if (inside <= 0.0) {
		return o;
	}
	bool idle = open == 0;
	vec3 horn = mix(vec3(0.92, 0.7, 0.4), tint, 0.1);
	if (idle) {
		horn = mix(horn, vec3(0.76, 0.76, 0.72), 0.6);
	}
	// Depth in from the rim, counted only where the rim faces open water.
	float face = 0.0;
	vec2 rad = p / max(length(p), 1e-4);
	for (int s = 0; s < 4; s++) {
		if ((open & (1 << s)) == 0) {
			continue;
		}
		vec2 dir = s == 0 ? vec2(1.0, 0.0) : (s == 1 ? vec2(-1.0, 0.0) : (s == 2 ? vec2(0.0, 1.0) : vec2(0.0, -1.0)));
		face = max(face, smoothstep(-0.2, 0.7, dot(rad, dir)));
	}
	float depth = face > 0.0 ? -d / face : 9.0;
	float thick = idle ? 0.0 : smoothstep(B * 0.6, 0.0, depth); // 1 at the open edge
	float lit = clamp(0.55 - dot(p, vec2(0.6, 0.8)) / B * 0.45, 0.0, 1.0);
	// Glass amber: see-through in the middle, denser toward the open edge.
	o = over(o, mix(horn * 0.85, mix(horn, vec3(1.0, 0.94, 0.82), 0.35), lit), inside * mix(0.28, 0.55, thick));
	// A sheen across it, as on the vault's glass.
	float sheen = smoothstep(B * 0.18, 0.0, abs(dot(p, vec2(0.7071, 0.7071)) + B * 0.25));
	o = over(o, vec3(1.0, 0.97, 0.9), sheen * 0.22 * inside);
	float detail = smoothstep(12.0, 26.0, B * ppu);
	// Pores pitting the plate.
	if (detail > 0.0) {
		vec2 g = p / (B * 0.34);
		vec2 cell = floor(g + 0.5);
		vec2 c = (cell + (vec2(hash(cell + ph), hash(cell.yx - ph)) - 0.5) * 0.3) * B * 0.34;
		float dp = (length(p - c) - B * 0.055) * ppu;
		o = over(o, mix(horn, ink, 0.6), clamp(0.5 - dp, 0.0, 1.0) * 0.45 * detail * inside);
		o = over(o, vec3(1.0, 0.97, 0.88), clamp(0.5 - (length(p - c - vec2(0.0, B * 0.07)) - B * 0.03) * ppu, 0.0, 1.0) * 0.3 * detail * inside);
	}
	if (!idle) {
		// The layers, laid one over another along the open edge.
		for (int k = 0; k < 3; k++) {
			float line = (depth - B * (0.07 + 0.09 * float(k))) * ppu;
			o = over(o, mix(horn, ink, 0.5), clamp(1.0 - abs(line), 0.0, 1.0) * mix(0.55, 0.22, float(k) / 2.0) * inside * smoothstep(0.0, 0.5, face));
		}
	}
	o = over(o, mix(horn, ink, 0.6), clamp(1.1 - abs(d * ppu), 0.0, 1.0) * 0.75);
	// The glass edge catching the light: a bright line just inside, top-left.
	o = over(o, vec3(1.0, 0.98, 0.92), clamp(1.0 - abs(d * ppu + 2.2), 0.0, 1.0) * lit * 0.7 * detail);
	if (crack > 0.0) {
		// Cracks running in from the corners, more of them as it weakens.
		for (int k = 0; k < 3; k++) {
			if (float(k) >= crack * 3.0 + 0.5) {
				break;
			}
			float a0 = ph * 3.0 + float(k) * 2.1;
			vec2 dir = vec2(cos(a0), sin(a0));
			vec2 nrm = vec2(-dir.y, dir.x);
			float along = dot(p, dir);
			float zig = 0.03 * sin(along * 40.0 + float(k));
			float dl = abs(dot(p, nrm) - zig) * ppu;
			float reach = step(-B * 0.2, along) * step(along, B * 0.95);
			o = over(o, mix(horn, ink, 0.85), clamp(1.2 - dl, 0.0, 1.0) * 0.8 * reach * inside);
		}
	}
	if (bite > 0.0 && !idle) {
		// The dent: a crescent bitten into an open edge, darker, healing.
		vec2 c = vec2(0.0);
		for (int s = 0; s < 4; s++) {
			if ((open & (1 << s)) != 0) {
				vec2 dir = s == 0 ? vec2(1.0, 0.0) : (s == 1 ? vec2(-1.0, 0.0) : (s == 2 ? vec2(0.0, 1.0) : vec2(0.0, -1.0)));
				c = rot(0.6 * sin(ph * 7.0)) * dir * R;
				break;
			}
		}
		float dent = length(p - c) - B * 0.28 * (0.6 + 0.4 * bite);
		o = over(o, mix(horn, ink, 0.7), clamp(0.5 - dent * ppu, 0.0, 1.0) * 0.5 * bite * inside);
		o = over(o, ink, clamp(1.0 - abs(dent * ppu), 0.0, 1.0) * 0.6 * bite * inside);
	}
	return o;
}

// Level 23: a regeneration block, stem cells (neoblasts) packed close: small,
// round, nearly all nucleus; they glow faintly while they work.
vec4 regen(vec2 p, float ph, float ppu, vec3 tint, vec3 ink) {
	vec4 o = vec4(0.0);
	float R = B * 0.93;
	float d = length(p) - R;
	float inside = clamp(0.5 - d * ppu, 0.0, 1.0);
	if (inside <= 0.0) {
		return o;
	}
	vec3 pale = mix(vec3(0.95, 0.86, 0.88), tint, 0.12);
	o = over(o, pale, inside * 0.42);
	float detail = smoothstep(10.0, 22.0, B * ppu);
	float pulse = 0.5 + 0.5 * sin(TIME * 2.2 + ph * 6.0);
	// Packed as a sunflower packs its seeds: round, no rows.
	for (int j = 0; j < 19; j++) {
		vec2 g = vec2(float(j), ph);
		float a = float(j) * 2.3999632 + ph;
		vec2 c = vec2(cos(a), sin(a)) * sqrt((float(j) + 0.5) / 19.0) * R * 0.8 + (vec2(hash(g), hash(g.yx)) - 0.5) * B * 0.06;
		float r = B * 0.15;
		float dc = (length(p - c) - r) * ppu;
		o = over(o, mix(pale, vec3(1.0), 0.3), clamp(0.5 - dc, 0.0, 1.0) * 0.55 * detail);
		float dn = (length(p - c) - r * 0.68) * ppu;
		o = over(o, mix(vec3(0.62, 0.42, 0.52), ink, 0.3), clamp(0.5 - dn, 0.0, 1.0) * 0.6 * detail);
		o = over(o, mix(pale, ink, 0.5), clamp(1.0 - abs(dc), 0.0, 1.0) * 0.4 * detail);
	}
	o = over(o, vec3(1.0, 0.92, 0.95), inside * 0.12 * pulse);
	o = over(o, mix(pale, ink, 0.5), clamp(1.1 - abs(d * ppu), 0.0, 1.0) * 0.6);
	return o;
}

// Level 22: a store cell, packed with oil droplets; full = 1, drawn on to 0
// (the droplets shrink and go, the cell with them).
vec4 store(vec2 p, float full, float ph, float ppu, vec3 tint, vec3 ink) {
	vec4 o = vec4(0.0);
	float k = 0.68 + 0.32 * full;
	vec2 q = p / k;
	float d = (length(q) - B * 0.9) * k;
	float inside = clamp(0.5 - d * ppu, 0.0, 1.0);
	if (inside <= 0.0) {
		return o;
	}
	vec3 cyto = mix(vec3(0.84, 0.86, 0.74), tint, 0.25);
	o = over(o, cyto, inside * 0.5);
	vec3 oil = vec3(0.97, 0.86, 0.5);
	float detail = smoothstep(10.0, 22.0, B * ppu);
	for (int j = 0; j < 9; j++) {
		// One in the middle, eight in a ring round it.
		vec2 g = vec2(float(j), 1.0);
		float a = float(j) * 0.7853982 + ph;
		vec2 c = (j == 0 ? vec2(0.0) : vec2(cos(a), sin(a)) * B * 0.56) * k + (vec2(hash(g + ph), hash(g.yx + ph * 1.7)) - 0.5) * B * 0.06 * k;
		// The droplets go one by one, round the ring, the middle one last.
		float keep = clamp(full * 9.0 - float(j) * 0.9, 0.0, 1.0);
		float r0 = B * (j == 0 ? 0.26 : 0.15 + 0.05 * hash(g * 1.3 + ph)) * k;
		float r = r0 * keep;
		if (r <= 0.0) {
			// Gone: where it sat, a faint ring.
			float dg = (length(p - c) - r0 * 0.7) * ppu;
			o = over(o, mix(cyto, ink, 0.4), clamp(1.0 - abs(dg), 0.0, 1.0) * 0.25 * detail);
			continue;
		}
		float dk = (length(p - c) - r) * ppu;
		float body = clamp(0.5 - dk, 0.0, 1.0);
		// Oil bends the light: a bright crescent on the lit side, dark rim.
		float lit = clamp(dot(normalize(p - c + 1e-5), vec2(-0.6, -0.8)), 0.0, 1.0);
		o = over(o, mix(oil, vec3(1.0, 0.98, 0.9), 0.5 * lit), body * 0.7);
		o = over(o, mix(oil, ink, 0.55), clamp(1.0 - abs(dk), 0.0, 1.0) * 0.6 * detail);
		o = over(o, vec3(1.0), clamp(0.5 - (length(p - c + vec2(0.35, 0.45) * r) - r * 0.28) * ppu, 0.0, 1.0) * 0.55 * detail);
	}
	o = over(o, mix(cyto, ink, 0.5), clamp(1.1 - abs(d * ppu), 0.0, 1.0) * 0.6);
	return o;
}

void fragment() {
	vec2 p = v_q * 2.0;
	float ppu = v_side * 0.5 / px; // screen pixels per quad unit
	vec2 p0 = p;
	float ppu0 = ppu;
	// A broken block (level 23) is drawn small, growing back to full size.
	float harm = v_c.w >= 0.5 ? v_c.w : 0.0;
	bool broken = harm >= 0.75;
	float regrown = broken ? 1.0 - (harm - 0.75) * 4.0 : 1.0;
	float crack = harm > 0.0 && !broken ? (harm - 0.5) / 0.24 : 0.0;
	float back = broken ? max(smoothstep(0.5, 1.0, regrown), 0.02) : 1.0;
	p /= back;
	ppu *= back;
	int code = int(round(v_c.x * 128.0));
	int kind = code & 7;
	int open = code >> 3;
	float ph = v_c.y * TAU;
	float fade = v_c.w < 0.5 ? v_c.w / 0.49 : 0.0;
	vec3 tint = v_col.rgb;
	float swim = v_col.a;
	vec3 ink = mix(tint * 0.42, vec3(0.66, 1.0, 0.9), dark);
	vec4 o = vec4(0.0);
	if (kind == 2) {
		float a = atan(p.y, p.x);
		float r = 0.62 * (0.74 + 0.16 * sin(3.0 * a + ph) + 0.09 * sin(7.0 * a + 2.0 * ph));
		float d = (length(p) - r) * ppu;
		o = over(o, mix(tint, vec3(0.86, 0.8, 0.72), 0.35 * clamp(-p.y - p.x * 0.5, 0.0, 1.0)), clamp(0.5 - d, 0.0, 1.0));
		o = over(o, tint * 0.5, clamp(1.1 - abs(d), 0.0, 1.0) * 0.7);
		o.a *= 0.86;
	} else if (kind == 1) {
		float e = v_c.z;
		vec3 base = mix(mix(vec3(0.16, 0.42, 0.28), tint * 0.6, 0.35), vec3(0.3, 0.62, 0.42), dark);
		if (fade > 0.0) {
			// The young have gone: a torn empty pocket. For a moment the young
			// one is still seen there, fading as it swims off as a colony.
			float d = (length(p) - R_GROWN) * ppu;
			o = over(o, tint, clamp(0.5 - d, 0.0, 1.0) * 0.08);
			o = over(o, ink, clamp(1.0 - abs(d), 0.0, 1.0) * 0.4);
			float leaving = 1.0 - smoothstep(0.02, 0.1, fade);
			if (leaving > 0.0) {
				vec3 green = mix(vec3(0.2, 0.5, 0.3), tint * 0.7, 0.3);
				float k = 1.0 - 5.0 * (fade - 0.02);
				vec4 j = embryo(p / k, 1.0, ph, ppu * k, green, ink);
				o = over(o, j.rgb, j.a * leaving / max((1.0 - fade) * (1.0 - fade), 0.5));
			}
		} else if (e <= 0.0 && dark > 0.5) {
			// A plain germ cell: pale nucleus, a little chloroplast.
			float R = R_GERM;
			float d = (length(p) - R) * ppu;
			float inside = clamp(0.5 - d, 0.0, 1.0);
			float lit = clamp(0.5 - dot(p, vec2(0.55, 0.8)) / R * 0.6, 0.0, 1.0);
			o = over(o, mix(base, vec3(0.52, 0.8, 0.56), lit * 0.5), inside * 0.78);
			o = over(o, vec3(0.88, 0.94, 0.72), clamp(0.5 - (length(p - vec2(-0.05, 0.04)) - R * 0.32) * ppu, 0.0, 1.0) * 0.8);
			o = over(o, ink, clamp(0.8 - abs((length(p - vec2(-0.05, 0.04)) - R * 0.32) * ppu), 0.0, 1.0) * 0.5);
			o = over(o, ink, clamp(1.1 - abs(d), 0.0, 1.0) * 0.75);
		} else {
			vec3 green = mix(mix(vec3(0.2, 0.5, 0.3), tint * 0.7, 0.3), vec3(0.32, 0.66, 0.46), dark);
			o = embryo(p, e, ph, ppu, green, ink);
		}
	} else if (kind == 3) {
		o = armour(p, open, ph, v_c.z, crack, ppu, tint, ink);
		if (fade > 0.0) {
			o.rgb = mix(o.rgb, vec3(0.72, 0.76, 0.76), 0.6 * fade + 0.3);
		}
	} else if (kind == 5) {
		o = regen(p, ph, ppu, tint, ink);
		if (fade > 0.0) {
			o.rgb = mix(o.rgb, vec3(0.72, 0.76, 0.76), 0.6 * fade + 0.3);
		}
	} else if (kind == 4) {
		o = store(p, dark > 0.5 ? 1.0 : v_c.z, ph, ppu, tint, ink);
		if (fade > 0.0) {
			o.rgb = mix(o.rgb, vec3(0.72, 0.76, 0.76), 0.6 * fade + 0.3);
		}
	} else {
		// A patch of small cells.
		float detail = smoothstep(14.0, 30.0, B * ppu);
		bool idle = open == 0;
		vec3 cell = idle ? mix(tint, vec3(0.74, 0.76, 0.74), 0.7) : mix(tint, vec3(0.86, 0.96, 0.8), 0.35);
		if (detail < 0.99) {
			float dr = (length(p) - B * 0.9) * ppu;
			o = over(o, cell, clamp(0.5 - dr, 0.0, 1.0) * 0.5 * (1.0 - detail));
		}
		if (detail > 0.0 && length(p) < B * 1.05) {
			// A rosette: one cell in the middle, six round it.
			for (int j = 0; j < 7; j++) {
				vec2 g = vec2(float(j), 2.0);
				vec2 jitter = vec2(hash(g + ph), hash(g.yx + ph * 1.3)) - 0.5;
				float an = float(j) * 1.0471976 + ph;
				vec2 c = (j == 0 ? vec2(0.0) : vec2(cos(an), sin(an)) * B * 0.6) + jitter * 0.04;
				float r = B * (j == 0 ? 0.3 : 0.29);
				float dk = (length(p - c) - r) * ppu;
				o = over(o, cell, clamp(0.5 - dk, 0.0, 1.0) * 0.55 * detail);
				o = over(o, ink, clamp(0.8 - abs(dk), 0.0, 1.0) * 0.5 * detail);
				o = over(o, ink, clamp(0.5 - (length(p - c) - r * 0.32) * ppu, 0.0, 1.0) * 0.42 * detail);
			}
		}
		if (open != 0) {
			// Whips on the open sides, rooted round the rim and fanning out,
			// the beat running round it.
			float T = fade > 0.0 ? ph : TIME * (5.0 + 7.0 * swim);
			float a = (1.0 - fade) * 0.85;
			for (int s = 0; s < 4; s++) {
				if ((open & (1 << s)) == 0) {
					continue;
				}
				vec2 qs = s == 0 ? p : (s == 1 ? vec2(-p.x, p.y) : (s == 2 ? vec2(p.y, p.x) : vec2(-p.y, p.x)));
				if (qs.x < B * 0.3) {
					continue;
				}
				for (int k = -1; k <= 1; k++) {
					float th = float(k) * 0.55;
					vec2 q = rot(-th) * qs;
					q.x -= B * 0.9;
					if (q.x > 0.0) {
						float y0 = float(k) * 0.3;
						float w = whip(q, -0.025, T + ph * 3.0 + y0 * 6.0 + float(s), ppu, swim);
						w = max(w, whip(q, 0.025, T + ph * 3.0 + y0 * 6.0 + float(s) + 0.5, ppu, swim));
						o = over(o, ink, w * a);
					}
				}
			}
		}
		if (fade > 0.0) {
			o.rgb = mix(o.rgb, vec3(0.72, 0.76, 0.76), 0.6 * fade + 0.3);
		}
	}
	if (fade > 0.0) {
		o.a *= (1.0 - fade) * (1.0 - fade);
	}
	if (broken) {
		// The block grows back out of a pale bud on the wound: first torn
		// remnants, then the bud swelling, then the block itself.
		o.a *= smoothstep(0.5, 0.8, regrown);
		float bud_r = B * mix(0.18, 0.85, smoothstep(0.0, 0.6, regrown));
		float bud_a = (1.0 - smoothstep(0.65, 1.0, regrown)) * smoothstep(0.0, 0.08, regrown);
		float db = (length(p0) - bud_r) * ppu0;
		vec3 bud = vec3(0.96, 0.94, 0.9);
		vec4 b = vec4(0.0);
		b = over(b, bud, clamp(0.5 - db, 0.0, 1.0) * 0.62);
		// Its cells, small and close.
		vec2 g = floor(p0 / (B * 0.26));
		vec2 c = (g + 0.5 + (vec2(hash(g + ph), hash(g.yx + ph)) - 0.5) * 0.4) * B * 0.26;
		float dc = (length(p0 - c) - B * 0.09) * ppu0;
		b = over(b, mix(bud, ink, 0.35), clamp(1.0 - abs(dc), 0.0, 1.0) * 0.35 * clamp(0.5 - db, 0.0, 1.0) * smoothstep(12.0, 24.0, B * ppu0));
		b = over(b, mix(bud, ink, 0.45), clamp(1.1 - abs(db), 0.0, 1.0) * 0.55);
		o = over(o, b.rgb, b.a * bud_a);
		// Torn remnants scattered round the wound, fading.
		float torn = 1.0 - smoothstep(0.0, 0.25, regrown);
		if (torn > 0.0) {
			for (int k = 0; k < 6; k++) {
				float a = float(k) * 1.047 + ph * 4.0;
				vec2 c2 = vec2(cos(a), sin(a)) * B * (0.55 + 0.25 * hash(vec2(float(k), ph)));
				float r2 = B * (0.08 + 0.06 * hash(vec2(ph, float(k))));
				float dd = (length(p0 - c2) - r2) * ppu0;
				o = over(o, mix(tint * 0.5, vec3(0.42, 0.4, 0.36), 0.5), clamp(0.5 - dd, 0.0, 1.0) * 0.6 * torn);
			}
		}
	}
	COLOR = o;
}
