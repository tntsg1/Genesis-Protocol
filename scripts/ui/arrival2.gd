extends "res://scripts/ui/arrival.gd"
# The passage to planet two (chapter 7, DECISIONS Q228+), before level 7-1,
# about 30 seconds, letterboxed like the landfall on planet one (arrival.gd,
# whose drawing helpers this reuses): the seed ship leaves the ocean world
# behind; the stars stream past; the ice world grows ahead; the ship comes
# down on the ice plain; in cross-section the pod drills down through the ice
# shell, breaks through into the black water under it, and lets the first
# cells out in the one warm pocket. Esc, "跳过" or the end emit `finished`.
# The words are a first draft for the user to rewrite.

const LEN2 := 30.0
const BEATS2 := [0.0, 7.0, 13.0, 19.0, 23.5, LEN2] # leaving, the stars, planet two, the ice plain, the drill
const LINES2 := [
	[1.0, 6.4, "星球一的海里，生命已经扎下了根"],
	[8.0, 12.4, "种子飞船再次出发"],
	[14.0, 18.6, "星球二：海面冻成了厚厚的冰壳"],
	[19.8, 23.0, "冰壳下面还有海水"],
	[25.0, 29.4, "钻穿冰层，在暖水区播下生命"],
]
const ICE_M := 3200.0
const WARM_COL := Color(1.0, 0.72, 0.45)

var chips := PackedVector3Array() # ice chips off the drill: angle, speed, phase


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for k in 40:
		chips.append(Vector3(rng.randf(), rng.randf(), rng.randf()))
	refresh()


func _process(dt: float) -> void:
	if done:
		return
	t += dt
	if t >= LEN2:
		_end()
		return
	refresh()


func _beat(k: int) -> float:
	return clampf((t - BEATS2[k]) / (BEATS2[k + 1] - BEATS2[k]), 0.0, 1.0)


func refresh() -> void:
	sz = get_viewport().get_visible_rect().size
	# The planet rect: planet one going away in shot 1, planet two coming up
	# in shot 3.
	var shot1 := t < BEATS2[1]
	var shot3 := t >= BEATS2[2] and t < BEATS2[3]
	planet.visible = shot1 or shot3
	if planet.visible:
		var r: float
		var c: Vector2
		if shot1:
			var u := _ease(_beat(0))
			r = sz.y * lerpf(0.42, 0.2, u)
			c = Vector2(sz.x * lerpf(0.3, 0.24, u), sz.y * lerpf(0.72, 0.64, u))
			planet.material.set_shader_parameter("kind", 2)
			planet.material.set_shader_parameter("light", Vector2(0.7, -0.5))
		else:
			var u := _ease(_beat(2))
			r = sz.y * lerpf(0.1, 0.4, u)
			c = Vector2(sz.x * lerpf(0.72, 0.64, u), sz.y * 0.5)
			planet.material.set_shader_parameter("kind", 1)
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


# --- Drawing. ---------------------------------------------------------------

func _draw_back() -> void:
	if t < BEATS2[1]:
		_draw_leaving()
	elif t < BEATS2[2]:
		_draw_warp()
	elif t < BEATS2[3]:
		_draw_approach()
	elif t < BEATS2[4]:
		_draw_ice_plain()
	else:
		_draw_drill()


func _space() -> void:
	back.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.012, 0.018, 0.03))


# Shot 1: planet one falling behind, lower left.
func _draw_leaving() -> void:
	_space()
	_draw_stars(Vector2(_beat(0) * 60.0, _beat(0) * 30.0))
	var sun := Vector2(sz.x * 0.9, sz.y * 0.14)
	back.draw_texture_rect(glow, Rect2(sun - Vector2.ONE * 140, Vector2.ONE * 280), false, Color(1.0, 0.96, 0.88, 0.45))
	back.draw_circle(sun, 6.0, Color(1.0, 0.98, 0.92))


# Shot 2: the stars stream past from a point ahead of the ship.
func _draw_warp() -> void:
	_space()
	var u := _beat(1)
	var k := sin(PI * u) # the streaks grow and shrink again
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
	back.draw_texture_rect(glow, Rect2(c - Vector2.ONE * 120, Vector2.ONE * 240), false, Color(0.8, 0.9, 1.0, 0.25 * k))


# Shot 3: planet two coming up ahead (the shader rect is drawn over this).
func _draw_approach() -> void:
	_space()
	_draw_stars(Vector2(-_beat(2) * 50.0, 0))
	var sun := Vector2(sz.x * 0.12, sz.y * 0.2)
	back.draw_texture_rect(glow, Rect2(sun - Vector2.ONE * 90, Vector2.ONE * 180), false, Color(1.0, 0.95, 0.85, 0.35))
	back.draw_circle(sun, 4.0, Color(1.0, 0.98, 0.92))


