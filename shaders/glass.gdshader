// Frosted light-glass panel: blurred view of the world behind, a light tint,
// a hairline frame with a lit top edge (the lamp catching the glass), accent
// corner brackets. Flat 2D.
// Entrance (GlassPanel.appear, all 0 -> 1): `trace` draws the frame round
// from the top-left corner with a bright head, `bracket_in` grows the
// corner brackets (with a little overshoot), `scan` sweeps the reveal line
// down. `flash` is a brief accent wash (something changed in the panel).
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec2 size = vec2(300.0, 200.0);
uniform float radius = 10.0;
uniform vec4 tint : source_color = vec4(0.975, 0.99, 1.0, 0.74);
uniform vec4 edge : source_color = vec4(0.24, 0.52, 0.62, 0.35);
uniform vec4 accent : source_color = vec4(0.07, 0.65, 0.73, 1.0);
uniform float bracket = 14.0;
uniform float scan = 1.0;
uniform float trace = 1.0;
uniform float bracket_in = 1.0;
uniform float flash = 0.0;
uniform float blur = 3.0;
uniform float highlight = 0.0; // hover / focus glow 0..1
uniform float desat = 0.0; // the view behind drained of colour (the designer's room)

void fragment() {
	vec2 p = UV * size;
	vec2 h = size * 0.5;
	vec2 q = abs(p - h) - (h - vec2(radius));
	float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
	float inside = clamp(0.5 - d, 0.0, 1.0);

	vec3 behind = textureLod(screen_tex, SCREEN_UV, blur).rgb;
	behind = mix(behind, vec3(dot(behind, vec3(0.299, 0.587, 0.114))), desat);
	vec3 col = mix(behind, tint.rgb, tint.a);
	col = mix(col, vec3(1.0), 0.06 * (1.0 - UV.y));

	// How far round the frame this pixel is (0 at the top-left corner,
	// clockwise), for the trace.
	vec2 c = p - h;
	float round_at = fract(atan(c.y * size.x / max(size.y, 1.0), c.x) / 6.2831853 + 0.5 - 0.125 + 1.0);
	float traced = smoothstep(trace + 0.004, trace - 0.004, round_at) * step(0.001, trace);
	float head = exp(-abs(round_at - trace) * 60.0) * step(trace, 0.999) * step(0.001, trace);

	// Hairline frame (1 px), brighter when highlighted; the top edge lit.
	float frame = clamp(1.0 - abs(d + 0.6), 0.0, 1.0);
	float lit = smoothstep(h.y * 1.2, 0.0, p.y);
	vec3 frame_col = mix(edge.rgb, accent.rgb, highlight);
	col = mix(col, frame_col, frame * mix(edge.a, 0.9, highlight) * traced * (1.0 - 0.5 * lit));
	col = mix(col, vec3(1.0), clamp(1.0 - abs(d + 1.7), 0.0, 1.0) * lit * 0.85 * traced);
	col = mix(col, accent.rgb, frame * head);
	// Accent corner brackets, inset 4 px, growing in.
	float bl = bracket * bracket_in;
	vec2 m = min(p, size - p);
	float in_corner = step(m.x, bl) * step(m.y, bl);
	float bx = clamp(1.0 - abs(m.x - 4.0) * 1.2, 0.0, 1.0) * step(m.y, bl) * step(4.0, m.y);
	float by = clamp(1.0 - abs(m.y - 4.0) * 1.2, 0.0, 1.0) * step(m.x, bl) * step(4.0, m.x);
	col = mix(col, accent.rgb, max(bx, by) * in_corner * 0.85 * step(0.01, bracket_in));
	// Inner glow when highlighted, and the change flash.
	col = mix(col, accent.rgb, highlight * 0.07 * smoothstep(-16.0, 0.0, d));
	col = mix(col, accent.rgb, flash * 0.16 * smoothstep(-26.0, 0.0, d));

	// Appear: content above the scan line is revealed, the line itself glows.
	float y = scan * (size.y + 24.0) - 12.0;
	float reveal = smoothstep(y + 8.0, y - 8.0, p.y);
	float line = exp(-abs(p.y - y) * 0.3) * step(scan, 0.999);
	col = mix(col, mix(accent.rgb, vec3(1.0), 0.35), line * 0.7);
	// Keep the node's modulate: writing COLOR outright would drop it.
	COLOR = vec4(col, inside * max(max(reveal, line * 0.8), frame * traced) * COLOR.a);
}
