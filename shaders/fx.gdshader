// Effect particles, simulated entirely here: the CPU writes a slot once when
// a particle is born and never touches it again. Position, size and fade are
// functions of (now - birth). Expired slots collapse to nothing in vertex().
// Instance data (scripts/fx.gd):
//   transform  origin, uniform scale = particle size in world units
//   COLOR      rgb colour, a = kind (0 mote, 1 hairline ring, 2 spark,
//              3 bubble, 4 star, 5 soft flash, 6 DNA helix, 7 reticle,
//              8 dust)
//   CUSTOM     (birth time, vx, vy, life)
shader_type canvas_item;
render_mode blend_mix, unshaded;

uniform float now = 0.0;
uniform float drag = 2.2;

varying vec4 v_color;
varying float v_t;     // 0..1 through the particle's life
varying float v_kind;
varying vec2 v_dir;

void vertex() {
	float age = now - INSTANCE_CUSTOM.x;
	float life = max(INSTANCE_CUSTOM.w, 1e-3);
	v_t = age / life;
	v_color = COLOR;
	v_kind = COLOR.a;
	vec2 vel = INSTANCE_CUSTOM.yz;
	v_dir = length(vel) > 1e-3 ? normalize(vel) : vec2(1.0, 0.0);
	if (age < 0.0 || v_t > 1.0) {
		VERTEX = vec2(0.0);
	} else {
		// Water drag: v * (1 - e^-kt) / k. Bubbles also rise slowly.
		vec2 off = vel * (1.0 - exp(-drag * age)) / drag;
		if (v_kind > 2.5 && v_kind < 3.5) {
			off += vec2(sin(age * 3.0 + INSTANCE_CUSTOM.x * 7.0) * 3.0, -age * 14.0);
		}
		float scale = length(MODEL_MATRIX[0].xy);
		float grow = 1.0;
		if (v_kind > 0.5 && v_kind < 1.5) {
			grow = 0.25 + 0.75 * (1.0 - pow(1.0 - v_t, 3.0)); // ring expands
		} else if (v_kind > 7.5) {
			grow = 1.0 - 0.45 * v_t; // dust settles and dissolves
		} else if (v_kind > 6.5) {
			grow = 1.0 - 0.5 * (1.0 - pow(1.0 - min(v_t * 1.6, 1.0), 3.0)); // reticle closes in
		} else if (v_kind > 5.5) {
			grow = 0.4 + 0.6 * sin(min(v_t * 3.1416 * 1.6, 3.1416 * 0.5));
		} else if (v_kind > 4.5) {
			grow = 0.6 + 0.4 * v_t;
		} else if (v_kind > 3.5) {
			grow = 0.5 + 0.8 * sin(min(v_t * 3.1416 * 1.3, 3.1416));
		}
		VERTEX = VERTEX * grow + off / max(scale, 1e-3);
	}
}

void fragment() {
	// QuadMesh UV.y runs bottom-to-top on a 2D canvas: flip to screen space.
	vec2 p = vec2(UV.x - 0.5, 0.5 - UV.y) * 2.0;
	float r = length(p);
	float fade = 1.0 - smoothstep(0.55, 1.0, v_t);
	float px = fwidth(r);
	vec3 col = v_color.rgb;
	float a = 0.0;
	if (v_kind < 0.5) {
		// Glowing droplet: bright core, coloured rim, soft halo.
		a = (smoothstep(1.0, 0.55, r) * 0.9 + (1.0 - smoothstep(0.55, 1.0, r)) * 0.25) * fade;
		col = mix(col, vec3(1.0), smoothstep(0.45, 0.0, r) * 0.65);
	} else if (v_kind < 1.5) {
		// Hairline ring: about a pixel wide at any zoom, fading as it spreads.
		float ring = clamp(1.0 - abs(r - 0.85) / (px * 1.3), 0.0, 1.0);
		a = ring * 0.55 * pow(1.0 - v_t, 1.5);
	} else if (v_kind < 2.5) {
		// Streak along the direction of travel.
		vec2 q = vec2(dot(p, v_dir), dot(p, vec2(-v_dir.y, v_dir.x)));
		a = smoothstep(1.0, 0.0, abs(q.x)) * smoothstep(0.2, 0.0, abs(q.y)) * fade;
		col = mix(col, vec3(1.0), 0.4);
	} else if (v_kind < 3.5) {
		float ring = clamp(1.0 - abs(r - 0.8) / max(0.14, px), 0.0, 1.0);
		float glint = smoothstep(0.3, 0.0, length(p - vec2(-0.3, -0.3)));
		a = (ring * 0.8 + glint * 0.9 + 0.08 * step(r, 0.8)) * fade;
		col = mix(col, vec3(1.0), 0.5);
	} else if (v_kind < 4.5) {
		// Four-point sparkle.
		float arms = max(smoothstep(0.16, 0.0, abs(p.x)) * smoothstep(1.0, 0.0, abs(p.y)),
				smoothstep(0.16, 0.0, abs(p.y)) * smoothstep(1.0, 0.0, abs(p.x)));
		a = max(arms, smoothstep(0.4, 0.0, r)) * fade;
		col = mix(col, vec3(1.0), 0.55);
	} else if (v_kind < 5.5) {
		a = smoothstep(1.0, 0.0, r) * (1.0 - v_t) * 0.55;
		col = mix(col, vec3(1.0), 0.6);
	} else if (v_kind > 7.5) {
		// Fine grain of nutrient: a soft pale dot.
		a = smoothstep(1.0, 0.2, r) * 0.55 * (1.0 - v_t) * smoothstep(0.0, 0.08, v_t);
	} else if (v_kind > 6.5) {
		// Focusing reticle: a hairline circle in four arcs with inward ticks.
		float ang = atan(p.y, p.x);
		float arcs = smoothstep(0.1, 0.16, abs(fract(ang / 1.5708 + 0.5) - 0.5));
		float ring = clamp(1.0 - abs(r - 0.85) / (px * 1.2), 0.0, 1.0) * arcs;
		vec2 q = abs(p);
		float tick = max(step(q.y, px * 0.7) * step(0.62, q.x) * step(q.x, 0.8),
				step(q.x, px * 0.7) * step(0.62, q.y) * step(q.y, 0.8));
		float in_a = smoothstep(0.0, 0.12, v_t);
		a = max(ring * 0.8, tick * 0.9) * in_a * (1.0 - smoothstep(0.6, 1.0, v_t));
	} else {
		// A short double helix, upright, twisting as it rises.
		float ph = v_t * 9.0;
		float s = sin(p.y * 4.2 + ph);
		float w = 0.035 + px;
		float s1 = smoothstep(w, w * 0.4, abs(p.x - 0.34 * s));
		float s2 = smoothstep(w, w * 0.4, abs(p.x + 0.34 * s));
		float rung = smoothstep(0.07, 0.02, abs(fract(p.y / 0.3) - 0.5) * 0.3) * step(abs(p.x), 0.34 * abs(s));
		float span = smoothstep(0.95, 0.75, abs(p.y));
		a = max(max(s1, s2), rung * 0.5) * span * fade * 0.8;
	}
	COLOR = vec4(pow(col, vec3(2.2)), clamp(a, 0.0, 1.0));
}
