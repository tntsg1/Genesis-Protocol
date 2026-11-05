extends CanvasLayer
# Landfall on planet one (DECISIONS Q208 / Q227), before level 6-1, about 30
# seconds, letterboxed like the end of Europa (ending.gd): the seed ship comes
# up on a world all ocean; it falls through the air into the sea; the seed pod
# sinks through water that darkens as it goes (a depth readout counting); on
# the seabed by a hot spring it opens and the first cells drift out to the
# warm water. Esc, "跳过" or the end emit `finished`. The words are a first
# draft for the user to rewrite.

signal finished

const Ending := preload("res://scripts/ui/ending.gd")
const LEN := 30.0
const BEATS := [0.0, 7.5, 13.5, 22.5, LEN] # space, the fall, the sinking, the spring
const LINES := [
	[1.2, 6.6, "星球一：一颗被海洋覆盖的星球"],
	[8.4, 12.8, "这里的空气和海水里都没有氧气"],
	[15.0, 21.2, "阳光照不到海底"],
	[24.2, 29.0, "热泉口：播下第一批生命"],
]
const DEPTH_M := 2400.0
const CELL_COL := Color(0.55, 0.95, 0.88)

var t := 0.0
var done := false
var sz := Vector2(1920, 1080)
var back: Control
var front: Control
var planet: ColorRect
var skip: Button
var glow: GradientTexture2D
var stars := PackedVector3Array()
var snow := PackedVector3Array() # marine snow: x, y, size
var cells := PackedVector3Array() # the first cells: angle seed, delay, speed


func _init() -> void:
	layer = 60
	glow = Ending._glow_tex()
	back = _layer_control()
	back.mouse_filter = Control.MOUSE_FILTER_STOP
	back.draw.connect(_draw_back)
	planet = ColorRect.new()
	planet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	planet.material = ShaderMaterial.new()
	planet.material.shader = preload("res://shaders/planet.gdshader")
	planet.material.set_shader_parameter("kind", 2)
	planet.material.set_shader_parameter("light", Vector2(-0.75, -0.4))
	add_child(planet)
	front = _layer_control()
	front.draw.connect(_draw_front)
	skip = Button.new()
	skip.text = "跳过  Esc"
	skip.flat = true
	skip.focus_mode = Control.FOCUS_NONE
	skip.add_theme_font_override("font", Ui.sans(500))
	skip.add_theme_font_size_override("font_size", 16)
	skip.add_theme_color_override("font_color", Color(0.8, 0.88, 0.92, 0.5))
	skip.add_theme_color_override("font_hover_color", Color(0.92, 0.98, 1.0, 0.95))
	skip.pressed.connect(_end)
	add_child(skip)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2027
	for k in 320:
		stars.append(Vector3(rng.randf(), rng.randf(), pow(rng.randf(), 3.0)))
	for k in 220:
		snow.append(Vector3(rng.randf(), rng.randf(), pow(rng.randf(), 2.0)))
	for k in 46:
		cells.append(Vector3(rng.randf(), rng.randf(), rng.randf()))


func _layer_control() -> Control:
	var c := Control.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.material = ShaderMaterial.new()
	c.material.shader = preload("res://shaders/dither.gdshader")
	add_child(c)
	return c


func _ready() -> void:
	refresh()


# (Dark already: night mode holds off while it plays.)
func _enter_tree() -> void:
	NightMode.suspend += 1


func _exit_tree() -> void:
	NightMode.suspend -= 1


func _process(dt: float) -> void:
	if done:
		return
	t += dt
	if t >= LEN:
		_end()
		return
	refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_end()


func _end() -> void:
	if done:
		return
	done = true
	finished.emit()
	queue_free()


func _beat(k: int) -> float:
	return clampf((t - BEATS[k]) / (BEATS[k + 1] - BEATS[k]), 0.0, 1.0)


