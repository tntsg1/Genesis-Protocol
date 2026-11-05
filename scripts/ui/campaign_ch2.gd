extends RefCounted
# The campaign page's second scene (2026-10-30: "一章一个背景…第二张换个更酷炫
# 更牛逼的"): chapter 2 is fought on the seafloor, so the model drops below
# the ocean to a hydrothermal canyon, as the same kind of scan data as the
# drill site (scripts/ui/campaign_model.gd). A canyon winds through the block
# with terraced walls and its contours; black smokers stand on its floor and
# ledges, plumes of motes climbing off them, chemosynthetic mats round their
# feet; the front face is cut open to its strata. Over the canyon hangs the
# chapter's emblem: a predator cell as a hologram on a projector - lattice
# membrane, nucleus, a swallowed prey in a food vacuole, a ring of
# cnidocysts that fire their threads now and then, a scan band riding it.
# The drill shaft and the stations are the model's own and stay; this adds
# the points (baked on the model's worker), the lines and the animation.
# World units are kilometres, as in the model.

const RIM := -6.1 # the canyon's rim (the plateau)
const CFLOOR := -9.7 # its floor
const SLAB := -10.4 # the bottom of the cut block
const TOP := -5.9 # the water's top in this scene
const HALF := Vector2(4.0, 2.6) # the block's half width / depth (the model's)
const HOLO_C := Vector3(-2.15, -6.55, -0.55) # the hologram's centre
const PREDATOR := Color(0.78, 0.3, 0.52)
const ROCK := Color(0.2, 0.28, 0.46)
const ROCK_INK := Color(0.08, 0.12, 0.3)
const INK := Color(0.07, 0.2, 0.32)

var m: Control # the model
var root: Node3D
var points: MeshInstance3D
var point_mat: ShaderMaterial
var holo: Node3D # turns
var holo_pts: MeshInstance3D
var holo_mat: ShaderMaterial
var threads: ImmediateMesh
var cage: Node3D # the projector's rings (do not turn with it)
var chimneys: Array = [] # [x, z, height, base y]
var tips := PackedVector3Array()
var cnido: Array = [] # [position, outward normal] on the membrane (local)
var fire_k := -1 # the cnidocyst firing now
var fire_t := 0.0
var baked := false # the points are in (the bake's arrays are the worker's till then)
var _rng := RandomNumberGenerator.new()


func _init(model: Control, parent: Node3D) -> void:
	m = model
	root = parent
	_rng.seed = 21
	chimneys = []
	for c: Array in [[-1.75, 0.18, 1.55], [-0.85, -0.22, 1.05], [1.55, 0.2, 1.75], [2.15, -0.25, 0.95], [-1.25, 1.35, 0.8]]:
		var z: float = c[0]
		var x := axis_x(z) + float(c[1])
		chimneys.append([x, z, c[2], height(x, z)])


func _n(x: float, y: float, z := 0.0) -> float:
	return m._n(x, y, z)


# The canyon winds a little; the shaft goes down its middle.
static func axis_x(z: float) -> float:
	return 0.55 + 0.32 * (sin(z * 0.8 + 0.6) - sin(0.35 * 0.8 + 0.6))


# The ground's height at (x, z): floor, terraced walls, the rim's plateau.
func height(x: float, z: float) -> float:
	var dx := absf(x - axis_x(z))
	var w0 := 0.55
	var w1 := 2.55
	if dx <= w0:
		return CFLOOR + _n(x * 1.3, z * 1.3, 70.0) * 0.06
	if dx >= w1:
		return RIM + _n(x * 0.5, z * 0.5, 71.0) * 0.14
	var t := (dx - w0) / (w1 - w0)
	var q := t * 4.0
	var steps := (floorf(q) + smoothstep(0.3, 0.7, fposmod(q, 1.0))) / 4.0
	var ty := lerpf(t, steps, 0.7)
	return lerpf(CFLOOR, RIM, ty) + _n(x * 0.9, z * 0.9, 72.0) * 0.1


