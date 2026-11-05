extends CanvasLayer
# The end of Europa (level 24 won): the chapter's bodies swim in the dish, the
# seed vault comes down and takes them up, the ship Genesis Protocol lifts off
# the ice under Jupiter, passes it and goes; about 40 seconds, letterboxed, each
# shot moving slowly. The bodies are drawn as the bench draws them
# (body_bench.gd Body), the worlds and the vault by shaders (planet, ice_field,
# glass_vault). Esc, a click on "跳过" or the end itself emits `finished`.

signal finished

const Bench := preload("res://scripts/ui/body_bench.gd")
const LEN := 40.0
const BEATS := [0.0, 7.0, 14.0, 21.0, 31.0, LEN] # dish, vault, lift-off, Jupiter, warp
# The chapter's bodies, as the guide left each level (levels.gd 5-2 .. 5-5),
# and the three-armour body that starved the guardian.
const BODIES := [
	[[0, 0, 1], [1, 0, 1], [2, 0, 1], [3, 0, 1], [0, 1, 6], [1, 1, 1], [2, 1, 1], [3, 1, 6], [0, 2, 1], [1, 2, 1], [2, 2, 1], [3, 2, 6]],
	[[0, 0, 1], [1, 0, 1], [2, 0, 1], [3, 0, 1], [0, 1, 6], [1, 1, 6], [2, 1, 6], [3, 1, 1], [0, 2, 1], [1, 2, 1], [2, 2, 1], [3, 2, 1]],
	[[0, 0, 7], [1, 0, 1], [2, 0, 1], [3, 0, 1], [0, 1, 6], [1, 1, 8], [2, 1, 6], [3, 1, 1], [0, 2, 7], [1, 2, 1], [2, 2, 1], [3, 2, 1]],
	[[0, 0, 7], [1, 0, 1], [2, 0, 1], [3, 0, 1], [0, 1, 6], [1, 1, 9], [2, 1, 6], [3, 1, 1], [0, 2, 7], [1, 2, 1], [2, 2, 1], [3, 2, 1]],
	[[0, 0, 7], [1, 0, 1], [2, 0, 1], [3, 0, 7], [0, 1, 6], [1, 1, 9], [2, 1, 8], [3, 1, 6], [0, 2, 7], [1, 2, 1], [2, 2, 1], [3, 2, 7]],
]
# Where each swims in the dish (in dish radii) and its turn.
const HOMES := [Vector2(-0.42, -0.3), Vector2(0.38, -0.36), Vector2(0.0, 0.05), Vector2(-0.4, 0.42), Vector2(0.42, 0.38)]
# The words, one at a time in the lower bar: [from, to, text].
const LINES := [
	[1.2, 6.2, "木卫二 · 热液喷口　实验结束"],
	[8.2, 13.4, "五种生命设计已封存"],
	[14.9, 20.4, "播种飞船「创生协议」"],
	[22.0, 25.4, "人类学会了设计生命。"],
	[25.9, 28.2, "种子舱里的五种生命，"],
	[28.4, 30.7, "要去唤醒一颗没有氧气的星球。"],
]
const SUN := Vector2(-0.85, -0.3)

var t := 0.0
var done := false
var sz := Vector2(1920, 1080)
var back: Control
var mid: Control
var front: Control
var jupiter: ColorRect
var europa: ColorRect
var ice: ColorRect
var vault: ColorRect
var bodies: Array[Node2D] = []
var skip: Button
var glow: GradientTexture2D
var stars := PackedVector3Array()


func _init() -> void:
	layer = 60
	glow = _glow_tex()
	back = _layer_control()
	back.mouse_filter = Control.MOUSE_FILTER_STOP
	back.draw.connect(_draw_back)
	jupiter = _shader_rect(preload("res://shaders/planet.gdshader"))
	europa = _shader_rect(preload("res://shaders/planet.gdshader"))
	europa.material.set_shader_parameter("kind", 1)
	ice = _shader_rect(preload("res://shaders/ice_field.gdshader"))
	mid = _layer_control()
	mid.draw.connect(_draw_mid)
	for cells in BODIES:
		var b := Bench.Body.new()
		b.scale_px = 1.5
		b.dark = 1.0
		add_child(b)
		b.show_cells(cells, 0.8)
		bodies.append(b)
	vault = _shader_rect(preload("res://shaders/glass_vault.gdshader"))
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
	skip.add_theme_color_override("font_pressed_color", Color(0.7, 1.0, 0.85))
	skip.pressed.connect(_end)
	add_child(skip)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	for k in 320:
		stars.append(Vector3(rng.randf(), rng.randf(), pow(rng.randf(), 3.0)))


