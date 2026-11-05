// Look 2 water layers at quarter resolution (blurry by nature, so nothing
// is lost): R = out-of-focus cells far below the focal plane, G = light
// caustics, B = the slow hue that tints the water. The showcase renders this
// into a SubViewport covering the screen each frame; dish.gdshader samples
// it with SCREEN_UV.
shader_type canvas_item;

uniform vec2 cam_pos = vec2(1100.0);
uniform float cam_zoom = 1.0;
uniform vec2 screen = vec2(1920.0, 1080.0);

float hash(vec2 p) {
	uvec2 q = floatBitsToUint(p);
	uint h = (q.x * 1597334677u) ^ (q.y * 3812015801u);
	h ^= h >> 16u;
	h *= 2246822519u;
	h ^= h >> 13u;
	h *= 3266489917u;
	h ^= h >> 16u;
	return float(h) * (1.0 / 4294967295.0);
}

vec2 hash2(vec2 p) {
	return vec2(hash(p), hash(p + 17.3));
}

float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

// Big soft out-of-focus cells far below the focal plane: blurred discs with
// a brighter membrane, one per jittered grid cell (some cells empty).
float deep_cells(vec2 w) {
	float cell = 300.0;
	// The 2 x 2 cells nearest the point (a disc never reaches past those).
	vec2 g = floor(w / cell - 0.5);
	float v = 0.0;
	for (int j = 0; j <= 1; j++) {
		for (int i = 0; i <= 1; i++) {
			vec2 id = g + vec2(float(i), float(j));
			if (hash(id + 4.7) > 0.62) {
				continue;
			}
			vec2 c = (id + 0.2 + 0.6 * hash2(id)) * cell;
			float r = cell * (0.18 + 0.2 * hash(id + 1.3));
			float a = hash(id + 9.1) * 6.2832;
			vec2 q = w - c;
			q = vec2(q.x * cos(a) + q.y * sin(a), -q.x * sin(a) + q.y * cos(a)) / vec2(1.0, 0.72);
			float d = length(q);
			float body = smoothstep(r, r * 0.4, d);
			float rim = exp(-pow((d - r * 0.86) / (r * 0.13), 2.0));
			float nuc = smoothstep(r * 0.3, r * 0.1, length(q - vec2(r * 0.15, 0.0)));
			v = max(v, body * 0.55 + rim * 0.5 + nuc * 0.25);
		}
	}
	return v;
}

// Light caustics: the bright web of a rippled surface (two moving Voronoi
// edge networks multiplied).
float caustic(vec2 p, float t) {
	float acc = 1.0;
	for (int k = 0; k < 1; k++) {
		vec2 q = p * (1.0 + float(k) * 0.7) + vec2(float(k) * 3.1, 0.0);
		vec2 i = floor(q);
		vec2 f = fract(q);
		float m1 = 8.0, m2 = 8.0;
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec2 g = vec2(float(x), float(y));
				vec2 o = hash2(i + g);
				o = 0.5 + 0.45 * sin(t * (0.5 + 0.2 * float(k)) + 6.2832 * o);
				float d = length(g + o - f);
				if (d < m1) {
					m2 = m1;
					m1 = d;
				} else if (d < m2) {
					m2 = d;
				}
			}
		}
		acc *= pow(1.0 - smoothstep(0.0, 0.2, m2 - m1), 2.0);
	}
	return acc;
}


void fragment() {
	// World position of this pixel (camera centred, no rotation).
	vec2 world = cam_pos + (UV - 0.5) * screen / cam_zoom;
	vec2 wb = world * 0.8 + cam_pos * 0.2 + vec2(TIME * 4.0, TIME * 2.0);
	float ghosts = deep_cells(wb);
	float cau = caustic(world * 0.0055, TIME);
	float hue = noise(world * 0.0011 + vec2(TIME * 0.008, 0.0));
	COLOR = vec4(ghosts, cau, hue, 1.0);
}
