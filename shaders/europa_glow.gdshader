// The campaign model's light pieces (ninth round): rings, the shaft's core
// and glass, outlines, ticks, the derrick's ink lines. Unlit; `energy` over
// 1 blooms in the interface's glow; `fres` > 0 fades the faces looking at
// the camera (glass). Vertex colour multiplies (ImmediateMesh lines).
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

uniform vec4 tint : source_color = vec4(1.0);
uniform float energy = 1.0;
uniform float fres = 0.0;
uniform float build_y = -100.0;
uniform float form = 1.0; // the chapter change: its scene's lines fade with it

varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (wp.y < build_y) {
		discard;
	}
	float f = 1.0;
	if (fres > 0.0) {
		f = mix(1.0, pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 2.0), fres);
	}
	ALBEDO = tint.rgb * COLOR.rgb * energy;
	ALPHA = clamp(tint.a * COLOR.a * f * form, 0.0, 1.0);
}
