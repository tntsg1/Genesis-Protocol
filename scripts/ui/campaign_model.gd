extends Control
# The campaign page's model of the drill site, as scan data (tenth round:
# "太廉价了，像卡通" - the ninth round's solid block read as a toy): one
# cloud of ~110k soft points in a depth ramp - frost-silver ice with
# Europa's lineae across the top, strata banding the faces and the cutaway
# at the front corner where the shaft goes down, cracks rising inside, the
# ice's underside a cyan skin; the ocean a haze of sinking motes with
# convection loops and vent plumes; the seafloor a contour map. The base and
# derrick are fine wireframes, the stations rings round the shaft. The
# selected one lays a holographic slice through the block and lights every
# point at its depth; a laser loop sweeps down the block every nine seconds.
# A point-cloud Europa in the corner marks where on the moon the site is.
# Text is drawn in 2D over it (crisp, the interface's fonts), anchored to 3D
# points. The block assembles top-down behind the page's scan line, points
# gathering in at the front; 进入实验 drops a light down the shaft and the
# camera dives to the station. It sways on its own; drag to turn it.
# World units are kilometres (depth is true; the block is 8 x 5.2 wide).

var page: Control
var sel := 0
var hover := -1
var time := 0.0
var descent := -1.0 # 进入实验: seconds since the dive began
const DESCENT := 0.75

const HALF := Vector2(4.0, 2.6) # the block's half width (x) and depth (z)
const NOTCH := Vector2(0.55, 0.35) # the cutaway's inner corner (x, z)
const ICE := 3.0
const FLOOR := 6.2
const SHAFT := Vector2(0.55, 0.35)

var vp: SubViewport
var tex: TextureRect
var world: Node3D
var cam: Camera3D
var overlay: Control
var builds: Array[ShaderMaterial] = [] # everything that builds with the scan
var rings: Array[MeshInstance3D] = []
var ring_mats: Array[ShaderMaterial] = []
var slice_mat: ShaderMaterial
var slice: MeshInstance3D
var scan_mat: ShaderMaterial
var scan_plane: MeshInstance3D
var drop: MeshInstance3D
var point_mat: ShaderMaterial
var flow_mat: ShaderMaterial
var sel_ring: MeshInstance3D
var sel_mat: ShaderMaterial
var sweep_y := 1.0
var sweep_rings: Array[MeshInstance3D] = [] # round the ice (notched), round the ocean
var sweep_mat: ShaderMaterial
var globe_mat: ShaderMaterial
var points: MeshInstance3D
var noise: FastNoiseLite
var vent_tips := PackedVector3Array()
var _bake_task := -1
var _cloud: Cloud
var _gcloud: Cloud
var beacon_mat: ShaderMaterial
# The globe in the corner.
var gvp: SubViewport
var gtex: TextureRect
var gcam: Camera3D
var globe: MeshInstance3D
var site: Node3D

