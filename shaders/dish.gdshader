// The culture dish under the microscope lamp, in world space. Flat 2D layers:
//   clear water, brightest where the lamp is centred, with slow light
//   ripples and soft shafts; particles hanging at three depths (parallax
//   with the camera); a faint green tint where nutrient is dissolved; rock and coral growing along the inside of the
//   glass; the glass rim catching the light; the bench outside.
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D nutrient_tex : filter_linear;
uniform sampler2D light_tex : filter_linear;
uniform vec2 world_size = vec2(2200.0, 2200.0);
uniform vec2 dish_center = vec2(1100.0, 1100.0);
uniform float dish_radius = 1060.0;
uniform vec2 cam_pos = vec2(0.0);
uniform sampler2D algae_tex : filter_linear;
// View filter (C cycles it): species fades the water back so every body
// reads in its species' colour; population lays each species' territory
// over the dish as a heat map from pop_tex (rgb species colours mixed by
// headcount, a crowding 0..1) with contour lines. 0..1 each, eased.
uniform sampler2D pop_tex : filter_linear;
uniform float species_amount = 0.0;
uniform float pop_amount = 0.0;
// Environment (GDD 5.3) per field cell: temperature (deg C), acidity 0..1,
// signal A, signal B. The zones always tint the water a little; analysis
// mode can lay one of them out as a map (env_layer 1 temperature, 2 acidity,
// 3 signals), fading in with env_amount.
uniform sampler2D env_tex : filter_linear;
uniform int env_layer = 0;
uniform float env_amount = 0.0;
// Analysis mode: the water turns into pale graph paper (50 / 250 µm grid).
uniform float analysis = 0.0;
// Look 2 (after the first playtest, reference: Pathogenic): a richer water,
// a world below the focal plane (big out-of-focus cells drifting), light
// caustics. 0 = the plain look, 1 = full.
uniform float look2 = 1.0;
// Look 2's slow layers, rendered at quarter resolution (water_fx.gdshader).
uniform sampler2D water_fx : filter_linear;

varying vec2 v_world;

// Water ripples from the pointer (DishPointer): xy = centre (world),
// z = ring radius in screen pixels, w = amplitude in pixels. Visual only:
// the simulation never feels them, so experiments stay reproducible.
uniform vec4 ripples[10];
uniform int ripple_count = 0;

// Sixth round ("更像实验室", "鼠标更明显"): the pointer's scan field and the
// wake it stirs through the water. Visual only, like the ripples.
//   scan  xy = the pointer (world), z = the field's radius (world),
//         w = how far it is up 0..1: inside, the projected grid lights up
//         and a 10 µm sub-grid appears
//   wake  xy = a point on the pointer's recent path (world), zw = how fast
//         it moved there (world / s); wake_k = what is left of it 0..1.
//         The grid keeps an afterglow along the path and the water a bright
//         crease; nothing is moved (cells must stay easy to lock onto).
uniform vec4 scan = vec4(-1e6, -1e6, 1.0, 0.0);
// The main menu's "设置" preview: the stage's engraved scales light up with a
// pulse running along them.
uniform float stage_glow = 0.0;
uniform vec4 wake[12];
uniform float wake_k[12];
uniform int wake_count = 0;
const vec3 HOLO = vec3(0.09, 0.6, 0.7);

// Light (z) of the wake at w (xy, a drag, is no longer used); one screen
// pixel is px world units.
vec3 wake_field(vec2 w, float px) {
	vec3 acc = vec3(0.0);
	float R = 70.0 * px;
	for (int i = 0; i < 12; i++) {
		if (i >= wake_count) {
			break;
		}
		float k = wake_k[i];
		vec2 d = w - wake[i].xy;
		float f = exp(-dot(d, d) / (R * R));
		if (f < 0.01) {
			continue;
		}
		vec2 v = wake[i].zw;
		float sp = length(v);
		vec2 push = v / max(sp, 1e-4) * min(sp * 0.04, 14.0 * px);
		// The eddy pair: either side of the path turns back on itself.
		float side = sign(v.x * d.y - v.y * d.x);
		vec2 curl = vec2(-d.y, d.x) / max(length(d), 1e-4) * side * min(sp * 0.015, 6.0 * px);
		acc.xy += (push + curl * (1.0 - k)) * f * k;
		acc.z += f * k * smoothstep(150.0, 1500.0, sp / px);
	}
	return acc;
}

