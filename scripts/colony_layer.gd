extends Node2D
# The bodies of level 21 as a player sees them: each species' jelly (baked from
# its blueprint, shaders/colony_skin.gdshader), the blocks and the grit
# (shaders/colony.gdshader, the kernel fills the buffers), and fine streaks in
# the water, so the stream can be seen before anything is swept by it.

const CAP_BLOCKS := 4096
const CAP_SKINS := 400
const STREAKS := 90
const SKIN_TEX := 96

var host: Node2D
var blocks_mat: ShaderMaterial
var blocks: MultiMeshInstance2D
var skin_mat: ShaderMaterial
var skin: MultiMeshInstance2D
var skin_sp := -1
var body_r := 50.0 # the blueprint's reach from its middle (for the marks above it)
var worn := PackedFloat32Array()
var heal_s := 120.0 # seconds a cracked armour block takes to regrow in this body
var streaks := PackedVector2Array()
var streak_life := PackedFloat32Array()
var stream := Vector2.ZERO
var t := 0.0


static func sprites(capacity: int, mat: ShaderMaterial) -> MultiMeshInstance2D:
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = capacity
	mm.visible_instance_count = 0
	mm.custom_aabb = AABB(Vector3(-200.0, -200.0, -1.0), Vector3(2600.0, 2600.0, 2.0))
	var node := MultiMeshInstance2D.new()
	node.multimesh = mm
	node.material = mat
	return node


func _init() -> void:
	blocks_mat = ShaderMaterial.new()
	blocks_mat.shader = preload("res://shaders/colony.gdshader")
	blocks_mat.set_shader_parameter("seeds", Colony.embryo_seeds())
	blocks_mat.set_shader_parameter("gon", Colony.embryo_gonidia())
	skin_mat = ShaderMaterial.new()
	skin_mat.shader = preload("res://shaders/colony_skin.gdshader")
	skin = sprites(CAP_SKINS, skin_mat)
	blocks = sprites(CAP_BLOCKS, blocks_mat)
	add_child(skin)
	add_child(blocks)
	visible = false


func _setup_skin(cells: Array) -> void:
	skin_mat.set_shader_parameter("skin", Colony.bake_skin(cells, SKIN_TEX))
	skin_mat.set_shader_parameter("side", Colony.skin_side(cells))
	skin_mat.set_shader_parameter("range", Colony.SKIN_RANGE)


func tick(dt: float, a: float, view: Rect2) -> void:
	var lr: Node = host.level_runner
	var on: bool = lr != null and lr.level.has("colony")
	visible = on
	if not on:
		skin_sp = -1
		return
	stream = lr.level.colony.stream
	var zoom: float = host.cam.zoom.x
	t += dt
	var sim: SimCore = host.sim
	if lr.phase == "run" and lr.sp_index >= 0:
		if skin_sp != lr.sp_index:
			skin_sp = lr.sp_index
			_setup_skin(lr.design.params.blocks)
			body_r = _reach(lr.design.params.blocks)
			var regen: float = lr.level.colony.get("regen", 1.0) if int(Colony.stats(lr.design.params.blocks).regen) > 0 else 1.0
			heal_s = float(lr.level.colony.get("regrow", 120.0)) / regen
		blocks_mat.set_shader_parameter("px", 1.0 / zoom)
		skin_mat.set_shader_parameter("px", 1.0 / zoom)
		skin.multimesh.buffer = sim.build_colony_skins(skin_sp, view, a, CAP_SKINS)
		skin.multimesh.visible_instance_count = sim.get_colony_drawn()
		blocks.multimesh.buffer = sim.build_colony_blocks(view, a, t, CAP_BLOCKS)
		blocks.multimesh.visible_instance_count = sim.get_colony_drawn()
		worn = sim.get_worn(a) if lr.level.id == "5-5" else PackedFloat32Array()
	elif lr.phase != "done":
		# Designing or releasing: nothing of ours is in the dish yet, so the
		# buffers still hold the last try's bodies. Hide them, and bake the new
		# blueprint's jelly once it is out.
		skin_sp = -1
		skin.multimesh.visible_instance_count = 0
		blocks.multimesh.visible_instance_count = 0
	_tick_streaks(dt)
	queue_redraw()


# The dish's centre and rim are fixed (LevelEval.prepare).
func _tick_streaks(dt: float) -> void:
	if streaks.is_empty():
		streaks.resize(STREAKS)
		streak_life.resize(STREAKS)
		for k in STREAKS:
			streaks[k] = _anywhere()
			streak_life[k] = randf()
	for k in STREAKS:
		streaks[k] += stream * 1.5 * dt
		streak_life[k] += dt / 7.0
		if streak_life[k] >= 1.0:
			streak_life[k] = 0.0
			streaks[k] = _anywhere()


