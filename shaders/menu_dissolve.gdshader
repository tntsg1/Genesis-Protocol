// The main menu dissolving along a scan front (seventh round, the one-take
// transition): everything left of `front` (screen fraction) is gone, broken
// up in small blocks so the edge frays, and the blocks just ahead of it burn
// bright cyan before they go (scripts/ui/menu_fx.gd sends shards off it).
// front < -0.5: off (the menu draws as usual). Text samples its glyphs, so
// COLOR already carries the texture.
shader_type canvas_item;

uniform float front = -1.0;

float hash(vec2 p) {
	uvec2 q = floatBitsToUint(p);
	uint h = (q.x * 1597334677u) ^ (q.y * 3812015801u);
	h ^= h >> 16u;
	h *= 2246822519u;
	h ^= h >> 13u;
	return float(h) * (1.0 / 4294967295.0);
}

void fragment() {
	vec4 c = COLOR;
	if (front > -0.5) {
		vec2 cell = floor(FRAGCOORD.xy / 6.0);
		float x = SCREEN_UV.x + (hash(cell) - 0.5) * 0.09;
		float gone = step(x, front);
		float edge = 1.0 - smoothstep(0.0, 0.035, x - front);
		c.rgb = mix(c.rgb, vec3(0.55, 1.6, 1.9), edge * (1.0 - gone) * 0.85);
		c.a *= 1.0 - gone;
	}
	COLOR = c;
}
