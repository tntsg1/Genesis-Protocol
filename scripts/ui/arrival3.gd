extends "res://scripts/ui/arrival2.gd"
# The passage to planet three (chapter 8, DECISIONS Q250), before level 8-1,
# about 30 seconds, in the style of the two before it (arrival.gd /
# arrival2.gd, whose helpers this reuses): the seed ship leaves the ice world;
# the stars stream past; a murky green-brown world grows ahead; down through
# a hazy sky in a drizzle of acid rain to a swamp of dark water and mist; then
# in cross-section the pod sinks through the water into the mud, its layers
# banded green, purple and black, and lets the first cells out at the bands.
# The words are a first draft for the user to rewrite.

const LEN3 := 30.0
const BEATS3 := [0.0, 6.0, 11.5, 17.0, 22.0, LEN3] # leaving, the stars, planet three, the swamp, the mud
const LINES3 := [
	[1.0, 5.6, "冰封海下，生命熬过了长夜"],
	[7.0, 11.0, "种子飞船再次出发"],
	[12.5, 16.6, "星球三：一颗被沼泽覆盖的星球"],
	[17.8, 21.6, "这里的雨是酸的"],
	[23.0, 29.4, "泥越往下，氧越少：在每一层播下生命"],
]
# The mud's bands, top to bottom (a Winogradsky column): brown silt, green
# (cyanobacteria), purple (purple bacteria), black (sulfate reducers).
const BANDS := [Color(0.42, 0.33, 0.22), Color(0.3, 0.5, 0.26), Color(0.48, 0.3, 0.52), Color(0.1, 0.1, 0.09)]


func _process(dt: float) -> void:
	if done:
		return
	t += dt
	if t >= LEN3:
		_end()
		return
	refresh()


func _beat(k: int) -> float:
	return clampf((t - BEATS3[k]) / (BEATS3[k + 1] - BEATS3[k]), 0.0, 1.0)


func refresh() -> void:
	sz = get_viewport().get_visible_rect().size
	var shot1 := t < BEATS3[1]
	var shot3 := t >= BEATS3[2] and t < BEATS3[3]
	planet.visible = shot1 or shot3
	if planet.visible:
		var r: float
		var c: Vector2
		if shot1:
			var u := _ease(_beat(0))
			r = sz.y * lerpf(0.4, 0.2, u)
			c = Vector2(sz.x * lerpf(0.3, 0.24, u), sz.y * lerpf(0.7, 0.62, u))
			planet.material.set_shader_parameter("kind", 1)
			planet.material.set_shader_parameter("light", Vector2(0.7, -0.5))
		else:
			var u := _ease(_beat(2))
			r = sz.y * lerpf(0.1, 0.4, u)
			c = Vector2(sz.x * lerpf(0.72, 0.64, u), sz.y * 0.5)
			# (The ocean world, tinted murky: a swamp world from space.)
			planet.material.set_shader_parameter("kind", 2)
			planet.material.set_shader_parameter("light", Vector2(-0.6, -0.45))
		var pad := 1.15
		planet.position = c - Vector2.ONE * r * pad
		planet.size = Vector2.ONE * r * pad * 2.0
		planet.material.set_shader_parameter("spin", 0.4 + t * 0.012)
		planet.material.set_shader_parameter("px", 1.0 / r)
	skip.position = Vector2(sz.x - 150, maxf(_bar() * 0.5 - 18, 8))
	skip.size = Vector2(120, 36)
	back.queue_redraw()
	front.queue_redraw()


func _draw_back() -> void:
	if t < BEATS3[1]:
		_space()
		_draw_stars(Vector2(_beat(0) * 60.0, _beat(0) * 30.0))
	elif t < BEATS3[2]:
		_warp3()
	elif t < BEATS3[3]:
		_space()
		_draw_stars(Vector2(-_beat(2) * 50.0, 0))
		var sun := Vector2(sz.x * 0.12, sz.y * 0.2)
		back.draw_texture_rect(glow, Rect2(sun - Vector2.ONE * 90, Vector2.ONE * 180), false, Color(1.0, 0.95, 0.85, 0.35))
		back.draw_circle(sun, 4.0, Color(1.0, 0.98, 0.92))
	elif t < BEATS3[4]:
		_draw_swamp()
	else:
		_draw_column()


# The stream of stars, as in arrival2.gd (its beats are its own).
func _warp3() -> void:
	_space()
	var u := _beat(1)
	var k := sin(PI * u)
	var c := Vector2(sz.x * 0.62, sz.y * 0.48)
	for s: Vector3 in stars:
		var dir := Vector2(s.x - 0.5, s.y - 0.5)
		if dir.length() < 0.02:
			continue
		dir = dir.normalized()
		var r := fposmod(s.x * 900.0 + s.y * 500.0 + t * (300.0 + 900.0 * k) * (0.4 + s.z), sz.x * 0.75)
		var a := c + dir * r
		var b := a - dir * (2.0 + 160.0 * k * (0.3 + s.z) * (r / (sz.x * 0.75)))
		back.draw_line(a, b, Color(0.82, 0.9, 1.0, (0.2 + 0.7 * s.z) * (0.4 + 0.6 * r / (sz.x * 0.4))), 1.0 + s.z * 1.4, true)


