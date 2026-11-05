extends Node2D
# Giant viruses as a player sees them (level 19). In the water they need no
# zoom: big glass capsids in a coat of fibres (shaders/giant.gdshader; the
# kernel fills the buffer). Inside a cell, on the kernel's own clock (seconds
# since it was swallowed):
#   0 – 1.2  it goes down in a vacuole, taken for food
#   1.2 – 2.2  the stargate on its corner opens and the core spills out
#   2.2 – burst  a factory grows in the cytoplasm: new capsids bud on its rim
#     and fill, then drift out until the cell is packed
# A virophage reaching the factory goes in from the edge and multiplies; the
# factory turns over to it from then on, and the capsids still budding come
# out misshapen. Sizes are in world units unless the name says px.

const CELL := 12 # floats per cell in SimCore.get_infected
const ATTACH := 1.2
const INJECT := 2.2
const SIDE := 26.0 # a giant's quad side, µm
const CAP_FREE := 800
const CAP_INNER := 512
const SCENE_CAP := 60 # factories drawn per frame (see phage_layer.gd)
const TOTAL := 14 # new capsids drawn in a factory
const NEW_SIDE := 5.2
const VIRO := 22 # virophages drawn in a stolen factory
const SCENE_ZOOM := 1.8
const FINE_ZOOM := 7.0
const FACTORY := Color(0.5, 0.3, 0.8)
const STOLEN := Color(0.08, 0.66, 0.62)
const DNA := Color(0.84, 0.17, 0.34)
const INK := Color(0.3, 0.2, 0.5)

var host: Node2D
var zoom := 1.0
var t := 0.0
var takeover := 15.0 # the virophage's seconds to take a factory (its 复制速度)
var cells := PackedFloat32Array()
var mat: ShaderMaterial
var free_mm: MultiMeshInstance2D
var inner_mm: MultiMeshInstance2D
var _soft: GradientTexture2D


func _init() -> void:
	mat = ShaderMaterial.new()
	mat.shader = preload("res://shaders/giant.gdshader")
	free_mm = _sprites(CAP_FREE) # (added under the cells by showcase.gd)
	inner_mm = _sprites(CAP_INNER)
	inner_mm.z_index = 1
	add_child(inner_mm)
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


func _sprites(capacity: int) -> MultiMeshInstance2D:
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = capacity
	mm.visible_instance_count = 0
	mm.custom_aabb = AABB(Vector3(-200.0, -200.0, -1.0), Vector3(2600.0, 2600.0, 2.0))
	var node := MultiMeshInstance2D.new()
	node.multimesh = mm
	node.material = mat
	return node


func tick(dt: float, a: float, view: Rect2) -> void:
	var sim: SimCore = host.sim
	var on: bool = host.level_runner != null and host.level_runner.level.has("giant")
	visible = on
	free_mm.visible = on
	if not on:
		return
	zoom = host.cam.zoom.x
	t += dt
	mat.set_shader_parameter("px", 1.0 / zoom)
	var near := view.grow(SIDE)
	# (Drawn larger than life from afar: the whole dish has to see them.)
	free_mm.multimesh.buffer = sim.build_giant_buffer(near, a, maxf(SIDE, 38.0 / zoom), CAP_FREE)
	free_mm.multimesh.visible_instance_count = sim.get_giant_drawn()
	cells = PackedFloat32Array()
	if zoom >= SCENE_ZOOM:
		var all: PackedFloat32Array = sim.get_infected(near, a)
		var left := SCENE_CAP
		for k in range(0, all.size(), CELL):
			if all[k + 10] > 3.5 and left > 0:
				left -= 1
				cells.append_array(all.slice(k, k + CELL))
	_build_inner()
	queue_redraw()


func _stolen(k: int, s: float) -> float:
	var at := cells[k + 11]
	return 0.0 if at < 0.0 else smoothstep(at, at + takeover, s)


func _core(a: float, _b: float) -> Vector2:
	return Vector2(0.14 * a, 0.0)


func _core_r(a: float, b: float, rep: float) -> float:
	return minf(a, b) * lerpf(0.14, 0.7, pow(rep, 0.7))


