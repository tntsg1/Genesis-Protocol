// The campaign model as scan data (tenth round: "太廉价了，像卡通"): every
// point of the drill site's cloud - ice faces, strata, cracks, the ice's
// underside, ocean motes, vent plumes, the seafloor's contours, the globe.
// Each point is one triangle (three copies of its centre) blown up in clip
// space to a round dot `UV.x` pixels across, so dots stay crisp at any
// distance. UV.y picks the motion (0 still, 1 an ocean mote sinking and
// drifting, 2 a plume particle rising, 3 a glow pulsing in waves - a swarm's
// light, a mat's veins - 4 a slow sway - an aurora, reeds), UV2.x is the
// point's own phase, UV2.y its group's (where its wave is).
// Points fade with distance into the page's white; the build front, the
// selected station's depth and a slow sweep light them up in cyan.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform float build_y = -100.0;
uniform float px = 1.0; // the window's pixel scale
uniform float slice_y = -3.1;
uniform float slice_a = 0.0;
uniform float sweep = 1.0;
uniform float sweep_y = 1.0;
uniform vec2 fog = vec2(22.0, 32.0); // view depth where the fade starts / ends
uniform float fog_min = 0.35;
uniform vec4 hot : source_color = vec4(0.0, 0.62, 0.74, 1.0);
// The chapter change (one scene per chapter): 1 every point in place, 0
// all of them scattered and gone; in between they stream in or fly apart,
// each on its own delay, burning cyan in flight.
uniform float form = 1.0;
uniform vec2 motes = vec2(-3.05, 3.1); // the motes' water: top, height
uniform float rise = 2.5; // how high a plume particle climbs

varying vec2 corner;
varying vec4 col;

float hash(float n) {
	return fract(sin(n * 91.345) * 43758.5453);
}

void vertex() {
	int k = VERTEX_ID % 3;
	corner = k == 0 ? vec2(-1.0, -1.0) : (k == 1 ? vec2(3.0, -1.0) : vec2(-1.0, 3.0));
	vec3 p = VERTEX;
	float ph = UV2.x;
	float size = UV.x;
	col = COLOR;
	float lum = 0.0; // motion 3's light
	if (UV.y > 0.5 && UV.y < 1.5) {
		// A mote: sinks slowly through the ocean (wrapping), sways.
		float f = fract((motes.x - p.y) / motes.y + TIME * 0.006 + ph);
		p.y = motes.x - f * motes.y;
		p.x += sin(TIME * 0.13 + ph * 6.283) * 0.12;
		p.z += cos(TIME * 0.11 + ph * 4.1) * 0.12;
		col.a *= smoothstep(0.0, 0.08, f) * (1.0 - smoothstep(0.92, 1.0, f));
	} else if (UV.y > 1.5 && UV.y < 2.5) {
		// A plume particle: rises from the vent, spreading and fading.
		float t = fract(ph + TIME * 0.16);
		float ang = ph * 37.0;
		p.y += t * rise;
		p.x += cos(ang) * t * t * 0.55 + sin(TIME * 0.5 + t * 4.0) * 0.06 * t;
		p.z += sin(ang) * t * t * 0.55;
		col.a *= smoothstep(0.0, 0.05, t) * (1.0 - t);
		size *= 1.0 + t * 1.2;
	} else if (UV.y > 2.5 && UV.y < 3.5) {
		// A pulse: a wave of light runs through the group.
		float k = 0.5 + 0.5 * sin(TIME * 1.3 - UV2.y + ph * 0.6);
		lum = k * k * k * 0.42; // (a soft wave: the sweep's own glow is the strong one)
		size *= 1.0 + lum * 0.8;
	} else if (UV.y > 3.5) {
		// A sway: curtains and stems bend in a slow current.
		float w = sin(TIME * 0.55 + p.y * 1.6 + UV2.y);
		p.x += w * 0.16;
		p.z += cos(TIME * 0.4 + p.y * 1.1 + UV2.y) * 0.08;
		col.a *= 0.75 + 0.25 * w;
	}
	float glow = lum;
	float fa = 1.0; // the chapter change's fade (after the glow lifts alpha)
	if (form < 0.999) {
		float k = clamp(form * 1.6 - hash(ph * 5.3 + 0.7) * 0.6, 0.0, 1.0);
		float e = k * k * (3.0 - 2.0 * k);
		vec3 dir = normalize(vec3(hash(ph * 17.3), hash(ph * 29.1), hash(ph * 11.9)) - 0.5 + 1e-4);
		p += dir * (1.0 - e) * (1.2 + 3.0 * hash(ph * 3.7)) + vec3(0.0, (1.0 - e) * 0.9, 0.0);
		fa = e * e;
		glow = max(glow * e, (1.0 - e) * e * 2.0);
	}
	vec3 wp = (MODEL_MATRIX * vec4(p, 1.0)).xyz;
	bool hidden = false;
	if (build_y > -50.0) {
		// The build: nothing below the front; just above it the points
		// gather in from a scatter and burn cyan.
		float d = wp.y - build_y;
		hidden = d < 0.0;
		float front = 1.0 - smoothstep(0.0, 0.9, d);
		p += (vec3(hash(ph * 13.1), hash(ph * 7.7), hash(ph * 3.3)) - 0.5) * front * front * 0.9;
		glow = max(glow, front);
	}
	float hs = exp(-pow((wp.y - slice_y) / 0.07, 2.0)) * slice_a;
	float hb = exp(-pow((wp.y - sweep_y) / 0.16, 2.0)) * sweep * 0.75;
	glow = max(glow, max(hs, hb));
	col.rgb = mix(col.rgb, hot.rgb * (1.0 + glow * 1.4), glow);
	col.a = mix(col.a, max(col.a, 0.9), glow);
	size *= 1.0 + glow * 0.6;
	col.a *= fa;
	vec4 v = MODELVIEW_MATRIX * vec4(p, 1.0);
	col.a *= mix(1.0, fog_min, smoothstep(fog.x, fog.y, -v.z));
	POSITION = PROJECTION_MATRIX * v;
	POSITION.xy += corner * size * px / VIEWPORT_SIZE * POSITION.w;
	if (hidden || col.a <= 0.003) {
		POSITION = vec4(0.0, 0.0, -2.0, 1.0);
	}
}

void fragment() {
	float d = length(corner);
	ALBEDO = col.rgb;
	ALPHA = col.a * exp(-d * d * 3.5);
}
