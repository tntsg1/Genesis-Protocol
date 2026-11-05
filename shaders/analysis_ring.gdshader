// Analysis mode: one instance per organism (SimCore.build_analysis_buffer).
// A fine dashed ring marks how far it can see, tinted by its species, with a
// small solid ring for its body. Flat 2D ink on the pale diagram.
//   COLOR.rgb species colour, CUSTOM.x action, CUSTOM.y body / vision ratio
shader_type canvas_item;
render_mode blend_mix, unshaded;

#include "res://shaders/night.gdshaderinc"

uniform float fade = 1.0;
// Vision rings only read when zoomed in; far out they would pile up.
uniform float vision = 1.0;

varying vec4 v_custom;

void vertex() {
	v_custom = INSTANCE_CUSTOM;
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float px = fwidth(r);
	vec3 ink = mix(COLOR.rgb * 0.62, vec3(0.16, 0.27, 0.33), 0.35);
	// Vision ring: dashed, 1 px.
	float ang = atan(p.y, p.x);
	float dash = step(0.45, fract(ang / 6.2832 * 48.0));
	float ring = clamp(1.0 - abs(r - 0.985) / max(px, 1e-4), 0.0, 1.0) * dash;
	// Body outline.
	float b = v_custom.y;
	float body = clamp(1.0 - abs(r - b) / max(px * 1.2, 1e-4), 0.0, 1.0);
	float a = (ring * 0.4 * vision + body * 0.85) * fade;
	ink = mix(ink, night_ui(ink), night); // (night: light lines on the dark water)
	COLOR = vec4(pow(ink, vec3(2.2)), clamp(a, 0.0, 1.0));
}