func _layer_control() -> Control:
	var c := Control.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.material = ShaderMaterial.new()
	c.material.shader = preload("res://shaders/dither.gdshader")
	add_child(c)
	return c


func _shader_rect(shader: Shader) -> ColorRect:
	var r := ColorRect.new()
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.material = ShaderMaterial.new()
	r.material.shader = shader
	add_child(r)
	return r


static func _glow_tex() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.35, Color(1, 1, 1, 0.35))
	g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CUBIC
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	# (Float texels: no rings where a big glow fades into the dark.)
	tex.use_hdr = true
	tex.width = 256
	tex.height = 256
	return tex


func _ready() -> void:
	refresh()


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


# 0..1 through beat k.
func _beat(k: int) -> float:
	return clampf((t - BEATS[k]) / (BEATS[k + 1] - BEATS[k]), 0.0, 1.0)


func _ease(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


func _bar() -> float:
	return sz.y * 0.1 * _ease(t / 1.6)


# Lays every node out for time t, then redraws.
func refresh() -> void:
	sz = get_viewport().get_visible_rect().size
	var shot := 0
	for k in range(1, 5):
		if t >= BEATS[k]:
			shot = k
	var in_lab := shot <= 1
	for b in bodies:
		b.visible = in_lab
	vault.visible = shot == 1
	ice.visible = shot == 2
	jupiter.visible = shot == 2 or shot == 3
	europa.visible = shot == 3
	if in_lab:
		_lay_lab()
	elif shot == 2:
		_lay_liftoff()
	elif shot == 3:
		_lay_jupiter()
	skip.position = Vector2(sz.x - 150, maxf(_bar() * 0.5 - 18, 8))
	skip.size = Vector2(120, 36)
	back.queue_redraw()
	mid.queue_redraw()
	front.queue_redraw()


func _planet(r: ColorRect, c: Vector2, radius: float, spin: float) -> void:
	var pad := 1.15
	r.position = c - Vector2.ONE * radius * pad
	r.size = Vector2.ONE * radius * pad * 2.0
	var m: ShaderMaterial = r.material
	m.set_shader_parameter("pad", pad)
	m.set_shader_parameter("px", 1.0 / radius)
	m.set_shader_parameter("spin", spin)
	m.set_shader_parameter("light", SUN)


# --- Shots 1-2: the dish, the vault. ---------------------------------------

# The dish (centre, radius) at time t: the camera creeps in, then draws back
# and down as the vault comes.
func _dish() -> Array:
	var v := _ease(_beat(1) * 1.4)
	var push := 1.0 + 0.06 * _ease(t / 7.0)
	var c := sz * Vector2(0.5, lerpf(0.54, 0.74, v)) + Vector2(0, _pan())
	return [c, sz.y * lerpf(0.36 * push, 0.24, v)]


# Once the dish is empty the camera rises with the vault: everything slides
# down, the empty dish out of the frame.
func _pan() -> float:
	return sz.y * 0.22 * _ease((_beat(1) - 0.6) / 0.35)


func _vault_rect() -> Rect2:
	var v := _beat(1)
	var w := sz.y * 0.15
	var h := w * 2.6
	var down := _ease(clampf(v * 2.2, 0.0, 1.0))
	var c := Vector2(sz.x * 0.5, lerpf(-h * 0.6, sz.y * 0.31, down) + _pan())
	return Rect2(c - Vector2(w, h) * 0.5, Vector2(w, h))


# 0..1: how far body k has been taken up into the vault.
func _taken(k: int) -> float:
	return clampf((_beat(1) - 0.36 - k * 0.07) / 0.2, 0.0, 1.0)


func _lay_lab() -> void:
	var d := _dish()
	var c: Vector2 = d[0]
	var r: float = d[1]
	var vr := _vault_rect()
	for k in bodies.size():
		var b := bodies[k]
		var home: Vector2 = HOMES[k]
		var drift := Vector2(sin(t * 0.31 + k * 1.7), cos(t * 0.27 + k * 2.3)) * 0.04
		var p := c + (home + drift) * r
		var go := _ease(_taken(k))
		# Up along a curve to its place in the vault (stacked from the bottom,
		# hanging in the medium), smaller as it goes.
		var slot := vr.get_center() + Vector2((0.1 if k % 2 == 0 else -0.1) * vr.size.x, (0.27 - k * 0.13) * vr.size.y)
		slot += Vector2(sin(t * 0.7 + k), cos(t * 0.5 + k * 2.0)) * 3.0
		var lift := p.lerp(slot, go) + Vector2((1.0 if k % 2 == 0 else -1.0) * sin(go * PI) * r * 0.35, 0.0)
		b.position = lift
		b.rotation = k * 1.3 + t * 0.06 * (1.0 if k % 2 == 0 else -1.0) + go * 1.5
		b.scale = Vector2.ONE * lerpf(r / (sz.y * 0.36), vr.size.x * 0.0027, go)
	var v := _beat(1)
	var fill := 0.0
	for k in bodies.size():
		fill += _ease(_taken(k)) / bodies.size()
	vault.position = vr.position
	vault.size = vr.size
	var m: ShaderMaterial = vault.material
	m.set_shader_parameter("fill", fill * 0.82)
	m.set_shader_parameter("seal", clampf((v - 0.86) / 0.12, 0.0, 1.0))
	m.set_shader_parameter("aspect", vr.size.y / vr.size.x)
	m.set_shader_parameter("px", 2.0 / vr.size.x)
	m.set_shader_parameter("t", t)


# --- Shot 3: lift-off from the ice. -----------------------------------------

func _horizon() -> float:
	# The camera tilts up after the ship: the horizon sinks.
	var u := _beat(2)
	return sz.y * (0.66 + 0.2 * _ease((u - 0.35) / 0.65))


func _lay_liftoff() -> void:
	var u := _beat(2)
	var hz := _horizon()
	_planet(jupiter, Vector2(sz.x * 0.72, hz - sz.y * 0.08) + _shake() * 0.3, sz.y * (0.46 + 0.02 * u), 0.4 + t * 0.012)
	ice.position = Vector2(0, hz) + _shake() + Vector2(-8, 0)
	ice.size = Vector2(sz.x + 16, sz.y - hz + 10)
	var m: ShaderMaterial = ice.material
	m.set_shader_parameter("t", t)
	m.set_shader_parameter("glare_x", 0.18)


# --- Shot 4: Jupiter, Europa beside it. --------------------------------------

func _lay_jupiter() -> void:
	var u := _beat(3)
	var push := 1.0 + 0.1 * _ease(u)
	var c := sz * 0.5
	var jc := c + (sz * Vector2(0.27, 0.56) - c) * push
	_planet(jupiter, jc, sz.y * 0.5 * push, 1.1 + t * 0.012)
	var ec := c + (sz * Vector2(0.71, 0.3) - c) * push
	_planet(europa, ec, sz.y * 0.07 * push, 0.5 + t * 0.01)


# --- Drawing. ---------------------------------------------------------------

func _draw_back() -> void:
	back.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.012, 0.018, 0.03))
	if t < BEATS[2]:
		_draw_dish()
	elif t < BEATS[4]:
		var drift := Vector2(0, (_horizon() - sz.y * 0.66) * 0.3) if t < BEATS[3] else Vector2(-_beat(3) * 60.0, 0)
		_draw_stars(back, drift)