# Shot 4: a hazy yellow-green sky, a drizzle of acid rain, dark water with
# mist and reeds; the pod comes down into the water.
func _draw_swamp() -> void:
	var u := _beat(3)
	var hz := sz.y * 0.5
	_vgrad(Color(0.32, 0.36, 0.22), Color(0.66, 0.68, 0.46), 0.0, hz)
	_vgrad(Color(0.16, 0.2, 0.14), Color(0.07, 0.09, 0.07), hz, sz.y)
	back.draw_texture_rect(glow, Rect2(-sz.x * 0.2, hz - 60, sz.x * 1.4, 120), false, Color(0.85, 0.88, 0.62, 0.45))
	# Reeds along the far shore and the near edges.
	for k in 70:
		var x := sz.x * fposmod(k * 0.618, 1.0)
		var near := fposmod(k * 0.37, 1.0)
		var base := hz + 6.0 + near * sz.y * (0.05 if near < 0.7 else 0.4)
		var h := (30.0 + 160.0 * near * near) * (0.7 + 0.3 * fposmod(k * 0.21, 1.0))
		var sway := sin(t * 0.8 + k) * 4.0 * near
		back.draw_line(Vector2(x, base), Vector2(x + sway, base - h), Color(0.18, 0.22, 0.12, 0.6 + 0.4 * near), 1.0 + 3.0 * near, true)
	# Mist drifting low over the water.
	for k in 8:
		var cx := fposmod(k * 0.29 * sz.x + t * (12.0 + k * 4.0), sz.x * 1.4) - sz.x * 0.2
		back.draw_texture_rect(glow, Rect2(cx - 260, hz + 10 + k * 18, 520, 60), false, Color(0.8, 0.84, 0.66, 0.18))
	# The acid drizzle.
	for k in 160:
		var x := fposmod(k * 0.618 * sz.x + t * 40.0, sz.x)
		var y := fposmod(k * 0.377 * sz.y + t * 420.0, sz.y)
		back.draw_line(Vector2(x, y), Vector2(x - 3.0, y + 14.0), Color(0.8, 0.9, 0.4, 0.28), 1.0, true)
	# The pod down into the water, rings where it went in.
	var hit := 0.55
	if u < hit:
		var p := Vector2(sz.x * 0.52, lerpf(-sz.y * 0.1, hz + sz.y * 0.12, _ease(u / hit)))
		back.draw_texture_rect(glow, Rect2(p - Vector2(70, 70), Vector2(140, 140)), false, Color(1.0, 0.85, 0.6, 0.5))
		_pod(p, sz.y * 0.09, 0.0, 0.0)
	else:
		var k := (u - hit) / (1.0 - hit)
		var a := Vector2(sz.x * 0.52, hz + sz.y * 0.12)
		for i in 3:
			var rr := (40.0 + 300.0 * k) * (1.0 + i * 0.3)
			back.draw_arc(a, rr, 0, TAU, 64, Color(0.8, 0.86, 0.6, 0.5 * (1.0 - k)), 2.0, true)


# Shot 5: the column. Murky water over the mud's bands; the pod sinks, opens
# at the bands, and the first cells drift out into each.
func _band_y(k: int) -> float:
	return sz.y * (0.4 + 0.12 * k)


