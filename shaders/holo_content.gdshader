// Holographic content: everything inside a holo panel draws through this
// (the panel's body carries it, its descendants use the parent material).
//   appear  0 -> 1 on materialise: the content flickers on (stepped noise)
//           with its colour channels split apart and closing in
//   glitch  a brief chromatic split (a press, a change)
//   shift   parallax, pixels (the visor moves against the cursor)
// Glyphs sample the font atlas, so the split shows on text as red / cyan
// fringes; lines and fills (a white texture) are unaffected.
shader_type canvas_item;

#include "res://shaders/night.gdshaderinc"

uniform float appear = 1.0;
uniform float glitch = 0.0;
uniform vec2 shift = vec2(0.0);
uniform float seed = 0.0;
// 3D tilt toward the cursor, as in holo_frame (same pivot and lean).
uniform vec2 tilt = vec2(0.0);
uniform vec2 pivot = vec2(0.0);
// Scan wipe, as in holo_frame.
uniform vec3 wipe = vec3(0.0, 1.0, 9.0);

varying vec4 v_col; // the vertex colour alone (COLOR in fragment includes the texture)

void vertex() {
	VERTEX += shift;
	v_col = COLOR;
	if (dot(tilt, tilt) > 1e-8) {
		vec2 c = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
		vec2 d = c - pivot;
		float w = 1.0 - dot(d, tilt);
		c = pivot + d / max(w, 0.5);
		VERTEX = (inverse(MODEL_MATRIX) * vec4(c, 0.0, 1.0)).xy;
	}
}

float hash1(float n) {
	return fract(sin(n * 127.1 + seed * 311.7) * 43758.5453);
}

void fragment() {
	vec3 rgb = COLOR.rgb;
	// Night: the content's colours to the night palette (COLOR is linear).
	if (night > 0.0) {
		rgb = mix(rgb, night_ui_lin(rgb), night);
	}
	float a = COLOR.a;
	float split = glitch + (1.0 - appear) * 2.5;
	if (split > 0.01) {
		vec2 o = vec2(TEXTURE_PIXEL_SIZE.x * 1.8 * split, 0.0);
		float a0 = texture(TEXTURE, UV).a;
		float ar = texture(TEXTURE, UV - o).a;
		float ab = texture(TEXTURE, UV + o).a;
		// Fringes where a shifted copy lands outside the glyph.
		float k = min(split, 1.0) * 0.8 * v_col.a;
		vec3 fringe = vec3(1.0, 0.25, 0.45) * max(ar - a0, 0.0) + vec3(0.1, 0.85, 1.0) * max(ab - a0, 0.0);
		float fa = max(max(ar, ab) - a0, 0.0) * k;
		float total = a + fa;
		rgb = (rgb * a + fringe * k) / max(total, 1e-4);
		a = min(total, 1.0);
	}
	if (appear < 1.0) {
		// Stepped flicker: on more and more often as it materialises.
		float on = step(hash1(floor(TIME * 26.0)), appear * 1.25);
		a *= mix(0.12, 1.0, on) * smoothstep(0.0, 0.25, appear);
	}
	// A faint scan shimmer on the light.
	a *= 0.93 + 0.07 * (0.5 + 0.5 * sin(FRAGCOORD.y * 2.1 - TIME * 6.0));
	if (wipe.z < 8.0) {
		// Ahead of the front: gone; on it: the type burns bright cyan.
		float g = dot(SCREEN_UV, wipe.xy) - wipe.z;
		a *= 1.0 - smoothstep(-0.002, 0.0, g);
		rgb = mix(rgb, vec3(0.55, 1.6, 1.9), exp(-abs(g) * 120.0) * 0.9);
	}
	COLOR = vec4(rgb, a);
}