func _draw_stars(ci: CanvasItem, drift: Vector2, alpha := 1.0) -> void:
	for s: Vector3 in stars:
		var p := Vector2(fposmod(s.x * sz.x + drift.x * (0.3 + s.z), sz.x), fposmod(s.y * sz.y + drift.y * (0.3 + s.z), sz.y))
		var tw := 0.75 + 0.25 * sin(t * (0.8 + s.z * 2.0) + s.x * 40.0)
		var a := (0.18 + 0.75 * s.z) * tw * alpha
		ci.draw_circle(p, 0.5 + s.z * 1.1, Color(0.86, 0.92, 1.0, a))
		if s.z > 0.6:
			var g := 10.0 + 18.0 * s.z
			ci.draw_texture_rect(glow, Rect2(p - Vector2.ONE * g * 0.5, Vector2.ONE * g), false, Color(0.7, 0.82, 1.0, a * 0.35))


# The dish on the dark bench, lit from above: a pool of light, the glass rim
# catching it, the water's sheen.
func _draw_dish() -> void:
	var d := _dish()
	var c: Vector2 = d[0]
	var r: float = d[1]
	back.draw_texture_rect(glow, Rect2(c - Vector2(r, r) * 2.4, Vector2(r, r) * 4.8), false, Color(0.16, 0.32, 0.36, 0.55))
	back.draw_circle(c, r * 1.04, Color(0.03, 0.07, 0.08))
	back.draw_texture_rect(glow, Rect2(c - Vector2(r, r) * 1.05, Vector2(r, r) * 2.1), false, Color(0.12, 0.3, 0.32, 0.7))
	back.draw_circle(c, r, Color(0.06, 0.16, 0.17, 0.35))