static func _ramp(y: float) -> Color:
	return ROCK.lerp(ROCK_INK, smoothstep(RIM, CFLOOR, y) * 0.5)


# --- the points (on the model's worker) ------------------------------------------

func bake(c, hc) -> void:
	_ground(c)
	_section(c)
	_smokers(c)
	_water(c)
	_hologram(hc)


func _ground(c) -> void:
	var rng: RandomNumberGenerator = c.rng
	var hx := HALF.x
	var hz := HALF.y
	# Across the canyon, side by side: walked by arc length so the steep
	# walls get as many points as the flats; contours every 150 m.
	var z := -hz + 0.02
	while z < hz:
		for side: float in [-1.0, 1.0]:
			var ax := axis_x(z)
			var dx := 0.0
			var prev := Vector2(ax, height(ax, z))
			var run := 0.0
			while true:
				dx += 0.006
				var x := ax + side * dx
				if x < -hx or x > hx:
					break
				var p := Vector2(x, height(x, z))
				run += p.distance_to(prev)
				prev = p
				if run < 0.034:
					continue
				run = 0.0
				var y := p.y
				var cl := absf(fposmod(y / 0.15, 1.0) - 0.5)
				var line := smoothstep(0.42, 0.485, cl)
				if line < 0.2 and rng.randf() < 0.6:
					continue
				var col := _ramp(y).lerp(ROCK_INK, line * 0.6)
				col.a = 0.26 + line * 0.46
				c.add(Vector3(x + rng.randf_range(-0.01, 0.01), y, z + rng.randf_range(-0.012, 0.012)), col, 1.5 + line * 0.5)
		z += 0.034


# The cut faces: front and back, strata down to the slab; the front's top
# edge traced bright so the canyon's profile reads.
func _section(c) -> void:
	var rng: RandomNumberGenerator = c.rng
	var hx := HALF.x
	var hz := HALF.y
	for zf: float in [hz, -hz]:
		var front := zf > 0.0
		var x := -hx
		while x < hx:
			var top := height(x, zf)
			var y := SLAB
			while y < top:
				var band := absf(fposmod(y * 7.0 + _n(x * 0.8, y, 80.0) * 0.7, 1.0) - 0.5)
				var keep := band > 0.38 or rng.randf() < 0.3
				if keep:
					var col := _ramp(y).lerp(ROCK_INK, 0.45 if band > 0.38 else 0.0)
					col.a = (0.16 + (0.24 if band > 0.38 else 0.0)) * (1.0 if front else 0.45)
					c.add(Vector3(x, y, zf), col, 1.4)
				y += 0.05
			if front:
				var col := INK
				col.a = 0.75
				c.add(Vector3(x, top, zf), col, 1.9)
			x += 0.03 if front else 0.05


