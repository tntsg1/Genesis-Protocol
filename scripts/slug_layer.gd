extends Node2D
# The slug as a player sees it (level 20), drawn under the cells it is made of
# (they are real cells, held by the kernel). Gathering: the centre pulses, the
# water around it brightens outward in waves. Crawling: a glassy sheath round
# the cells, tapering to the tail, leaving a fading trail of slime. Rising:
# the stalk climbs out of the base and a head swells at its tip; the dead stalk
# stands on after the spores have flown. Sizes are in world units.

const SHEATH := Color(0.62, 0.9, 0.86)
const EDGE := Color(0.08, 0.5, 0.5)
const STALK := Color(0.62, 0.52, 0.34)
const TRAIL_STEP := 16.0 # µm between trail marks
const TRAIL_LIFE := 30.0

var host: Node2D
var zoom := 1.0
var t := 0.0
var slugs: Array = []
var trails := {} # slug id -> [{pos, r, age}]
var _soft: GradientTexture2D


func _init() -> void:
	var g := Gradient.new()
	g.set_color(0, Color.WHITE)
	g.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	_soft = GradientTexture2D.new()
	_soft.gradient = g
	_soft.fill = GradientTexture2D.FILL_RADIAL
	_soft.fill_from = Vector2(0.5, 0.5)
	_soft.fill_to = Vector2(1.0, 0.5)
	_soft.width = 96
	_soft.height = 96


func tick(dt: float) -> void:
	var on: bool = host.level_runner != null and host.level_runner.level.has("slug")
	visible = on
	if not on:
		trails.clear()
		return
	zoom = host.cam.zoom.x
	t += dt
	slugs = host.sim.get_slugs()
	for g: Dictionary in slugs:
		if int(g.stage) == 1:
			var list: Array = trails.get_or_add(int(g.id), [])
			if list.is_empty() or (list[-1].pos as Vector2).distance_to(g.pos) > TRAIL_STEP:
				list.append({pos = g.pos, r = _width(g), age = 0.0})
	for id: int in trails.keys():
		var list: Array = trails[id]
		for m: Dictionary in list:
			m.age += dt
		trails[id] = list.filter(func(m: Dictionary) -> bool: return m.age < TRAIL_LIFE)
	queue_redraw()


func _width(g: Dictionary) -> float:
	return 3.0 * sqrt(float(g.n)) + 7.0


func _soft_spot(at: Vector2, r: float, col: Color) -> void:
	draw_texture_rect(_soft, Rect2(at - Vector2.ONE * r, Vector2.ONE * r * 2.0), false, col)


func _draw() -> void:
	for id: int in trails:
		for m: Dictionary in trails[id]:
			_soft_spot(m.pos, float(m.r) * 1.2, Color(SHEATH, 0.16 * (1.0 - float(m.age) / TRAIL_LIFE)))
	for g: Dictionary in slugs:
		match int(g.stage):
			0: _gathering(g)
			1: _crawling(g)
			2, 3: _fruit(g)


# The centre calling: waves of brighter water running out from it.
func _gathering(g: Dictionary) -> void:
	var r := _width(g)
	for j in 3:
		var u := fposmod(t * 0.35 + j / 3.0, 1.0)
		_soft_spot(g.pos, r + 150.0 * u, Color(SHEATH, 0.22 * (1.0 - u)))
	_soft_spot(g.pos, r * 1.5, Color(SHEATH, 0.5))


func _crawling(g: Dictionary) -> void:
	var pos: Vector2 = g.mid
	var h: Vector2 = g.heading
	var side := h.orthogonal()
	var b := _width(g)
	var a := b * 2.2
	var pts := PackedVector2Array()
	for j in 40:
		var f := j / 40.0 * TAU
		# Blunt in front, drawn out to a tip behind; a slow wave runs along it.
		var c := cos(f)
		var along := a * c * (1.0 + 0.3 * smoothstep(0.0, -1.0, c))
		var across := b * sin(f) * (0.72 + 0.28 * (0.5 + 0.5 * c))
		across *= 1.0 + 0.05 * sin(c * 5.0 + t * 2.4)
		pts.append(pos + h * along + side * across)
	_soft_spot(pos, a * 1.5, Color(SHEATH, 0.3))
	draw_colored_polygon(pts, Color(SHEATH, 0.34))
	pts.append(pts[0])
	draw_polyline(pts, Color(EDGE, 0.55), maxf(0.3, 1.2 / zoom), true)


func _fruit(g: Dictionary) -> void:
	var base: Vector2 = g.base
	var stage := int(g.stage)
	var rise: float = clampf(float(g.t) / 10.0, 0.0, 1.0) if stage == 2 else 1.0
	var n: float = float(g.n) if stage == 2 else float(g.spores) * 1.25
	var size := 3.0 * sqrt(maxf(n, 1.0))
	var tall := (22.0 + size * 2.4) * rise
	var gone: float = clampf(float(g.t) / 45.0, 0.0, 1.0) if stage == 3 else 0.0
	var fade := 1.0 - gone * gone
	_soft_spot(base, size * 1.8, Color(0.0, 0.0, 0.0, 0.12 * fade))
	var top := base - Vector2(0.0, tall)
	# A slender, slightly bowed stalk, wider at the foot.
	var w := maxf(0.9, size * 0.075)
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for j in 13:
		var u := j / 12.0
		var at := base.lerp(top, u) + Vector2(sin(u * PI) * size * 0.1, 0.0)
		var half := w * lerpf(1.5, 0.55, u)
		left.append(at - Vector2(half, 0.0))
		right.append(at + Vector2(half, 0.0))
	var body := left.duplicate()
	for j in range(12, -1, -1):
		body.append(right[j])
	draw_colored_polygon(body, Color(STALK.lightened(0.25), 0.5 * fade))
	draw_polyline(left, Color(STALK.darkened(0.3), 0.75 * fade), maxf(0.3, 1.0 / zoom), true)
	draw_polyline(right, Color(STALK.darkened(0.3), 0.75 * fade), maxf(0.3, 1.0 / zoom), true)
	if stage == 2:
		_soft_spot(top, size * 1.6, Color(0.95, 0.8, 0.46, 0.55))
	else:
		# The empty head, a thin cup, fading with the rest.
		draw_arc(top, size * 0.5, 0.0, TAU, 28, Color(STALK.darkened(0.2), 0.5 * fade), maxf(0.3, 1.0 / zoom), true)
