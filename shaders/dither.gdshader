shader_type canvas_item;
// Plain drawing with a little noise in the alpha, so wide soft glows fading
// into the dark don't show 8-bit rings (scripts/ui/ending.gd's layers).

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	float n = hash(FRAGCOORD.xy) + hash(FRAGCOORD.xy + 17.3) - 1.0;
	COLOR.a = clamp(COLOR.a + n * 0.012 * step(0.001, COLOR.a) * step(COLOR.a, 0.999), 0.0, 1.0);
	COLOR.rgb += n / 255.0;
}
