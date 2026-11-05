shader_type canvas_item;
// The water's chemical signals as a haze under the cells
// (scripts/dish_marks.gd): R = signal A, G = signal B, raw concentration on
// the simulation's grid. Softened with a few taps (the grid is coarse), faint
// where little is left, slowly shimmering so it reads as something in the
// water rather than a stain. Light, never dark.

uniform sampler2D sig : filter_linear;
uniform vec2 texel = vec2(0.008);
uniform vec4 col_a : source_color = vec4(0.1, 0.68, 0.6, 1.0);
uniform vec4 col_b : source_color = vec4(0.5, 0.4, 0.82, 1.0);

void fragment() {
	vec2 s = vec2(0.0);
	float w = 0.0;
	for (int i = -2; i <= 2; i++) {
		for (int j = -2; j <= 2; j++) {
			float k = exp(-float(i * i + j * j) / 3.0);
			s += texture(sig, UV + vec2(float(i), float(j)) * texel).rg * k;
			w += k;
		}
	}
	s /= w;
	float shimmer = 0.85 + 0.15 * sin(UV.x * 90.0 + TIME * 0.7) * sin(UV.y * 80.0 - TIME * 0.5);
	float a = smoothstep(0.004, 0.3, s.r) * 0.46 * shimmer;
	float b = smoothstep(0.004, 0.3, s.g) * 0.46 * shimmer;
	float t = a + b;
	vec3 c = t > 0.0 ? (col_a.rgb * a + col_b.rgb * b) / t : col_a.rgb;
	// A brighter rim where the haze is thickest (the front of a call).
	float rim = smoothstep(0.25, 0.6, max(s.r, s.g)) * 0.18;
	COLOR = vec4(mix(c, vec3(1.0), rim), clamp(t + rim * 0.5, 0.0, 0.42));
}
