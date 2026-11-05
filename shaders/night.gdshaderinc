// Night mode, "深海荧光" (DECISIONS 黑夜模式 2026-11-05): shared by every
// shader that draws itself at night. `night` (0..1, eased) is the project's
// global shader parameter, set by scripts/night_mode.gd.
//   night_ui()   a day colour (sRGB) turned to the night palette: the light
//                and grey (glass, paper, the white dish) go to a warm deep
//                black, the ink and hairlines to a warm white; what is vivid
//                (the accent, warnings, species colours) keeps its hue and
//                its lightness, a touch brighter. Used for the UI and for
//                anything without a night look of its own.
//   night_glow() a body's day colour turned to light: its own hue, glowing
//                through (the fill a soft translucent light, lines and the
//                dark details brighter still), so a cell reads as lit from
//                within, not as a negative.

global uniform float night;

vec3 nt_lin(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

vec3 nt_srgb(vec3 c) {
	return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
}

vec3 nt_lab(vec3 c) {
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

vec3 nt_unlab(vec3 c) {
	float l = c.x + 0.3963377774 * c.y + 0.2158037573 * c.z;
	float m = c.x - 0.1055613458 * c.y - 0.0638541728 * c.z;
	float s = c.x - 0.0894841775 * c.y - 1.2914855480 * c.z;
	l = l * l * l;
	m = m * m * m;
	s = s * s * s;
	return max(vec3(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
		-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
		-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s), vec3(0.0));
}

// The warm white of the night's ink, and its deep warm black.
const vec3 NT_INK = vec3(0.95, 0.91, 0.84);
const vec3 NT_DEEP = vec3(0.045, 0.038, 0.034);

vec3 night_ui(vec3 c) {
	vec3 lab = nt_lab(nt_lin(clamp(c, 0.0, 1.0)));
	float L = lab.x;
	float C = length(lab.yz);
	float vivid = smoothstep(0.075, 0.15, C);
	// The grey turned over: white glass 0.21, the ink 0.93.
	float t = clamp((1.0 - L) / 0.75, 0.0, 1.0);
	float Ln = 0.19 + 0.76 * pow(t, 0.8);
	// Its cool tint swapped for a warm one, stronger as it lightens.
	vec2 warm = vec2(0.004, 0.022) * (0.4 + 0.7 * Ln);
	vec2 ab = mix(warm + lab.yz * 0.2, lab.yz * 1.1, vivid);
	float Lv = mix(L, max(L, 0.74), 0.55);
	return nt_srgb(nt_unlab(vec3(mix(Ln, Lv, vivid), ab)));
}

// The same on linear colours (what most of the world's shaders write).
vec3 night_ui_lin(vec3 c) {
	return nt_lin(night_ui(nt_srgb(max(c, vec3(0.0)))));
}

// A body's day colour `c` (sRGB) with its species colour `base` (sRGB): the
// light fill becomes a soft light in its own hue, the darker lines and
// details brighter. Returns sRGB.
vec3 night_glow(vec3 c, vec3 base) {
	vec3 lab = nt_lab(nt_lin(clamp(c, 0.0, 1.0)));
	vec3 bl = nt_lab(nt_lin(clamp(base, 0.0, 1.0)));
	float L = lab.x;
	float C = length(lab.yz);
	// Pale and greyish pixels take the species' hue.
	vec2 bh = bl.yz / max(length(bl.yz), 1e-4);
	float own = smoothstep(0.03, 0.09, C);
	vec2 hue = normalize(mix(bh, lab.yz / max(C, 1e-4), own) + vec2(1e-5));
	float chroma = clamp(max(C * 1.35, length(bl.yz) * 0.9), 0.05, 0.2);
	float Lo = 0.6 + 0.3 * smoothstep(0.92, 0.35, L);
	return nt_srgb(nt_unlab(vec3(Lo, hue * chroma * mix(1.0, 0.75, smoothstep(0.75, 0.9, Lo)))));
}