# The swallowed capsid and the new ones, as sprites in world space.
func _build_inner() -> void:
	var buf := PackedFloat32Array()
	buf.resize(CAP_INNER * 12)
	buf.fill(0.0)
	var n := 0
	for k in range(0, cells.size(), CELL):
		var c := Vector2(cells[k], cells[k + 1])
		var h := cells[k + 2]
		var sw := cells[k + 9]
		var a := cells[k + 3] * sw
		var b := cells[k + 4] * sw
		var s := cells[k + 5]
		var burst := cells[k + 7]
		var rep := clampf((s - INJECT) / (burst - INJECT), 0.0, 1.0)
		var seed := fposmod(cells[k + 6], TAU) * 13.0
		var fc := _core(a, b)
		# Going down: from the membrane to the middle, in its vacuole.
		var gone := smoothstep(INJECT, INJECT + 1.2, s)
		if gone < 1.0 and n < CAP_INNER:
			var d := Vector2.from_angle(cells[k + 6])
			var from := d * 0.93 / sqrt(d.x * d.x / (a * a) + d.y * d.y / (b * b))
			var at := from.lerp(fc, smoothstep(0.0, ATTACH, s))
			_put(buf, n, c + at.rotated(h), minf(a, b) * 2.2, 1.0, 1.0, seed * 0.03, smoothstep(ATTACH, INJECT, s), false, 0.99 * (1.0 - gone))
			n += 1
		if zoom < FINE_ZOOM:
			continue
		var at_h := cells[k + 11]
		for j in TOTAL:
			if n >= CAP_INNER:
				break
			var st := _new_capsid(a, b, fc, rep, seed, j)
			var scale: float = st[1]
			if scale <= 0.0:
				continue
			# Budding after the factory changed hands, it comes out wrong.
			var bad := at_h >= 0.0 and float(st[2]) * (burst - INJECT) + INJECT > at_h + takeover * 0.5
			var f := fposmod(seed + j * 0.37, 1.0)
			var pos: Vector2 = c + (st[0] as Vector2).rotated(h)
			var sx := 1.3 if bad else 1.0
			var sy := 0.68 if bad else 1.0
			_put(buf, n, pos, NEW_SIDE * (0.45 + 0.55 * scale), sx, sy, f, 0.0, false, 0.99 * scale * (0.72 if bad else 1.0))
			n += 1
	inner_mm.multimesh.buffer = buf
	inner_mm.multimesh.visible_instance_count = n


func _put(buf: PackedFloat32Array, n: int, at: Vector2, side: float, sx: float, sy: float, turn: float, gate: float, rode: bool, a: float) -> void:
	var i := n * 12
	var ang := turn * TAU
	var ux := Vector2.from_angle(ang) * side * sx
	var uy := Vector2.from_angle(ang + PI * 0.5) * side * sy
	buf[i] = ux.x
	buf[i + 1] = uy.x
	buf[i + 3] = at.x
	buf[i + 4] = ux.y
	buf[i + 5] = uy.y
	buf[i + 7] = at.y
	buf[i + 8] = 0.0
	buf[i + 9] = gate * 0.49 + (0.5 if rode else 0.0)
	buf[i + 10] = 1.0
	buf[i + 11] = 0.5 * a


# The j-th new capsid, in the cell's frame: [position, scale, when it budded
# (0..1 of the factory's run)]. It buds on the factory's rim and drifts out.
func _new_capsid(a: float, b: float, fc: Vector2, rep: float, seed: float, j: int) -> Array:
	var born := 0.16 + 0.68 * float(j) / TOTAL
	var scale := smoothstep(born, born + 0.06, rep)
	var fa := fposmod(seed + j * 2.399963, TAU)
	var dir := Vector2.from_angle(fa)
	var rim := fc + dir * _core_r(a, b, born)
	var home := Vector2(dir.x * a * 0.76, dir.y * b * 0.76)
	var at := rim.lerp(home, smoothstep(born + 0.05, born + 0.3, rep))
	at += Vector2(sin(t * 0.6 + j * 1.3), cos(t * 0.5 + j * 2.1)) * 0.16
	return [at, scale, born]


func _draw() -> void:
	for k in range(0, cells.size(), CELL):
		_scene(k)
	_landing()