# Camera: orbit round `target`; the sway, the pointer's lean and the drag
# add to the rest angles; `intro` (1 -> 0) cranes it in as the block builds.
const YAW := 0.68
const PITCH := 0.36
const DIST := 26.5
var yaw_drag := 0.0
var pitch_drag := 0.0
var dragging := false
var drag_moved := 0.0
var lean := Vector2.ZERO
var focus_y := -3.6
var intro := 0.0
var slice_y := -3.1
var slice_a := 0.0
var build_y := -100.0
var lab := PackedVector2Array() # station labels, laid out so they never overlap
# One scene per chapter (2026-10-30): the drill site for chapter 1, the vent
# canyon (scripts/ui/campaign_ch2.gd) for chapter 2, each under its own node;
# form[c] is 1 in place .. 0 scattered, and a chapter change scatters the one
# and streams the other in. The shaft, the stations and the list are shared.
const Ch2 := preload("res://scripts/ui/campaign_ch2.gd")
const Chapters := preload("res://scripts/ui/campaign_chapters.gd")
const LAST := 10 # chapters with a map
var ch1: Node3D
var ch2: Node3D
var c2 # Ch2
var scenes := {} # chapter (3..10) -> its scene (scripts/ui/campaign_scene.gd)
var nodes := {} # chapter -> its node
var shaft_node: Node3D # the drill shaft: chapters 1 and 2 only ("chapter 0")
var _node_ch := {} # node -> chapter, for the materials built into it
var _into: Node3D # where _add puts things while a scene is built
var chapter := 1
var preview_ch := 0 # a chapter on show without levels yet (developer mode)
var form: Array[float] = [0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
var ch_mats := [[], [], [], [], [], [], [], [], [], [], []] # each scene's materials (they take its `form`)
var _spot := {} # level index -> its station (chapters past 2)
var point_mat2: ShaderMaterial
var _cloud2: Cloud
var _hcloud: Cloud
var _scale := 1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = false
	vp = SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.use_hdr_2d = true
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(vp)
	tex = TextureRect.new()
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_SCALE
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tex.texture = vp.get_texture()
	# The transparent render comes out premultiplied (the cloud's points
	# blend into a clear buffer); drawn straight they'd darken twice.
	tex.material = _premult()
	tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(tex)
	_build_scene()
	_build_globe()
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.draw.connect(_draw_overlay)
	add_child(overlay)
	resized.connect(_fit)
	visibility_changed.connect(_fit)
	_fit()


# The render size follows the control at the window's real pixel density.
func _fit() -> void:
	if vp == null:
		return
	var on := is_visible_in_tree()
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	gvp.render_target_update_mode = vp.render_target_update_mode
	_scale = clampf(get_viewport().get_final_transform().get_scale().x, 0.75, 1.5)
	vp.size = Vector2i(maxi(64, int(size.x * _scale)), maxi(64, int(size.y * _scale)))


# --- the scene -------------------------------------------------------------------

static func _premult() -> CanvasItemMaterial:
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	return m


func _mat(shader: Shader) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader
	return m


func _glow(col: Color, energy: float, fres := 0.0) -> ShaderMaterial:
	var m := _mat(preload("res://shaders/europa_glow.gdshader"))
	m.set_shader_parameter("tint", col)
	m.set_shader_parameter("energy", energy)
	m.set_shader_parameter("fres", fres)
	builds.append(m)
	if _into != null:
		ch_mats[_node_ch.get(_into, 1)].append(m)
	return m


func _add(mesh: Mesh, mat: Material, pos: Vector3, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	(parent if parent else (_into if _into else world)).add_child(mi)
	return mi


func _build_scene() -> void:
	world = Node3D.new()
	vp.add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	cam = Camera3D.new()
	cam.fov = 30.0
	cam.near = 0.5
	cam.far = 120.0
	world.add_child(cam)
	ch1 = Node3D.new()
	world.add_child(ch1)
	ch2 = Node3D.new()
	ch2.visible = false
	world.add_child(ch2)
	shaft_node = Node3D.new()
	world.add_child(shaft_node)
	_node_ch = {ch1: 1, ch2: 2, shaft_node: 0}
	nodes = {1: ch1, 2: ch2}
	_into = ch1

	# The clouds take a few hundred ms to generate: on a worker, so the
	# menu's entrance never hitches; the meshes go in when it's done.
	noise = FastNoiseLite.new()
	noise.seed = 11
	noise.frequency = 1.0
	noise.fractal_octaves = 3
	point_mat = _mat(preload("res://shaders/europa_points.gdshader"))
	builds.append(point_mat)
	ch_mats[1].append(point_mat)
	points = _add(null, point_mat, Vector3.ZERO)
	points.custom_aabb = AABB(Vector3(-6, -9, -5), Vector3(12, 12, 10))
	_flow()
	_into = null

	# The shaft: a bright core, collars down it, the bit at the bottom.
	_into = shaft_node
	var bottom := 0.0
	for l: Dictionary in Levels.ALL:
		if int(String(l.id).get_slice("-", 0)) <= 2:
			bottom = maxf(bottom, float(l.depth))
	bottom += 0.45
	var core := CylinderMesh.new()
	core.top_radius = 0.014
	core.bottom_radius = 0.014
	core.height = bottom + 0.1
	core.radial_segments = 8
	_add(core, _glow(Color(0.35, 1.3, 1.5), 1.0), Vector3(SHAFT.x, 0.05 - core.height * 0.5, SHAFT.y))
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var y := -0.15
	while y > -bottom:
		_circle(im, Vector3(SHAFT.x, y, SHAFT.y), 0.06, 16)
		y -= 0.3
	for k in 4:
		var a := k * PI * 0.5 + PI * 0.25
		var o := Vector3(cos(a), 0, sin(a)) * 0.06
		im.surface_add_vertex(Vector3(SHAFT.x, -0.15, SHAFT.y) + o)
		im.surface_add_vertex(Vector3(SHAFT.x, -bottom, SHAFT.y) + o)
	im.surface_end()
	_add(im, _glow(Color(0.1, 0.45, 0.55, 0.55), 1.0), Vector3.ZERO)
	var bit := CylinderMesh.new()
	bit.top_radius = 0.06
	bit.bottom_radius = 0.0
	bit.height = 0.18
	_add(bit, _glow(Color(0.1, 0.22, 0.3), 1.0), Vector3(SHAFT.x, -bottom - 0.09, SHAFT.y))
	_into = null

	_into = ch1
	_base()
	_into = null
	_stations()
	_into = ch1
	_outline()
	_into = null

	var sm := PlaneMesh.new()
	sm.size = HALF * 2.0
	slice_mat = _mat(preload("res://shaders/europa_slice.gdshader"))
	slice_mat.set_shader_parameter("extent", HALF)
	slice_mat.set_shader_parameter("fill", 0.03)
	slice_mat.set_shader_parameter("grid_a", 0.1)
	slice = _add(sm, slice_mat, Vector3(0, slice_y, 0))
	var bm := PlaneMesh.new()
	bm.size = HALF * 2.0 + Vector2(0.5, 0.5)
	scan_mat = _mat(preload("res://shaders/europa_slice.gdshader"))
	scan_mat.set_shader_parameter("extent", HALF + Vector2(0.25, 0.25))
	scan_mat.set_shader_parameter("fill", 0.1)
	scan_plane = _add(bm, scan_mat, Vector3.ZERO)
	scan_plane.visible = false
	var ds := SphereMesh.new()
	ds.radius = 0.07
	ds.height = 0.14
	drop = _add(ds, _glow(Color(0.7, 0.97, 1.0), 5.0), Vector3(SHAFT.x, 0.0, SHAFT.y))
	drop.visible = false

	# Chapter 2's scene.
	_into = ch2
	c2 = Ch2.new(self, ch2)
	point_mat2 = _mat(preload("res://shaders/europa_points.gdshader"))
	point_mat2.set_shader_parameter("motes", Vector2(Ch2.TOP, Ch2.TOP - Ch2.CFLOOR))
	point_mat2.set_shader_parameter("rise", 2.4)
	builds.append(point_mat2)
	ch_mats[2].append(point_mat2)
	c2.point_mat = point_mat2
	c2.points = _add(null, point_mat2, Vector3.ZERO)
	c2.points.custom_aabb = AABB(Vector3(-6, -12, -5), Vector3(12, 8, 10))
	c2.build_lines()
	ch_mats[2].append(c2.holo_mat)
	_into = null
	# Chapters 3 to 10: lines now, points when first needed.
	for c in range(3, LAST + 1):
		var node := Node3D.new()
		node.visible = false
		world.add_child(node)
		_node_ch[node] = c
		nodes[c] = node
		_into = node
		var sc = Chapters.make(c, self, node)
		sc.setup()
		for mt: ShaderMaterial in [sc.point_mat, sc.holo_mat]:
			builds.append(mt)
			ch_mats[c].append(mt)
		scenes[c] = sc
	_into = null
	_bake_task = WorkerThreadPool.add_task(_bake, false, "campaign model")


# --- the point cloud -----------------------------------------------------------
# Every point is three copies of its centre (the points shader spreads them
# into a dot); colour (authored in sRGB), size in pixels, motion and its
# own phase ride along.

class Cloud:
	var pos := PackedVector3Array()
	var col := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var rng := RandomNumberGenerator.new()

	# grp: the group's phase (motion 3's wave, motion 4's sway).
	func add(p: Vector3, c: Color, size: float, motion := 0.0, grp := 0.0) -> void:
		var lc := c.srgb_to_linear()
		lc.a = c.a
		var ph := rng.randf()
		for k in 3:
			pos.append(p)
			col.append(lc)
			uv.append(Vector2(size, motion))
			uv2.append(Vector2(ph, grp))

	func mesh() -> ArrayMesh:
		var a := []
		a.resize(Mesh.ARRAY_MAX)
		a[Mesh.ARRAY_VERTEX] = pos
		a[Mesh.ARRAY_COLOR] = col
		a[Mesh.ARRAY_TEX_UV] = uv
		a[Mesh.ARRAY_TEX_UV2] = uv2
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
		return m


const INK := Color(0.07, 0.2, 0.32)
const ICE_HI := Color(0.62, 0.74, 0.8)
const LINEA := Color(0.52, 0.36, 0.34)
const ROCK := Color(0.24, 0.3, 0.45)
const ROCK_INK := Color(0.09, 0.14, 0.3)


# The cloud's colour by depth (km): frost silver at the surface, glacial
# teal deeper, the ocean's bright cyan under the ice going blue to the
# floor, indigo rock.
static func _ramp(d: float) -> Color:
	if d < ICE:
		return ICE_HI.lerp(Color(0.26, 0.58, 0.72), smoothstep(0.0, 1.4, d)).lerp(Color(0.03, 0.42, 0.6), smoothstep(1.2, 3.0, d))
	if d < FLOOR:
		return Color(0.0, 0.64, 0.8).lerp(Color(0.08, 0.36, 0.64), smoothstep(ICE, FLOOR, d))
	return ROCK

func _n(x: float, y: float, z := 0.0) -> float:
	return noise.get_noise_3d(x, y, z)


static func _in_notch(x: float, z: float) -> bool:
	return x > NOTCH.x and z > NOTCH.y


# Europa's lineae on the ice: three families of long bands, bent and
# patchy, each with a twin ridge either side. Returns (band, ridge).
func _lineae(x: float, z: float) -> Vector2:
	var band := 0.0
	var ridge := 0.0
	for f: Array in [[Vector2(0.848, 0.53), 0.55, 1.0], [Vector2(-0.346, 0.938), 0.42, 7.0], [Vector2(0.978, -0.206), 0.8, 13.0]]:
		var dir: Vector2 = f[0]
		var freq: float = f[1]
		var s: float = f[2]
		var v := (x * dir.x + z * dir.y) * freq + _n(x * 0.3 + s, z * 0.3, s) * 0.4
		var d := absf(fposmod(v, 1.0) - 0.5) / freq
		var patch := smoothstep(-0.45, 0.05, _n(x * 0.35 - s * 3.0, z * 0.35, 40.0 + s))
		band += exp(-d * d / 0.0016) * patch
		ridge += exp(-pow((d - 0.065) / 0.02, 2.0)) * patch
	return Vector2(minf(band, 1.0), minf(ridge, 1.0))


# Points over a rectangle: from `o` along `u` and `v` (whole lengths),
# jittered off the grid; `f` gets each point and its distance (km) to the
# rectangle's nearest edge.
func _sheet(o: Vector3, u: Vector3, v: Vector3, step: float, rng: RandomNumberGenerator, f: Callable) -> void:
	var lu := u.length()
	var lv := v.length()
	var nu := int(lu / step)
	var nv := int(lv / step)
	for i in nu:
		for j in nv:
			var a := (i + 0.5 + rng.randf_range(-0.4, 0.4)) / nu
			var b := (j + 0.5 + rng.randf_range(-0.4, 0.4)) / nv
			f.call(o + u * a + v * b, minf(minf(a, 1.0 - a) * lu, minf(b, 1.0 - b) * lv))


func _bake() -> void:
	_cloud = Cloud.new()
	_cloud.rng.seed = 7
	_ice(_cloud)
	_ocean(_cloud)
	_seafloor(_cloud)
	_gcloud = Cloud.new()
	_gcloud.rng.seed = 5
	_globe_cloud(_gcloud)
	_cloud2 = Cloud.new()
	_cloud2.rng.seed = 13
	_hcloud = Cloud.new()
	_hcloud.rng.seed = 17
	c2.bake(_cloud2, _hcloud)


func _finish_bake() -> void:
	WorkerThreadPool.wait_for_task_completion(_bake_task)
	_bake_task = -1
	points.mesh = _cloud.mesh()
	globe.mesh = _gcloud.mesh()
	_cloud = null
	_gcloud = null
	var tip := SphereMesh.new()
	tip.radius = 0.035
	tip.height = 0.07
	_into = ch1
	for at in vent_tips:
		_add(tip, _glow(Color(0.4, 1.4, 1.6), 1.0), at)
	_into = ch2
	c2.finish(_cloud2, _hcloud)
	_into = null
	_cloud2 = null
	_hcloud = null
	for c in [1, 2]:
		for mt: ShaderMaterial in ch_mats[c]:
			mt.set_shader_parameter("form", form[c])


func _exit_tree() -> void:
	if _bake_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_bake_task)
		_bake_task = -1
		_cloud = null
		_gcloud = null
		_cloud2 = null
		_hcloud = null
	for c in scenes:
		if scenes[c].task >= 0:
			WorkerThreadPool.wait_for_task_completion(scenes[c].task)
			scenes[c].task = -1


func _ice(c: Cloud) -> void:
	var rng := c.rng
	# The surface: frost scattered thin, the lineae dense and rust-dark,
	# their ridges raised in ink; the rim kept crisp.
	_sheet(Vector3(-HALF.x, 0, -HALF.y), Vector3(HALF.x * 2.0, 0, 0), Vector3(0, 0, HALF.y * 2.0), 0.034, rng, func(p: Vector3, e: float) -> void:
		if _in_notch(p.x, p.z):
			return
		var l := _lineae(p.x, p.z)
		var h := _n(p.x * 2.0, p.z * 2.0, 3.0) * 0.03 + l.y * 0.07 - l.x * 0.02
		var feature := maxf(l.x, l.y)
		if feature < 0.25 and e > 0.1 and rng.randf() < 0.85:
			return
		var col := Color(0.42, 0.62, 0.72).lerp(LINEA, l.x).lerp(INK, l.y * 0.6)
		col.a = 0.32 + l.x * 0.45 + l.y * 0.4
		c.add(Vector3(p.x, h, p.z), col, 1.5 + l.y * 0.6))
	# The faces: the shell from frost to glacial blue down 3 km, strata as
	# dense dark bands, the edges crisp. The cut faces in the notch are the
	# section through it: denser, bluer.
	var face := func(p: Vector3, e: float, cut: bool) -> void:
		var d := -p.y
		var w := _n(p.x * 0.6 + p.z * 0.6, d * 2.5, 7.0) * 0.22
		var band := absf(fposmod((d + w) * 2.6, 1.0) - 0.5)
		var strata := 1.0 - smoothstep(0.025, 0.07, band)
		var fine := 1.0 - smoothstep(0.0, 0.05, absf(fposmod((d + w * 0.5) * 9.0, 1.0) - 0.5))
		var keep := maxf(maxf(strata, fine * 0.5), 0.16 if cut else 0.1)
		if e < 0.08:
			keep = 1.0
		if rng.randf() > keep:
			return
		var col := _ramp(d).lerp(Color(0.0, 0.3, 0.46), strata * 0.6)
		col.a = (0.4 if cut else 0.32) + strata * 0.4 + fine * 0.1
		c.add(p, col, 1.5 + strata * 0.4)
	var dn := Vector3(0, -ICE, 0)
	var x0 := -HALF.x
	var x1 := HALF.x
	var z0 := -HALF.y
	var z1 := HALF.y
	_sheet(Vector3(x0, 0, z0), Vector3(x1 - x0, 0, 0), dn, 0.04, rng, face.bind(false))
	_sheet(Vector3(x0, 0, z0), Vector3(0, 0, z1 - z0), dn, 0.04, rng, face.bind(false))
	_sheet(Vector3(x0, 0, z1), Vector3(NOTCH.x - x0, 0, 0), dn, 0.036, rng, face.bind(false))
	_sheet(Vector3(x1, 0, z0), Vector3(0, 0, NOTCH.y - z0), dn, 0.036, rng, face.bind(false))
	_sheet(Vector3(NOTCH.x, 0, NOTCH.y), Vector3(0, 0, z1 - NOTCH.y), dn, 0.026, rng, face.bind(true))
	_sheet(Vector3(NOTCH.x, 0, NOTCH.y), Vector3(x1 - NOTCH.x, 0, 0), dn, 0.026, rng, face.bind(true))
	# Inside: strata sheets, faint, warped.
	for d: float in [0.75, 1.4, 2.05, 2.6]:
		_sheet(Vector3(x0, 0, z0), Vector3(x1 - x0, 0, 0), Vector3(0, 0, z1 - z0), 0.11, rng, func(p: Vector3, _e: float) -> void:
			if _in_notch(p.x, p.z):
				return
			var col := _ramp(d)
			col.a = 0.13
			c.add(Vector3(p.x, -d + _n(p.x * 0.7, p.z * 0.7, d) * 0.18, p.z), col, 1.4))
	# Cracks: lens-shaped curtains rising from the ocean into the shell.
	for k in 9:
		var s := Vector2(rng.randf_range(x0 + 0.6, x1 - 0.6), rng.randf_range(z0 + 0.5, z1 - 0.5))
		var dir := Vector2.from_angle(rng.randf() * TAU)
		var ln := rng.randf_range(1.0, 2.4)
		var top := rng.randf_range(0.8, 2.5)
		var t := 0.0
		while t < ln:
			var q := s + dir * t + dir.orthogonal() * _n(s.x + t, s.y, 21.0 + k) * 0.25
			var e := 1.0 - pow(2.0 * t / ln - 1.0, 2.0)
			if absf(q.x) < HALF.x and absf(q.y) < HALF.y and not _in_notch(q.x, q.y):
				var yy := -ICE
				while yy < -ICE + top * e:
					var col := INK
					col.a = 0.18 + 0.22 * (1.0 - (yy + ICE) / maxf(0.01, top * e))
					c.add(Vector3(q.x, yy + rng.randf_range(-0.02, 0.02), q.y), col, 1.3)
					yy += 0.06
			t += 0.045
	# The underside: the ice's base over the ocean, a dense cyan skin - the
	# boundary the whole campaign lives under.
	_sheet(Vector3(x0, -ICE, z0), Vector3(x1 - x0, 0, 0), Vector3(0, 0, z1 - z0), 0.038, rng, func(p: Vector3, _e: float) -> void:
		var open := _in_notch(p.x, p.z)
		var col := Color(0.0, 0.6, 0.72)
		col.a = 0.16 if open else 0.3
		c.add(Vector3(p.x, -ICE + _n(p.x * 1.2, p.z * 1.2, 30.0) * (0.03 if open else 0.12), p.z), col, 1.5))


const VENTS := [Vector3(-2.3, 0, -1.2), Vector3(-1.1, 0, 1.6), Vector3(2.4, 0, -0.6)]


func _ocean(c: Cloud) -> void:
	var rng := c.rng
	# The walls, barely there.
	var wall := func(p: Vector3, _e: float) -> void:
		var col := _ramp(-p.y)
		col.a = 0.12 + 0.12 * (1.0 - smoothstep(-ICE, -FLOOR, p.y))
		c.add(p, col, 1.4)
	var dn := Vector3(0, -(FLOOR - ICE), 0)
	var top := -ICE
	_sheet(Vector3(-HALF.x, top, -HALF.y), Vector3(HALF.x * 2.0, 0, 0), dn, 0.11, rng, wall)
	_sheet(Vector3(-HALF.x, top, HALF.y), Vector3(HALF.x * 2.0, 0, 0), dn, 0.11, rng, wall)
	_sheet(Vector3(-HALF.x, top, -HALF.y), Vector3(0, 0, HALF.y * 2.0), dn, 0.11, rng, wall)
	_sheet(Vector3(HALF.x, top, -HALF.y), Vector3(0, 0, HALF.y * 2.0), dn, 0.11, rng, wall)
	# Motes sinking through it.
	# Motes sinking through it: a fine haze and brighter specks.
	for k in 11000:
		var p := Vector3(rng.randf_range(-HALF.x, HALF.x) * 0.97, rng.randf_range(-FLOOR, -ICE), rng.randf_range(-HALF.y, HALF.y) * 0.97)
		var col := _ramp(-p.y)
		var bright := rng.randf() < 0.3
		col.a = rng.randf_range(0.35, 0.65) if bright else rng.randf_range(0.1, 0.22)
		c.add(p, col, rng.randf_range(1.4, 2.0) if bright else 1.3, 1.0)
	# Plumes off the vents.
	for v: Vector3 in VENTS:
		for k in 650:
			var col := Color(0.25, 0.85, 0.95, 0.5)
			var r := Vector2.from_angle(rng.randf() * TAU) * rng.randf() * 0.05
			c.add(Vector3(v.x + r.x, -FLOOR + 0.62, v.z + r.y), col, 1.7, 2.0)


func _floor_h(x: float, z: float) -> float:
	var h := _n(x * 0.45, z * 0.45, 50.0) * 0.22
	for v: Vector3 in VENTS:
		var r2 := (x - v.x) ** 2 + (z - v.z) ** 2
		h += 0.42 * exp(-r2 / 0.22)
	return h


func _seafloor(c: Cloud) -> void:
	var rng := c.rng
	# The floor as a contour map: lines every 40 m dense and dark, sparse
	# grain between.
	_sheet(Vector3(-HALF.x, 0, -HALF.y), Vector3(HALF.x * 2.0, 0, 0), Vector3(0, 0, HALF.y * 2.0), 0.036, rng, func(p: Vector3, _e: float) -> void:
		var h := _floor_h(p.x, p.z)
		var cl := absf(fposmod(h / 0.06, 1.0) - 0.5)
		var line := smoothstep(0.425, 0.485, cl)
		if line < 0.2 and rng.randf() < 0.82:
			return
		var col := ROCK.lerp(ROCK_INK, line * 0.6)
		col.a = 0.22 + line * 0.4
		c.add(Vector3(p.x, -FLOOR + h, p.z), col, 1.5 + line * 0.5))
	# The slab under it, layered.
	var side := func(p: Vector3, _e: float) -> void:
		var band := absf(fposmod(p.y * 9.0 + _n(p.x + p.z, p.y, 60.0) * 0.6, 1.0) - 0.5)
		if band < 0.38 and rng.randf() < 0.6:
			return
		var col := ROCK.lerp(ROCK_INK, 0.4 if band > 0.38 else 0.0)
		col.a = 0.2 + (0.25 if band > 0.38 else 0.0)
		c.add(p, col, 1.5)
	var dn := Vector3(0, -0.5, 0)
	var y0 := -FLOOR
	_sheet(Vector3(-HALF.x, y0, -HALF.y), Vector3(HALF.x * 2.0, 0, 0), dn, 0.05, rng, side)
	_sheet(Vector3(-HALF.x, y0, HALF.y), Vector3(HALF.x * 2.0, 0, 0), dn, 0.05, rng, side)
	_sheet(Vector3(-HALF.x, y0, -HALF.y), Vector3(0, 0, HALF.y * 2.0), dn, 0.05, rng, side)
	_sheet(Vector3(HALF.x, y0, -HALF.y), Vector3(0, 0, HALF.y * 2.0), dn, 0.05, rng, side)
	# The chimneys on the mounds: rings of points narrowing up.
	for v: Vector3 in VENTS:
		var base := -FLOOR + _floor_h(v.x, v.z) - 0.05
		for j in 10:
			var t := j / 9.0
			var r := lerpf(0.11, 0.035, t)
			for k in 18:
				var a := TAU * k / 18.0 + j * 0.3
				var col := INK
				col.a = 0.6
				c.add(Vector3(v.x + cos(a) * r, base + t * 0.24, v.z + sin(a) * r), col, 1.5)
		vent_tips.append(Vector3(v.x, base + 0.26, v.z))


# Convection: loops from each vent up under the ice and back down, a
# comet running along each.
func _flow() -> void:
	var v := PackedVector3Array()
	var uv := PackedVector2Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for vent: Vector3 in VENTS:
		for side: float in [-1.0, 1.0]:
			for dz: float in [-0.35, 0.3]:
				var rx := rng.randf_range(0.8, 1.4)
				var cx := clampf(vent.x + side * rx, -HALF.x + rx + 0.1, HALF.x - rx - 0.1)
				var cy := -4.62
				var ry := 1.38
				var z := clampf(vent.z + dz, -HALF.y + 0.1, HALF.y - 0.1)
				var ph := rng.randf()
				var n := 72
				var prev := Vector3.ZERO
				var run := 0.0
				for k in n + 1:
					var a := TAU * k / n * (-side)
					var ca := cos(a + PI * (1.0 if side > 0.0 else 0.0))
					var sa := sin(a + PI * (1.0 if side > 0.0 else 0.0))
					var p := Vector3(cx + rx * signf(ca) * pow(absf(ca), 0.55), cy + ry * signf(sa) * pow(absf(sa), 0.55), z)
					if k > 0:
						v.append(prev)
						uv.append(Vector2(run, ph))
						run += prev.distance_to(p)
						v.append(p)
						uv.append(Vector2(run, ph))
					prev = p
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = v
	a[Mesh.ARRAY_TEX_UV] = uv
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, a)
	flow_mat = _mat(preload("res://shaders/europa_flow.gdshader"))
	builds.append(flow_mat)
	_add(m, flow_mat, Vector3.ZERO)