func _ease(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


func _bar() -> float:
	return sz.y * 0.1 * _ease(t / 1.6)


func refresh() -> void:
	sz = get_viewport().get_visible_rect().size
	planet.visible = t < BEATS[1]
	if planet.visible:
		var u := _beat(0)
		var r := sz.y * (0.3 + 0.06 * _ease(u))
		var c := Vector2(sz.x * 0.66, sz.y * 0.52)
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
	if t < BEATS[1]:
		_draw_space()
	elif t < BEATS[2]:
		_draw_fall()
	elif t < BEATS[3]:
		_draw_sinking()
	else:
		_draw_spring()


func _vgrad(top: Color, bottom: Color, y0: float, y1: float) -> void:
	var pts := PackedVector2Array([Vector2(0, y0), Vector2(sz.x, y0), Vector2(sz.x, y1), Vector2(0, y1)])
	back.draw_polygon(pts, PackedColorArray([top, top, bottom, bottom]))


func _draw_stars(drift: Vector2, alpha := 1.0) -> void:
	for s: Vector3 in stars:
		var p := Vector2(fposmod(s.x * sz.x + drift.x * (0.3 + s.z), sz.x), fposmod(s.y * sz.y + drift.y * (0.3 + s.z), sz.y))
		var tw := 0.75 + 0.25 * sin(t * (0.8 + s.z * 2.0) + s.x * 40.0)
		back.draw_circle(p, 0.5 + s.z * 1.1, Color(0.86, 0.92, 1.0, (0.18 + 0.75 * s.z) * tw * alpha))


# Shot 1: the ship comes up on the ocean world (the planet is a shader rect
# drawn over this; the ship goes in front, on `front`).
func _draw_space() -> void:
	back.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.012, 0.018, 0.03))
	_draw_stars(Vector2(-_beat(0) * 40.0, 0))
	# The sun, far off to the upper left.
	var sun := Vector2(sz.x * 0.08, sz.y * 0.16)
	back.draw_texture_rect(glow, Rect2(sun - Vector2.ONE * 160, Vector2.ONE * 320), false, Color(1.0, 0.96, 0.88, 0.5))
	back.draw_circle(sun, 7.0, Color(1.0, 0.98, 0.92))


# Shot 2: down through the air, a trail of heat, into the sea.
func _horizon() -> float:
	return sz.y * (0.5 + 0.08 * _ease(_beat(1)))


func _fall_at() -> Vector2:
	var u := _ease(_beat(1) / 0.92)
	var hz := _horizon()
	return Vector2(sz.x * lerpf(0.2, 0.6, u), lerpf(sz.y * 0.12, hz + sz.y * 0.12, pow(u, 1.25)))


func _draw_fall() -> void:
	var hz := _horizon()
	_vgrad(Color(0.36, 0.56, 0.66), Color(0.8, 0.87, 0.84), 0.0, hz)
	_vgrad(Color(0.2, 0.46, 0.55), Color(0.08, 0.27, 0.38), hz, sz.y)
	# Haze along the horizon and a glint of the sun on the water.
	back.draw_texture_rect(glow, Rect2(-sz.x * 0.2, hz - 40, sz.x * 1.4, 80), false, Color(0.95, 0.96, 0.9, 0.45))
	for k in 18:
		var y := hz + 8.0 + k * k * 1.6
		var w := sz.x * (0.04 + 0.012 * k) * (0.8 + 0.2 * sin(t * 2.0 + k))
		back.draw_texture_rect(glow, Rect2(sz.x * 0.22 - w * 0.5, y - 2, w, 4), false, Color(1.0, 0.97, 0.9, 0.25 * (1.0 - k / 18.0)))
	# Clouds drifting past (soft, a few layers).
	for k in 7:
		var cx := fposmod(k * 0.37 * sz.x - t * (30.0 + k * 9.0), sz.x * 1.4) - sz.x * 0.2
		var cy := sz.y * (0.08 + 0.05 * k)
		back.draw_texture_rect(glow, Rect2(cx - 220, cy - 30, 440, 60), false, Color(1.0, 1.0, 0.98, 0.35))
	# The splash, then the ring.
	var hit := BEATS[2] - 0.5
	if t > hit:
		var a := Vector2(sz.x * 0.6, hz + sz.y * 0.12)
		var k := (t - hit) / 0.5
		for i in 3:
			var rr := (60.0 + 260.0 * k) * (1.0 + i * 0.25)
			back.draw_arc(a, rr, 0, TAU, 64, Color(0.9, 0.98, 1.0, 0.6 * (1.0 - k)), 2.0, true)


# Shot 3: the pod sinking; the water darkens with depth, the light from above
# thins, specks of marine snow rise past.
func _depth() -> float:
	return _ease(_beat(2))


func _water(u: float) -> Array:
	var top := Color(0.46, 0.78, 0.86).lerp(Color(0.2, 0.4, 0.52), u)
	var bottom := Color(0.26, 0.56, 0.68).lerp(Color(0.13, 0.28, 0.4), u)
	return [top, bottom]


