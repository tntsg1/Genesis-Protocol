// The campaign's way into a level (eighth round): the frame the player was
// looking at, frozen, with a lens opening in it at the chosen station. The
// opening grows (radius, pixels) until it swallows the screen; through it
// the live dish of the new level racks into focus. Round the rim the frozen
// page bends outward like glass, a bright cyan ring with degree ticks rides
// the edge, and the page itself rushes toward the viewer and softens (push).
// radius < 0: no opening at all (a veil that only fades, `alpha`).
shader_type canvas_item;

uniform sampler2D snap : filter_linear_mipmap;
uniform vec2 view = vec2(1920.0, 1080.0);
uniform vec2 centre = vec2(960.0, 540.0);
uniform float radius = 0.0;
uniform float push = 0.0;
uniform float alpha = 1.0;

void fragment() {
	vec2 p = UV * view;
	vec2 d = p - centre;
	float r = length(d);
	vec2 n = d / max(r, 1e-3);
	float rim = radius < 0.0 ? 1e6 : r - radius;
	// The page rushes in round the opening, and bends just outside its rim.
	vec2 q = centre + d / (1.0 + 0.4 * push);
	q += n * 26.0 * exp(-max(rim, 0.0) / 46.0) * step(0.0, radius) * smoothstep(0.0, 40.0, radius);
	float lod = push * 3.5;
	vec2 uv = q / view;
	// Lateral colour where it bends.
	float lc = 0.004 * exp(-max(rim, 0.0) / 60.0) * step(0.0, radius);
	vec3 col;
	col.r = textureLod(snap, uv + n * lc, lod).r;
	col.g = textureLod(snap, uv, lod).g;
	col.b = textureLod(snap, uv - n * lc, lod).b;
	// Lift toward white as it goes (the lamp floods through).
	col = mix(col, vec3(0.97, 0.99, 1.0), push * 0.35);
	float a = smoothstep(-1.5, 1.5, rim) * alpha;
	// The rim: a bright ring, a soft halo, degree ticks just outside it.
	if (radius >= 0.0) {
		float ring = exp(-abs(rim) / 1.6);
		float halo = exp(-max(rim, 0.0) / 30.0) * smoothstep(-8.0, 0.0, rim);
		float ang = atan(d.y, d.x);
		float tick = step(fract(ang / (6.2831853 / 72.0)), 0.1) * step(5.0, rim) * step(rim, 13.0);
		float inner = exp(-abs(rim + 22.0) / 0.9) * 0.45;
		vec3 hot = vec3(0.6, 1.6, 1.9);
		col = mix(col, vec3(0.7, 0.95, 1.0), halo * 0.5);
		col = mix(col, hot, max(ring, tick * 0.7));
		a = max(a, max(ring, inner) * alpha);
		col = mix(col, hot, inner * step(rim, 0.0));
	}
	COLOR = vec4(col, a);
}