# Where the next lot will drift in, for the ten seconds it is announced.
func _landing() -> void:
	var lr: Node = host.level_runner
	if lr == null or lr.eval == null:
		return # (still on the design page)
	for e: Dictionary in lr.level.get("events", []):
		var left: float = float(e.at) - lr.eval.t
		if left <= 0.0 or left > 10.0:
			continue
		var at: Vector2 = LevelEval.wave_pos(e)
		var beat := 0.5 + 0.5 * sin(t * 3.0)
		_soft_spot(at, 130.0, Color(FACTORY, 0.16 + 0.12 * beat))
		draw_set_transform(at, 0.0, Vector2.ONE / zoom)
		var txt := "%d 颗巨毒囊　%d 秒后" % [int(e.n), ceili(left)]
		var f: Font = Ui.sans(600)
		var w := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		draw_string(f, Vector2(-w * 0.5, 5.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, FACTORY.darkened(0.2))
		draw_set_transform(Vector2.ZERO)


func _soft_spot(at: Vector2, r: float, col: Color) -> void:
	draw_texture_rect(_soft, Rect2(at - Vector2.ONE * r, Vector2.ONE * r * 2.0), false, col)


func _scene(k: int) -> void:
	var c := Vector2(cells[k], cells[k + 1])
	var h := cells[k + 2]
	var sw := cells[k + 9]
	var a := cells[k + 3] * sw
	var b := cells[k + 4] * sw
	var s := cells[k + 5]
	var burst := cells[k + 7]
	var rep := clampf((s - INJECT) / (burst - INJECT), 0.0, 1.0)
	var seed := fposmod(cells[k + 6], TAU) * 13.0
	var stolen := _stolen(k, s)
	var col := FACTORY.lerp(STOLEN, stolen)
	var fc := _core(a, b)
	var fine := zoom >= FINE_ZOOM
	draw_set_transform(c, h)
	# The vacuole it came down in, thinning away as the core gets out.
	var vac := 1.0 - smoothstep(INJECT, INJECT + 1.0, s)
	if vac > 0.0:
		var d := Vector2.from_angle(cells[k + 6])
		var from := d * 0.93 / sqrt(d.x * d.x / (a * a) + d.y * d.y / (b * b))
		var at := from.lerp(fc, smoothstep(0.0, ATTACH, s))
		draw_arc(at, minf(a, b) * 0.86, 0.0, TAU, 40, Color(INK, 0.34 * vac), maxf(0.06, 0.8 / zoom), true)
	if rep > 0.0:
		var r := _core_r(a, b, rep)
		_soft_spot(fc, r * 2.0, Color(col, 0.38))
		if not fine:
			_soft_spot(fc, r * 1.3, Color(col.lightened(0.3), 0.6))
		else:
			var pts := _blob(fc, r, seed)
			draw_colored_polygon(pts, Color(col.lightened(0.42), 0.5))
			_genome(fc, r, rep, seed, stolen)
			pts.append(pts[0])
			draw_polyline(pts, Color(col.darkened(0.2), 0.6), maxf(0.05, 0.9 / zoom), true)
			if cells[k + 11] >= 0.0:
				_virophages(k, a, b, fc, r, s, stolen, seed)
	draw_set_transform(Vector2.ZERO)


# The factory's soft outline, breathing.
func _blob(fc: Vector2, r: float, seed: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for j in 44:
		var f := j / 44.0 * TAU
		var rr := r * (1.0 + 0.1 * sin(f * 3.0 + seed + t * 0.4) + 0.06 * sin(f * 7.0 - seed * 2.0 - t * 0.3))
		pts.append(fc + Vector2.from_angle(f) * rr)
	return pts


# The giant's DNA, copied in the factory's heart. Stolen, it thins away.
func _genome(fc: Vector2, r: float, rep: float, seed: float, stolen: float) -> void:
	var n := 90 + int(260.0 * smoothstep(0.0, 0.6, rep))
	var pts := PackedVector2Array()
	pts.resize(n)
	for j in n:
		var u := float(j) / (n - 1)
		var f := u * TAU * 13.0 + seed
		var rr := r * 0.62 * (0.3 + 0.7 * (0.5 + 0.5 * sin(f * 0.37 + seed + t * 0.13)))
		pts[j] = fc + Vector2(cos(f + 0.4 * sin(f * 0.61 + t * 0.09)), sin(f * 0.97)) * rr
	var w := maxf(0.05, 0.8 / zoom)
	draw_polyline(pts, Color(DNA.lightened(0.2), 0.3 * (1.0 - 0.75 * stolen)), w * 3.0, true)
	draw_polyline(pts, Color(DNA.darkened(0.1), 0.7 * (1.0 - 0.75 * stolen)), w, true)


# The virophages in the factory: they arrive at the edge and multiply.
func _virophages(k: int, a: float, b: float, fc: Vector2, r: float, s: float, stolen: float, seed: float) -> void:
	var at_h := cells[k + 11]
	var d := Vector2.from_angle(fposmod(seed * 3.1, TAU))
	var from := Vector2(d.x * a * 0.96, d.y * b * 0.96)
	var come := smoothstep(at_h, at_h + 1.0, s)
	var n := 1 + int((VIRO - 1) * stolen)
	for j in n:
		var f := seed + j * 2.399963
		var rim := fc + Vector2.from_angle(f + t * 0.1) * r * (0.4 + 0.55 * sqrt((j + 0.5) / VIRO))
		var at := from.lerp(rim, come if j == 0 else 1.0)
		_hex(at, 0.36, STOLEN)


func _hex(at: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for j in 6:
		pts.append(at + Vector2.from_angle(j * TAU / 6.0 + 0.52) * r)
	draw_colored_polygon(pts, Color(col.lightened(0.3), 0.8))
	pts.append(pts[0])
	draw_polyline(pts, col.darkened(0.25), maxf(0.03, 0.6 / zoom), true)
