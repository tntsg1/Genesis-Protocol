shader_type canvas_item;
// Chapter 6 boss (6-5): the giant foraminiferan and its pseudopod net
// (SimCore net field, 0..1 per 16 µm cell). From its many-chambered spiral
// shell, fine pseudopods radiate and branch and join into a web; granules
// stream along them both ways, as they do in a living foraminiferan. Where
// the field thins the strands thin and fade; it is drawn pale amber, a lava
// tint kept light (the dish stays bright).

uniform sampler2D net_tex : filter_linear, repeat_disable;
uniform vec2 rect_pos;
uniform vec2 rect_size;
uniform vec2 field_size;
uniform vec2 center;
uniform float core = 70.0;
uniform float t = 0.0;
uniform float amount = 1.0;

const vec3 STRAND = vec3(0.86, 0.56, 0.34);
const vec3 STRAND_LIT = vec3(1.0, 0.86, 0.62);
const vec3 SHELL = vec3(0.98, 0.93, 0.84);
const vec3 SHELL_EDGE = vec3(0.62, 0.42, 0.3);

uint hash_u(uvec2 p) {
	uint h = p.x * 0x8da6b343u ^ p.y * 0xd8163841u;
	h ^= h >> 13u;
	h *= 0x2c1b3c6du;
	h ^= h >> 12u;
	return h;
}

float hash(vec2 p) {
	return float(hash_u(uvec2(ivec2(floor(p)) + ivec2(8192)))) / 4294967295.0;
}

vec2 hash2(vec2 p) {
	return vec2(hash(p), hash(p + vec2(17.3, 41.7)));
}

float net_at(vec2 w) {
	vec2 uv = w / field_size;
	vec2 px = 1.0 / vec2(textureSize(net_tex, 0));
	float a = texture(net_tex, uv + px * vec2(-0.5, -0.5)).r;
	float b = texture(net_tex, uv + px * vec2(0.5, -0.5)).r;
	float c = texture(net_tex, uv + px * vec2(-0.5, 0.5)).r;
	float d = texture(net_tex, uv + px * vec2(0.5, 0.5)).r;
	return (a + b + c + d) * 0.25;
}

// Distance to the nearest edge of a Voronoi cell (the web's cross links).
float web(vec2 p) {
	vec2 ip = floor(p);
	vec2 fp = fract(p);
	float d1 = 8.0, d2 = 8.0;
	vec2 m1 = vec2(0.0);
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 o = hash2(ip + g) * 0.8 + 0.1;
			vec2 r = g + o - fp;
			float d = dot(r, r);
			if (d < d1) {
				d2 = d1;
				d1 = d;
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	return sqrt(d2) - sqrt(d1);
}

// The shell: a planispiral of chambers, each a little bigger than the last.
float shell_sd(vec2 q, out float pores) {
	float sd = 1e5;
	float r = core * 0.18;
	float a = 0.0;
	float rad = core * 0.05;
	pores = 0.0;
	for (int k = 0; k < 13; k++) {
		vec2 c = vec2(cos(a), sin(a)) * rad;
		float d = length(q - c) - r;
		sd = min(sd, d);
		// A few pores on each chamber.
		vec2 lp = (q - c) / r;
		float pr = length(fract(lp * 2.6 + float(k) * 0.37) - 0.5);
		pores = max(pores, (1.0 - smoothstep(0.08, 0.14, pr)) * step(d, -r * 0.18));
		a += 0.62;
		rad *= 1.17;
		r *= 1.11;
	}
	return sd;
}

void fragment() {
	vec2 w = rect_pos + UV * rect_size;
	vec2 q = w - center;
	float dist = length(q);
	float n = net_at(w);
	vec4 col = vec4(0.0);
	if (n > 0.02) {
		float px = fwidth(w.x);
		// Radial pseudopods from the shell, slightly wavy, branching outward
		// (more of them further out).
		float ang = atan(q.y, q.x);
		float rings = dist / 60.0;
		float spokes = 72.0 + 48.0 * step(260.0, dist);
		float wav = 0.06 * sin(dist / 37.0 + ang * 3.0) + 0.03 * sin(dist / 13.0 - ang * 5.0);
		float s = (ang + wav) / 6.28318 * spokes;
		float rid = floor(s);
		float rd = abs(fract(s) - 0.5) / spokes * 6.28318 * dist; // µm to the spoke
		float keep = step(0.25, hash(vec2(rid, floor(dist / 140.0))));
		float spoke = (1.0 - smoothstep(0.5, 0.5 + px * 1.4, rd)) * keep;
		// The web between them.
		float e = web(w / 38.0) * 38.0;
		float link = 1.0 - smoothstep(0.4, 0.4 + px * 1.4, e);
		float strand = max(spoke, link * 0.75);
		// Granules streaming along the spokes, out and back.
		float gpos = dist / 22.0 - t * (mod(rid, 2.0) < 1.0 ? 0.9 : -0.7) + hash(vec2(rid, 3.0)) * 10.0;
		float gr = length(vec2((fract(gpos) - 0.5) * 22.0, rd)) ;
		float gran = (1.0 - smoothstep(1.0, 1.0 + px * 1.5, gr)) * keep * step(0.55, hash(vec2(rid, floor(gpos))));
		float dens = smoothstep(0.08, 0.6, n);
		vec3 c = mix(STRAND, STRAND_LIT, gran);
		float a = max(strand * 0.75, gran) * dens;
		// A faint film where it is thick (the reticulopodial mesh).
		a = max(a, 0.07 * smoothstep(0.4, 1.0, n));
		col = vec4(c, a);
	}
	// The shell over the middle of it.
	float pores;
	float sd = shell_sd(q, pores);
	if (sd < 3.0) {
		float px = fwidth(w.x);
		float inside = 1.0 - smoothstep(-px, px, sd);
		float edge = 1.0 - smoothstep(px * 0.5, px * 2.2, abs(sd));
		vec3 sc = mix(SHELL, SHELL * 0.92, smoothstep(-core * 0.5, 0.0, sd));
		sc = mix(sc, SHELL_EDGE, edge * 0.9);
		sc = mix(sc, SHELL_EDGE * 1.1, pores * 0.5);
		vec4 shell = vec4(sc, max(inside * 0.96, edge));
		col = mix(col, shell, shell.a);
	}
	col.a *= amount;
	COLOR = col;
}
