shader_type canvas_item;
// Night mode (DECISIONS 黑夜模式 2026-11-05): the whole finished frame, made
// black. In OKLab, the light and the grey (the white dish, the frosted
// panels, the ink) have their lightness turned over and pushed down, so the
// page goes pure black and the ink light; what is vivid (the accent, the
// warnings, organelles, the hot spring's glow) keeps its brightness and its
// hue, so it still reads. The pale cells come out as dark bodies with bright
// rims, as in a dark-field microscope. The screen copy here holds sRGB values
// (measured, tests/night_shots.gd NIGHT=off), and COLOR is taken as sRGB too.

uniform sampler2D screen : hint_screen_texture, filter_nearest;
uniform float amount = 1.0;

vec3 to_lin(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

vec3 to_srgb(vec3 c) {
	return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
}

vec3 lin_to_oklab(vec3 c) {
	float l = 0.4122214708 * c.r + 0.5363325363 * c.g + 0.0514459929 * c.b;
	float m = 0.2119034982 * c.r + 0.6806995451 * c.g + 0.1073969566 * c.b;
	float s = 0.0883024619 * c.r + 0.2817188376 * c.g + 0.6299787005 * c.b;
	l = pow(max(l, 0.0), 1.0 / 3.0);
	m = pow(max(m, 0.0), 1.0 / 3.0);
	s = pow(max(s, 0.0), 1.0 / 3.0);
	return vec3(0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
		1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
		0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s);
}

vec3 oklab_to_lin(vec3 c) {
	float l = c.x + 0.3963377774 * c.y + 0.2158037573 * c.z;
	float m = c.x - 0.1055613458 * c.y - 0.0638541728 * c.z;
	float s = c.x - 0.0894841775 * c.y - 1.2914855480 * c.z;
	l = l * l * l;
	m = m * m * m;
	s = s * s * s;
	return vec3(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
		-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
		-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s);
}

void fragment() {
	vec3 c = max(texture(screen, SCREEN_UV).rgb, vec3(0.0));
	vec3 lab = lin_to_oklab(to_lin(min(c, vec3(1.0))));
	float L = clamp(lab.x, 0.0, 1.0);
	float C = length(lab.yz);
	// Turned over in two pieces: the near-white (the page, the dish, the
	// frosted glass) goes to true black; everything darker than that (ink,
	// thin anti-aliased strokes, outlines) is lifted, so text reads light.
	float tv = 1.0 - L;
	float inv = tv < 0.14 ? tv * 0.3 : 0.042 + 0.958 * pow((tv - 0.14) / 0.86, 0.62);
	// Vivid colours keep (most of) their own lightness.
	float vivid = smoothstep(0.05, 0.13, C);
	float lo = mix(inv, max(inv, L * 0.96), vivid);
	// Faint tints a touch stronger (the pale cyan of a cell, the ink-blue).
	vec2 ab = lab.yz * mix(1.25, 1.0, vivid);
	vec3 n = to_srgb(clamp(oklab_to_lin(vec3(lo, ab)), vec3(0.0), vec3(1.0)));
	COLOR = vec4(mix(c, n, amount), 1.0);
}