# Shot 4: the ice plain under a dim sky; pressure ridges run off to the
# horizon; the ship comes down tail first on its engine.
func _plain_hz() -> float:
	return sz.y * 0.58


func _draw_ice_plain() -> void:
	var hz := _plain_hz()
	_vgrad(Color(0.015, 0.025, 0.05), Color(0.12, 0.16, 0.22), 0.0, hz)
	for s: Vector3 in stars:
		var p := Vector2(s.x * sz.x, s.y * hz * 0.9)
		back.draw_circle(p, 0.5 + s.z, Color(0.86, 0.92, 1.0, 0.15 + 0.6 * s.z))
	# The far sun, low and small; a band of pale light along the horizon.
	back.draw_texture_rect(glow, Rect2(-sz.x * 0.2, hz - 50, sz.x * 1.4, 100), false, Color(0.75, 0.85, 0.95, 0.3))
	back.draw_circle(Vector2(sz.x * 0.16, hz - 26), 4.0, Color(1.0, 0.96, 0.86))
	_vgrad(Color(0.55, 0.65, 0.74), Color(0.82, 0.9, 0.95), hz, sz.y)
	# Pressure ridges and cracks, converging on the horizon.
	for k in 13:
		var x0 := sz.x * (k / 12.0 - 0.5) * 3.2 + sz.x * 0.5
		var x1 := sz.x * 0.5 + (x0 - sz.x * 0.5) * 0.04
		var pts := PackedVector2Array()
		for j in 9:
			var f := j / 8.0
			var y := lerpf(sz.y, hz, pow(f, 0.6))
			pts.append(Vector2(lerpf(x0, x1, pow(f, 0.6)) + sin(f * 9.0 + k * 1.7) * 18.0 * (1.0 - f), y))
		back.draw_polyline(pts, Color(0.42, 0.55, 0.66, 0.55), 1.5, true)
	# The ship's glare on the ice below it, and the snow its engine blows out.
	var u := _beat(3)
	var down := _ease(u / 0.75)
	var land := Vector2(sz.x * 0.5, hz + sz.y * 0.16)
	var near := clampf(down * 1.3 - 0.2, 0.0, 1.0)
	back.draw_texture_rect(glow, Rect2(land - Vector2(260, 60) * (0.5 + near), Vector2(520, 120) * (0.5 + near)), false, Color(1.0, 0.85, 0.65, 0.5 * near * (1.0 - _ease((u - 0.8) / 0.2))))
	for c: Vector3 in chips:
		var ph := fposmod(t * (0.5 + c.y) + c.z, 1.0)
		var side := -1.0 if c.x < 0.5 else 1.0
		var p := land + Vector2(side * (40.0 + ph * 420.0 * (0.5 + c.y)), -ph * 70.0 * c.z + 6.0)
		back.draw_texture_rect(glow, Rect2(p - Vector2(30, 14), Vector2(60, 28)), false, Color(0.95, 0.98, 1.0, 0.35 * near * (1.0 - ph)))


# Shot 5: the cross-section; ice shell above, black water below with the
# warm pocket glowing among ice keels; the pod bores down, breaks through,
# sinks to the warm water, opens.
func _ice_top() -> float:
	return sz.y * 0.16


func _ice_bot() -> float:
	return sz.y * 0.55


func _drill_u() -> float:
	return _ease(_beat(4) / 0.4)


func _warm_at() -> Vector2:
	return Vector2(sz.x * 0.3, sz.y * 0.8)


func _pod_at() -> Vector2:
	var u := _beat(4)
	var x := sz.x * 0.52
	var s := sz.y * 0.1
	if u < 0.4:
		return Vector2(x, lerpf(_ice_top() - s * 0.3, _ice_bot() + s * 0.2, _drill_u()))
	var k := _ease((u - 0.4) / 0.22)
	var a := Vector2(x, _ice_bot() + s * 0.2)
	var b := _warm_at() + Vector2(sz.x * 0.06, -sz.y * 0.02)
	return a.lerp(b, k) + Vector2(0, sin(PI * k) * sz.y * 0.05)