func _smokers(c) -> void:
	var rng: RandomNumberGenerator = c.rng
	for ch: Array in chimneys:
		var x: float = ch[0]
		var z: float = ch[1]
		var h: float = ch[2]
		var base: float = ch[3] - 0.04
		var n := int(h / 0.026)
		var flanges := [rng.randf_range(0.3, 0.45), rng.randf_range(0.6, 0.75)]
		for j in n:
			var t := float(j) / n
			var r := lerpf(0.17, 0.045, pow(t, 0.8)) * (1.0 + 0.32 * _n(x * 3.0, t * 6.0, z * 3.0))
			for fl: float in flanges:
				r *= 1.0 + 1.3 * exp(-pow((t - fl) / 0.025, 2.0))
			var lean := Vector2(sin(t * 2.2 + x) * 0.06, cos(t * 1.7 + z) * 0.05) * t
			var cnt := maxi(8, int(TAU * r / 0.012))
			for k in cnt:
				var a := TAU * k / cnt + j * 0.37
				if rng.randf() < 0.45:
					continue
				var col := INK.lerp(Color(0.1, 0.4, 0.55), 0.35 * t)
				col.a = 0.24 + 0.16 * rng.randf()
				c.add(Vector3(x + lean.x + cos(a) * r, base + t * h, z + lean.y + sin(a) * r), col, 1.3)
		var tip := Vector3(x + sin(2.2 + x) * 0.06, base + h + 0.02, z + cos(1.7 + z) * 0.05)
		tips.append(tip)
		# Heat at the mouth: a bright shimmer of still points.
		for k in 260:
			var o := Vector3(rng.randfn(), rng.randfn() * 0.6, rng.randfn()) * 0.07
			c.add(tip + o, Color(0.55, 0.95, 1.0, 0.55), 2.2)
		# The plume: particles rising off the mouth (motion 2).
		for k in 1700:
			var r := Vector2.from_angle(rng.randf() * TAU) * rng.randf() * 0.05
			c.add(Vector3(tip.x + r.x, tip.y, tip.z + r.y), Color(0.3, 0.85, 0.95, 0.34), 1.7, 2.0)
		# Mats of chemosynthetic life round the foot.
		for k in 900:
			var o := Vector2(rng.randfn(), rng.randfn()) * 0.32
			var gx := x + o.x
			var gz := z + o.y
			c.add(Vector3(gx, height(gx, gz) + 0.015, gz), Color(0.12, 0.62, 0.55, rng.randf_range(0.25, 0.55)), rng.randf_range(1.3, 2.0))


func _water(c) -> void:
	var rng: RandomNumberGenerator = c.rng
	var hx := HALF.x
	var hz := HALF.y
	for k in 7500:
		var x := rng.randf_range(-hx, hx) * 0.97
		var z := rng.randf_range(-hz, hz) * 0.97
		var y := rng.randf_range(height(x, z) + 0.05, TOP)
		var bright := rng.randf() < 0.28
		var col := Color(0.0, 0.62, 0.8).lerp(Color(0.1, 0.32, 0.62), smoothstep(TOP, CFLOOR, y))
		col.a = rng.randf_range(0.35, 0.6) if bright else rng.randf_range(0.1, 0.2)
		c.add(Vector3(x, y, z), col, rng.randf_range(1.4, 2.0) if bright else 1.3, 1.0)


