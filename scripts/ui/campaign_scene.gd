extends RefCounted
# One chapter's map on the campaign page (2026-10-30: "看一下10个章节，每个章节
# 做一个地图"), for chapters 3 to 10 (scripts/ui/campaign_chapters.gd fills
# them in; chapter 1 is the drill site in campaign_model.gd, chapter 2 the
# vent canyon in campaign_ch2.gd). The same kind of scan data as the drill
# site: a cut block of points in kilometres, fine lines, and the chapter's
# emblem as a hologram on a projector. A scene says where its band of depth
# is (the build and the sweep run down it), where the camera looks, where
# its stations sit (its own path: past chapter 2 there is no drill shaft),
# and what its labels say. Its points bake on a worker the first time the
# chapter is needed.

const HALF := Vector2(4.0, 2.6) # the block (the model's)
const INK := Color(0.07, 0.2, 0.32)
const LINE := Color(0.05, 0.55, 0.66, 0.75)
const PREDATOR := Color(0.78, 0.3, 0.52)

var m: Control # the model
var root: Node3D
var chapter := 3
var points: MeshInstance3D
var point_mat: ShaderMaterial
var holo: Node3D # turns
var holo_pts: MeshInstance3D
var holo_mat: ShaderMaterial
var holo_lines: ImmediateMesh # animated lines riding the hologram
var cage: Node3D
var anim: ImmediateMesh # animated lines in the scene (waves, beams...)
var baked := false
var task := -1
var pc # the clouds while baking (the model's Cloud)
var hc

# Set by each scene.
var top := -0.5 # the band's top (world y): the build and the sweep start here
var bottom := -6.6
var focus := -3.6 # where the camera looks (y)
var dist := 25.5 # (as far as the drill site's: the 8 km block must fit the frame)
var tgt_x := -0.2
var motes := Vector2(-0.6, 5.8) # the motes' water: top, height
var rise := 2.5
var hot := Color(0.0, 0.62, 0.74)
var holo_c := Vector3(-2.2, -2.0, -0.6)
var holo_r := 1.0 # the cage's size
var holo_scale := 1.35 # the emblem a little larger than life on the projector
var place := "" # the map's name (Chinese), its English line
var place_en := ""
var emblem := "" # the hologram's label
var emblem_en := ""
var emblem_col := Color(0.07, 0.65, 0.73)
var _rng := RandomNumberGenerator.new()


func _init(model: Control, parent: Node3D, ch: int) -> void:
	m = model
	root = parent
	chapter = ch
	_rng.seed = 40 + ch
	configure()


# --- for each scene to fill in ----------------------------------------------------

func configure() -> void:
	pass


# The points: `c` the scene, `h` the hologram (centred on the origin).
func bake(_c, _h) -> void:
	pass


# Lines that do not move (the box is drawn by setup()).
func lines() -> void:
	pass


func animate(_time: float, _delta: float) -> void:
	pass


# Labels beyond the place's name and the emblem's.
func more_labels(_a: float) -> void:
	pass


# Where n stations sit: by default a probe line down the block.
func spots(n: int) -> Array:
	var out := []
	for k in n:
		var t := (k + 0.5) / maxf(1.0, n)
		out.append(Vector3(0.55, lerpf(top - 0.5, bottom + 0.6, t), 0.35))
	return out


# --- the frame ----------------------------------------------------------------

func setup() -> void:
	point_mat = m._mat(preload("res://shaders/europa_points.gdshader"))
	point_mat.set_shader_parameter("motes", motes)
	point_mat.set_shader_parameter("rise", rise)
	point_mat.set_shader_parameter("hot", hot)
	points = m._add(null, point_mat, Vector3.ZERO)
	points.custom_aabb = AABB(Vector3(-7, bottom - 2.0, -6), Vector3(14, top - bottom + 6.0, 12))
	_box()
	anim = ImmediateMesh.new()
	m._add(anim, m._glow(Color(0.1, 0.7, 0.8, 0.8), 1.2), Vector3.ZERO)
	holo = Node3D.new()
	holo.position = holo_c
	holo.scale = Vector3.ONE * holo_scale
	root.add_child(holo)
	holo_mat = m._mat(preload("res://shaders/europa_points.gdshader"))
	holo_mat.set_shader_parameter("hot", Color(0.35, 0.9, 1.0))
	holo_pts = m._add(null, holo_mat, Vector3.ZERO, holo)
	holo_pts.custom_aabb = AABB(Vector3(-2, -2, -2), Vector3(4, 4, 4))
	holo_lines = ImmediateMesh.new()
	m._add(holo_lines, m._glow(emblem_col, 1.3), Vector3.ZERO, holo)
	cage = Node3D.new()
	cage.position = holo_c
	cage.scale = Vector3.ONE * holo_scale
	root.add_child(cage)
	var cg := ImmediateMesh.new()
	cg.surface_begin(Mesh.PRIMITIVE_LINES)
	var r := holo_r
	m._circle(cg, Vector3(0, -r * 0.98, 0), r * 1.25, 72, true)
	m._circle(cg, Vector3(0, r * 0.95, 0), r * 1.15, 72, true)
	m._circle(cg, Vector3(0, -r * 1.2, 0), r * 0.42, 40)
	m._circle(cg, Vector3(0, -r * 1.2, 0), r * 0.3, 40)
	for j in 6:
		var a := TAU * j / 6.0
		cg.surface_add_vertex(Vector3(cos(a) * r * 0.42, -r * 1.2, sin(a) * r * 0.42))
		cg.surface_add_vertex(Vector3(cos(a) * r * 1.02, 0.0, sin(a) * r * 0.86))
	cg.surface_end()
	m._add(cg, m._glow(Color(0.05, 0.6, 0.72, 0.5), 1.0), Vector3.ZERO, cage)
	lines()


