// Holographic panel (the frameless HUD, after the fourth round: "too
// ordinary"). No box: a feathered haze of light behind the content (with the
// view behind it softly blurred, so text reads over the dish), a glowing
// header rule with a tab and a diamond at its start, a faint rail down the
// left, a corner tick, drifting scanlines. The quad is grown by `margin` so
// the haze and glow can spill past the panel's rectangle.
// Entrance (GlassPanel.appear): `trace` draws the rule from the left with a
// bright head, `haze_in` brings the haze up (the panel flickers on its own
// via the content shader). `flash` = something changed. `shift` = parallax.
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec2 size = vec2(300.0, 200.0);
uniform float margin = 64.0;
uniform vec4 haze : source_color = vec4(0.975, 0.99, 1.0, 0.46);
uniform vec4 accent : source_color = vec4(0.07, 0.65, 0.73, 1.0);
uniform vec4 ink : source_color = vec4(0.11, 0.2, 0.25, 1.0);
uniform float trace = 1.0;
uniform float haze_in = 1.0;
uniform float flash = 0.0;
uniform float highlight = 0.0;
uniform vec2 shift = vec2(0.0);
uniform float blur = 3.6;
// 3D tilt toward the cursor (fifth round): `tilt` leans the panel (the side
// toward the cursor comes forward), about `pivot` (canvas pixels).
uniform vec2 tilt = vec2(0.0);
uniform vec2 pivot = vec2(0.0);
// Scan wipe (eighth round, the transitions): the panel shows only where
// dot(SCREEN_UV, wipe.xy) < wipe.z, with a bright edge on the front. z >= 8:
// off. GlassPanel.set_wipe() drives it for the frame and the content.
uniform vec3 wipe = vec3(0.0, 1.0, 9.0);

varying vec2 v_p; // panel space, pixels (0,0 = top-left of the rectangle)

void vertex() {
	vec2 g = UV * 2.0 - 1.0;
	VERTEX += g * margin + shift;
	v_p = UV * (size + 2.0 * margin) - margin;
	if (dot(tilt, tilt) > 1e-8) {
		vec2 c = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
		vec2 d = c - pivot;
		float w = 1.0 - dot(d, tilt);
		c = pivot + d / max(w, 0.5);
		VERTEX = (inverse(MODEL_MATRIX) * vec4(c, 0.0, 1.0)).xy;
	}
}

float box(vec2 p, vec2 s, float r) {
	vec2 h = s * 0.5;
	vec2 q = abs(p - h) - (h - vec2(r));
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 p = v_p;
	float d = box(p, size, 8.0);

	// The lens under the data: no edge anywhere. The water behind is
	// thrown well out of focus and lifted toward white, strongest where the
	// text starts (top left) and melting away over ~60 px past the panel.
	float fog = (1.0 - smoothstep(-36.0, 58.0, d)) * haze_in;
	fog *= fog * (3.0 - 2.0 * fog);
	vec2 sp = SCREEN_PIXEL_SIZE * exp2(blur) * 0.8;
	vec3 behind = textureLod(screen_tex, SCREEN_UV, blur).rgb * 2.0;
	behind += textureLod(screen_tex, SCREEN_UV + vec2(sp.x, sp.y), blur).rgb;
	behind += textureLod(screen_tex, SCREEN_UV + vec2(-sp.x, sp.y), blur).rgb;
	behind += textureLod(screen_tex, SCREEN_UV + vec2(sp.x, -sp.y), blur).rgb;
	behind += textureLod(screen_tex, SCREEN_UV + vec2(-sp.x, -sp.y), blur).rgb;
	behind /= 6.0;
	vec2 rel = p / max(size, vec2(1.0));
	float lift = haze.a * mix(1.12, 0.78, clamp(length(rel * vec2(0.7, 1.0)), 0.0, 1.0)) + 0.1 * highlight;
	vec3 col = mix(behind, haze.rgb, clamp(lift, 0.0, 1.0));
	float a = fog;
	// Scanlines drifting down through the haze.
	float sl = 0.5 + 0.5 * sin(FRAGCOORD.y * 2.1 - TIME * 6.0);
	col = mix(col, accent.rgb, sl * 0.035 * fog);

	// Header rule along the top, drawn from the left (trace) with a head.
	float x0 = -12.0;
	float len = size.x + 12.0;
	float along = clamp((p.x - x0) / len, 0.0, 1.0);
	float on_rule = step(x0, p.x) * step(p.x, size.x) * step(along, trace + 0.001);
	float ry = abs(p.y - 0.5);
	float rule = clamp(1.0 - ry, 0.0, 1.0) * on_rule;
	// The tab: a thicker segment at the left, longer when highlighted.
	float tab_w = 34.0 + 40.0 * highlight;
	float tab = step(0.0, p.x) * step(p.x, tab_w) * step(abs(p.y - 1.0), 1.5) * step(p.x / len, trace);
	// Glow round the rule (analytic: the UI layer has no bloom).
	float glow = exp(-ry * 0.45) * on_rule * (0.22 + 0.3 * highlight + 0.5 * flash);
	float head = exp(-length(vec2((p.x - (x0 + len * trace)) * 0.25, ry * 0.6))) * step(trace, 0.999) * step(0.001, trace);
	// Diamond at the rule's start.
	vec2 dq = abs(p - vec2(x0, 0.5));
	float diamond = clamp(4.0 - (dq.x + dq.y), 0.0, 1.0) * step(0.02, trace);
	// Rail down the left, fading; corner tick bottom-right.
	float rail = clamp(1.0 - abs(p.x + 6.0), 0.0, 1.0) * step(0.0, p.y) * (1.0 - smoothstep(0.0, size.y * 0.6, p.y)) * trace;
	vec2 cq = size - p;
	float tick = (step(abs(cq.x - 2.0), 0.7) * step(0.0, cq.y) * step(cq.y, 9.0) + step(abs(cq.y - 2.0), 0.7) * step(0.0, cq.x) * step(cq.x, 9.0)) * haze_in;

	vec3 lit = mix(accent.rgb, vec3(1.0), 0.35);
	col = mix(col, accent.rgb, glow * 0.6);
	a = max(a, glow * 0.7);
	col = mix(col, accent.rgb, max(rule * 0.85, tab));
	a = max(a, max(rule * 0.85, tab));
	col = mix(col, lit, clamp(head, 0.0, 1.0));
	a = max(a, clamp(head, 0.0, 1.0));
	col = mix(col, accent.rgb, diamond);
	a = max(a, diamond);
	col = mix(col, accent.rgb, rail * 0.5);
	a = max(a, rail * 0.5);
	col = mix(col, ink.rgb, tick * 0.6);
	a = max(a, tick * 0.6);
	// The change flash washes the haze.
	col = mix(col, accent.rgb, flash * 0.18 * fog);
	if (wipe.z < 8.0) {
		float g = dot(SCREEN_UV, wipe.xy) - wipe.z;
		float edge = exp(-abs(g) * 220.0) * step(d, 6.0);
		a *= 1.0 - smoothstep(-0.003, 0.0, g);
		col = mix(col, vec3(0.6, 1.5, 1.8), edge * 0.9);
		a = max(a, edge * 0.85);
	}
	COLOR = vec4(col, a * COLOR.a);
}