func _draw_sinking() -> void:
	var u := _depth()
	var w := _water(u)
	_vgrad(w[0], w[1], 0.0, sz.y)
	# Light shafts from the surface, fading with depth.
	for k in 6:
		var x := sz.x * (0.1 + 0.17 * k) + sin(t * 0.3 + k) * 30.0
		var pts := PackedVector2Array([Vector2(x - 30, 0), Vector2(x + 30, 0), Vector2(x + 180, sz.y), Vector2(x + 60, sz.y)])
		var a := 0.12 * (1.0 - u) * (0.6 + 0.4 * sin(t * 0.7 + k * 1.7))
		back.draw_polygon(pts, PackedColorArray([Color(1, 1, 1, a), Color(1, 1, 1, a), Color(1, 1, 1, 0), Color(1, 1, 1, 0)]))
	# Marine snow rising past (the camera goes down with the pod).
	var fall := t * 120.0
	for s: Vector3 in snow:
		var p := Vector2(s.x * sz.x + sin(t * 0.5 + s.y * 20.0) * 6.0, fposmod(s.y * sz.y - fall * (0.4 + s.z), sz.y))
		back.draw_circle(p, 0.8 + s.z * 1.8, Color(0.85, 0.95, 1.0, 0.18 + 0.4 * s.z))
	_pod(Vector2(sz.x * 0.5 + sin(t * 0.8) * 12.0, sz.y * 0.47), sz.y * 0.16, 0.0, u)


# The seed pod: the ship's green vault on its own, with lamps that light
# the water below once it is dark enough to need them.
func _pod(at: Vector2, s: float, open: float, dark: float) -> void:
	var lamp := clampf((dark - 0.3) / 0.5, 0.0, 1.0)
	if lamp > 0.0:
		var cone := PackedVector2Array([at + Vector2(-0.1, 0.05) * s, at + Vector2(0.1, 0.05) * s, at + Vector2(0.6, 1.4) * s, at + Vector2(-0.6, 1.4) * s])
		back.draw_polygon(cone, PackedColorArray([Color(0.85, 1.0, 0.95, 0.3 * lamp), Color(0.85, 1.0, 0.95, 0.3 * lamp), Color(0.85, 1.0, 0.95, 0), Color(0.85, 1.0, 0.95, 0)]))
	back.draw_texture_rect(glow, Rect2(at - Vector2(0.6, 0.6) * s, Vector2(1.2, 1.2) * s), false, Color(0.4, 1.0, 0.75, 0.25))
	back.draw_set_transform(at, PI * 0.5, Vector2(s, s))
	var lit := Color(0.62, 0.74, 0.78)
	var shade := Color(0.16, 0.22, 0.25)
	# The shell, its two halves parting when it opens.
	for side in [-1.0, 1.0]:
		var off := Vector2(0, side * 0.07 * open)
		ShipArt.tube(back, off, 0.16, 0.13, lit if side < 0 else shade, Color(0.05, 0.08, 0.1), Color(0.6, 0.95, 1.0, 0.6 if side < 0 else 0.2))
	ShipArt.tube(back, Vector2.ZERO, 0.14, 0.1 * (1.0 - 0.3 * open), Color(0.45, 0.92, 0.7, 0.9), Color(0.1, 0.36, 0.26, 0.9), Color(0, 0, 0, 0))
	for q in 4:
		back.draw_circle(Vector2(-0.12 + q * 0.08, -0.12), 0.012, Color(1.0, 0.92, 0.7, 0.4 + 0.6 * lamp))
	back.draw_set_transform(Vector2.ZERO)