func _draw_drill() -> void:
	var u := _beat(4)
	var top := _ice_top()
	var bot := _ice_bot()
	# The sky strip over the ice.
	_vgrad(Color(0.015, 0.025, 0.05), Color(0.08, 0.11, 0.16), 0.0, top)
	# The water under the ice, and the warm pocket.
	_vgrad(Color(0.16, 0.3, 0.42), Color(0.05, 0.12, 0.2), bot, sz.y)
	var warm := _warm_at()
	back.draw_texture_rect(glow, Rect2(warm - Vector2(420, 260), Vector2(840, 520)), false, Color(WARM_COL, 0.3))
	back.draw_texture_rect(glow, Rect2(warm - Vector2(160, 100), Vector2(320, 200)), false, Color(WARM_COL, 0.3))
	# The seabed far down, dim.
	var bed := PackedVector2Array()
	for k in 33:
		var x := sz.x * k / 32.0
		bed.append(Vector2(x, sz.y * 0.93 + sin(k * 0.8) * 8.0 + sin(k * 0.31) * 14.0))
	bed.append(Vector2(sz.x, sz.y))
	bed.append(Vector2(0, sz.y))
	back.draw_colored_polygon(bed, Color(0.08, 0.1, 0.12))
	# The ice shell: strata, trapped bubbles, keels hanging under it.
	_vgrad(Color(0.8, 0.9, 0.96), Color(0.42, 0.6, 0.72), top, bot)
	for k in 9:
		var y := lerpf(top, bot, (k + 0.5) / 9.0)
		var pts := PackedVector2Array()
		for j in 25:
			var x := sz.x * j / 24.0
			pts.append(Vector2(x, y + sin(j * 0.7 + k * 1.3) * 5.0))
		back.draw_polyline(pts, Color(1, 1, 1, 0.16), 1.2, true)
	for c: Vector3 in chips:
		back.draw_circle(Vector2(c.x * sz.x, lerpf(top + 10, bot - 10, c.y)), 1.2 + c.z * 2.0, Color(1, 1, 1, 0.3))
	var keel := PackedVector2Array([Vector2(0, bot - 2)])
	for k in 41:
		var x := sz.x * k / 40.0
		var d := maxf(0.0, sin(k * 0.55 + 0.8)) * 60.0 + maxf(0.0, sin(k * 1.7)) * 26.0
		# (A deep keel each side of the warm pocket: the walls that hold it.)
		d += 160.0 * exp(-pow((x - (warm.x - sz.x * 0.17)) / 40.0, 2.0)) + 150.0 * exp(-pow((x - (warm.x + sz.x * 0.2)) / 46.0, 2.0))
		keel.append(Vector2(x, bot + d))
	keel.append(Vector2(sz.x, bot - 2))
	back.draw_colored_polygon(keel, Color(0.42, 0.6, 0.72))
	# The borehole behind the pod, darker; chips flying off the bit.
	var pod := _pod_at()
	var hole_bot := minf(pod.y, bot)
	if hole_bot > top:
		back.draw_rect(Rect2(sz.x * 0.52 - 14.0, top, 28.0, hole_bot - top), Color(0.3, 0.44, 0.55, 0.7))
	if u < 0.4:
		var bit := pod + Vector2(0, sz.y * 0.07)
		var pts := PackedVector2Array([bit + Vector2(-16, -8), bit + Vector2(16, -8), bit + Vector2(0, 22)])
		back.draw_colored_polygon(pts, Color(0.62, 0.66, 0.7))
		for k in 4:
			var a := t * 14.0 + k * PI * 0.5
			back.draw_line(bit + Vector2(cos(a) * 14.0, -6), bit + Vector2(cos(a) * 4.0, 16), Color(0.3, 0.33, 0.36), 2.0, true)
		for c: Vector3 in chips:
			var ph := fposmod(t * (1.5 + c.y * 2.0) + c.z, 1.0)
			var side := -1.0 if c.x < 0.5 else 1.0
			back.draw_circle(bit + Vector2(side * (8.0 + ph * 40.0), -ph * 90.0 * (0.4 + c.y)), 1.5 + c.z, Color(1, 1, 1, 0.8 * (1.0 - ph)))
	# The breakthrough: a burst of bubbles and slush under the shell.
	var burst := clampf((u - 0.38) / 0.14, 0.0, 1.0)
	if burst > 0.0 and burst < 1.0:
		for c: Vector3 in chips:
			var p := Vector2(sz.x * 0.52, bot) + Vector2((c.x - 0.5) * 180.0 * burst, (c.y * 120.0 + 20.0) * burst - 40.0 * burst * burst)
			back.draw_circle(p, 1.5 + 2.5 * c.z, Color(0.9, 0.97, 1.0, 0.7 * (1.0 - burst)))
	var open := _ease((u - 0.64) / 0.08)
	_pod(pod, sz.y * 0.1, open, 0.3 + 0.7 * clampf((u - 0.35) / 0.2, 0.0, 1.0))
	# The first cells out to the warm water.
	if open > 0.2:
		for c: Vector3 in cells:
			var k := clampf((u - 0.68 - c.y * 0.08) / 0.18, 0.0, 1.0)
			if k <= 0.0:
				continue
			var s := _ease(k)
			var a0 := pod + Vector2(0.05 * sz.y * (c.x - 0.5), 0)
			var a1 := warm + Vector2((c.x - 0.5) * 220.0, (c.z - 0.5) * 120.0)
			var p := a0.lerp(a1, s) + Vector2(sin(t * 3.0 + c.x * 30.0), cos(t * 2.4 + c.z * 20.0)) * 3.0
			back.draw_texture_rect(glow, Rect2(p - Vector2(9, 9), Vector2(18, 18)), false, Color(CELL_COL, 0.55))
			back.draw_circle(p, 2.6, Color(0.85, 1.0, 0.95, 0.95))