func _circle(im: ImmediateMesh, at: Vector3, r: float, seg: int, dash := false) -> void:
	for k in seg:
		if dash and k % 2 == 1:
			continue
		var a0 := TAU * k / seg
		var a1 := TAU * (k + 1) / seg
		im.surface_add_vertex(at + Vector3(cos(a0), 0, sin(a0)) * r)
		im.surface_add_vertex(at + Vector3(cos(a1), 0, sin(a1)) * r)


func _wire_box(im: ImmediateMesh, at: Vector3, s: Vector3) -> void:
	var h := s * 0.5
	var c: Array[Vector3] = []
	for k in 8:
		c.append(at + Vector3(h.x * (1 if k & 1 else -1), h.y * (1 if k & 2 else -1), h.z * (1 if k & 4 else -1)))
	for e: Vector2i in [Vector2i(0, 1), Vector2i(2, 3), Vector2i(4, 5), Vector2i(6, 7), Vector2i(0, 2), Vector2i(1, 3),
			Vector2i(4, 6), Vector2i(5, 7), Vector2i(0, 4), Vector2i(1, 5), Vector2i(2, 6), Vector2i(3, 7)]:
		im.surface_add_vertex(c[e.x])
		im.surface_add_vertex(c[e.y])


# The base on the ice, drawn as a technical wireframe: modules with ribs,
# corridors, a dome, solar arrays, a landing pad, the derrick over the
# shaft, a mast with a blinking beacon.
func _base() -> void:
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var sx := SHAFT.x
	var sz := SHAFT.y
	for m: Array in [[Vector3(-0.55, 0.13, -0.35), Vector3(0.9, 0.26, 0.44)], [Vector3(1.55, 0.11, -0.55), Vector3(0.62, 0.22, 0.46)],
			[Vector3(-1.35, 0.1, 0.25), Vector3(0.5, 0.2, 0.7)]]:
		var at: Vector3 = m[0]
		var s: Vector3 = m[1]
		_wire_box(im, at, s)
		var ribs := int(s.x / 0.12)
		for k in range(1, ribs):
			var x := at.x - s.x * 0.5 + s.x * k / ribs
			im.surface_add_vertex(Vector3(x, at.y + s.y * 0.5, at.z - s.z * 0.5))
			im.surface_add_vertex(Vector3(x, at.y + s.y * 0.5, at.z + s.z * 0.5))
	_wire_box(im, Vector3(0.18, 0.05, -0.4), Vector3(0.55, 0.08, 0.1))
	_wire_box(im, Vector3(-1.1, 0.05, -0.15), Vector3(0.1, 0.08, 0.5))
	# The dome.
	var dc := Vector3(-0.35, 0.0, 1.35)
	for k in 4:
		var a := k * PI / 8.0
		_circle(im, dc + Vector3(0, sin(a) * 0.32, 0), cos(a) * 0.32, 32)
	for k in 8:
		var a := TAU * k / 8.0
		for j in 8:
			var b0 := PI * 0.5 * j / 8.0
			var b1 := PI * 0.5 * (j + 1) / 8.0
			im.surface_add_vertex(dc + Vector3(cos(a) * cos(b0), sin(b0), sin(a) * cos(b0)) * 0.32)
			im.surface_add_vertex(dc + Vector3(cos(a) * cos(b1), sin(b1), sin(a) * cos(b1)) * 0.32)
	# Solar arrays, tilted, each a grid of cells.
	for k in 3:
		var o := Vector3(-2.6 + k * 0.56, 0.16, -1.2)
		var u := Vector3(0.48, 0, 0)
		var v := Vector3(0, sin(0.45), -cos(0.45)) * 0.26
		var c0 := o - u * 0.5 - v * 0.5
		for i in 5:
			im.surface_add_vertex(c0 + u * i / 4.0)
			im.surface_add_vertex(c0 + u * i / 4.0 + v)
		for j in 3:
			im.surface_add_vertex(c0 + v * j / 2.0)
			im.surface_add_vertex(c0 + v * j / 2.0 + u)
		im.surface_add_vertex(o)
		im.surface_add_vertex(Vector3(o.x, 0.0, o.z))
	# The derrick: a lattice tower over the shaft.
	var h := 1.05
	var legs: Array[Vector3] = []
	for cc in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		legs.append(Vector3(cc.x, 0, cc.y))
	var lv := func(k: int, yy: float) -> Vector3:
		var w := lerpf(0.24, 0.06, yy / h)
		return Vector3(sx + legs[k].x * w, yy, sz + legs[k].z * w)
	for k in 4:
		im.surface_add_vertex(lv.call(k, 0.0))
		im.surface_add_vertex(lv.call(k, h))
	for lvl in 6:
		var y0 := h * lvl / 6.0
		var y1 := h * (lvl + 1) / 6.0
		for k in 4:
			var k2 := (k + 1) % 4
			im.surface_add_vertex(lv.call(k, y0))
			im.surface_add_vertex(lv.call(k2, y0))
			im.surface_add_vertex(lv.call(k, y0))
			im.surface_add_vertex(lv.call(k2, y1))
			im.surface_add_vertex(lv.call(k2, y0))
			im.surface_add_vertex(lv.call(k, y1))
	# The mast.
	im.surface_add_vertex(Vector3(1.75, 0.22, -0.55))
	im.surface_add_vertex(Vector3(1.75, 0.95, -0.55))
	im.surface_end()
	_add(im, _glow(Color(0.08, 0.22, 0.3, 0.85), 1.0), Vector3.ZERO)
	# Cyan accents: the pad's rings, the modules' light strips.
	var ac := ImmediateMesh.new()
	ac.surface_begin(Mesh.PRIMITIVE_LINES)
	_circle(ac, Vector3(-2.3, 0.01, 1.4), 0.42, 48)
	_circle(ac, Vector3(-2.3, 0.01, 1.4), 0.34, 48, true)
	for m: Array in [[Vector3(-0.55, 0.13, -0.35), Vector3(0.9, 0.26, 0.44)], [Vector3(1.55, 0.11, -0.55), Vector3(0.62, 0.22, 0.46)],
			[Vector3(-1.35, 0.1, 0.25), Vector3(0.5, 0.2, 0.7)]]:
		var at: Vector3 = m[0]
		var s: Vector3 = m[1]
		var yy := at.y + s.y * 0.1
		for e: Array in [[Vector3(-1, 0, 1), Vector3(1, 0, 1)], [Vector3(1, 0, 1), Vector3(1, 0, -1)]]:
			ac.surface_add_vertex(Vector3(at.x + e[0].x * s.x * 0.5, yy, at.z + e[0].z * s.z * 0.5))
			ac.surface_add_vertex(Vector3(at.x + e[1].x * s.x * 0.5, yy, at.z + e[1].z * s.z * 0.5))
	ac.surface_end()
	_add(ac, _glow(Color(0.1, 0.95, 1.15), 1.0), Vector3.ZERO)
	var bs := SphereMesh.new()
	bs.radius = 0.035
	bs.height = 0.07
	beacon_mat = _glow(Color(1.0, 0.4, 0.45), 2.5)
	_add(bs, beacon_mat, Vector3(1.75, 0.97, -0.55))
	_add(bs, _glow(Color(0.7, 0.97, 1.0), 3.0), Vector3(sx, h + 0.03, sz))