func _draw_mid() -> void:
	if t < BEATS[2]:
		_draw_rim()
	elif t < BEATS[3]:
		_draw_liftoff()
	elif t < BEATS[4]:
		_draw_passing()


# The dish's glass wall over the water: thick, bright where the light falls.
func _draw_rim() -> void:
	var d := _dish()
	var c: Vector2 = d[0]
	var r: float = d[1]
	mid.draw_arc(c, r * 1.02, 0, TAU, 160, Color(0.55, 0.85, 0.88, 0.22), r * 0.035, true)
	mid.draw_arc(c, r, 0, TAU, 160, Color(0.75, 0.97, 1.0, 0.55), 1.6, true)
	mid.draw_arc(c, r * 1.04, 0, TAU, 160, Color(0.75, 0.97, 1.0, 0.3), 1.2, true)
	mid.draw_arc(c, r * 1.02, PI * 1.05, PI * 1.45, 64, Color(0.95, 1.0, 1.0, 0.75), 3.0, true)
	mid.draw_arc(c, r * 1.02, PI * 0.15, PI * 0.3, 24, Color(0.95, 1.0, 1.0, 0.35), 2.0, true)


# The ship, nose along +x, `s` its length: a crew module, the seed vault's
# glass pod with the five bodies in it, a truss spine with radiators and tanks,
# the engine. Dark glass-steel lit from its -y side, a cold rim of light on
# every edge (the dish's look carried out into space).
func _ship(ci: CanvasItem, at: Vector2, ang: float, s: float, burn: float) -> void:
	ShipArt.ship(ci, at, ang, s, burn, t, glow)


# The ground shaking under the engine, strongest as it lights.
func _shake() -> Vector2:
	var u := _beat(2)
	var a := sz.y * 0.004 * _ease(u * 4.0) * (1.0 - _ease((u - 0.2) / 0.4))
	return Vector2(sin(t * 61.0), cos(t * 47.0)) * a