func _draw_front() -> void:
	if t < BEATS2[1]:
		# Away from planet one, up and to the right, engine lit.
		var u := _ease(_beat(0))
		var at := Vector2(sz.x * lerpf(0.42, 0.7, u), sz.y * lerpf(0.5, 0.36, u))
		ShipArt.ship(front, at, -0.35, sz.y * lerpf(0.16, 0.09, u), 0.9, t, glow)
	elif t < BEATS2[2]:
		var u := _beat(1)
		ShipArt.ship(front, Vector2(sz.x * 0.4, sz.y * 0.52) + Vector2(sin(t * 7.0), cos(t * 5.0)) * 1.5, -0.05, sz.y * 0.09, 1.0, t, glow)
		var flash := maxf(1.0 - absf(u - 0.08) / 0.08, 0.0)
		front.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.9, 0.95, 1.0, 0.45 * flash))
	elif t < BEATS2[3]:
		var u := _ease(_beat(2))
		var at := Vector2(sz.x * lerpf(0.14, 0.46, u), sz.y * lerpf(0.56, 0.5, u))
		ShipArt.ship(front, at, -0.04, sz.y * lerpf(0.1, 0.05, u), 0.4 * (1.0 - u), t, glow)
	elif t < BEATS2[4]:
		var u := _beat(3)
		var down := _ease(u / 0.75)
		var hz := _plain_hz()
		var at := Vector2(sz.x * 0.5, lerpf(-sz.y * 0.1, hz + sz.y * 0.16 - sz.y * 0.09, down))
		ShipArt.ship(front, at, -PI * 0.5, sz.y * 0.18, 1.0 - _ease((u - 0.8) / 0.15), t, glow)
	else:
		# The readout beside the borehole: depth while drilling, then the water.
		var u := _beat(4)
		var x := sz.x * 0.52 + 70.0
		var pod := _pod_at()
		var font := Ui.mono("Medium")
		if u < 0.4:
			front.draw_string(font, Vector2(x, pod.y + 6), "冰层 %d m" % int(ICE_M * _drill_u()), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.1, 0.2, 0.3, 0.9))
		elif u < 0.62:
			front.draw_string(font, Vector2(pod.x + 70.0, pod.y + 6), "冰下海水  −1.8°C", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.8, 0.95, 1.0, 0.9))
		else:
			front.draw_string(font, Vector2(pod.x + 70.0, pod.y + 6), "暖水区  14°C", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1.0, 0.85, 0.65, 0.95))
	var bh := _bar()
	front.draw_rect(Rect2(0, 0, sz.x, bh), Color.BLACK)
	front.draw_rect(Rect2(0, sz.y - bh, sz.x, bh), Color.BLACK)
	for l: Array in LINES2:
		var a := minf(_ease((t - l[0]) / 0.6), _ease((l[1] - t) / 0.6))
		if a > 0.0:
			_text(Vector2(sz.x * 0.5, sz.y - bh * 0.5 + 12), l[2], 32, Color(0.92, 0.97, 0.98, a), Ui.sans(500))
	var black := 1.0 - _ease(t / 1.2)
	for k in [2, 3, 4]:
		black = maxf(black, 1.0 - clampf(absf(t - BEATS2[k]) / 0.4, 0.0, 1.0))
	black = maxf(black, _ease((t - (LEN2 - 1.4)) / 1.4))
	front.draw_rect(Rect2(Vector2.ZERO, sz), Color(0, 0, 0, black))
