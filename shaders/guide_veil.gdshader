shader_type canvas_item;

#include "res://shaders/night.gdshaderinc"
// The guide's veil (scripts/campaign/tutorial.gd): pale frosted white over
// the whole screen but a rounded hole over the step's target, the hole's rim
// glowing faintly in the accent. Light, never dark (the lab is white glass).

uniform vec2 size = vec2(1920.0, 1080.0);
uniform vec4 hole = vec4(0.0); // x, y, w, h in pixels
uniform vec4 hole2 = vec4(0.0); // a second one (a drag's source); w 0 = none
uniform float alpha = 0.0;
uniform float radius = 14.0;
uniform vec4 tint : source_color = vec4(0.95, 0.975, 1.0, 0.46); // (0.66 washed the rules' text out)
uniform vec4 glow : source_color = vec4(0.16, 0.62, 0.78, 1.0);

float box(vec2 p, vec4 h) {
	vec2 c = h.xy + h.zw * 0.5;
	float r = min(radius, min(h.z, h.w) * 0.5);
	vec2 q = abs(p - c) - h.zw * 0.5 + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 p = UV * size;
	float d = box(p, hole);
	if (hole2.z > 0.0) {
		d = min(d, box(p, hole2));
	}
	float veil = smoothstep(0.0, 22.0, d);
	float rim = exp(-max(d, 0.0) / 26.0) * step(0.0, d);
	// (Night: a dark warm veil, a touch denser.)
	vec4 col = vec4(mix(tint.rgb, night_ui_lin(tint.rgb), night), mix(tint.a, min(tint.a * 1.3, 0.8), night) * veil);
	col.rgb = mix(col.rgb, glow.rgb, rim * 0.45);
	col.a = max(col.a, rim * 0.22);
	col.a *= alpha;
	COLOR = col;
}