// A line `d` world units from its centre, `w` pixels wide, antialiased.
float hair(float d, float px, float w) {
	return clamp(w * 0.5 - abs(d) / px + 0.5, 0.0, 1.0);
}

float sd_round_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + vec2(r);
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

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


// Integer hash on the float's bits: exact for equal inputs, so value noise
// stays continuous across cell borders (the usual sin-fract hash broke into
// visible squares when FMA contraction nudged its input).
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

vec2 hash2(vec2 p) {
	return vec2(hash(p), hash(p + 17.3));
}

float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0, a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += noise(p) * a;
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

// Out-of-focus discs on a jittered grid.
float bokeh(vec2 w, float cell, float radius, float density, vec2 drift) {
	vec2 g = (w + drift) / cell;
	vec2 id = floor(g);
	float acc = 0.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 c = id + vec2(float(i), float(j));
			if (hash(c + 3.7) > density) {
				continue;
			}
			float d = length(g - c - hash2(c)) * cell;
			float r = radius * (0.5 + hash(c + 9.1));
			acc += smoothstep(r, r * 0.6, d) * (0.4 + 0.6 * smoothstep(r * 0.5, r, d)) * (0.5 + 0.5 * hash(c + 1.3));
		}
	}
	return clamp(acc, 0.0, 1.0);
}

// Small sharp particles, softly twinkling.
float specks(vec2 w, float cell, float r, float density, vec2 drift) {
	vec2 g = (w + drift) / cell;
	vec2 id = floor(g);
	float on = step(hash(id + 5.0), density);
	vec2 o = hash2(id) * 0.7 + 0.15;
	float d = length(g - id - o) * cell;
	float tw = 0.65 + 0.35 * sin(TIME * (0.7 + hash(id) * 1.5) + hash(id + 2.0) * 6.28);
	// Edge softness in world units: one pixel when far, a soft blur when
	// zoomed in (these specks sit out of the focal plane).
	float soft = max(fwidth(w.x), r * 0.9);
	return on * clamp((r - d) / soft + 0.5, 0.0, 1.0) * tw;
}

// Smooth (cubic B-spline) lookup of a low-resolution field from four
// bilinear taps; fields are uploaded at simulation resolution and smoothed
// here, so the CPU never resamples them.
vec4 cubic_w(float v) {
	vec4 n = vec4(1.0, 2.0, 3.0, 4.0) - v;
	vec4 s = n * n * n;
	float x = s.x;
	float y = s.y - 4.0 * s.x;
	float z = s.z - 4.0 * s.y + 6.0 * s.x;
	float w = 6.0 - x - y - z;
	return vec4(x, y, z, w) * (1.0 / 6.0);
}

float field(sampler2D tex, vec2 uv) {
	vec2 ts = vec2(textureSize(tex, 0));
	vec2 st = uv * ts - 0.5;
	vec2 fxy = fract(st);
	st -= fxy;
	vec4 xc = cubic_w(fxy.x);
	vec4 yc = cubic_w(fxy.y);
	vec4 c = st.xxyy + vec2(-0.5, 1.5).xyxy;
	vec4 sw = vec4(xc.xz + xc.yw, yc.xz + yc.yw);
	vec4 off = c + vec4(xc.yw, yc.yw) / sw;
	off /= ts.xxyy;
	float s0 = texture(tex, off.xz).r;
	float s1 = texture(tex, off.yz).r;
	float s2 = texture(tex, off.xw).r;
	float s3 = texture(tex, off.yw).r;
	float sx = sw.x / (sw.x + sw.y);
	float sy = sw.z / (sw.z + sw.w);
	return mix(mix(s3, s2, sx), mix(s1, s0, sx), sy);
}