# Shot 4: the seabed; a chimney breathes warm water; the pod settles beside
# it and opens, and the first cells drift out to the warm.
func _draw_spring() -> void:
	var u := _beat(3)
	var w := _water(1.0)
	_vgrad(w[0], w[1].lerp(Color(0.3, 0.32, 0.34), 0.25), 0.0, sz.y)
	var bed := sz.y * 0.78
	var vent := Vector2(sz.x * 0.62, bed - sz.y * 0.3)
	# The warm glow round the spring's mouth, under everything.
	back.draw_texture_rect(glow, Rect2(vent - Vector2(520, 380), Vector2(1040, 760)), false, Color(1.0, 0.66, 0.4, 0.34))
	# Seabed: dark rock, lit warm toward the spring.
	var ground := PackedVector2Array()
	var cols := PackedColorArray()
	for k in 41:
		var x := sz.x * k / 40.0
		var y := bed + sin(k * 0.9) * 10.0 + sin(k * 0.37) * 18.0
		ground.append(Vector2(x, y))
		var warm := clampf(1.0 - absf(x - vent.x) / (sz.x * 0.35), 0.0, 1.0)
		cols.append(Color(0.3, 0.33, 0.36).lerp(Color(0.56, 0.42, 0.32), warm * 0.8))
	ground.append(Vector2(sz.x, sz.y))
	ground.append(Vector2(0, sz.y))
	cols.append(Color(0.18, 0.21, 0.24))
	cols.append(Color(0.18, 0.21, 0.24))
	back.draw_polygon(ground, cols)
	# The chimney: a tapering stack of mineral, its mouth glowing.
	var base_w := sz.y * 0.1
	var top_w := sz.y * 0.035
	# (Lumpy, as mineral piles up: the outline wanders and bulges.)
	var stack := PackedVector2Array()
	var scol := PackedColorArray()
	for k in 25:
		var f := k / 24.0
		var y := lerpf(bed + 6, vent.y, f)
		var hw := lerpf(base_w, top_w, pow(f, 0.8)) * (1.0 + 0.18 * sin(f * 19.0) + 0.1 * sin(f * 41.0 + 1.3))
		stack.append(Vector2(vent.x - hw, y))
		scol.append(Color(0.34, 0.31, 0.3).lerp(Color(0.68, 0.5, 0.36), f))
	for k in 25:
		var f := 1.0 - k / 24.0
		var y := lerpf(bed + 6, vent.y, f)
		var hw := lerpf(base_w * 0.85, top_w, pow(f, 0.8)) * (1.0 + 0.16 * sin(f * 23.0 + 2.0) + 0.09 * sin(f * 37.0))
		stack.append(Vector2(vent.x + hw, y))
		scol.append(Color(0.28, 0.26, 0.26).lerp(Color(0.58, 0.42, 0.3), f))
	back.draw_polygon(stack, scol)
	# Two small side chimneys, smoking a little.
	for side in [-1.0, 1.0]:
		var sx: float = vent.x + side * base_w * 0.55
		var sy: float = lerpf(bed, vent.y, 0.45 if side < 0 else 0.3)
		back.draw_circle(Vector2(sx, sy), top_w * 0.7, Color(0.5, 0.38, 0.3))
		back.draw_texture_rect(glow, Rect2(Vector2(sx, sy) - Vector2(24, 40), Vector2(48, 48)), false, Color(1.0, 0.75, 0.5, 0.45))
	back.draw_texture_rect(glow, Rect2(vent - Vector2(60, 40), Vector2(120, 80)), false, Color(1.0, 0.8, 0.5, 0.8))
	# The plume: warm water shimmering up and greying as it cools.
	for k in 14:
		var ph := fposmod(t * 0.35 + k / 14.0, 1.0)
		var p := vent + Vector2(sin(t * 1.3 + k * 2.1) * (10.0 + 50.0 * ph), -ph * sz.y * 0.36)
		var r := 30.0 + 90.0 * ph
		back.draw_texture_rect(glow, Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0), false, Color(1.0, 0.7, 0.45).lerp(Color(0.6, 0.65, 0.68), ph) * Color(1, 1, 1, 0.22 * (1.0 - ph)))
	# The pod comes down beside it, settles, opens.
	var land := Vector2(sz.x * 0.4, bed - sz.y * 0.07)
	var down := _ease(u / 0.35)
	var pod_at := land + Vector2(0, -sz.y * 0.45 * (1.0 - down))
	var open := _ease((u - 0.45) / 0.15)
	if down >= 1.0:
		var puff := clampf((u - 0.35) / 0.1, 0.0, 1.0)
		if puff < 1.0:
			back.draw_texture_rect(glow, Rect2(land + Vector2(-200, 10), Vector2(400, 90)), false, Color(0.7, 0.68, 0.62, 0.4 * (1.0 - puff)))
	_pod(pod_at, sz.y * 0.13, open, 1.0)
	# The first cells: out of the pod, drifting to the warm water.
	if open > 0.2:
		for c: Vector3 in cells:
			var k := clampf((u - 0.55 - c.y * 0.15) / 0.4, 0.0, 1.0)
			if k <= 0.0:
				continue
			var s := _ease(k)
			var a0 := pod_at + Vector2(0.06 * sz.y * (c.x - 0.5), -0.01 * sz.y)
			var a1 := vent + Vector2((c.x - 0.5) * 160.0, 40.0 + c.z * 110.0)
			var mid := (a0 + a1) * 0.5 + Vector2(0, -sz.y * 0.08 * (0.5 + c.z))
			var p := a0.lerp(mid, s).lerp(mid.lerp(a1, s), s) + Vector2(sin(t * 3.0 + c.x * 30.0), cos(t * 2.4 + c.z * 20.0)) * 3.0
			back.draw_texture_rect(glow, Rect2(p - Vector2(9, 9), Vector2(18, 18)), false, Color(CELL_COL, 0.55))
			back.draw_circle(p, 2.6, Color(0.85, 1.0, 0.95, 0.95))