# The predator, centred on the origin (its node sits at HOLO_C and turns).
func _hologram(c) -> void:
	var rng: RandomNumberGenerator = c.rng
	var ax := Vector3(1.0, 0.72, 0.86)
	var shape := func(d: Vector3) -> Vector3:
		return d * ax * (1.0 + 0.07 * _n(d.x * 2.0, d.y * 2.0, d.z * 2.0 + 90.0))
	# The membrane as a lattice: latitude rings and meridians, densely
	# dotted, a faint fill between.
	var lat := Color(0.05, 0.62, 0.76, 0.5)
	for i in range(1, 16):
		var th := PI * i / 16.0
		var cnt := int(260 * sin(th)) + 8
		for k in cnt:
			var ph := TAU * k / cnt
			c.add(shape.call(Vector3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph))), lat, 1.5)
	for j in 14:
		var ph := TAU * j / 14.0
		for k in 150:
			var th := PI * (k + 0.5) / 150.0
			c.add(shape.call(Vector3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph))), Color(lat, 0.32), 1.3)
	for k in 3800:
		var d := Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized()
		c.add(shape.call(d), Color(0.1, 0.55, 0.7, 0.16), 1.3)
	# Nucleus (the predator's own colour) and its nucleolus.
	var nc := Vector3(0.24, 0.06, 0.05)
	for k in 1700:
		var d := Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized()
		c.add(nc + d * 0.3 * (1.0 + 0.05 * rng.randfn()), Color(PREDATOR, 0.5), 1.5)
	for k in 260:
		var d := Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized() * rng.randf() * 0.1
		c.add(nc + Vector3(0.06, 0.04, 0.0) + d, Color(PREDATOR.lerp(Color.WHITE, 0.2), 0.8), 1.9)
	# Vacuoles; one with a swallowed prey cell in it.
	for v: Array in [[Vector3(-0.42, -0.18, 0.2), 0.16, true], [Vector3(-0.2, 0.3, -0.35), 0.09, false], [Vector3(0.1, -0.35, -0.3), 0.11, false]]:
		var at: Vector3 = v[0]
		var r: float = v[1]
		for k in 240:
			var d := Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized()
			c.add(at + d * r, Color(0.1, 0.6, 0.72, 0.42), 1.3)
		if v[2]:
			for k in 160:
				var d := Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized() * rng.randf() * r * 0.55
				c.add(at + d, Color(0.2, 0.62, 0.36, 0.7), 1.6)
	# Cnidocysts round the waist: elongated capsules along the normal.
	for k in 14:
		var ph := TAU * k / 14.0 + rng.randf_range(-0.12, 0.12)
		var th := PI * 0.5 + rng.randf_range(-0.55, 0.55)
		var dir := Vector3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph))
		var at: Vector3 = shape.call(dir) * 0.97
		var nrm := (dir / ax).normalized()
		cnido.append([at, nrm])
		var t1 := nrm.cross(Vector3.UP).normalized()
		var t2 := nrm.cross(t1)
		for q in 90:
			var u := rng.randf_range(-1.0, 1.0)
			var ring := Vector2.from_angle(rng.randf() * TAU) * sqrt(1.0 - u * u) * 0.035
			c.add(at - nrm * (0.06 + u * 0.08) + t1 * ring.x + t2 * ring.y, Color(PREDATOR, 0.75), 1.4)


# --- the lines -----------------------------------------------------------------

func build_lines() -> void:
	var hx := HALF.x
	var hz := HALF.y
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var seg := func(a: Vector3, b: Vector3) -> void:
		im.surface_add_vertex(a)
		im.surface_add_vertex(b)
	for cz: Vector2 in [Vector2(-hx, -hz), Vector2(hx, -hz), Vector2(-hx, hz), Vector2(hx, hz)]:
		seg.call(Vector3(cz.x, TOP, cz.y), Vector3(cz.x, SLAB, cz.y))
	for y: float in [TOP, SLAB]:
		var r: Array[Vector3] = [Vector3(-hx, y, -hz), Vector3(hx, y, -hz), Vector3(hx, y, hz), Vector3(-hx, y, hz)]
		for k in 4:
			seg.call(r[k], r[(k + 1) % 4])
	var k := 12
	while -k * 0.5 >= SLAB:
		var y := -k * 0.5
		seg.call(Vector3(-hx, y, hz), Vector3(-hx - (0.22 if k % 2 == 0 else 0.11), y, hz))
		k += 1
	im.surface_end()
	m._add(im, m._glow(Color(0.05, 0.55, 0.66, 0.75), 1.0), Vector3.ZERO)
	var ct := ImmediateMesh.new()
	ct.surface_begin(Mesh.PRIMITIVE_LINES)
	for y: float in [-7.0, -8.0, -9.0, -10.0]:
		var r: Array[Vector3] = [Vector3(-hx, y, -hz), Vector3(hx, y, -hz), Vector3(hx, y, hz), Vector3(-hx, y, hz)]
		for j in 4:
			ct.surface_add_vertex(r[j])
			ct.surface_add_vertex(r[(j + 1) % 4])
	ct.surface_end()
	m._add(ct, m._glow(Color(0.05, 0.55, 0.66, 0.26), 1.0), Vector3.ZERO)
	# The hologram: its turning body, the projector and its cage.
	holo = Node3D.new()
	holo.position = HOLO_C
	root.add_child(holo)
	holo_mat = m._mat(preload("res://shaders/europa_points.gdshader"))
	holo_mat.set_shader_parameter("hot", Color(0.35, 0.9, 1.0))
	m.builds.append(holo_mat)
	holo_pts = m._add(null, holo_mat, Vector3.ZERO, holo)
	holo_pts.custom_aabb = AABB(Vector3(-1.5, -1.5, -1.5), Vector3(3, 3, 3))
	threads = ImmediateMesh.new()
	m._add(threads, m._glow(Color(0.85, 0.32, 0.58), 1.3), Vector3.ZERO, holo)
	cage = Node3D.new()
	cage.position = HOLO_C
	root.add_child(cage)
	var cg := ImmediateMesh.new()
	cg.surface_begin(Mesh.PRIMITIVE_LINES)
	m._circle(cg, Vector3(0, -0.98, 0), 1.25, 72, true)
	m._circle(cg, Vector3(0, 0.95, 0), 1.15, 72, true)
	m._circle(cg, Vector3(0, -1.2, 0), 0.42, 40)
	m._circle(cg, Vector3(0, -1.2, 0), 0.3, 40)
	for j in 6:
		var a := TAU * j / 6.0
		cg.surface_add_vertex(Vector3(cos(a) * 0.42, -1.2, sin(a) * 0.42))
		cg.surface_add_vertex(Vector3(cos(a) * 1.02, 0.0, sin(a) * 0.86))
	cg.surface_end()
	m._add(cg, m._glow(Color(0.05, 0.6, 0.72, 0.5), 1.0), Vector3.ZERO, cage)


