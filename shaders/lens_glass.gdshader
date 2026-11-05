// The magnifier's glass (scripts/ui/magnifier.gd): the dish rendered closer
// (a SubViewport sharing the world, so cells show their real micro detail,
// not stretched pixels) seen through a round lens:
//   barrel    the image bends toward the rim, as through a thick loupe
//   dispersion red and blue part at the rim (stronger while it opens)
//   glass     a lit rim (light from the top left, like the lamp), a cool
//             fresnel tint and a thin inner shadow
// The texture is `oversize` times the drawn disc so the bend has room.
shader_type canvas_item;
render_mode unshaded;

uniform float radius_px = 150.0;
uniform float oversize = 1.2;
uniform float dispersion = 1.0;
uniform float open = 1.0;
uniform vec4 accent : source_color = vec4(0.07, 0.65, 0.73, 1.0);

vec2 src_uv(vec2 d, float r, float bend) {
	float s = r * (1.0 + bend * pow(r, 3.0));
	return 0.5 + d * (s / max(r, 1e-4)) * 0.5 / oversize;
}

// The same highlight roll-off as shaders/lens_post.gdshader (the glass sits
// above that layer, so it applies its own): water eases off white toward a
// neutral cool tone, the cells keep their colour. Keep the two in step.
vec3 rolloff(vec3 col) {
	float l = max(col.r, max(col.g, col.b));
	if (l > 0.7) {
		float x = min(l, 1.0) - 0.7;
		float m = 0.7 + x / (1.0 + x * 3.0) + max(l - 1.0, 0.0);
		col *= m / l;
		float k = clamp(x / 0.3, 0.0, 1.0);
		float lum = dot(col, vec3(0.2126, 0.7152, 0.0722));
		float mx = max(col.r, max(col.g, col.b));
		float sat = (mx - min(col.r, min(col.g, col.b))) / max(mx, 1e-4);
		float water = 1.0 - smoothstep(0.05, 0.16, sat);
		col = mix(col, vec3(lum) * vec3(0.965, 0.99, 1.02), 0.7 * k * water);
	}
	return col;
}

void fragment() {
	vec2 d = UV * 2.0 - 1.0;
	float r = length(d);
	float a = clamp((1.0 - r) * radius_px * open + 0.5, 0.0, 1.0);
	if (a <= 0.0) {
		discard;
	}
	float bend = 0.17;
	float ca = (0.012 + 0.05 * (1.0 - open)) * dispersion * pow(r, 4.0);
	vec3 col;
	col.r = texture(TEXTURE, src_uv(d, r, bend + ca)).r;
	col.g = texture(TEXTURE, src_uv(d, r, bend)).g;
	col.b = texture(TEXTURE, src_uv(d, r, bend - ca)).b;
	col = rolloff(col);
	// Glass: cool fresnel toward the rim, a thin dark line just inside it,
	// and the lamp's highlight on the top-left of the rim.
	float rim = smoothstep(0.82, 1.0, r);
	col = mix(col, col * vec3(0.9, 0.97, 1.02) + accent.rgb * 0.04, rim);
	col *= 1.0 - 0.22 * smoothstep(0.955, 0.985, r) * (1.0 - smoothstep(0.985, 1.0, r));
	vec2 n = d / max(r, 1e-4);
	float lit = max(dot(n, normalize(vec2(-0.6, -0.8))), 0.0);
	float band = smoothstep(0.93, 0.975, r) * (1.0 - smoothstep(0.985, 1.0, r));
	col += vec3(1.0, 1.0, 0.97) * band * pow(lit, 3.0) * 0.9;
	col += accent.rgb * band * pow(max(-dot(n, normalize(vec2(-0.6, -0.8))), 0.0), 2.0) * 0.35;
	// A soft crescent of light across the glass itself (the lamp reflected).
	float cres = smoothstep(0.55, 0.85, length(d - vec2(0.18, 0.24)) ) * (1.0 - smoothstep(0.86, 0.95, r));
	col += vec3(1.0) * cres * pow(lit, 2.0) * 0.07;
	COLOR = vec4(col, a);
}
