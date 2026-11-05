shader_type canvas_item;

#include "res://shaders/night.gdshaderinc"
// Level 24's vent guardian, a rotifer (a bdelloid like Philodina): a glassy,
// telescoping body; at the front the corona, two wheels of cilia beating in a
// wave that runs round them so they seem to turn; behind the mouth the mastax,
// a pair of jaws grinding; a gut, and a foot with two toes. Local units: 1 =
// the body's extent, +x forward. `fury` reddens it and speeds the cilia,
// `chew` (0..1 while it chews) works the jaws. `retract` (0..1, irritated) draws
// the corona into the head: the wheels sink in under the glass, the cilia fold
// and stop, the head blunts and puckers shut over them. `beat` is the cilia's
// phase, kept by the layer so that they can stop. `rage` (0..1, the frenzy near
// starving) flushes it: crimson throbbing through the glass, vessels standing
// out, a red bloom round it, the cilia long. `dead` (0..1, after it starved)
// drains it: colour gone, slack and thinner, the cilia hanging still.

uniform float px = 0.1; // one screen pixel in local units
uniform float fury = 0.0;
uniform float chew = 0.0;
uniform float seed = 0.0;
uniform float retract = 0.0;
uniform float beat = 0.0;
uniform float rage = 0.0;
uniform float dead = 0.0;

varying vec2 v_p;

void vertex() {
	v_p = VERTEX * 2.0;
}

vec4 over(vec4 o, vec3 c, float a) {
	float oa = a + o.a * (1.0 - a);
	return vec4((c * a + o.rgb * o.a * (1.0 - a)) / max(oa, 1e-4), oa);
}

float smin(float a, float b, float k) {
	float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
	return mix(b, a, h) - k * h * (1.0 - h);
}

float ellipse(vec2 p, vec2 c, vec2 r) {
	vec2 q = (p - c) / r;
	return (length(q) - 1.0) * min(r.x, r.y);
}

// The body as one smooth outline: trunk, neck, head, the foot tapering behind.
float body(vec2 p, float t) {
	float sway = 0.03 * sin(t * 1.3 + p.x * 2.0) * (1.0 - dead);
	vec2 q = vec2(p.x, p.y - sway * (1.0 - p.x));
	float d = ellipse(q, vec2(0.0, 0.0), vec2(0.62, 0.36));
	d = smin(d, ellipse(q, vec2(0.55, 0.0), vec2(0.3, 0.26)), 0.08);
	// (Drawn in, the head pulls back and narrows round what it holds.)
	d = smin(d, ellipse(q, vec2(0.8 - 0.08 * retract, 0.0), vec2(0.18 - 0.04 * retract, 0.3 - 0.07 * retract)), 0.06);
	// The foot: segments narrowing back, telescoped into each other.
	for (int k = 0; k < 3; k++) {
		float x = -0.62 - 0.14 * float(k);
		d = smin(d, ellipse(q, vec2(x, 0.0), vec2(0.13, 0.17 - 0.035 * float(k))), 0.05);
	}
	// Two toes.
	d = min(d, ellipse(q, vec2(-1.0, 0.05), vec2(0.07, 0.025)));
	d = min(d, ellipse(q, vec2(-1.0, -0.05), vec2(0.07, 0.025)));
	return d;
}

