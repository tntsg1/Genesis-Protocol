shader_type canvas_item;
// A colony's outer jelly (level 21): the distance to the blueprint's outline
// comes baked in `skin` (Colony.bake_skin), so the jelly hugs the shape the
// player built. Clear in the middle, denser and bright towards the skin, as
// the gel of a Volvox ball is. When the young have gone it thins and tears.
// COLOR = lineage colour. INSTANCE_CUSTOM (arrives clamped to 0..1): y = phase,
// z = energy 0..1, w = how far gone the shell is (0 = alive).

uniform sampler2D skin : filter_linear, repeat_disable;
uniform float range = 40.0; // the µm a full texture value stands for
uniform float side = 100.0; // the quad's side at full size, µm
uniform float px = 0.1;     // one screen pixel in world units
uniform float dark = 0.0;   // 1 on the bench's darkfield: the rim lights up

varying vec4 v_c;
varying vec4 v_col;
varying vec2 v_q;
varying float v_side;

void vertex() {
	v_c = INSTANCE_CUSTOM;
	v_col = COLOR;
	v_q = VERTEX;
	v_side = max(length(MODEL_MATRIX[0].xy), 1e-3);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = fract(sin(dot(i, vec2(127.1, 311.7))) * 43758.5453);
	float b = fract(sin(dot(i + vec2(1.0, 0.0), vec2(127.1, 311.7))) * 43758.5453);
	float c = fract(sin(dot(i + vec2(0.0, 1.0), vec2(127.1, 311.7))) * 43758.5453);
	float d = fract(sin(dot(i + vec2(1.0, 1.0), vec2(127.1, 311.7))) * 43758.5453);
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	vec2 uv = v_q + 0.5;
	float scale = v_side / side;
	float d = (texture(skin, uv).r - 0.5) * 2.0 * range * scale;
	float ph = v_c.y * 6.2831853;
	float a = atan(v_q.y, v_q.x);
	float fade = v_c.w;
	// The jelly breathes a little.
	d += (1.1 * sin(a * 3.0 + TIME * 0.9 + ph) + 0.7 * sin(a * 5.0 - TIME * 1.3 + ph * 3.0)) * scale;
	vec3 tint = v_col.rgb;
	float e = v_c.z;
	float inside = clamp(0.5 - d / px, 0.0, 1.0);
	float depth = clamp(-d / (14.0 * scale), 0.0, 1.0);
	vec4 o = vec4(mix(tint, vec3(1.0), 0.55), inside * (0.1 + 0.08 * e));
	float edge = 1.0 - depth;
	vec3 glow = mix(tint, vec3(0.92, 1.0, 0.96), 0.6);
	float oa = edge * edge * 0.3 * inside;
	o.rgb = mix(o.rgb, glow, oa / max(oa + o.a, 1e-4));
	o.a = o.a + oa * (1.0 - o.a);
	// The skin itself, and one soft light on the upper left of it.
	float line = clamp(0.9 - abs(d) / px, 0.0, 1.0) * 0.72;
	vec3 ink = mix(tint * 0.5, vec3(0.62, 1.0, 0.9), dark);
	o.rgb = mix(o.rgb, ink, line / max(line + o.a * (1.0 - line), 1e-4));
	o.a = line + o.a * (1.0 - line);
	vec2 n = normalize(vec2(dFdx(d), dFdy(d)) + vec2(1e-5));
	float spec = pow(clamp(dot(n, vec2(-0.6, -0.8)), 0.0, 1.0), 3.0) * clamp(1.0 - abs(d + 3.2 * scale) / (2.2 * scale), 0.0, 1.0) * 0.5 * inside;
	o.rgb = mix(o.rgb, vec3(1.0), spec / max(spec + o.a * (1.0 - spec), 1e-4));
	o.a = spec + o.a * (1.0 - spec);
	if (fade > 0.0) {
		float holes = noise(v_q * 7.0 + ph) * 0.65 + noise(v_q * 17.0 - ph) * 0.35;
		o.a *= smoothstep(fade * 1.15 - 0.08, fade * 1.15 + 0.02, holes) * (1.0 - fade * fade);
	}
	COLOR = o;
}