func _draw_front() -> void:
	# The ship over the planet in shot 1 and falling in shot 2.
	if t < BEATS[1]:
		var u := _ease(_beat(0))
		var at := Vector2(sz.x * lerpf(0.06, 0.44, u), sz.y * lerpf(0.66, 0.5, u))
		ShipArt.ship(front, at, -0.2 + 0.12 * u, sz.y * lerpf(0.26, 0.1, u), 0.3 + 0.5 * (1.0 - u), t, glow)
	elif t < BEATS[2]:
		var p := _fall_at()
		var dir := (_fall_at() - Vector2(sz.x * 0.2, sz.y * 0.12)).normalized()
		var heat := 1.0 - _ease((_beat(1) - 0.6) / 0.3)
		# The trail of heat behind it.
		for k in 14:
			var q := p - dir * (k * 26.0)
			var r := 30.0 - k * 1.5
			front.draw_texture_rect(glow, Rect2(q - Vector2(r, r), Vector2(r, r) * 2.0), false, Color(1.0, 0.75, 0.5, 0.3 * heat * (1.0 - k / 14.0)))
		front.draw_texture_rect(glow, Rect2(p - Vector2(50, 50), Vector2(100, 100)), false, Color(1.0, 0.92, 0.8, 0.8 * heat))
		ShipArt.ship(front, p, dir.angle(), sz.y * 0.08, 0.0, t, glow)
		# The flash as it strikes the water.
		var flash := clampf(1.0 - absf(t - (BEATS[2] - 0.45)) / 0.3, 0.0, 1.0)
		front.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.95, 1.0, 1.0, 0.7 * flash))
	elif t < BEATS[3]:
		# The depth, counting.
		var m := DEPTH_M * _depth()
		var x := sz.x - 210.0
		var y0 := sz.y * 0.22
		var y1 := sz.y * 0.78
		front.draw_line(Vector2(x, y0), Vector2(x, y1), Color(0.8, 0.95, 1.0, 0.45), 1.0, true)
		for k in 7:
			var y := lerpf(y0, y1, k / 6.0)
			front.draw_line(Vector2(x - 8, y), Vector2(x, y), Color(0.8, 0.95, 1.0, 0.45), 1.0, true)
		var my := lerpf(y0, y1, _depth())
		front.draw_line(Vector2(x - 14, my), Vector2(x + 6, my), Color(0.6, 1.0, 0.85, 0.9), 2.0, true)
		front.draw_string(Ui.mono("Medium"), Vector2(x + 16, my + 6), "深度 %d m" % int(m), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.85, 1.0, 0.95, 0.9))
		front.draw_string(Ui.mono("Medium"), Vector2(x + 16, my + 28), "光照 %d%%" % int(100.0 * pow(1.0 - _depth(), 2.0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.7, 0.9, 0.9, 0.7))
	var bh := _bar()
	front.draw_rect(Rect2(0, 0, sz.x, bh), Color.BLACK)
	front.draw_rect(Rect2(0, sz.y - bh, sz.x, bh), Color.BLACK)
	for l: Array in LINES:
		var a := minf(_ease((t - l[0]) / 0.6), _ease((l[1] - t) / 0.6))
		if a > 0.0:
			_text(Vector2(sz.x * 0.5, sz.y - bh * 0.5 + 12), l[2], 32, Color(0.92, 0.97, 0.98, a), Ui.sans(500))
	var black := 1.0 - _ease(t / 1.2)
	for k in [1, 3]:
		black = maxf(black, 1.0 - clampf(absf(t - BEATS[k]) / 0.4, 0.0, 1.0))
	black = maxf(black, _ease((t - (LEN - 1.4)) / 1.4))
	front.draw_rect(Rect2(Vector2.ZERO, sz), Color(0, 0, 0, black))


func _text(at: Vector2, s: String, size: int, col: Color, font: Font) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	front.draw_string(font, at - Vector2(w * 0.5, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