func _draw_column() -> void:
	var u := _beat(4)
	_vgrad(Color(0.3, 0.36, 0.26), Color(0.2, 0.24, 0.16), 0.0, _band_y(0))
	for k in BANDS.size():
		var y0 := _band_y(k)
		var y1 := _band_y(k + 1) if k + 1 < BANDS.size() else sz.y
		var c0: Color = BANDS[k]
		var c1: Color = BANDS[k + 1] if k + 1 < BANDS.size() else BANDS[k].darkened(0.4)
		_vgrad(c0, c0.lerp(c1, 0.5), y0, y1)
		# A wavy boundary, and specks of silt.
		var pts := PackedVector2Array()
		for j in 33:
			pts.append(Vector2(sz.x * j / 32.0, y0 + sin(j * 0.9 + k * 2.0) * 6.0))
		back.draw_polyline(pts, Color(c0.lightened(0.25), 0.45), 2.0, true)
	for k in 120:
		var p := Vector2(sz.x * fposmod(k * 0.618, 1.0), lerpf(_band_y(0), sz.y, fposmod(k * 0.377 + 0.1, 1.0)))
		back.draw_circle(p, 1.0 + fposmod(k * 0.29, 1.0) * 2.0, Color(1, 1, 1, 0.08))
	# Bubbles of gas rising from the black mud.
	for k in 14:
		var ph := fposmod(t * 0.25 + k / 14.0, 1.0)
		var p := Vector2(sz.x * (0.1 + 0.8 * fposmod(k * 0.43, 1.0)) + sin(t + k) * 6.0, lerpf(sz.y * 0.95, _band_y(0), ph))
		back.draw_arc(p, 3.0 + 2.0 * fposmod(k * 0.7, 1.0), 0, TAU, 12, Color(0.9, 0.95, 0.85, 0.35 * (1.0 - ph)), 1.0, true)
	# The pod sinks to the green band, opens; the cells go out to the bands.
	var down := _ease(u / 0.45)
	var pod := Vector2(sz.x * 0.5, lerpf(-sz.y * 0.05, _band_y(1) - sz.y * 0.02, down))
	var open := _ease((u - 0.5) / 0.1)
	_pod(pod, sz.y * 0.08, open, 0.6)
	if open > 0.2:
		for c: Vector3 in cells:
			var k := clampf((u - 0.55 - c.y * 0.08) / 0.3, 0.0, 1.0)
			if k <= 0.0:
				continue
			var band := int(c.z * 3.0) # (into the silt, green or purple band)
			var a1 := Vector2(sz.x * (0.1 + 0.8 * c.x), _band_y(band) + sz.y * 0.06)
			var p := pod.lerp(a1, _ease(k)) + Vector2(sin(t * 3.0 + c.x * 30.0), cos(t * 2.4 + c.z * 20.0)) * 3.0
			var col: Color = (BANDS[band] as Color).lightened(0.5)
			back.draw_texture_rect(glow, Rect2(p - Vector2(9, 9), Vector2(18, 18)), false, Color(col, 0.6))
			back.draw_circle(p, 2.6, Color(0.92, 1.0, 0.9, 0.95))


func _draw_front() -> void:
	if t < BEATS3[1]:
		var u := _ease(_beat(0))
		ShipArt.ship(front, Vector2(sz.x * lerpf(0.42, 0.7, u), sz.y * lerpf(0.5, 0.36, u)), -0.35, sz.y * lerpf(0.16, 0.09, u), 0.9, t, glow)
	elif t < BEATS3[2]:
		var u := _beat(1)
		ShipArt.ship(front, Vector2(sz.x * 0.4, sz.y * 0.52) + Vector2(sin(t * 7.0), cos(t * 5.0)) * 1.5, -0.05, sz.y * 0.09, 1.0, t, glow)
		var flash := maxf(1.0 - absf(u - 0.08) / 0.08, 0.0)
		front.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.9, 0.95, 1.0, 0.45 * flash))
	elif t < BEATS3[3]:
		var u := _ease(_beat(2))
		# (The planet shader has no tint: a murky film over the ocean world.)
		var pr := sz.y * lerpf(0.1, 0.4, u)
		var pc := Vector2(sz.x * lerpf(0.72, 0.64, u), sz.y * 0.5)
		front.draw_circle(pc, pr * 1.0, Color(0.2, 0.2, 0.05, 0.5))
		front.draw_circle(pc + Vector2(-0.18, -0.12) * pr, pr * 0.7, Color(0.55, 0.5, 0.2, 0.18))
		ShipArt.ship(front, Vector2(sz.x * lerpf(0.14, 0.46, u), sz.y * lerpf(0.56, 0.5, u)), -0.04, sz.y * lerpf(0.1, 0.05, u), 0.4 * (1.0 - u), t, glow)
	elif t >= BEATS3[4]:
		# The bands named as the pod passes them.
		var u := _beat(4)
		var font := Ui.mono("Medium")
		var names := ["淤泥 · 有氧", "绿层 · 光合", "紫层 · 微氧", "黑泥 · 硫化氢"]
		for k in names.size():
			var a := clampf((u - 0.1 * k) / 0.15, 0.0, 1.0)
			if a > 0.0:
				front.draw_string(font, Vector2(sz.x * 0.06, _band_y(k) + 26.0), names[k], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.95, 0.97, 0.9, 0.85 * a))
	var bh := _bar()
	front.draw_rect(Rect2(0, 0, sz.x, bh), Color.BLACK)
	front.draw_rect(Rect2(0, sz.y - bh, sz.x, bh), Color.BLACK)
	for l: Array in LINES3:
		var a := minf(_ease((t - l[0]) / 0.6), _ease((l[1] - t) / 0.6))
		if a > 0.0:
			_text(Vector2(sz.x * 0.5, sz.y - bh * 0.5 + 12), l[2], 32, Color(0.92, 0.97, 0.98, a), Ui.sans(500))
	var black := 1.0 - _ease(t / 1.2)
	for k in [2, 3, 4]:
		black = maxf(black, 1.0 - clampf(absf(t - BEATS3[k]) / 0.4, 0.0, 1.0))
	black = maxf(black, _ease((t - (LEN3 - 1.4)) / 1.4))
	front.draw_rect(Rect2(Vector2.ZERO, sz), Color(0, 0, 0, black))