func _box() -> void:
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var seg := func(a: Vector3, b: Vector3) -> void:
		im.surface_add_vertex(a)
		im.surface_add_vertex(b)
	for cz: Vector2 in [Vector2(-HALF.x, -HALF.y), Vector2(HALF.x, -HALF.y), Vector2(-HALF.x, HALF.y), Vector2(HALF.x, HALF.y)]:
		seg.call(Vector3(cz.x, top, cz.y), Vector3(cz.x, bottom, cz.y))
	for y: float in [top, bottom]:
		var r: Array[Vector3] = [Vector3(-HALF.x, y, -HALF.y), Vector3(HALF.x, y, -HALF.y), Vector3(HALF.x, y, HALF.y), Vector3(-HALF.x, y, HALF.y)]
		for k in 4:
			seg.call(r[k], r[(k + 1) % 4])
	var y := ceilf(top * 2.0) / 2.0
	while y > bottom:
		var long := is_equal_approx(fposmod(y, 1.0), 0.0)
		seg.call(Vector3(-HALF.x, y, HALF.y), Vector3(-HALF.x - (0.22 if long else 0.11), y, HALF.y))
		y -= 0.5
	im.surface_end()
	m._add(im, m._glow(LINE, 1.0), Vector3.ZERO)


func finish() -> void:
	points.mesh = pc.mesh()
	holo_pts.mesh = hc.mesh()
	pc = null
	hc = null
	baked = true


func tick(time: float, delta: float) -> void:
	if not baked:
		return
	holo.rotation.y = time * 0.22
	holo.position.y = holo_c.y + sin(time * 0.6) * 0.05
	cage.rotation.y = -time * 0.1
	holo_mat.set_shader_parameter("slice_y", holo_c.y + sin(time * 0.7) * holo_r * 0.75)
	holo_mat.set_shader_parameter("slice_a", 0.85)
	animate(time, delta)


# The depth ticks down the front edge, the place, the emblem.
func draw_labels(a: float) -> void:
	if a <= 0.01 or not baked:
		return
	var mono: Font = Ui.mono("Medium")
	var sans6: Font = Ui.sans(600)
	var y := ceilf(top)
	while y > bottom:
		var q: Vector2 = m._sp(Vector3(-HALF.x - 0.22, y, HALF.y))
		m._text(Ui.mono(), q + Vector2(-34, 4), "%d km" % int(-y) if y < 0.0 else "0", 10, Color(Ui.INK_FAINT, a), 0.8)
		y -= 1.0
	var lc: Vector2 = m._sp(Vector3(-HALF.x, top - 0.3, HALF.y))
	m._text(sans6, lc + Vector2(10, 0), place, 14, Color(Ui.INK, a), 0.7)
	m._text(mono, lc + Vector2(10, 15), place_en, 10, Color(Ui.INK_SOFT, a), 0.7)
	var hp: Vector2 = m._sp(holo_c + Vector3(0, holo_r * holo_scale, 0))
	var ht := hp + Vector2(-190, -46)
	m.overlay.draw_line(hp, ht + Vector2(170, 8), Color(emblem_col, 0.7 * a), 1.0, true)
	m.overlay.draw_circle(hp, 2.5, Color(emblem_col, a))
	m._text(sans6, ht, emblem, 13, Color(Ui.INK, a), 0.8)
	m._text(mono, ht + Vector2(0, 14), emblem_en, 10, Color(emblem_col, a), 0.8)
	more_labels(a)


# A label with a leader to a point in the scene.
func tag(at: Vector3, off: Vector2, zh: String, en: String, col: Color, a: float) -> void:
	var p: Vector2 = m._sp(at)
	var t := p + off
	m.overlay.draw_line(p, t + Vector2(maxf(0.0, -off.x) * 0.0 + 4.0, 8), Color(col, 0.7 * a), 1.0, true)
	m.overlay.draw_circle(p, 2.5, Color(col, a))
	m._text(Ui.sans(600), t, zh, 13, Color(Ui.INK, a), 0.8)
	m._text(Ui.mono("Medium"), t + Vector2(0, 14), en, 10, Color(col, a), 0.8)