func finish(c, hc) -> void:
	points.mesh = c.mesh()
	holo_pts.mesh = hc.mesh()
	var tip := SphereMesh.new()
	tip.radius = 0.035
	tip.height = 0.07
	for at in tips:
		m._add(tip, m._glow(Color(0.4, 1.4, 1.6), 1.0), at)
	baked = true


# --- every frame ---------------------------------------------------------------

func tick(time: float, delta: float) -> void:
	if not baked:
		return
	holo.rotation.y = time * 0.22
	holo.position.y = HOLO_C.y + sin(time * 0.6) * 0.05
	cage.rotation.y = -time * 0.1
	holo_mat.set_shader_parameter("slice_y", HOLO_C.y + sin(time * 0.7) * 0.75)
	holo_mat.set_shader_parameter("slice_a", 0.85)
	# A cnidocyst fires every 1.4 s: the thread shoots out, hangs, reels in.
	fire_t += delta
	if fire_k < 0 or fire_t > 1.4:
		fire_k = _rng.randi() % cnido.size() if not cnido.is_empty() else -1
		fire_t = 0.0
	threads.clear_surfaces()
	if fire_k < 0:
		return
	threads.surface_begin(Mesh.PRIMITIVE_LINES)
	for k in cnido.size():
		var at: Vector3 = cnido[k][0]
		var nrm: Vector3 = cnido[k][1]
		var reach := 0.07
		if k == fire_k:
			var u := fire_t / 1.4
			reach = 0.07 + 1.1 * (1.0 - pow(1.0 - minf(u * 5.0, 1.0), 3.0)) * (1.0 - smoothstep(0.55, 1.0, u))
		var t1 := nrm.cross(Vector3.UP).normalized()
		var t2 := nrm.cross(t1)
		var n := 18 if k == fire_k else 3
		var prev := at
		for s in range(1, n + 1):
			var f := float(s) / n
			var wob := (t1 * sin(f * 14.0 + time * 9.0) + t2 * cos(f * 11.0)) * 0.02 * f
			var p := at + nrm * reach * f + wob
			threads.surface_add_vertex(prev)
			threads.surface_add_vertex(p)
			prev = p
		if k == fire_k and reach > 0.3:
			# The barb.
			for sgn: float in [-1.0, 1.0]:
				threads.surface_add_vertex(prev)
				threads.surface_add_vertex(prev - nrm * 0.07 + t1 * 0.04 * sgn)
	threads.surface_end()
