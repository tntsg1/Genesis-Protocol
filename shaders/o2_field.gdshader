shader_type canvas_item;
// Chapter 6's oxygen (DECISIONS Q215): in the dish a faint cyan wash and a
// few small bubbles where the water holds oxygen; in the analysis view (X,
// layer 氧气) a clear map: anoxic water violet-grey, oxygen cyan to bright
// teal, and the 8% line (where it starts to poison an anaerobe) drawn white.
// The field comes from SimCore.get_o2_field (one float per 16 µm cell).

uniform sampler2D o2_tex : filter_linear, repeat_disable;
uniform vec2 rect_pos;
uniform vec2 rect_size;
uniform vec2 field_size; // world size the texture covers (grid * cell)
uniform vec2 dish_center;
uniform float dish_radius;
uniform float ambient = 1.0;
uniform float map_amount = 0.0;
uniform float tox = 0.08;
uniform float t = 0.0;

uint hash_u(uvec2 p) {
	uint h = p.x * 0x8da6b343u ^ p.y * 0xd8163841u;
	h ^= h >> 13u;
	h *= 0x2c1b3c6du;
	h ^= h >> 12u;
	return h;
}

float hash(vec2 p) {
	return float(hash_u(uvec2(ivec2(floor(p)) + ivec2(4096)))) / 4294967295.0;
}

// A smoother lookup than bilinear (the field is coarse): four taps.
float o2_at(vec2 w) {
	vec2 uv = w / field_size;
	vec2 px = 1.0 / vec2(textureSize(o2_tex, 0));
	float a = texture(o2_tex, uv + px * vec2(-0.5, -0.5)).r;
	float b = texture(o2_tex, uv + px * vec2(0.5, -0.5)).r;
	float c = texture(o2_tex, uv + px * vec2(-0.5, 0.5)).r;
	float d = texture(o2_tex, uv + px * vec2(0.5, 0.5)).r;
	return (a + b + c + d) * 0.25;
}

void fragment() {
	vec2 w = rect_pos + UV * rect_size;
	float rd = length(w - dish_center);
	float in_dish = 1.0 - smoothstep(dish_radius - 18.0, dish_radius - 2.0, rd);
	float o = o2_at(w);
	vec4 col = vec4(0.0);
	// Ambient: a wash that is barely there at a few percent and a light veil
	// where the water is rich; bubbles rise slowly where there is oxygen.
	float wash = smoothstep(0.0, 0.35, o);
	col = vec4(0.36, 0.84, 0.9, 0.16 * wash * ambient);
	vec2 g = w / 46.0;
	vec2 cellp = floor(vec2(g.x, g.y + t * 0.35));
	float h = hash(cellp);
	if (h < 0.22 * smoothstep(0.03, 0.3, o)) {
		vec2 c = cellp + vec2(0.25 + 0.5 * hash(cellp + 7.1), 0.25 + 0.5 * hash(cellp + 3.7));
		vec2 q = vec2(g.x, g.y + t * 0.35) - c;
		q.x += 0.06 * sin(t * 1.3 + h * 40.0);
		float r = (0.05 + 0.06 * hash(cellp + 1.3)) ;
		float d = length(q) - r;
		float ring = 1.0 - smoothstep(0.0, 0.025, abs(d));
		float core = 1.0 - smoothstep(-0.02, 0.0, d);
		vec4 bub = vec4(0.82, 0.97, 1.0, (0.55 * ring + 0.12 * core) * ambient * wash);
		col = mix(col, bub, bub.a);
	}
	// The map.
	if (map_amount > 0.001) {
		vec3 none = vec3(0.42, 0.4, 0.62);
		vec3 some = vec3(0.3, 0.78, 0.86);
		vec3 rich = vec3(0.12, 0.62, 0.62);
		vec3 m = o < tox ? mix(none, some, smoothstep(0.0, tox, o) * 0.5) : mix(some, rich, smoothstep(tox, 0.35, o));
		float a = 0.5;
		// Iso-lines every 5%, and the poison line at `tox` in white.
		float s = o / 0.05;
		float fw = max(fwidth(s), 1e-4);
		float iso = 1.0 - smoothstep(0.0, fw * 1.2, abs(fract(s + 0.5) - 0.5));
		m = mix(m, m * 0.7, iso * 0.5);
		float ft = max(fwidth(o), 1e-5);
		float tline = 1.0 - smoothstep(ft * 0.8, ft * 2.4, abs(o - tox));
		m = mix(m, vec3(1.0), tline);
		a = max(a, tline * 0.95);
		col = mix(col, vec4(m, a), map_amount);
	}
	col.a *= in_dish;
	COLOR = col;
}