# Stations: a fine double ring round the shaft with four ticks; the selected
# one also gets a dashed outer ring turning slowly.
func _stations() -> void:
	for i in Levels.ALL.size():
		var y := -float(Levels.ALL[i].depth)
		var im := ImmediateMesh.new()
		im.surface_begin(Mesh.PRIMITIVE_LINES)
		_circle(im, Vector3.ZERO, 0.24, 48)
		_circle(im, Vector3.ZERO, 0.19, 48)
		for k in 4:
			var d := Vector3(cos(k * PI * 0.5), 0, sin(k * PI * 0.5))
			im.surface_add_vertex(d * 0.24)
			im.surface_add_vertex(d * 0.33)
			im.surface_add_vertex(d * 0.06)
			im.surface_add_vertex(d * 0.19)
		im.surface_end()
		var m := _glow(Ui.ACCENT, 2.0)
		var r := _add(im, m, Vector3(SHAFT.x, y, SHAFT.y))
		rings.append(r)
		ring_mats.append(m)
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	_circle(im, Vector3.ZERO, 0.5, 40, true)
	_circle(im, Vector3.ZERO, 0.62, 96)
	im.surface_end()
	sel_mat = _glow(Color(0.1, 0.95, 1.15), 1.0)
	sel_ring = _add(im, sel_mat, Vector3(SHAFT.x, 0, SHAFT.y))