# Shot 3: on the ice, the vapour and the spray, the ship going up.
func _draw_liftoff() -> void:
	var u := _beat(2)
	var hz := _horizon()
	var base := Vector2(sz.x * 0.34, hz + sz.y * 0.1) + _shake()
	var ignite := _ease(u * 3.0)
	var rise := _ease((u - 0.22) / 0.78)
	var s := sz.y * 0.42
	var at := base - Vector2(0, s * 0.52 + rise * rise * sz.y * 1.4)
	# Its shadow on the ice, until it leaves.
	mid.draw_texture_rect(glow, Rect2(base - Vector2(sz.y * 0.18, sz.y * 0.03), Vector2(sz.y * 0.36, sz.y * 0.06)), false, Color(0.0, 0.02, 0.05, 0.7 * (1.0 - rise)))
	# The engine's light on the ice: a hot disc, a wide blue pool.
	var on_ice := ignite * (1.0 - rise * 0.8)
	mid.draw_texture_rect(glow, Rect2(base - Vector2(sz.y * 0.7, sz.y * 0.14), Vector2(sz.y * 1.4, sz.y * 0.28)), false, Color(0.5, 0.7, 1.0, 0.45 * on_ice))
	mid.draw_texture_rect(glow, Rect2(base - Vector2(sz.y * 0.16, sz.y * 0.035), Vector2(sz.y * 0.32, sz.y * 0.07)), false, Color(1.0, 0.95, 0.85, 0.8 * on_ice))
	# Ice crystals blasted outward, glinting, falling back.
	for k in 70:
		var seed := fposmod(k * 0.6180339, 1.0)
		var life := fposmod(u * (2.5 + seed * 2.0) + seed * 3.0, 1.0)
		var dir := Vector2(cos(PI + seed * PI), -absf(sin(PI + seed * PI)) * 0.5 - 0.1)
		var p := base + dir * sz.y * 0.5 * life + Vector2(0, sz.y * 0.35 * life * life)
		var a := ignite * (1.0 - rise) * sin(PI * life)
		mid.draw_circle(p, 1.0 + 1.6 * fposmod(k * 0.37, 1.0), Color(0.85, 0.95, 1.0, 0.8 * a))
	# The vapour: ice flashing off under the engine, billowing up and out.
	for k in 18:
		var f := k / 18.0
		var age := clampf(u * 1.6 - f * 0.3, 0.0, 1.0)
		if age <= 0.0:
			continue
		var side := sin(k * 2.4)
		var vw := sz.y * (0.06 + 0.18 * age) * (0.7 + 0.6 * fposmod(k * 0.37, 1.0))
		var p := base + Vector2(side * sz.y * 0.4 * age, -sz.y * (0.04 + 0.26 * age * (1.0 - absf(side) * 0.5)))
		var col := Color(0.55, 0.64, 0.74, 0.55 * ignite * (1.0 - age * 0.7))
		mid.draw_texture_rect(glow, Rect2(p - Vector2(vw, vw * 0.6), Vector2(vw * 2.0, vw * 1.2)), false, col)
	_ship(mid, at, -PI * 0.5, s, ignite * (1.0 + 0.5 * rise))


# Shot 4: the ship passing, between Jupiter's night and Europa.
func _draw_passing() -> void:
	var u := _beat(3)
	var a := Vector2(sz.x * 0.34, sz.y * 0.84)
	var b := Vector2(sz.x * 1.16, sz.y * 0.26)
	var at := a.lerp(b, _ease(u * 0.9 + 0.05))
	var dir := (b - a).normalized()
	# Its trail, fading behind it.
	for k in 30:
		var f := k / 30.0
		var p := at - dir * (f * sz.x * 0.45 + sz.y * 0.1)
		var r := 16.0 * (1.0 - f * 0.5)
		mid.draw_texture_rect(glow, Rect2(p - Vector2.ONE * r, Vector2.ONE * r * 2.0), false, Color(0.5, 0.75, 1.0, 0.16 * (1.0 - f)))
	_ship(mid, at, dir.angle(), sz.y * 0.2, 1.0)


func _draw_front() -> void:
	if t >= BEATS[1] and t < BEATS[2]:
		_draw_vault_label()
	elif t >= BEATS[2] and t < BEATS[3]:
		# The horizon's edge, catching the sun.
		var hz := _horizon()
		front.draw_texture_rect(glow, Rect2(-sz.x * 0.2, hz - 6, sz.x * 0.9, 12), false, Color(1.0, 0.95, 0.85, 0.35))
	elif t >= BEATS[4]:
		_draw_warp()
	# The bars, and the line in the lower one.
	var bh := _bar()
	front.draw_rect(Rect2(0, 0, sz.x, bh), Color.BLACK)
	front.draw_rect(Rect2(0, sz.y - bh, sz.x, bh), Color.BLACK)
	for l: Array in LINES:
		var a := minf(_ease((t - l[0]) / 0.6), _ease((l[1] - t) / 0.6))
		if a > 0.0:
			_text(Vector2(sz.x * 0.5, sz.y - bh * 0.5 + 12), l[2], 32, Color(0.92, 0.97, 0.98, a), Ui.sans(500))
	# Fade in, the cuts, fade out.
	var black := 1.0 - _ease(t / 1.4)
	for k in [2, 3, 4]:
		black = maxf(black, 1.0 - clampf(absf(t - BEATS[k]) / 0.4, 0.0, 1.0))
	black = maxf(black, _ease((t - (LEN - 1.8)) / 1.8))
	front.draw_rect(Rect2(Vector2.ZERO, sz), Color(0, 0, 0, black))


