// The body page's instruments (scope, gene strip, flow tank) as deep slate-blue
// glass instead of black: the room behind shows through, blurred; a darkfield
// light pools under the specimen (`focus`, `focus_r` in pixels); slow caustics
// drift over it, a fine grain lives in it, the rim catches the lamp along the
// top and the edges sink into shadow. Flat 2D.
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec2 size = vec2(880.0, 600.0);
uniform float radius = 8.0;
uniform vec4 base : source_color = vec4(0.095, 0.16, 0.215, 0.84);
uniform vec4 light : source_color = vec4(0.22, 0.52, 0.56, 1.0);
uniform vec2 focus = vec2(440.0, 300.0);
uniform float focus_r = 260.0;
uniform float focus_a = 0.55;
uniform float caustic = 1.0;
uniform float flash = 0.0; // a brief brightening (something went in)

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 p = UV * size;
	vec2 h = size * 0.5;
	vec2 q = abs(p - h) - (h - vec2(radius));
	float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
	float inside = clamp(0.5 - d, 0.0, 1.0);

	vec3 behind = textureLod(screen_tex, SCREEN_UV, 4.5).rgb;
	vec3 col = mix(behind, base.rgb, base.a);
	// A faint cool gradient, lighter at the top: glass under a lamp.
	col += vec3(0.02, 0.035, 0.04) * (1.0 - UV.y);

	// The darkfield light under the specimen.
	vec2 f = (p - focus) / max(focus_r, 1.0);
	float pool = exp(-dot(f, f) * 1.6);
	col += light.rgb * pool * (focus_a + 0.25 * flash);

	// Caustics: two slow interfering wave fields, sharpened.
	float t = TIME;
	float a = sin(p.x * 0.019 + t * 0.32 + 2.0 * sin(p.y * 0.014 - t * 0.21));
	float b = sin(p.y * 0.023 - t * 0.27 + 2.0 * sin(p.x * 0.011 + t * 0.17));
	float c = pow(abs(a * b), 5.0);
	col += vec3(0.30, 0.62, 0.66) * c * 0.06 * caustic * (0.4 + pool);

	// Lens falloff toward the corners.
	vec2 e = (p - h) / h;
	col *= mix(1.0, 0.7, smoothstep(0.55, 1.45, length(e * vec2(0.9, 1.0))));
	// The edge sinks in; the rim catches light along the top.
	col *= 1.0 - 0.28 * smoothstep(-18.0, 0.0, d);
	float rim = clamp(1.0 - abs(d + 1.2), 0.0, 1.0);
	float top = smoothstep(h.y * 1.1, 0.0, p.y);
	col = mix(col, vec3(0.62, 0.9, 0.94), rim * (0.18 + 0.5 * top));
	float rim2 = clamp(1.0 - abs(d + 3.0) * 0.8, 0.0, 1.0);
	col = mix(col, vec3(0.0, 0.02, 0.03), rim2 * 0.35 * (1.0 - top));

	// Grain, changing with the frame like a live camera.
	col += (hash(floor(p) + floor(t * 24.0) * 1.31) - 0.5) * 0.022;
	COLOR = vec4(col, inside * COLOR.a);
}