# Hologram lines: the block's edges, the ice / ocean boundary, the cutaway,
# depth contours round the walls every kilometre, ticks down the front
# left edge.
func _outline() -> void:
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var x0 := -HALF.x
	var x1 := HALF.x
	var z0 := -HALF.y
	var z1 := HALF.y
	var nx := NOTCH.x
	var nz := NOTCH.y
	var seg := func(a: Vector3, b: Vector3) -> void:
		im.surface_add_vertex(a)
		im.surface_add_vertex(b)
	var notched := func(y: float) -> void:
		var top: Array[Vector3] = [Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(x1, y, nz), Vector3(nx, y, nz), Vector3(nx, y, z1), Vector3(x0, y, z1)]
		for k in top.size():
			seg.call(top[k], top[(k + 1) % top.size()])
	notched.call(0.0)
	var yb := -FLOOR - 0.5
	for c: Vector2 in [Vector2(x0, z0), Vector2(x1, z0), Vector2(x0, z1)]:
		seg.call(Vector3(c.x, 0, c.y), Vector3(c.x, yb, c.y))
	seg.call(Vector3(x1, -ICE, z1), Vector3(x1, yb, z1))
	for c: Vector2 in [Vector2(x1, nz), Vector2(nx, nz), Vector2(nx, z1)]:
		seg.call(Vector3(c.x, 0, c.y), Vector3(c.x, -ICE, c.y))
	for y in [-ICE, -FLOOR, yb]:
		var r: Array[Vector3] = [Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(x1, y, z1), Vector3(x0, y, z1)]
		for k in 4:
			seg.call(r[k], r[(k + 1) % 4])
	seg.call(Vector3(x1, -ICE, nz), Vector3(nx, -ICE, nz))
	seg.call(Vector3(nx, -ICE, nz), Vector3(nx, -ICE, z1))
	for k in range(1, 14):
		var y := -k * 0.5
		var long := k % 2 == 0
		seg.call(Vector3(x0, y, z1), Vector3(x0 - (0.22 if long else 0.11), y, z1))
	im.surface_end()
	_add(im, _glow(Color(0.05, 0.55, 0.66, 0.75), 1.0), Vector3.ZERO)
	# Fainter: contours every kilometre.
	var ct := ImmediateMesh.new()
	ct.surface_begin(Mesh.PRIMITIVE_LINES)
	for k in range(1, 7):
		var y := -float(k)
		if y > -ICE:
			var top: Array[Vector3] = [Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(x1, y, nz), Vector3(nx, y, nz), Vector3(nx, y, z1), Vector3(x0, y, z1)]
			for j in top.size():
				ct.surface_add_vertex(top[j])
				ct.surface_add_vertex(top[(j + 1) % top.size()])
		elif y < -ICE:
			var r: Array[Vector3] = [Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(x1, y, z1), Vector3(x0, y, z1)]
			for j in 4:
				ct.surface_add_vertex(r[j])
				ct.surface_add_vertex(r[(j + 1) % 4])
	ct.surface_end()
	_add(ct, _glow(Color(0.05, 0.55, 0.66, 0.28), 1.0), Vector3.ZERO)
	# The laser that sweeps down the block: a bright loop round it, a
	# fainter one just outside.
	sweep_mat = _glow(Color(0.2, 1.5, 1.8), 1.0)
	for notch_it in [true, false]:
		var sw := ImmediateMesh.new()
		sw.surface_begin(Mesh.PRIMITIVE_LINES)
		for o: float in [0.015, 0.09]:
			var a0 := x0 - o
			var a1 := x1 + o
			var b0 := z0 - o
			var b1 := z1 + o
			var loop: Array[Vector3] = [Vector3(a0, 0, b0), Vector3(a1, 0, b0), Vector3(a1, 0, b1), Vector3(a0, 0, b1)]
			if notch_it:
				loop = [Vector3(a0, 0, b0), Vector3(a1, 0, b0), Vector3(a1, 0, nz - o), Vector3(nx - o, 0, nz - o), Vector3(nx - o, 0, b1), Vector3(a0, 0, b1)]
			for j in loop.size():
				sw.surface_add_vertex(loop[j])
				sw.surface_add_vertex(loop[(j + 1) % loop.size()])
		sw.surface_end()
		var mi := _add(sw, sweep_mat, Vector3.ZERO)
		mi.visible = false
		sweep_rings.append(mi)


func _build_globe() -> void:
	gvp = SubViewport.new()
	gvp.own_world_3d = true
	gvp.transparent_bg = true
	gvp.msaa_3d = Viewport.MSAA_4X
	gvp.use_hdr_2d = true
	gvp.size = Vector2i(440, 440)
	gvp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(gvp)
	var root := Node3D.new()
	gvp.add_child(root)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	gcam = Camera3D.new()
	gcam.fov = 34.0
	root.add_child(gcam)
	gcam.look_at_from_position(Vector3(0, 0.35, 3.6), Vector3.ZERO)
	globe = MeshInstance3D.new()
	globe.custom_aabb = AABB(Vector3(-1.5, -1.5, -1.5), Vector3(3, 3, 3))
	globe_mat = _mat(preload("res://shaders/europa_points.gdshader"))
	globe_mat.set_shader_parameter("fog", Vector2(3.2, 4.5))
	globe_mat.set_shader_parameter("fog_min", 0.12)
	globe_mat.set_shader_parameter("sweep", 0.0)
	globe_mat.set_shader_parameter("px", 440.0 / 210.0 * 1.5)
	globe.material_override = globe_mat
	globe.rotation = Vector3(0.18, 0, 0.12)
	root.add_child(globe)
	# The graticule and an orbit, fine lines.
	var gm := ImmediateMesh.new()
	gm.surface_begin(Mesh.PRIMITIVE_LINES)
	for k in range(-2, 3):
		var la := k * PI / 6.0
		_circle(gm, Vector3(0, sin(la) * 1.004, 0), cos(la) * 1.004, 72)
	for k in 6:
		var lo := k * PI / 6.0
		for j in 36:
			var b0 := PI * j / 36.0 - PI * 0.5
			var b1 := PI * (j + 1) / 36.0 - PI * 0.5
			gm.surface_add_vertex(Vector3(cos(lo) * cos(b0), sin(b0), sin(lo) * cos(b0)) * 1.004)
			gm.surface_add_vertex(Vector3(cos(lo) * cos(b1), sin(b1), sin(lo) * cos(b1)) * 1.004)
	gm.surface_end()
	var grat := MeshInstance3D.new()
	grat.mesh = gm
	var gmat := _mat(preload("res://shaders/europa_glow.gdshader"))
	gmat.set_shader_parameter("tint", Color(0.05, 0.55, 0.66, 0.3))
	grat.material_override = gmat
	globe.add_child(grat)
	# The drill site, a little north of the equator on the face we see.
	site = Node3D.new()
	var lat := deg_to_rad(14.0)
	var lon := deg_to_rad(80.0)
	site.position = Vector3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon)) * 1.0
	globe.add_child(site)
	var om := ImmediateMesh.new()
	om.surface_begin(Mesh.PRIMITIVE_LINES)
	_circle(om, Vector3.ZERO, 1.32, 128)
	_circle(om, Vector3.ZERO, 1.42, 128, true)
	om.surface_end()
	var orbit := MeshInstance3D.new()
	orbit.mesh = om
	var omat := _mat(preload("res://shaders/europa_glow.gdshader"))
	omat.set_shader_parameter("tint", Color(0.05, 0.6, 0.72, 0.5))
	orbit.material_override = omat
	orbit.rotation = Vector3(0.32, 0, -0.2)
	root.add_child(orbit)
	gtex = TextureRect.new()
	gtex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	gtex.stretch_mode = TextureRect.STRETCH_SCALE
	gtex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gtex.texture = gvp.get_texture()
	gtex.material = _premult()
	gtex.position = Vector2(0, 4)
	gtex.size = Vector2(210, 210)
	add_child(gtex)


# Europa as a scan: a Fibonacci sphere of points, the lineae dense and dark
# across it; the far side shows through, faint.
func _globe_cloud(c: Cloud) -> void:
	var n := 9000
	for i in n:
		var y := 1.0 - 2.0 * (i + 0.5) / n
		var r := sqrt(1.0 - y * y)
		var a := i * 2.39996323
		var p := Vector3(cos(a) * r, y, sin(a) * r)
		var line := 0.0
		for k in 6:
			var dir := Vector3(sin(k * 2.1), cos(k * 1.3) * 0.6, cos(k * 2.1 + 0.4)).normalized()
			var v := p.dot(dir) * (3.0 + k * 0.7) + _n(p.x * 2.0 + k, p.y * 2.0, p.z * 2.0) * 0.8
			var d := absf(fposmod(v, 1.0) - 0.5)
			line += exp(-d * d / 0.002) * smoothstep(-0.1, 0.3, _n(p.x * 3.5, p.y * 3.5 + k * 5.0, p.z * 3.5))
		line = minf(line, 1.0)
		if line < 0.15 and c.rng.randf() < 0.35:
			continue
		var col := Color(0.3, 0.6, 0.72).lerp(LINEA, line * 0.9)
		col.a = 0.35 + line * 0.45
		c.add(p, col, 1.5 + line * 0.9)


# --- the page's side ---------------------------------------------------------------

func select(i: int, instant: bool) -> void:
	sel = i
	if instant:
		slice_y = _station_y(i)
		focus_y = _focus_for(i)
		chapter = _chapter(i)
		for c in form.size():
			form[c] = 0.0
		form[chapter] = 1.0 if chapter <= 2 or (scenes.has(chapter) and scenes[chapter].baked) else 0.0
		# (The materials too: a map opened straight on kept its old form, 0.)
		for c in range(1, LAST + 1):
			nodes[c].visible = form[c] > 0.001
			for mt: ShaderMaterial in ch_mats[c]:
				mt.set_shader_parameter("form", form[c])


# The page opens: the camera cranes in while the block builds.
func enter() -> void:
	intro = 1.0
	descent = -1.0
	drop.visible = false
	yaw_drag = 0.0
	pitch_drag = 0.0


func descend() -> void:
	descent = 0.0
	drop.visible = true


func _station_y(i: int) -> float:
	return _station3(i).y