# --- helpers for the bake ----------------------------------------------------------

func _n(x: float, y: float, z := 0.0) -> float:
	return m._n(x, y, z)


static func dir3(rng: RandomNumberGenerator) -> Vector3:
	return Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized()


# A hologram's skin: latitude rings and meridians dotted densely, a faint
# fill between. `bump` roughens it.
func lattice(c, at: Vector3, radii: Vector3, col: Color, lat := 14, lon := 12, fill := 2400, bump := 0.06) -> void:
	var rng: RandomNumberGenerator = c.rng
	var shape := func(d: Vector3) -> Vector3:
		return at + d * radii * (1.0 + bump * _n(d.x * 2.0 + at.x, d.y * 2.0, d.z * 2.0 + 90.0))
	for i in range(1, lat):
		var th := PI * i / lat
		var cnt := int(200 * sin(th) * (radii.x + radii.z) * 0.5) + 8
		for k in cnt:
			var ph := TAU * k / cnt
			c.add(shape.call(Vector3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph))), col, 1.5)
	for j in lon:
		var ph := TAU * j / lon
		for k in 110:
			var th := PI * (k + 0.5) / 110.0
			c.add(shape.call(Vector3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph))), Color(col, col.a * 0.6), 1.3)
	for k in fill:
		c.add(shape.call(dir3(rng)), Color(col, col.a * 0.32), 1.3)


# A ball of points (solid, or a shell when `shell`).
func ball(c, at: Vector3, r: float, n: int, col: Color, size := 1.5, shell := false, motion := 0.0, grp := 0.0) -> void:
	var rng: RandomNumberGenerator = c.rng
	for k in n:
		var d := dir3(rng) * (1.0 if shell else pow(rng.randf(), 0.33))
		c.add(at + d * r, col, size, motion, grp)


# Motes drifting down the scene's water (motion 1).
func drift(c, n: int, col_top: Color, col_bottom: Color) -> void:
	var rng: RandomNumberGenerator = c.rng
	for k in n:
		var y := rng.randf_range(motes.x - motes.y, motes.x)
		var col := col_top.lerp(col_bottom, (motes.x - y) / motes.y)
		var bright := rng.randf() < 0.28
		col.a = rng.randf_range(0.35, 0.6) if bright else rng.randf_range(0.1, 0.2)
		c.add(Vector3(rng.randf_range(-HALF.x, HALF.x) * 0.97, y, rng.randf_range(-HALF.y, HALF.y) * 0.97), col, rng.randf_range(1.4, 2.0) if bright else 1.3, 1.0)


# A plume rising off a mouth (motion 2).
func plume(c, at: Vector3, n: int, col: Color, spread := 0.05) -> void:
	var rng: RandomNumberGenerator = c.rng
	for k in n:
		var r := Vector2.from_angle(rng.randf() * TAU) * rng.randf() * spread
		c.add(Vector3(at.x + r.x, at.y, at.z + r.y), col, 1.7, 2.0)


# A surface y = f(x, z) over the block as contours every `every` km, grain
# between; `col` by height.
func ground(c, f: Callable, every: float, col_of: Callable, step := 0.036, keep := 0.25) -> void:
	var rng: RandomNumberGenerator = c.rng
	var x := -HALF.x
	while x < HALF.x:
		var z := -HALF.y
		while z < HALF.y:
			var px := x + rng.randf_range(-0.4, 0.4) * step
			var pz := z + rng.randf_range(-0.4, 0.4) * step
			var y: float = f.call(px, pz)
			var cl := absf(fposmod(y / every, 1.0) - 0.5)
			var line := smoothstep(0.42, 0.485, cl)
			if line > 0.2 or rng.randf() < keep:
				var col: Color = col_of.call(y)
				col.a = col.a * (0.55 + line * 0.9)
				c.add(Vector3(px, y, pz), col, 1.5 + line * 0.5)
			z += step
		x += step


# A cut face (z = zf) from y0 up to f(x), banded.
func section(c, f: Callable, zf: float, y0: float, col: Color, front := true) -> void:
	var rng: RandomNumberGenerator = c.rng
	var x := -HALF.x
	while x < HALF.x:
		var t: float = f.call(x, zf)
		var y := y0
		while y < t:
			var band := absf(fposmod(y * 7.0 + _n(x * 0.8, y, 80.0 + chapter) * 0.7, 1.0) - 0.5)
			if band > 0.38 or rng.randf() < 0.3:
				c.add(Vector3(x, y, zf), Color(col, (0.16 + (0.24 if band > 0.38 else 0.0)) * (1.0 if front else 0.45)), 1.4)
			y += 0.05
		if front:
			c.add(Vector3(x, t, zf), Color(INK, 0.7), 1.9)
		x += 0.03 if front else 0.05