// The same smooth lookup for all four channels of the environment.
vec4 field4(sampler2D tex, vec2 uv) {
	vec2 ts = vec2(textureSize(tex, 0));
	vec2 st = uv * ts - 0.5;
	vec2 fxy = fract(st);
	st -= fxy;
	vec4 xc = cubic_w(fxy.x);
	vec4 yc = cubic_w(fxy.y);
	vec4 c = st.xxyy + vec2(-0.5, 1.5).xyxy;
	vec4 sw = vec4(xc.xz + xc.yw, yc.xz + yc.yw);
	vec4 off = c + vec4(xc.yw, yc.yw) / sw;
	off /= ts.xxyy;
	vec4 s0 = texture(tex, off.xz);
	vec4 s1 = texture(tex, off.yz);
	vec4 s2 = texture(tex, off.xw);
	vec4 s3 = texture(tex, off.yw);
	float sx = sw.x / (sw.x + sw.y);
	float sy = sw.z / (sw.z + sw.w);
	return mix(mix(s3, s2, sx), mix(s1, s0, sx), sy);
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	float px = max(fwidth(v_world.x), 1e-4); // world units per pixel
	// The pointer's ripples bend the water (refraction) and catch the light.
	vec3 rf = ripple_count > 0 ? ripple_field(v_world, px) : vec3(0.0);
	vec3 wk = wake_count > 0 ? wake_field(v_world, px) : vec3(0.0);
	// The wake only lights the water (no drag: moving things under the
	// pointer made cells hard to lock onto).
	vec2 world = v_world + rf.xy;
	vec2 uv = world / world_size;
	vec2 tp = 1.0 / vec2(textureSize(nutrient_tex, 0));
	vec2 warp = (vec2(noise(world * 0.03), noise(world * 0.03 + 7.1)) - 0.5) * tp * 2.5;
	float n = field(nutrient_tex, uv + warp);
	float l = field(light_tex, uv);
	float rd = length(world - dish_center);
	float in_dish = 1.0 - smoothstep(dish_radius - 1.5, dish_radius + 1.5, rd);
	float rr = rd / dish_radius;

	// Water and light.
	vec3 c = mix(vec3(0.985, 0.995, 1.0), vec3(0.86, 0.94, 0.965), smoothstep(0.1, 1.0, rr));
	c += vec3(0.02, 0.012, -0.012) * clamp(l * 1.5, 0.0, 1.0);
	vec2 cw = world * 0.008;
	float c1 = noise(cw + vec2(TIME * 0.06, TIME * 0.03));
	float c2 = noise(cw * 1.7 - vec2(TIME * 0.05, -TIME * 0.04));
	float rip = pow(clamp(1.0 - abs(c1 - c2) * 2.0, 0.0, 1.0), 6.0);
	c = mix(c, vec3(1.0), rip * 0.28);
	float shaft = noise(vec2((world.x - world.y * 0.5) * 0.0025 + TIME * 0.02, 3.0));
	c = mix(c, vec3(1.0, 0.995, 0.97), smoothstep(0.5, 0.85, shaft) * 0.35);
	if (look2 > 0.001 && in_dish > 0.0) {
		vec3 wfx = texture(water_fx, SCREEN_UV + rf.xy / px * SCREEN_PIXEL_SIZE).rgb;
		// Richer water: deeper teal toward the glass, lavender drifting through.
		float hue = wfx.b;
		vec3 deep = mix(vec3(0.58, 0.85, 0.9), vec3(0.8, 0.76, 0.95), smoothstep(0.3, 0.75, hue));
		c = mix(c, deep, smoothstep(0.35, 1.0, rr) * 0.32 * look2);
		// Warmer light where the lamp falls.
		c += vec3(0.03, 0.02, -0.01) * clamp(l * 1.5, 0.0, 1.0) * look2;
		// The world below the focal plane, slower than the dish (parallax).
		float ghosts = wfx.r;
		c = mix(c, mix(vec3(0.5, 0.74, 0.82), vec3(0.7, 0.62, 0.86), hue), ghosts * 0.2 * look2);
		// Caustics, strongest under the lamp.
		float cau = wfx.g;
		c = mix(c, vec3(1.0, 0.99, 0.95), cau * (0.22 + 0.3 * clamp(l, 0.0, 1.0)) * look2 * in_dish);
	}

	// Far particles.
	c = mix(c, vec3(0.6, 0.72, 0.78), specks(world - cam_pos * 0.3, 9.0, 1.1, 0.08 + n * 0.12, TIME * vec2(1.2, 0.6)) * 0.3);

	// Dissolved nutrient: a faint green tint where the water is rich (the
	// algae themselves are organisms, drawn by organism.gdshader).
	c = mix(c, vec3(0.82, 0.93, 0.78), smoothstep(0.05, 0.6, n) * 0.35);

	// The zones' water: warm amber shimmer rising off the vent, frost-blue
	// cold water with glints of ice, the acid pool yellow-green and fizzing.
	vec4 env = field4(env_tex, uv);
	float warm = smoothstep(18.0, 34.0, env.r);
	float cold = smoothstep(9.0, 2.0, env.r);
	float sour = smoothstep(0.15, 0.75, env.g);
	// (Each effect only where its water is: the open water pays nothing.)
	if (warm > 0.003) {
		c = mix(c, vec3(1.0, 0.86, 0.68), warm * 0.2);
		float shimmer = noise(vec2(world.x * 0.03, world.y * 0.008 + TIME * 0.6));
		c = mix(c, vec3(1.0, 0.93, 0.82), warm * smoothstep(0.62, 0.9, shimmer) * 0.3);
	}
	if (cold > 0.003) {
		c = mix(c, vec3(0.84, 0.93, 1.0), cold * 0.24);
		float frost = pow(clamp(1.0 - abs(noise(world * 0.05) - noise(world * 0.05 + 3.3)) * 6.0, 0.0, 1.0), 8.0);
		c = mix(c, vec3(1.0), cold * frost * 0.35);
	}
	if (sour > 0.003) {
		c = mix(c, vec3(0.9, 0.95, 0.68), sour * 0.22);
		c = mix(c, vec3(0.97, 0.99, 0.82), sour * bokeh(world + vec2(0.0, TIME * 26.0), 34.0, 3.0, 0.3, vec2(0.0)) * 0.6);
	}

	// Near particles: big out-of-focus motes drifting past the lens.
	c = mix(c, vec3(1.0), bokeh(world + cam_pos * 0.4, 240.0, 38.0, 0.16, TIME * vec2(4.0, -2.0)) * 0.22);
	c = mix(c, vec3(0.8, 0.88, 0.92), bokeh(world + cam_pos * 0.25, 180.0, 22.0, 0.14, TIME * vec2(-2.5, 1.5)) * 0.12);

	// Rock and coral along the inside of the glass (they reach at most
	// ~100 units in, so nothing is worked out further inside).
	if (rd > dish_radius - 135.0 && rd < dish_radius + 4.0) {
		float band = (dish_radius - rd) / 110.0; // 0 at the glass, 1 at 110 units in
		float ang = atan(world.y - dish_center.y, world.x - dish_center.x);
		vec2 ap = vec2(ang * dish_radius / 90.0, rd / 90.0);
		float rock = fbm(ap * vec2(1.0, 1.4)) + 0.5 - band * 1.1;
		float rock_cov = clamp((rock - 0.5) / (fwidth(rock) + 1e-4) + 0.5, 0.0, 1.0) * in_dish;
		vec3 stone = mix(vec3(0.95, 0.93, 0.89), vec3(0.9, 0.92, 0.93), noise(ap * 3.0));
		c = mix(c, stone, rock_cov * 0.8);
		c = mix(c, vec3(0.68, 0.74, 0.78), clamp(0.6 - abs(rock - 0.5) / (fwidth(rock) + 1e-4), 0.0, 1.0) * in_dish * 0.55);
		// Coral: branching pastel growths at the rock's edge.
		float cn = fbm(ap * 2.6 + 11.0);
		float coral = cn + 0.42 - band * 1.2 + 0.1 * sin(ap.x * 9.0);
		float coral_cov = clamp((coral - 0.62) / (fwidth(coral) + 1e-4) + 0.5, 0.0, 1.0) * in_dish * (1.0 - rock_cov * 0.6);
		vec3 coral_col = mix(vec3(0.98, 0.7, 0.66), vec3(0.98, 0.82, 0.55), noise(ap * 0.7 + 5.0));
		coral_col = mix(coral_col, vec3(0.62, 0.84, 0.6), step(0.72, noise(ap * 0.5 + 9.0)));
		c = mix(c, coral_col, coral_cov * 0.75);
		c = mix(c, coral_col * 0.8, clamp(0.6 - abs(coral - 0.62) / (fwidth(coral) + 1e-4), 0.0, 1.0) * in_dish * 0.8);
		// Polyp dots on the coral.
		vec2 pg = world / 7.0;
		float pd = length(pg - floor(pg) - 0.5) * 7.0;
		c = mix(c, mix(coral_col, vec3(1.0), 0.5), coral_cov * clamp(1.2 - pd / max(px, 0.4), 0.0, 1.0) * step(0.55, hash(floor(pg))) * 0.7);
	}

	// The instrument: a measuring grid projected onto the dish floor (50 µm,
	// 250 µm), polar rings every 200 µm with 30° spokes, a degree scale
	// inside the glass, a radar sweep that brightens what it passes; under
	// the pointer the grid lights up with a 10 µm sub-grid, and the path the
	// hand took keeps an afterglow. Detail fades as the lines crowd.
	if (in_dish > 0.0) {
		float ang_g = atan(world.y - dish_center.y, world.x - dish_center.x);
		float sweep = fract((ang_g - TIME * 0.42) / 6.2831853); // 0 = just swept
		sweep = 1.0 - sweep;
		float beam = exp(-sweep * 9.0) + 0.25 * exp(-sweep * 2.5);
		vec2 g1 = abs(fract(world / 50.0 - 0.5) - 0.5) * 50.0;
		vec2 g5 = abs(fract(world / 250.0 - 0.5) - 0.5) * 250.0;
		float minor = hair(min(g1.x, g1.y), px, 1.0) * smoothstep(7.0, 16.0, 50.0 / px);
		float major = hair(min(g5.x, g5.y), px, 1.2) * smoothstep(5.0, 12.0, 250.0 / px);
		// Small registration circles where the major lines cross.
		float node = hair(length(g5) - 5.0 * px, px, 1.0) * smoothstep(8.0, 16.0, 250.0 / px);
		float ring = hair(abs(fract(rd / 200.0 - 0.5) - 0.5) * 200.0, px, 1.0) * step(150.0, rd);
		float spoke_d = abs(fract(ang_g / 0.5235988 - 0.5) - 0.5) * 0.5235988 * rd;
		float spoke = hair(spoke_d, px, 1.0) * smoothstep(120.0, 260.0, rd) * (1.0 - smoothstep(dish_radius - 150.0, dish_radius - 120.0, rd));
		// Degree scale inside the rock band: every 2°, long every 10°.
		float deg_i = ang_g / 0.0349066;
		float tick_d = abs(fract(deg_i - 0.5) - 0.5) * 0.0349066 * rd;
		float long_t = step(abs(fract(deg_i / 5.0 + 0.5) - 0.5) * 5.0, 0.5);
		float band_in = dish_radius - 126.0 - rd;
		float tick = hair(tick_d, px, 1.0) * step(0.0, band_in) * step(band_in, mix(10.0, 20.0, long_t));
		float tick_ring = hair(dish_radius - 126.0 - rd, px, 1.0);
		// The pointer's field and the afterglow along its path.
		float sd = length(world - scan.xy) / max(scan.z, 1e-3);
		float field_in = (1.0 - smoothstep(0.82, 1.0, sd)) * scan.w;
		vec2 g01 = abs(fract(world / 10.0 - 0.5) - 0.5) * 10.0;
		float fine = hair(min(g01.x, g01.y), px, 1.0) * smoothstep(5.0, 10.0, 10.0 / px) * field_in;
		float lit = 1.0 + 2.2 * beam + 5.0 * field_in + 6.0 * wk.z;
		float grid = (minor * 0.045 + major * 0.1 + node * 0.18 + ring * 0.07 + spoke * 0.05) * lit
				+ (tick * 0.32 + tick_ring * 0.16) * (1.0 + beam) + fine * 0.16;
		grid *= (1.0 - analysis) * (1.0 - 0.8 * max(species_amount, pop_amount)) * in_dish;
		c = mix(c, HOLO, clamp(grid, 0.0, 0.85));
		// The sweep's faint wedge and the field's glass-like tint.
		c = mix(c, vec3(0.86, 0.97, 1.0), (exp(-sweep * 14.0) * 0.06 + field_in * 0.05) * in_dish * (1.0 - analysis));
	}
	// The wake: a bright crease of disturbed water behind the hand.
	c = mix(c, vec3(0.93, 0.99, 1.0), clamp(wk.z, 0.0, 1.0) * 0.35 * in_dish);

	// View filter.
	vec3 paper_v = vec3(0.955, 0.97, 0.978);
	if (species_amount > 0.001) {
		c = mix(c, paper_v, species_amount * 0.62 * in_dish);
	}
	if (pop_amount > 0.001) {
		vec4 pf = field4(pop_tex, uv);
		c = mix(c, paper_v, pop_amount * 0.6 * in_dish);
		float dens = clamp(pf.a, 0.0, 1.0);
		vec3 hue = clamp(pf.rgb, 0.0, 1.0);
		// Sparse water stays paper; crowds deepen into their species' colour.
		float wash = smoothstep(0.04, 0.85, dens);
		c = mix(c, mix(paper_v, hue, 0.25 + 0.6 * wash), smoothstep(0.03, 0.12, dens) * (0.35 + 0.5 * wash) * pop_amount * in_dish);
		float lv = dens * 5.0;
		float to_line = 0.5 - abs(fract(lv) - 0.5);
		float iso = clamp(1.0 - to_line / max(fwidth(lv) * 1.2, 1e-4), 0.0, 1.0) * step(0.15, dens);
		iso *= 1.0 - smoothstep(0.08, 0.25, fwidth(lv)); // lines packed tight fade out
		c = mix(c, hue * 0.75, iso * 0.45 * pop_amount * in_dish);
	}

	if (analysis > 0.001) {
		vec3 paper = vec3(0.965, 0.978, 0.985);
		vec2 g1 = abs(fract(world / 50.0 - 0.5) - 0.5) * 50.0 / px;
		vec2 g5 = abs(fract(world / 250.0 - 0.5) - 0.5) * 250.0 / px;
		float minor = clamp(1.0 - min(g1.x, g1.y), 0.0, 1.0);
		float major = clamp(1.3 - min(g5.x, g5.y), 0.0, 1.0);
		paper = mix(paper, vec3(0.78, 0.86, 0.9), minor * 0.35 + major * 0.55);
		c = mix(c, paper, analysis * 0.85 * in_dish);
	}

	// Environment maps (analysis): temperature from ice blue through white
	// to vent orange with an isotherm every 5 degrees; acidity as yellow-green
	// depth with a line every 0.2; signals A (magenta) and B (cyan).
	if (env_amount > 0.001 && env_layer > 0) {
		vec3 map = c;
		float lv = 0.0;
		float on = 1.0;
		if (env_layer == 1) {
			float t = env.r;
			map = mix(vec3(0.66, 0.83, 0.99), vec3(0.97, 0.98, 0.99), smoothstep(0.0, 12.0, t));
			map = mix(map, vec3(1.0, 0.76, 0.52), smoothstep(12.0, 36.0, t));
			lv = t / 5.0;
		} else if (env_layer == 2) {
			map = mix(vec3(0.96, 0.98, 0.97), vec3(0.72, 0.84, 0.18), smoothstep(0.0, 0.85, env.g));
			lv = env.g * 5.0;
			on = step(0.05, env.g);
		} else {
			float a = clamp(env.b / 1.2, 0.0, 1.0);
			float b = clamp(env.a / 1.2, 0.0, 1.0);
			map = vec3(0.97, 0.98, 0.99);
			map = mix(map, vec3(0.85, 0.35, 0.8), a * 0.85);
			map = mix(map, vec3(0.2, 0.7, 0.9), b * 0.85);
			lv = (env.b + env.a) * 4.0;
			on = step(0.03, env.b + env.a);
		}
		c = mix(c, map, env_amount * 0.55 * in_dish);
		float to_line = 0.5 - abs(fract(lv) - 0.5);
		float iso = clamp(1.0 - to_line / max(fwidth(lv) * 1.2, 1e-4), 0.0, 1.0) * on;
		c = mix(c, map * 0.6, iso * 0.6 * env_amount * in_dish);
	}

	// Outside the glass: the microscope's stage, white enamelled metal with
	// a brushed grain, the bore the dish sits in (a dark machined gap, then
	// a lit chamfer), engraved scales along its edges, socket screws at the
	// corners, threaded holes, a label; past its edge the lab bench (the
	// lens layer blurs all of it at the edges). Text: scripts/lab_marks.gd.
	vec3 outside = c;
	if (in_dish < 1.0) {
		vec2 q = world - dish_center;
		float ang_s = atan(q.y, q.x);
		float t = rd - dish_radius;
		const float H = 1720.0;
		float box = sd_round_box(q, vec2(H), 150.0);
		float grain = noise(vec2(world.x * 0.004, world.y * 0.9)) - 0.5;
		vec3 metal = vec3(0.935, 0.947, 0.958) + grain * 0.03;
		metal = mix(metal, vec3(0.965, 0.972, 0.98), smoothstep(-H, H, -q.y) * 0.5); // lit from the top
		// Bore: gap 0..26 (shadowed), chamfer 26..60 (lit by angle).
		float gap = 1.0 - smoothstep(24.0, 27.0, t);
		vec3 bore = mix(vec3(0.5, 0.57, 0.63), vec3(0.66, 0.71, 0.76), smoothstep(0.0, 24.0, t));
		float lightang = 0.5 + 0.5 * cos(ang_s + 2.2);
		vec3 chamfer = mix(vec3(0.78, 0.82, 0.86), vec3(0.98, 0.99, 1.0), lightang);
		float on_ch = smoothstep(26.0, 28.0, t) * (1.0 - smoothstep(58.0, 61.0, t));
		vec3 st = metal * (1.0 - 0.16 * exp(-max(t - 60.0, 0.0) / 50.0)); // the dish's shadow
		st = mix(st, chamfer, on_ch);
		st = mix(st, bore, gap);
		st = mix(st, vec3(0.55, 0.62, 0.68), hair(t - 61.0, px, 1.2) * 0.6);
		// Engraved scales: ticks every 50 along all four edges, long every 250.
		vec2 e = H - abs(q); // distance in from each edge
		float along_x = abs(fract(q.x / 50.0 - 0.5) - 0.5) * 50.0;
		float along_y = abs(fract(q.y / 50.0 - 0.5) - 0.5) * 50.0;
		float lx = step(abs(fract(q.x / 250.0 + 0.5) - 0.5) * 250.0, 25.0);
		float ly = step(abs(fract(q.y / 250.0 + 0.5) - 0.5) * 250.0, 25.0);
		float sc = hair(along_x, px, 1.3) * step(70.0, e.y) * step(e.y, 70.0 + mix(26.0, 52.0, lx)) * step(abs(q.x), H - 220.0)
				+ hair(along_y, px, 1.3) * step(70.0, e.x) * step(e.x, 70.0 + mix(26.0, 52.0, ly)) * step(abs(q.y), H - 220.0);
		sc += hair(e.y - 70.0, px, 1.3) * step(abs(q.x), H - 220.0) + hair(e.x - 70.0, px, 1.3) * step(abs(q.y), H - 220.0);
		st = mix(st, vec3(0.42, 0.5, 0.57), clamp(sc, 0.0, 1.0) * 0.55);
		if (stage_glow > 0.0) {
			float run = 0.5 + 0.5 * sin((q.x + q.y) * 0.004 - TIME * 3.0);
			st = mix(st, HOLO * (1.3 + run * 0.9), clamp(sc, 0.0, 1.0) * stage_glow);
			st = mix(st, vec3(0.9, 0.99, 1.0), hair(box + 70.0, px, 2.0) * stage_glow * 0.5);
		}
		// Socket screws at the corners, threaded holes along the sides.
		vec2 cq = abs(q) - vec2(H - 120.0);
		float screw = length(cq);
		st = mix(st, vec3(0.74, 0.78, 0.82), 1.0 - smoothstep(30.0, 32.0, screw));
		st = mix(st, vec3(0.96, 0.97, 0.98), (1.0 - smoothstep(26.0, 28.0, screw)) * 0.8);
		float hexd = max(abs(cq.x) * 0.866 + abs(cq.y) * 0.5, abs(cq.y)) - 11.0;
		st = mix(st, vec3(0.38, 0.44, 0.5), 1.0 - smoothstep(0.0, 1.5, hexd));
		vec2 hq = vec2(abs(q.x) - (H - 120.0), (fract(q.y / 260.0) - 0.5) * 260.0);
		float hole = length(hq) + step(H - 330.0, abs(q.y)) * 1e4;
		st = mix(st, vec3(0.62, 0.68, 0.74), 1.0 - smoothstep(13.0, 15.0, hole));
		st = mix(st, vec3(0.48, 0.55, 0.61), 1.0 - smoothstep(7.0, 9.0, hole));
		// The label: white with a cyan stripe.
		vec2 lq = q - vec2(-1180.0, 1330.0);
		float lab = sd_round_box(lq, vec2(300.0, 92.0), 10.0);
		st *= 1.0 - 0.1 * exp(-max(lab, 0.0) / 10.0) * step(0.0, lab);
		st = mix(st, vec3(0.99, 0.995, 1.0), 1.0 - smoothstep(0.0, 1.5, lab));
		st = mix(st, HOLO, (1.0 - smoothstep(0.0, 1.5, lab)) * step(lq.x, -258.0));
		// Past the stage: the bench, with the stage's shadow along its edge
		// and soft shapes of the lab beyond (out of focus anyway).
		vec3 bench = mix(vec3(0.86, 0.885, 0.91), vec3(0.8, 0.83, 0.86), smoothstep(H, H * 2.2, length(q)));
		bench *= 1.0 - 0.22 * exp(-max(box, 0.0) / 70.0);
		float shapes = 1.0 - smoothstep(0.0, 120.0, sd_round_box(q - vec2(2600.0, -900.0), vec2(260.0, 520.0), 80.0));
		shapes = max(shapes, 1.0 - smoothstep(0.0, 140.0, length(q - vec2(-2500.0, -1300.0)) - 380.0));
		shapes = max(shapes, 1.0 - smoothstep(0.0, 120.0, sd_round_box(q - vec2(-600.0, 2650.0), vec2(700.0, 180.0), 60.0)));
		bench = mix(bench, vec3(0.94, 0.955, 0.97), shapes * 0.7);
		outside = mix(st, bench, clamp(box / px + 0.5, 0.0, 1.0));
		// A bevel along the stage's edge.
		outside = mix(outside, vec3(0.99, 1.0, 1.0), hair(box + 6.0, px, 2.0) * 0.8 * smoothstep(-H, H, -q.y - q.x * 0.3));
	}
	c = mix(outside, c, in_dish);
	float ang = atan(world.y - dish_center.y, world.x - dish_center.x);
	float glint = pow(0.5 + 0.5 * cos(ang + 2.3), 3.0);
	c = mix(c, vec3(0.72, 0.82, 0.87), exp(-abs(rd - dish_radius + 10.0) * 0.3) * 0.5);
	c = mix(c, vec3(1.0), exp(-abs(rd - dish_radius) * 0.22) * (0.55 + 0.45 * glint));
	c = mix(c, vec3(1.0), exp(-abs(rd - dish_radius + 22.0) * 0.12) * glint * 0.35);
	// Two spring clips holding the dish, lying across the glass edge (only
	// worked out near the rim, where they can be).
	for (int ci = 0; ci < (rd > dish_radius - 120.0 && rd < dish_radius + 480.0 ? 2 : 0); ci++) {
		float ca = ci == 0 ? -0.62 : 2.52;
		vec2 dir = vec2(cos(ca), sin(ca));
		vec2 q = world - dish_center;
		vec2 lq = vec2(dot(q, dir), dot(q, vec2(-dir.y, dir.x)));
		vec2 m = lq - vec2(dish_radius + 170.0, 0.0);
		float clip = sd_round_box(m, vec2(240.0, 46.0), 22.0);
		float shadow = 1.0 - smoothstep(0.0, 26.0, sd_round_box(m - vec2(0.0, 10.0), vec2(240.0, 46.0), 22.0));
		c *= 1.0 - 0.12 * shadow * step(0.0, clip);
		vec3 steel = mix(vec3(0.8, 0.84, 0.88), vec3(0.97, 0.98, 0.99), smoothstep(46.0, -46.0, m.y));
		steel += (noise(vec2(lq.x * 0.9, lq.y * 0.01)) - 0.5) * 0.04;
		float inside_c = clamp(0.5 - clip / px, 0.0, 1.0);
		c = mix(c, steel, inside_c);
		c = mix(c, vec3(0.55, 0.62, 0.68), hair(clip, px, 1.2) * 0.7);
		// The screw that holds it.
		vec2 sm = m - vec2(110.0, 0.0);
		float sr = length(sm);
		c = mix(c, vec3(0.7, 0.75, 0.8), (1.0 - smoothstep(24.0, 26.0, sr)) * inside_c);
		c = mix(c, vec3(0.97, 0.98, 0.99), (1.0 - smoothstep(19.0, 21.0, sr)) * inside_c);
		float slot = max(abs(dot(sm, vec2(0.7071, 0.7071))) - 3.0, abs(dot(sm, vec2(-0.7071, 0.7071))) - 15.0);
		c = mix(c, vec3(0.45, 0.52, 0.58), (1.0 - smoothstep(0.0, 1.2, slot)) * inside_c);
	}
	// Ripple crests catch the lamp (a little over 1: they bloom), troughs dim.
	c *= 1.0 - 0.018 * max(-rf.z, 0.0);
	c += vec3(0.7, 0.93, 1.0) * max(rf.z, 0.0) * 0.016 * in_dish;
	COLOR = vec4(pow(c, vec3(2.2)), 1.0);
}