# A station in the world: on the shaft at its depth for chapters 1 and 2,
# on its scene's own path after.
func _station3(i: int) -> Vector3:
	var c := _chapter(i)
	if c <= 2 or not scenes.has(c):
		return Vector3(SHAFT.x, -float(Levels.ALL[i].depth), SHAFT.y)
	if not _spot.has(i):
		var idx := range(Levels.ALL.size()).filter(func(j: int) -> bool: return _chapter(j) == c)
		var sp: Array = scenes[c].spots(idx.size())
		for k in idx.size():
			_spot[idx[k]] = sp[k]
	return _spot[i]


# The chapter on show: a preview, else the selected level's.
func _want_ch() -> int:
	return clampi(preview_ch if preview_ch > 0 else _chapter(sel), 1, LAST)


func _scene_dist(c: int) -> float:
	return DIST if c == 1 else (25.5 if c == 2 else float(scenes[c].dist))


func _scene_x(c: int) -> float:
	return -0.2 if c == 1 else (-0.2 if c == 2 else float(scenes[c].tgt_x))


# Weighted by how much of each chapter is on show (they blend in a change).
func _blend(f: Callable) -> float:
	var w := 0.0
	var v := 0.0
	for c in range(1, LAST + 1):
		if form[c] > 0.0:
			w += form[c]
			v += form[c] * float(f.call(c))
	return v / w if w > 0.0 else float(f.call(chapter))


func _focus_for(i: int) -> float:
	var c := _chapter(i)
	if c >= 3 and scenes.has(c):
		return lerpf(scenes[c].focus, _station_y(i), 0.1)
	return lerpf(-3.4 if c < 2 else -7.7, _station_y(i), 0.35)


# The scan's depth (km) for the page's readout.
func scan_depth() -> float:
	return clampf(-build_y, 0.0, 10.6) if build_y > -50.0 else 0.0


func _sp(p: Vector3) -> Vector2:
	if cam.is_position_behind(p):
		return Vector2(-1e5, -1e5)
	return cam.unproject_position(p) / _scale


# A station's ring on screen (local).
func station_pos(i: int) -> Vector2:
	return _sp(_station3(i))


func _label_at(i: int) -> Vector2:
	return lab[i] if i < lab.size() else station_pos(i) + Vector2(46, 0)


# One column right of the rings, evenly spaced (2026-10-30: "关卡上面下面离得
#很近…黑色字和背景混在一起"): a row every ROW px, a little more between
# chapters, the column centred on the stations and kept on screen. The rows
# sit on one frosted plate (_draw_list_plate), the leaders slant to them.
const ROW := 62.0
const CH_GAP := 30.0


func _chapter(i: int) -> int:
	return int(String(Levels.ALL[i].id).get_slice("-", 0))


# One map per chapter (2026-10-30: "这个地图只显示第一张…完成之后到下一个地图
# 再显示第二张"): each chapter's levels are their own list, centred on their
# stations; only the chapter on show is drawn (the other fades with its scene).
func _layout_labels() -> void:
	var n := Levels.ALL.size()
	lab.resize(n)
	for c in range(1, LAST + 1):
		var idx := range(n).filter(func(i: int) -> bool: return _chapter(i) == c)
		if idx.is_empty():
			continue
		# Right of this chapter's own stations, kept on the model's half.
		var x := -1e9
		var mid := 0.0
		for i: int in idx:
			x = maxf(x, station_pos(i).x)
			mid += station_pos(i).y / idx.size()
		x = minf(x, size.x - 52.0 - 300.0)
		var span := ROW * (idx.size() - 1)
		var top := clampf(mid - span * 0.5, 170.0, maxf(170.0, size.y - 60.0 - span))
		for k in idx.size():
			lab[idx[k]] = Vector2(x + 52.0, top + ROW * k)


# How much of chapter c's map is on show (its scene's form).
func _shown(c: int) -> float:
	return form[clampi(c, 1, LAST)]


# The frosted plate behind a chapter's list, as far down as the build has
# come, the chapter's name at its head.
func _draw_list_plate(c: int) -> void:
	var first := -1
	var last := -1
	for i in Levels.ALL.size():
		if _chapter(i) != c:
			continue
		if first < 0:
			first = i
		if _pk(i) > 0.0 and station_pos(i).x > -1e4:
			last = i
	var a := _ease(_pk(maxi(first, 0))) * _shown(c)
	if last < 0 or a <= 0.01:
		return
	var x := lab[first].x - 30.0
	var r := Rect2(x, lab[first].y - 54.0, 300.0, lab[last].y - lab[first].y + 54.0 + 34.0)
	overlay.draw_rect(r.grow(6.0), Color(1, 1, 1, 0.18 * a))
	overlay.draw_rect(r, Color(0.985, 0.992, 1.0, 0.9 * a))
	overlay.draw_rect(r, Color(Ui.ACCENT, 0.22 * a), false, 1.0)
	overlay.draw_rect(Rect2(r.position, Vector2(40.0, 2.0)), Color(Ui.ACCENT, a))
	var cy := lab[first].y - 36.0
	_text(Ui.sans(600), Vector2(x + 16.0, cy), page.chapter_name(c), 12, Color(Ui.INK_SOFT, a))
	_text(Ui.mono(), Vector2(x + 168.0, cy), "CHAPTER %s" % page.ROMAN[c - 1], 9, Color(Ui.INK_FAINT, a))
	for i in range(first + 1, last + 1):
		var sy := (lab[i].y + lab[i - 1].y) * 0.5 + 2.0
		overlay.draw_line(Vector2(x + 16.0, sy), Vector2(x + 284.0, sy), Color(Ui.INK_FAINT, 0.18 * a), 1.0)


# Where the page's lead line to the card starts (local).
func label_end(i: int) -> Vector2:
	return _label_at(i) + Vector2(262, 0)


# How far the build has come past a station (0 hidden .. 1 in).
func _pk(i: int) -> float:
	if build_y < -50.0:
		return 1.0
	return clampf((_station_y(i) - build_y) / 0.5, 0.0, 1.0)


