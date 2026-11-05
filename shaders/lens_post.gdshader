// The microscope's lens over the dish (fifth round: "画面层次"), between the
// dish and the interface. The eye goes where the lamp is:
//   focus     the middle of the view stays sharp; toward the edges the
//             water falls out of focus (depth of field, a ring of taps over
//             the screen's mip chain), which also calms what lies behind
//             the panels
//   falloff   the edges go cooler and a little dimmer (never dark: the
//             dish is bright and cheerful), the centre gets the lamp's lift
//   fringe    a hint of lateral colour at the rim, as real optics do
// `amount` eases to 0 where everything must read (analysis mode).
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float amount = 1.0;
// The sharp middle: an ellipse in screen units (x stretched by the aspect).
uniform float focus_r = 0.36;
uniform float focus_soft = 0.42;
uniform float max_blur = 3.2; // mip level at the far corners
uniform vec2 aspect = vec2(1.7778, 1.0);
// The main menu's "退出" preview dims the lamp a little; the dive into the
// dish racks focus across the whole view (0 sharp .. 1 fully soft).
uniform float dim = 0.0;
uniform float defocus = 0.0;

const vec2 TAPS[8] = vec2[](
	vec2(1.0, 0.0), vec2(0.7071, 0.7071), vec2(0.0, 1.0), vec2(-0.7071, 0.7071),
	vec2(-1.0, 0.0), vec2(-0.7071, -0.7071), vec2(0.0, -1.0), vec2(0.7071, -0.7071));

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 p = (uv - 0.5) * aspect;
	// Slightly wider than tall: the panels sit at the sides.
	float r = length(p * vec2(0.86, 1.0));
	float out_k = max(smoothstep(focus_r, focus_r + focus_soft, r) * amount, defocus);
	vec3 sharp = textureLod(screen_tex, uv, 0.0).rgb;
	vec3 col = sharp;
	if (out_k > 0.002) {
		float lod = out_k * max_blur;
		vec2 px = SCREEN_PIXEL_SIZE * exp2(lod) * 0.9;
		vec3 acc = textureLod(screen_tex, uv, lod).rgb * 2.0;
		for (int i = 0; i < 8; i++) {
			acc += textureLod(screen_tex, uv + TAPS[i] * px, lod).rgb;
		}
		vec3 blurred = acc / 10.0;
		// Lateral colour: red and blue drift apart radially at the rim.
		vec2 dir = normalize(p + 1e-5) / aspect;
		float ca = out_k * out_k * 2.2;
		blurred.r = mix(blurred.r, textureLod(screen_tex, uv + dir * SCREEN_PIXEL_SIZE.x * ca * 3.0, lod).r, 0.6);
		blurred.b = mix(blurred.b, textureLod(screen_tex, uv - dir * SCREEN_PIXEL_SIZE.x * ca * 3.0, lod).b, 0.6);
		col = mix(sharp, blurred, smoothstep(0.0, 0.55, out_k));
	}
	// Cool, slightly dimmer edges.
	float edge = smoothstep(focus_r * 0.6, focus_r + focus_soft * 1.3, r);
	col *= mix(vec3(1.0), vec3(0.83, 0.9, 0.96), edge * (0.35 + 0.65 * amount));
	// Highlight roll-off: the open water under the lamp no longer clips to
	// flat white (it read as overexposed); 0.7..1 eases into 0.7..0.86 (linear)
	// with a faint cool tint, and what blooms above 1 keeps its headroom.
	float l = max(col.r, max(col.g, col.b));
	if (l > 0.7) {
		float x = min(l, 1.0) - 0.7;
		float m = 0.7 + x / (1.0 + x * 3.0) + max(l - 1.0, 0.0);
		col *= m / l;
		// Clear water, not cream: the lamp's warmth shows once highlights
		// stop clipping, so pull them toward a neutral, faintly cool white.
		float k = clamp(x / 0.3, 0.0, 1.0);
		float lum = dot(col, vec3(0.2126, 0.7152, 0.0722));
		// Only the near-whites (the water), never the cells' colours.
		float mn = min(col.r, min(col.g, col.b));
		float sat = (max(col.r, max(col.g, col.b)) - mn) / max(max(col.r, max(col.g, col.b)), 1e-4);
		float water = 1.0 - smoothstep(0.05, 0.16, sat);
		col = mix(col, vec3(lum) * vec3(0.965, 0.99, 1.02), 0.7 * k * water);
	}
	if (dim > 0.0) {
		float lum = dot(col, vec3(0.2126, 0.7152, 0.0722));
		col = mix(col, vec3(lum) * vec3(0.9, 0.95, 1.0), dim * 0.35) * (1.0 - 0.2 * dim * (0.4 + 0.6 * edge));
	}
	COLOR = vec4(col, 1.0);
}