# Where the next hunters come in (levels 22-23, "hunt_waves"), for the
# seconds they are announced: a soft red spot breathing, how many, how soon.
func _hunters_due() -> void:
	var lr: Node = host.level_runner
	if lr == null or lr.eval == null:
		return
	var zoom: float = host.cam.zoom.x
	for e: Dictionary in lr.level.get("events", []):
		if e.kind != "hunt_waves":
			continue
		for w in range(1, e.waves.size()):
			var wave: Array = e.waves[w]
			var left: float = float(wave[0]) - float(lr.eval.t)
			if left <= 0.0 or left > float(e.warn):
				continue
			var at: Vector2 = wave[2]
			var beat := 0.5 + 0.5 * sin(t * 3.0)
			if _soft == null:
				_soft = _soft_tex()
			draw_texture_rect(_soft, Rect2(at - Vector2.ONE * 150.0, Vector2.ONE * 300.0), false, Color(0.86, 0.3, 0.45, 0.16 + 0.14 * beat))
			draw_arc(at, 60.0 + 30.0 * (1.0 - fposmod(t * 0.8, 1.0)), 0.0, TAU, 48, Color(0.95, 0.4, 0.5, 0.5 * fposmod(t * 0.8, 1.0)), 2.0 / zoom, true)
			draw_set_transform(at, 0.0, Vector2.ONE / zoom)
			var txt := "巨噬者陆续增到 %d 只　%d 秒后" % [int(wave[1]), ceili(left)]
			var f: Font = Ui.sans(600)
			var tw := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
			draw_string(f, Vector2(-tw * 0.5, 5.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.75, 0.18, 0.32))
			draw_set_transform(Vector2.ZERO)


# Level 24: over each body whose rim armour the guardian cracked, a small
# crack and how far the armour has grown back (swallowed again before it is
# whole, it is eaten).
func _worn_marks() -> void:
	if worn.is_empty():
		return
	var zoom: float = host.cam.zoom.x
	var amber := Color(0.86, 0.56, 0.2)
	var f: Font = Ui.sans(600)
	for k in range(0, worn.size(), 5):
		var at := Vector2(worn[k], worn[k + 1])
		var cracked := int(worn[k + 2])
		var grown := worn[k + 3]
		var spurn := worn[k + 4]
		draw_set_transform(at + Vector2(0.0, -body_r - 6.0 / zoom), 0.0, Vector2.ONE / zoom)
		# The crack: a jagged stroke, a tick of the cracked shell.
		var zig := PackedVector2Array([Vector2(-23, -14), Vector2(-19, -8), Vector2(-22, -4), Vector2(-17, 2)])
		draw_polyline(zig, amber, 2.0, true)
		var txt := "裂甲" if cracked == 1 else "裂甲 ×%d" % cracked
		# Just spat out, it is left alone for a while; after that, until the
		# armour is whole, it is the one to keep away.
		var rot: PackedFloat32Array = host.sim.get_rotifers(1.0)
		var reach := rot.size() >= 6 and at.distance_to(Vector2(rot[0], rot[1]) + Vector2.from_angle(rot[2]) * 88.0) < 450.0
		var heal := "约 %d 秒长好" % ceili((1.0 - grown) * heal_s)
		if spurn > 0.0:
			txt += "　%d 秒内不吸" % ceili(spurn)
		elif reach:
			txt += "　危险 · " + heal
		else:
			txt += "　" + heal
		draw_string(f, Vector2(-12, -2), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.82, 0.28, 0.24) if spurn <= 0.0 and reach else amber)
		# Grown back: a hairline that fills.
		draw_rect(Rect2(-23, 5, 46, 3), Color(amber, 0.25))
		draw_rect(Rect2(-23, 5, 46.0 * grown, 3), amber)
	draw_set_transform(Vector2.ZERO)


static func _reach(cells: Array) -> float:
	if cells.is_empty():
		return 50.0
	var mid := Vector2.ZERO
	for c: Array in cells:
		mid += Vector2(c[0], c[1])
	mid /= cells.size()
	var r := 0.0
	for c: Array in cells:
		r = maxf(r, (Vector2(c[0], c[1]) - mid).length())
	return (r + 0.5) * Colony.BLOCK


var _soft: Texture2D


static func _soft_tex() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	return tex


func _anywhere() -> Vector2:
	return Vector2(1100, 1100) + Vector2.from_angle(randf() * TAU) * sqrt(randf()) * 1040.0


func _draw() -> void:
	_hunters_due()
	_worn_marks()
	if streaks.is_empty():
		return
	var d := stream.normalized()
	var lines := PackedVector2Array()
	var cols := PackedColorArray()
	var zoom: float = host.cam.zoom.x
	var length := 26.0 + 16.0 / zoom
	for k in STREAKS:
		var f := sin(PI * streak_life[k])
		if f < 0.1:
			continue
		var p := streaks[k]
		lines.append(p)
		lines.append(p - d * length * (0.6 + 0.8 * fposmod(k * 0.37, 1.0)))
		cols.append(Color(0.2, 0.42, 0.56, 0.3 * f))
	draw_multiline_colors(lines, cols, 1.3 / zoom)