func _process(delta: float) -> void:
	if _bake_task >= 0 and WorkerThreadPool.is_task_completed(_bake_task):
		_finish_bake()
	if not is_visible_in_tree():
		return
	time += delta
	if absf(get_viewport().get_final_transform().get_scale().x - _scale) > 0.01 and Engine.get_process_frames() % 30 == 0:
		_fit()
	# The build follows the page's scan line down the control.
	var k := 1.0
	if page.reveal < 0.999:
		k = clampf((page.scan_y() - global_position.y) / maxf(1.0, size.y), 0.0, 1.0)
	var b0 := 1.7 if chapter == 1 else (-5.3 if chapter == 2 else float(scenes[chapter].top) + 0.6)
	var b1 := (-FLOOR - 0.7) if chapter == 1 else (-10.6 if chapter == 2 else float(scenes[chapter].bottom) - 0.2)
	build_y = lerpf(b0, b1, k) if k < 1.0 else -100.0
	for m in builds:
		m.set_shader_parameter("build_y", build_y)
	scan_plane.visible = build_y > -50.0 and k > 0.0
	if scan_plane.visible:
		scan_plane.position.y = build_y
		scan_mat.set_shader_parameter("amount", 1.0)
	intro = maxf(0.0, intro - delta / 1.7)
	# The chapter's scene: the one going scatters fast, the one coming
	# streams in over 1.5 s (the points' own delays spread it).
	chapter = _want_ch()
	# A chapter past 2 bakes its points the first time it is wanted; it
	# streams in once they are there.
	for c in scenes:
		var sc = scenes[c]
		if sc.task >= 0 and WorkerThreadPool.is_task_completed(sc.task):
			WorkerThreadPool.wait_for_task_completion(sc.task)
			sc.task = -1
			_into = nodes[c]
			sc.finish()
			_into = null
		elif c == chapter and not sc.baked and sc.task < 0:
			sc.pc = Cloud.new()
			sc.pc.rng.seed = 200 + c
			sc.hc = Cloud.new()
			sc.hc.rng.seed = 300 + c
			sc.task = WorkerThreadPool.add_task(func() -> void: sc.bake(sc.pc, sc.hc), false, "campaign map %d" % c)
	for c in range(1, LAST + 1):
		var on: bool = c == chapter and (c <= 2 or scenes[c].baked)
		var f: float = move_toward(form[c], 1.0 if on else 0.0, delta / (1.5 if on else 0.9))
		if f != form[c]:
			form[c] = f
			for mt: ShaderMaterial in ch_mats[c]:
				mt.set_shader_parameter("form", f)
		nodes[c].visible = form[c] > 0.001
		if c >= 3 and nodes[c].visible:
			scenes[c].tick(time, delta)
	var sf := clampf(form[1] + form[2], 0.0, 1.0)
	if sf != form[0]:
		form[0] = sf
		for mt: ShaderMaterial in ch_mats[0]:
			mt.set_shader_parameter("form", sf)
	shaft_node.visible = sf > 0.001
	gtex.modulate.a = form[1]
	flow_mat.set_shader_parameter("amount", (1.0 if build_y < -50.0 else 0.6) * form[1])
	c2.tick(time, delta)
	# Stations: pop on with the build, then their state.
	for i in rings.size():
		var l: Dictionary = Levels.ALL[i]
		var open: bool = Levels.playable(l) and CampaignSave.unlocked(l.index)
		var done: bool = CampaignSave.stars(l.id)[0]
		var pk := _back(_pk(i))
		var s := (1.35 if i == sel else 1.0) * (1.12 if i == hover else 1.0) * pk
		var r := rings[i]
		r.position = _station3(i)
		r.scale = r.scale.lerp(Vector3.ONE * maxf(s, 0.001), minf(1.0, delta * 12.0)) if pk >= 1.0 else Vector3.ONE * maxf(s, 0.001)
		var m := ring_mats[i]
		var col: Color = Ui.ACCENT if open else Color(0.3, 0.45, 0.52)
		if done:
			col = Color(0.2, 0.75, 0.62)
		m.set_shader_parameter("tint", col)
		var e := 2.0 if open else 1.0
		if i == sel:
			e = 2.4 + 0.7 * (0.5 + 0.5 * sin(time * 3.2))
		m.set_shader_parameter("energy", e * (1.25 if i == hover else 1.0))
		m.set_shader_parameter("form", _shown(_chapter(i)))
		r.visible = _shown(_chapter(i)) > 0.01
	# The selected depth: the slice glides there and lights the cloud's
	# points at that depth; the dashed ring turns round it.
	slice_y = lerpf(slice_y, _station_y(sel), minf(1.0, delta * 6.0))
	slice.position.y = slice_y
	slice_a = move_toward(slice_a, 1.0 if build_y < -50.0 and descent < 0.0 and preview_ch == 0 else 0.0, delta * (2.0 if descent < 0.0 else 4.0))
	slice_mat.set_shader_parameter("amount", slice_a * (0.85 + 0.15 * sin(time * 2.0)))
	# The sweep: down the block every nine seconds, the laser loop riding it
	# (in the canyon, down from its water's top).
	var sw := fmod(time, 9.0) / 9.0
	if chapter == 1:
		sweep_y = 0.8 - sw * 9.5
	elif chapter == 2:
		sweep_y = -5.5 - sw * 5.4
	else:
		sweep_y = float(scenes[chapter].top) + 0.3 - sw * (float(scenes[chapter].top) - float(scenes[chapter].bottom) + 0.6)
	var sw_on := build_y < -50.0 and descent < 0.0
	for pm: ShaderMaterial in _pmats(false):
		pm.set_shader_parameter("slice_y", slice_y)
		pm.set_shader_parameter("slice_a", slice_a)
		pm.set_shader_parameter("sweep", 1.0 if sw_on else 0.0)
		pm.set_shader_parameter("sweep_y", sweep_y)
	var in_box := sweep_y < 0.0 and sweep_y > -FLOOR - 0.5
	sweep_rings[0].visible = sw_on and in_box and sweep_y > -ICE
	sweep_rings[1].visible = sw_on and in_box and sweep_y <= -ICE
	for r in sweep_rings:
		r.position.y = sweep_y
	sweep_mat.set_shader_parameter("tint", Color(0.2, 1.5, 1.8, 0.9 * smoothstep(0.0, 0.4, -sweep_y) * smoothstep(0.0, 0.4, sweep_y + FLOOR + 0.5)))
	for pm: ShaderMaterial in _pmats(true):
		pm.set_shader_parameter("px", _scale * 1.9)
	var sst := _station3(sel)
	sel_ring.position = Vector3(sst.x, slice_y, sst.z)
	sel_ring.rotation.y = time * 0.4
	sel_ring.scale = Vector3.ONE * (1.0 + 0.04 * sin(time * 3.2))
	sel_mat.set_shader_parameter("tint", Color(0.1, 0.95, 1.15, slice_a))
	var fy: float = float(scenes[preview_ch].focus) if preview_ch >= 3 else _focus_for(sel)
	focus_y = lerpf(focus_y, fy, minf(1.0, delta * 3.0))
	beacon_mat.set_shader_parameter("energy", 3.5 if fmod(time, 1.4) < 0.18 else 0.6)
	globe.rotation.y = 0.35 + sin(time * 0.11) * 0.45
	# Camera.
	if not dragging:
		yaw_drag = lerpf(yaw_drag, clampf(yaw_drag, -0.55, 0.55), minf(1.0, delta * 4.0))
	var want := Vector2.ZERO
	var mp := get_local_mouse_position() if GlassPanel.pointer.x > -1e4 else size * 0.5
	if Rect2(Vector2.ZERO, size).has_point(mp) and not dragging:
		want = (mp / size - Vector2(0.5, 0.5)) * Vector2(0.16, 0.08)
	lean = lean.lerp(want, minf(1.0, delta * 2.5))
	var ie := intro * intro * (3.0 - 2.0 * intro)
	var yaw := YAW + sin(time * 0.13) * 0.1 + yaw_drag + lean.x - ie * 0.55
	var pitch := clampf(PITCH + pitch_drag + lean.y + ie * 0.32, 0.05, 1.1)
	var dist := _blend(_scene_dist) + ie * 9.0 # (each map its own framing)
	var tgt := Vector3(_blend(_scene_x), focus_y, 0.0)
	if descent >= 0.0:
		descent += delta
		var dk := clampf(descent / DESCENT, 0.0, 1.0)
		var de := dk * dk * dk
		var st := _station3(sel)
		tgt = tgt.lerp(st, minf(1.0, dk * 1.6))
		dist = lerpf(dist, 6.5, de)
		pitch = lerpf(pitch, 0.3, de)
		drop.position = Vector3(st.x, lerpf(st.y + 3.0, st.y, minf(1.0, dk * 1.3) ** 2), st.z)
	cam.position = tgt + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * dist
	cam.look_at(tgt)
	var cd := cam.position.distance_to(tgt)
	for pm: ShaderMaterial in _pmats(true):
		pm.set_shader_parameter("fog", Vector2(cd - 2.5, cd + 5.0))
	_layout_labels()
	cam.v_offset = 0.55 * (1.0 - clampf(descent / DESCENT, 0.0, 1.0) if descent >= 0.0 else 1.0)
	overlay.queue_redraw()


static func _back(t: float) -> float:
	var x := clampf(t, 0.0, 1.0) - 1.0
	return 1.0 + 2.7 * x * x * x + 1.7 * x * x


static func _ease(t: float) -> float:
	return 1.0 - pow(1.0 - clampf(t, 0.0, 1.0), 3.0)


# --- input -----------------------------------------------------------------------

func _hit(at: Vector2) -> int:
	for i in Levels.ALL.size():
		if _chapter(i) != chapter:
			continue
		var c := station_pos(i)
		if c.distance_to(at) < 22.0 or Rect2(_label_at(i) - Vector2(26, ROW * 0.5), Vector2(296, ROW)).has_point(at):
			return i
	return -1


func _gui_input(event: InputEvent) -> void:
	if page.diving or not page.shown:
		return
	var mm := event as InputEventMouseMotion
	if mm:
		if dragging:
			yaw_drag -= mm.relative.x * 0.006
			pitch_drag = clampf(pitch_drag + mm.relative.y * 0.004, -0.25, 0.45)
			drag_moved += mm.relative.length()
			mouse_default_cursor_shape = Control.CURSOR_DRAG
			return
		hover = _hit(mm.position)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if hover >= 0 else Control.CURSOR_MOVE
		return
	var mb := event as InputEventMouseButton
	if mb and mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			var h := _hit(mb.position)
			if h >= 0:
				if h == sel and mb.double_click:
					page._start()
				else:
					page._select(h)
				return
			dragging = true
			drag_moved = 0.0
		else:
			dragging = false


# --- the 2D layer over it --------------------------------------------------------

func _fade(y: float) -> float:
	if build_y < -50.0:
		return form[1]
	return clampf((y - build_y) / 0.5, 0.0, 1.0) * form[1]


