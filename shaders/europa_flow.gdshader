// Convection in the campaign model's ocean (tenth round): thin streamlines
// from the vents up under the ice and round again, faint along their whole
// length with bright comets running along them. UV.x is the distance along
// the line (km), UV.y the line's own phase.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 tint : source_color = vec4(0.0, 0.62, 0.74, 1.0);
uniform float build_y = -100.0;
uniform float amount = 1.0;

varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (wp.y < build_y) {
		discard;
	}
	float f = fract(UV.x * 0.32 - TIME * 0.11 + UV.y);
	float head = smoothstep(0.7, 0.995, f) * (1.0 - smoothstep(0.995, 1.0, f));
	ALBEDO = tint.rgb * (1.0 + head * 1.8);
	ALPHA = clamp((0.16 + head * 0.85) * amount, 0.0, 1.0);
}
