// A holographic slice through the campaign model (ninth round): a grid at
// 0.5 km, a bright border, a scan line running across. One marks the
// selected station's depth; another rides the top-down build.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

uniform vec4 tint : source_color = vec4(0.07, 0.65, 0.73, 1.0);
uniform float amount = 0.0;
uniform vec2 extent = vec2(4.0, 2.6);
uniform float fill = 0.06;
uniform float grid_a = 0.28;

varying vec2 lp;

void vertex() {
	lp = VERTEX.xz;
}

void fragment() {
	vec2 q = lp;
	vec2 fw = max(fwidth(q), vec2(1e-4));
	vec2 g = abs(fract(q * 2.0 + 0.5) - 0.5) * 0.5;
	float grid = max(1.0 - smoothstep(0.0, fw.x * 1.2, g.x), 1.0 - smoothstep(0.0, fw.y * 1.2, g.y));
	vec2 e = extent - abs(q);
	float edge = 1.0 - smoothstep(0.0, max(fw.x, fw.y) * 2.5, min(e.x, e.y));
	float sx = mix(-extent.x, extent.x, fract(TIME * 0.32));
	float scan = exp(-abs(q.x - sx) * 5.0);
	float a = amount * (fill + grid * grid_a + edge * 0.9 + scan * 0.22);
	ALBEDO = tint.rgb * (1.0 + edge * 1.6 + scan * 1.2);
	ALPHA = clamp(a, 0.0, 1.0);
}