func _text(f: Font, at: Vector2, s: String, fs: int, col: Color, outline := 0.0) -> void:
	if outline > 0.0:
		overlay.draw_string_outline(f, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(1, 1, 1, outline * col.a))
	overlay.draw_string(f, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _draw_overlay() -> void:
	if cam == null:
		return
	var mono := Ui.mono("Medium")
	var sans6 := Ui.sans(600)
	# Layers, along the front left edge.
	var a := _fade(0.0)
	var p := _sp(Vector3(-HALF.x, 0, HALF.y))
	_text(mono, p + Vector2(-6, -12), "SURFACE  −160 °C", 10, Color(Ui.INK_FAINT, a), 0.8)
	for km in range(1, 7):
		var ka := _fade(-km)
		var q := _sp(Vector3(-HALF.x - 0.22, -km, HALF.y))
		_text(Ui.mono(), q + Vector2(-34, 4), "%d km" % km, 10, Color(Ui.INK_FAINT, ka), 0.8)
	var li := _sp(Vector3(-HALF.x, -0.45, HALF.y))
	a = _fade(-0.45)
	_text(sans6, li + Vector2(10, 0), "冰壳", 14, Color(Ui.INK, a), 0.7)
	_text(mono, li + Vector2(10, 15), "ICE SHELL  0 – 3.0 km", 10, Color(Ui.INK_SOFT, a), 0.7)
	var lo := _sp(Vector3(-HALF.x, -ICE - 0.45, HALF.y))
	a = _fade(-ICE - 0.45)
	_text(sans6, lo + Vector2(10, 0), "冰下海洋", 14, Color(Ui.INK, a), 0.7)
	_text(mono, lo + Vector2(10, 15), "SUBSURFACE OCEAN  +0 °C", 10, Color(Ui.INK_SOFT, a), 0.7)
	var lf := _sp(Vector3(-HALF.x, -FLOOR - 0.5, HALF.y))
	a = _fade(-FLOOR - 0.5)
	_text(sans6, lf + Vector2(4, 22), "海床 · 热液喷口", 13, Color(Ui.INK_SOFT, a), 0.7)
	_text(mono, lf + Vector2(4, 37), "SEAFLOOR · HYDROTHERMAL VENTS", 10, Color(Ui.INK_FAINT, a), 0.7)
	# The site's tag at the derrick, and the line from the globe.
	var top := _sp(Vector3(SHAFT.x, 1.1, SHAFT.y))
	a = _fade(0.0)
	var tag := top + Vector2(18, -26)
	overlay.draw_line(top, tag + Vector2(-4, 6), Color(Ui.ACCENT, 0.7 * a), 1.0, true)
	_text(sans6, tag, "钻探站 E-07", 13, Color(Ui.INK, a), 0.8)
	_text(mono, tag + Vector2(0, 14), "DRILL SITE  ·  ICE 3.0 km", 10, Color(Ui.ACCENT, a), 0.8)
	_draw_globe_frame(top, a)
	_draw_ch2_labels()
	for c in scenes:
		scenes[c].draw_labels(form[c])
	# Stations: the chapter on show (the other fading with its scene).
	for c in range(1, LAST + 1):
		_draw_list_plate(c)
	for i in Levels.ALL.size():
		_draw_station(i)
	# 进入实验: the dive's readout.
	if descent >= 0.0:
		var dk := clampf(descent / DESCENT, 0.0, 1.0)
		var c := station_pos(sel)
		var r := lerpf(60.0, 22.0, _ease(dk))
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				var q := c + Vector2(sx, sy) * r
				overlay.draw_line(q, q - Vector2(sx * 10, 0), Color(1.4, 2.4, 2.7), 1.5, true)
				overlay.draw_line(q, q - Vector2(0, sy * 10), Color(1.4, 2.4, 2.7), 1.5, true)
		_text(mono, c + Vector2(r + 8, -r), "DESCENT  %.2f km" % lerpf(0.0, -_station_y(sel), dk * dk), 11, Ui.ACCENT, 0.9)


# The point materials on show (with the holograms' when `holo`).
func _pmats(holo: bool) -> Array:
	var out := [point_mat, point_mat2]
	if holo:
		out.append(c2.holo_mat)
	for c in scenes:
		if nodes[c].visible:
			out.append(scenes[c].point_mat)
			if holo:
				out.append(scenes[c].holo_mat)
	return out


# Chapter 2's names: the depths down the front edge, the canyon, the
# tallest smoker, the hologram.
func _draw_ch2_labels() -> void:
	var a: float = form[2]
	if a <= 0.01 or not c2.baked:
		return
	var mono := Ui.mono("Medium")
	var sans6 := Ui.sans(600)
	for km in range(6, 11):
		var ka := a * (1.0 if build_y < -50.0 else clampf((-km - build_y) / 0.5, 0.0, 1.0))
		var q := _sp(Vector3(-HALF.x - 0.22, -km, HALF.y))
		_text(Ui.mono(), q + Vector2(-34, 4), "%d km" % km, 10, Color(Ui.INK_FAINT, ka), 0.8)
	var lc := _sp(Vector3(-HALF.x, Ch2.RIM - 0.3, HALF.y))
	_text(sans6, lc + Vector2(10, 0), "热液峡谷", 14, Color(Ui.INK, a), 0.7)
	_text(mono, lc + Vector2(10, 15), "HYDROTHERMAL CANYON  6.1 – 9.7 km", 10, Color(Ui.INK_SOFT, a), 0.7)
	if c2.tips.size() > 2:
		var tp := _sp(c2.tips[2] + Vector3(0, 0.15, 0))
		var tag := tp + Vector2(-150, -70)
		overlay.draw_line(tp, tag + Vector2(120, 8), Color(Ui.ACCENT, 0.7 * a), 1.0, true)
		overlay.draw_circle(tp, 2.5, Color(Ui.ACCENT, a))
		_text(sans6, tag, "黑烟囱", 13, Color(Ui.INK, a), 0.8)
		_text(mono, tag + Vector2(0, 14), "BLACK SMOKER  ·  350 °C", 10, Color(Ui.ACCENT, a), 0.8)
	var hp := _sp(Ch2.HOLO_C + Vector3(0, 1.0, 0))
	var ht := hp + Vector2(-190, -46)
	overlay.draw_line(hp, ht + Vector2(170, 8), Color(Ch2.PREDATOR, 0.7 * a), 1.0, true)
	overlay.draw_circle(hp, 2.5, Color(Ch2.PREDATOR, a))
	_text(sans6, ht, "捕食者全息 · 刺猎", 13, Color(Ui.INK, a), 0.8)
	_text(mono, ht + Vector2(0, 14), "PREDATOR SPECIMEN  ·  ×12 000", 10, Color(Ch2.PREDATOR, a), 0.8)


func _draw_globe_frame(site_to: Vector2, a: float) -> void:
	var r := Rect2(gtex.position, gtex.size)
	var col := Color(Ui.ACCENT, 0.7 * a)
	for c in [r.position, Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), r.end]:
		var sx := 1.0 if c.x == r.position.x else -1.0
		var sy := 1.0 if c.y == r.position.y else -1.0
		overlay.draw_line(c, c + Vector2(sx * 14, 0), col, 1.2, true)
		overlay.draw_line(c, c + Vector2(0, sy * 14), col, 1.2, true)
	# The globe's holographic rim.
	var gc := gcam.unproject_position(Vector3.ZERO)
	var gr := gc.distance_to(gcam.unproject_position(gcam.global_basis.x * 1.0))
	var k := gtex.size / Vector2(gvp.size)
	gc = gc * k + gtex.position
	gr *= k.x
	overlay.draw_arc(gc, gr + 1.0, 0.0, TAU, 96, Color(0.3, 1.5, 1.8, 0.8 * a), 1.2, true)
	overlay.draw_arc(gc, gr + 6.0, time * 0.3, time * 0.3 + PI * 1.2, 64, Color(Ui.ACCENT, 0.45 * a), 1.0, true)
	var mono := Ui.mono("Medium")
	_text(Ui.sans(600), r.position + Vector2(r.size.x + 14, 34), "木卫二  EUROPA", 13, Color(Ui.INK, a), 0.8)
	_text(mono, r.position + Vector2(r.size.x + 14, 49), "R 1561 km  ·  SITE 14.0°N 80.0°E", 10, Color(Ui.INK_FAINT, a), 0.8)
	# The marker on the globe, when it faces us, and the line down to the site.
	var wp := site.global_position
	if wp.dot((gcam.global_position - wp).normalized()) < 0.15:
		return
	var m := gcam.unproject_position(wp) * (gtex.size / Vector2(gvp.size)) + gtex.position
	var t := time * 2.0
	overlay.draw_arc(m, 7.0 + 3.0 * fposmod(t, 1.0), 0.0, TAU, 24, Color(Ui.ACCENT, (1.0 - fposmod(t, 1.0)) * a), 1.2, true)
	overlay.draw_arc(m, 5.0, 0.0, TAU, 20, Color(Ui.ACCENT, a), 1.2, true)
	var mid := Vector2(site_to.x, m.y)
	var pts := PackedVector2Array([m + Vector2(6, 0), mid, site_to + Vector2(0, -6)])
	overlay.draw_polyline(pts, Color(Ui.ACCENT, 0.45 * a), 1.0, true)
	var total := pts[0].distance_to(pts[1]) + pts[1].distance_to(pts[2])
	var run := fposmod(time * 160.0, total)
	var seg := pts[0].distance_to(pts[1])
	var dotp := pts[0].lerp(pts[1], run / seg) if run < seg else pts[1].lerp(pts[2], (run - seg) / maxf(1.0, total - seg))
	overlay.draw_circle(dotp, 2.2, Color(1.3, 2.3, 2.6, a))


func _draw_station(i: int) -> void:
	var k := _pk(i)
	if descent >= 0.0 and i != sel:
		k *= 1.0 - clampf(descent / (DESCENT * 0.5), 0.0, 1.0)
	k *= _shown(_chapter(i))
	if k <= 0.01 or station_pos(i).x < -1e4:
		return
	var l: Dictionary = Levels.ALL[i]
	var open: bool = Levels.playable(l) and CampaignSave.unlocked(l.index)
	var c := station_pos(i)
	var at := _label_at(i)
	var col := Ui.ACCENT if open else Ui.INK_FAINT
	var a := _ease(k)
	var x0 := at.x + 24.0 * (1.0 - a)
	var y := at.y
	var is_sel := i == sel
	if is_sel:
		# The selected row lit on the list's plate.
		overlay.draw_rect(Rect2(x0 - 24, y - 24, 296, 46), Color(Ui.ACCENT, 0.13 * a))
		overlay.draw_rect(Rect2(x0 - 24, y - 24, 2.5, 46), Color(Ui.ACCENT, a))
	elif i == hover:
		overlay.draw_rect(Rect2(x0 - 24, y - 24, 296, 46), Color(Ui.ACCENT, 0.06 * a))
	# Leader: out from the ring, then over to the label.
	var lead := PackedVector2Array([c + Vector2(15, 0), c + Vector2(26, 0), Vector2(x0 - 16, y)])
	overlay.draw_polyline(lead, Color(col, 0.65 * a), 1.0, true)
	overlay.draw_circle(Vector2(x0 - 16, y), 2.0, Color(col, a))
	_text(Ui.mono("SemiBold"), Vector2(x0, y - 5), l.id, 11, Color(col, a), 0.8)
	_text(Ui.sans(600 if is_sel else 500), Vector2(x0 + 34, y - 4), l.name, 17 if is_sel else 16, Color(Ui.INK if open else Ui.INK_SOFT, a))
	_text(Ui.mono(), Vector2(x0, y + 12), "%.1f km" % l.depth, 10, Color(Ui.INK_FAINT, a), 0.8)
	var st: Array = CampaignSave.stars(l.id)
	for s in 3:
		# Small five-point stars, the same mark as the card and the report.
		var d := Vector2(x0 + 200 + s * 17, y - 9)
		var dia := PackedVector2Array()
		for q in 10:
			var ang := -PI / 2.0 + q * PI / 5.0
			dia.append(d + Vector2(cos(ang), sin(ang)) * (6.5 if q % 2 == 0 else 2.7))
		if st[s]:
			overlay.draw_colored_polygon(dia, Color(Ui.ACCENT, a))
		else:
			dia.append(dia[0])
			overlay.draw_polyline(dia, Color(Ui.INK_SOFT, 0.6 * a), 1.0, true)