void fragment() {
	vec2 p = v_p;
	float t = TIME + seed * 10.0;
	// (Deeper than the colonies' glass: the one thing in the dish to watch.)
	vec3 glass = mix(vec3(0.84, 0.66, 0.46), vec3(0.92, 0.48, 0.38), fury * 0.7);
	vec3 ink = mix(vec3(0.3, 0.2, 0.14), vec3(0.5, 0.12, 0.1), fury * 0.6);
	// Raging: blood throbbing through it, a beat with a sharp rise.
	float throb = rage * (0.55 + 0.45 * pow(0.5 + 0.5 * sin(t * 7.5), 3.0));
	glass = mix(glass, vec3(0.94, 0.34, 0.4), throb * 0.65);
	ink = mix(ink, vec3(0.55, 0.06, 0.12), rage * 0.5);
	// Starved: the colour drains out of it.
	glass = mix(glass, vec3(0.82, 0.8, 0.76), dead * 0.85);
	ink = mix(ink, vec3(0.44, 0.42, 0.4), dead * 0.8);
	vec4 o = vec4(0.0);
	// (Dead, it goes slack and thinner.)
	float d = body(vec2(p.x, p.y / (1.0 - 0.12 * dead)), t);
	float aa = px * 1.2;
	float inside = clamp(0.5 - d / aa, 0.0, 1.0);
	// Raging: a red bloom round the body, swelling with each throb.
	o = over(o, vec3(0.95, 0.3, 0.38), clamp(1.0 - d / (0.1 + 0.06 * throb), 0.0, 1.0) * (1.0 - inside) * 0.3 * throb);
	// The corona: two wheels at the front, their cilia beating in a wave.
	// Drawn in, the wheels sink back into the head, shrink and close together.
	float out_ = 1.0 - retract;
	for (int w = 0; w < 2; w++) {
		vec2 c = vec2(0.93 - 0.24 * retract, (w == 0 ? 0.17 : -0.17) * (1.0 - 0.6 * retract));
		float r = 0.17 * (1.0 - 0.5 * retract);
		vec2 q = p - c;
		float rr = length(q);
		float a = atan(q.y, q.x);
		// The disc.
		float dd = (rr - r) / aa;
		o = over(o, mix(glass, vec3(1.0), 0.25), clamp(0.5 - dd, 0.0, 1.0) * mix(0.45, 0.3, retract));
		// Cilia round its front edge: a wave running round, so it seems to turn.
		float front = smoothstep(-1.9, -1.0, a) * (1.0 - smoothstep(1.0, 1.9, a));
		if (w == 1) {
			front = smoothstep(-1.9, -1.0, a) * (1.0 - smoothstep(1.0, 1.9, a));
		}
		float n = 26.0;
		float ka = floor(a / 6.2832 * n + 0.5);
		float lean = 0.35 * sin(ka * 0.9 - beat * (w == 0 ? 1.0 : -1.0));
		float ca = ka / n * 6.2832 + lean * 0.08;
		vec2 dir = vec2(cos(ca), sin(ca));
		float along = dot(q, dir) - r;
		float across = abs(dot(q, vec2(-dir.y, dir.x)));
		// (Folded flat to the disc as it sinks: shorter, and still. Raging,
		// longer; dead, limp stubs of uneven length.)
		float len = 0.07 * (0.75 + 0.25 * sin(ka * 0.9 - beat * (w == 0 ? 1.0 : -1.0))) * out_ * out_ * (1.0 + 0.35 * rage);
		len = mix(len, 0.07 * (0.25 + 0.35 * fract(sin(ka * 12.9898 + float(w) * 4.1) * 43758.5)), dead);
		float hair = step(0.0, along) * step(along, len) * clamp(1.0 - across / (aa * 0.9), 0.0, 1.0) * front;
		o = over(o, ink, hair * 0.8);
		o = over(o, ink, clamp(1.0 - abs(dd), 0.0, 1.0) * mix(0.6, 0.35, retract));
	}
	// The body: glass, darker at the rim (seen through, it is thicker there).
	float rim = smoothstep(-0.12, 0.0, d);
	// A soft shadow under it, then the body.
	o = over(o, vec3(0.1, 0.12, 0.14), clamp(1.0 - d / 0.06, 0.0, 1.0) * (1.0 - inside) * 0.18);
	o = over(o, glass, inside * mix(0.42, 0.75, rim));
	o = over(o, ink, clamp(1.6 - abs(d) / aa, 0.0, 1.0) * 0.85);
	if (inside > 0.0) {
		// Folds across the trunk and foot (it telescopes).
		for (int k = 0; k < 5; k++) {
			float x = 0.45 - 0.27 * float(k);
			float f = abs(p.x - x - 0.02 * sin(p.y * 6.0 + t)) / aa;
			o = over(o, ink, clamp(1.0 - f, 0.0, 1.0) * 0.18 * inside * smoothstep(0.4, 0.0, abs(p.y)));
		}
		// Raging: vessels standing out along the trunk, pulsing with it.
		if (throb > 0.0) {
			for (int k = 0; k < 4; k++) {
				float yo = (float(k) - 1.5) * 0.11;
				float v = abs(p.y - yo - 0.025 * sin(p.x * 13.0 + float(k) * 1.7)) / aa;
				o = over(o, vec3(0.78, 0.1, 0.18), clamp(1.0 - v * 0.7, 0.0, 1.0) * 0.4 * throb * inside * smoothstep(0.62, 0.35, abs(p.x - 0.05)));
			}
		}
		// The gut, brownish green with what it ate.
		float g = ellipse(p, vec2(0.05, 0.0), vec2(0.36, 0.2));
		o = over(o, mix(vec3(0.55, 0.62, 0.36), vec3(0.62, 0.36, 0.28), fury * 0.5), clamp(0.5 - g / aa, 0.0, 1.0) * 0.45 * (1.0 - 0.6 * dead));
		for (int k = 0; k < 7; k++) {
			vec2 c = vec2(-0.2 + 0.08 * float(k), 0.08 * sin(float(k) * 2.3 + seed * 5.0));
			float bd = (length(p - c) - 0.035) / aa;
			o = over(o, vec3(0.42, 0.55, 0.3), clamp(0.5 - bd, 0.0, 1.0) * 0.5 * clamp(0.5 - g / aa, 0.0, 1.0) * (1.0 - 0.6 * dead));
		}
		// The mastax: two jaws closing on each other, grinding fast while it chews.
		float grind = sin(t * (3.0 + 18.0 * chew)) * (0.3 + 0.7 * chew) * (1.0 - dead);
		for (int s = 0; s < 2; s++) {
			float side = s == 0 ? 1.0 : -1.0;
			vec2 c = vec2(0.6, side * (0.05 + 0.025 * grind));
			vec2 q = p - c;
			float jaw = ellipse(q, vec2(0.0), vec2(0.09, 0.045));
			float teeth = abs(fract(q.x * 40.0) - 0.5) * 0.01;
			o = over(o, ink, clamp(0.5 - (jaw + teeth) / aa, 0.0, 1.0) * 0.7);
		}
		// The mouth's opening between the wheels (shut while it is drawn in).
		float m = ellipse(p, vec2(0.86 - 0.1 * retract, 0.0), vec2(0.07, 0.05 + 0.03 * chew) * (1.0 - 0.75 * retract));
		o = over(o, ink, clamp(0.5 - m / aa, 0.0, 1.0) * 0.5);
		// Drawn in: the head's front puckered shut, creases running back from its tip.
		if (retract > 0.0) {
			vec2 q = p - vec2(0.96 - 0.12 * retract, 0.0);
			float rr = length(q);
			float ang = atan(q.y, -q.x);
			float k = floor(ang / 0.32 + 0.5);
			float da = abs(ang - k * 0.32) * rr;
			float crease = clamp(1.0 - da / aa, 0.0, 1.0) * step(abs(k), 3.0)
				* smoothstep(0.015, 0.03, rr) * (1.0 - smoothstep(0.08, 0.13, rr));
			o = over(o, ink, crease * 0.45 * retract * inside);
		}
	}
	o.a *= 1.0 - 0.4 * dead;
	if (night > 0.0) {
		// Night (深海荧光): lit from within in its own colour.
		o.rgb = mix(o.rgb, nt_lin(night_glow(nt_srgb(max(o.rgb, vec3(0.0))), nt_srgb(max(glass, vec3(0.0))))), night);
		o.a = mix(o.a, min(1.0, o.a * 1.25), night);
	}
	COLOR = o;
}