func _text(at: Vector2, s: String, size: int, col: Color, font: Font) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	front.draw_string(font, at - Vector2(w * 0.5, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


# A quiet label beside the vault once it has filled, with a hairline to it.
func _draw_vault_label() -> void:
	var a := _ease((_beat(1) - 0.86) / 0.1)
	if a <= 0.0:
		return
	var vr := _vault_rect()
	var from := Vector2(vr.end.x + 8, vr.get_center().y)
	var to := from + Vector2(70, 0)
	front.draw_line(from, to, Color(0.75, 0.97, 1.0, 0.5 * a), 1.0, true)
	var font := Ui.mono("Medium")
	front.draw_string(font, to + Vector2(10, -4), "种子舱", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.85, 1.0, 0.95, 0.9 * a))
	front.draw_string(font, to + Vector2(10, 18), "SEED VAULT · 5 / 5", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.6, 0.85, 0.8, 0.7 * a))


# Shot 5: the stars draw out into lines; the title.
func _draw_warp() -> void:
	var u := _beat(4)
	var c := sz * 0.5
	var stretch := _ease(u * 1.5)
	var title := _ease((u - 0.3) / 0.25)
	for s: Vector3 in stars:
		var d := (Vector2(s.x, s.y) - Vector2(0.5, 0.5)) * sz * (0.6 + 0.4 * s.z)
		var p := c + d * (1.0 + 0.4 * stretch)
		var q := c + d * (1.0 + (0.4 + 1.2 * (0.3 + s.z)) * stretch)
		# Clear of the title once it shows: lines fade near the middle.
		var near := (p / sz - Vector2(0.5, 0.5)) * Vector2(1.0, 1.9)
		var keep := lerpf(1.0, smoothstep(0.18, 0.34, near.length()), title)
		# Cyan-green, the game's light; a few warm ones among them.
		var col := Color(1.0, 0.85, 0.65) if fposmod(s.x * 97.0, 1.0) < 0.06 else Color(0.6, 0.95, 0.9).lerp(Color(0.7, 0.85, 1.0), s.y)
		var lines := PackedVector2Array([p, q])
		front.draw_polyline_colors(lines, PackedColorArray([Color(col, 0.0), Color(col, (0.25 + 0.7 * s.z) * keep)]), 0.8 + 1.6 * s.z, true)
	# The jump: a flash as the stars draw out.
	var flash := clampf(1.0 - absf(u - 0.12) / 0.06, 0.0, 1.0)
	front.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.85, 1.0, 0.95, 0.5 * flash))
	# A light at the centre the lines run out of, then the title in front of it.
	var bloom := _ease(u * 2.0) * (1.0 - 0.6 * _ease((u - 0.5) * 3.0))
	front.draw_texture_rect(glow, Rect2(c - Vector2(sz.y, sz.y * 0.5) * 0.6, Vector2(sz.y, sz.y * 0.5) * 1.2), false, Color(0.55, 0.75, 1.0, 0.35 * bloom))
	if title > 0.0:
		front.draw_texture_rect(glow, Rect2(c - Vector2(420, 120), Vector2(840, 240)), false, Color(0, 0, 0, 0.55 * title))
		_text(c + Vector2(0, -6), "创生协议", 72, Color(0.94, 0.98, 1.0, title), Ui.sans(700))
		_text(c + Vector2(0, 42), "G E N E S I S   P R O T O C O L", 18, Color(0.68, 0.84, 0.95, title * 0.85), Ui.mono("Medium"))
	var next := _ease((u - 0.58) / 0.2)
	if next > 0.0:
		front.draw_line(c + Vector2(-60, 82), c + Vector2(60, 82), Color(0.6, 1.0, 0.8, 0.7 * next), 1.0, true)
		_text(c + Vector2(0, 124), "第 六 章 · 播 种 篇", 28, Color(0.86, 1.0, 0.93, next), Ui.sans(600))
