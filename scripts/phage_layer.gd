extends Node2D
# Phages as a player sees them (level 15 on). In the water: specks from afar,
# zoomed in real phages drifting and tumbling (shaders/phage.gdshader; the
# kernel fills the buffer). On a cell, zoomed in, the whole infection plays
# on the kernel's own clock (seconds since landing, SimCore PHAGE_*):
#   0 – 1.2  planted on the membrane, tail fibres down
#   1.2 – 1.5  the sheath fires, the head drops, the tube goes through
#   1.5 – 2.2  the DNA runs down the tube and across to the nucleus
#   2.2 – burst  the nucleus turns, the DNA piles up, heads then tails then
#     fibres come together in the cytoplasm, the cell swells
#   burst  the membrane tears open all at once and shatters; the pieces curl
#     into little vesicles while the new phages (real particles) spill out
# An infected cell reddens all over as the burst nears (the kernel tints it),
# so it reads from afar with no mark of its own. Sizes are in world units
# unless the name says px.

const VirusBench := preload("res://scripts/ui/virus_bench.gd")
const ATTACH := 1.2
const CELL := 12 # floats per cell in SimCore.get_infected
const FIRE := 1.5
const INJECT := 2.2
const SIZE := 3.8 # a phage's quad side, µm
const BURST_T := 3.0
const TOTAL := 30 # new phages drawn in a cell
const NEW_SIDE := 2.0 # their quad side, µm
const FINE_ZOOM := 7.0 # from here the cell's insides are drawn in full
const CAP_INNER := 768
const SCENE_ZOOM := 1.8 # from here in the infection scene is drawn
const CAPTION_ZOOM := 7.0 # from here the cell in the middle of the view is captioned
# What a crowd may cost. Soft spots share one texture and batch into a single
# draw; lines and circles don't, and a wave of bursts ran past 10000 draws a
# frame (2026-11-01 "病毒一多就突然变得卡起来"). Up close nothing is lost.
const BURST_FINE_ZOOM := 3.5 # from here a burst shows its torn membrane
const BURST_DETAIL := 8 # ... on this many at once, the rest as soft spots
const SCENE_CAP := 60 # infected cells drawn inside per frame
const SFX_GAP := 0.09 # seconds between burst sounds
const TAG_TIME := 8.0 # seconds a named tag rides on its cell
const MARK_TIME := 4.0 # seconds a newly infected cell keeps its little mark
const MARK_CAP := 24
const STAGES := [["吸附", "尾丝抓住细胞膜"], ["注入", "尾鞘收缩，把 DNA 打进细胞"], ["复制", "细胞核被劫持，开始造新的病毒"], ["裂解", "细胞快被撑破了"]]
const STAGES_CUT := [["吸附", "尾丝抓住细胞膜"], ["注入", "尾鞘收缩，把 DNA 打进细胞"], ["剪碎", "剪刀蛋白沿着 DNA 爬，把它咬成几段"], ["记住", "留下一小段，存进自己的基因"]]
const STAGES_WOKEN := [["醒来", "日子变坏，基因里的潜伏针醒了"], ["切出", "它把自己从基因上剪下来，弯成一个环"], ["复制", "细胞核被劫持，开始造新的病毒"], ["裂解", "细胞快被撑破了"]]
const STAGES_RULE := [["醒来", "你的规则叫醒了它：这只细胞快老死了"], ["切出", "它把自己从基因上剪下来，弯成一个环"], ["复制", "细胞核被劫持，开始造新的病毒"], ["裂解", "细胞快被撑破了"]]
const STAGES_KNOWN := [["吸附", "尾丝抓住细胞膜"], ["注入", "尾鞘收缩，把 DNA 打进细胞"], ["认出", "它记得这段 DNA：一进来就剪"], ["没事", "碎片散了，细胞毫发无伤"]]
const STAGES_GIANT := [["吞下", "它把巨毒囊当成了食物"], ["开门", "星门打开，内核流进细胞"], ["工厂", "细胞里长出一座病毒工厂"], ["撑破", "工厂造满了，细胞快被撑破"]]
const STAGES_STOLEN := [["吞下", "它把巨毒囊当成了食物"], ["闯入", "噬毒体闯进工厂"], ["夺走", "工厂开始替噬毒体干活"], ["撑破", "放出来的多半是噬毒体"]]
const SNIP := 4.4 # the scissors bite (seconds on the first-time clock)
const CUT_NEW := 8.0 # SimCore PHAGE_CUT_NEW / OLD
const CUT_OLD := 3.6
const MEMORY := Color(0.12, 0.66, 0.6)
const LATENT := Color(0.5, 0.3, 0.82)
const WOKEN_OUT := 4.6 # the carried DNA is out of the genes by then
const CAP_FREE := 5000
const CAP_FIXED := 256
const DANGER := Color(0.84, 0.17, 0.34)
const INK := Color(0.33, 0.26, 0.52) # (glassy like the cells; same tones as phage.gdshader)
const SHELL := Color(0.74, 0.68, 0.88)

var host: Node2D
var zoom := 1.0
var alpha := 0.0
var cells := PackedFloat32Array() # SimCore.get_infected
var carriers := PackedFloat32Array() # SimCore.get_carriers, close up
var bursts: Array = [] # {pos, age, h, a, b, seed}
var tags: Array = [] # cells named on the dish: {id, text, col, age, pos, r}
var _sfx_wait := 0.0
var mat: ShaderMaterial
var free_mm: MultiMeshInstance2D
var fixed_mm: MultiMeshInstance2D
var inner_mm: MultiMeshInstance2D # phages being built inside cells
var inner_mat: ShaderMaterial
var t := 0.0
var _soft: GradientTexture2D # a soft round spot
var _caption_box := StyleBoxFlat.new()
var _cap := Node2D.new()


func _init() -> void:
	_caption_box.bg_color = Color(1.0, 1.0, 1.0, 0.93)
	_caption_box.set_corner_radius_all(4)
	_cap.z_index = 2
	_cap.draw.connect(_caption)
	add_child(_cap)
	mat = ShaderMaterial.new()
	mat.shader = preload("res://shaders/phage.gdshader")
	free_mm = _sprites(CAP_FREE) # (added under the cells by showcase.gd)
	fixed_mm = _sprites(CAP_FIXED)
	fixed_mm.z_index = 1
	add_child(fixed_mm)
	inner_mat = mat.duplicate()
	inner_mat.set_shader_parameter("inner", true)
	inner_mm = _sprites(CAP_INNER)
	inner_mm.material = inner_mat
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


# The look of the player's virus (level 18; level 19's is a virophage: a bare
# head); {} is the wild one.
func set_look(v: Dictionary, virophage := false) -> void:
	var look: Dictionary = VirusBench.look_of(v, virophage)
	for key: String in look:
		mat.set_shader_parameter(key, look[key])
		inner_mat.set_shader_parameter(key, look[key])


# Name a cell where it swims, for a few seconds: a thin line and a label, no
# ring and no camera move.
func tag_cell(id: int, text: String, col: Color) -> void:
	tags.append({id = id, text = text, col = col, age = 0.0, pos = Vector2.ZERO, r = 6.0})


func _sprites(capacity: int) -> MultiMeshInstance2D:
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = capacity
	mm.visible_instance_count = 0
	# (Refilled every frame: its computed bounds lag and the batch gets culled.)
	mm.custom_aabb = AABB(Vector3(-200.0, -200.0, -1.0), Vector3(2600.0, 2600.0, 2.0))
	var node := MultiMeshInstance2D.new()
	node.multimesh = mm
	node.material = mat
	return node


func tick(dt: float, a: float, view: Rect2, events: PackedFloat32Array) -> void:
	var sim: SimCore = host.sim
	zoom = host.cam.zoom.x
	alpha = a
	t += dt
	for k in range(0, events.size(), 6):
		if int(events[k]) == SimCore.EV_LYSIS:
			var p := Vector2(events[k + 1], events[k + 2])
			if view.grow(40.0).has_point(p):
				bursts.append({pos = p, age = 0.0, h = events[k + 5], r = events[k + 4], seed = randf() * 100.0})
				if zoom > 1.4 and _sfx_wait <= 0.0:
					_sfx_wait = SFX_GAP
					Audio.sfx("bubble", -5.0, randf_range(0.55, 0.75))
	_sfx_wait -= dt
	for b: Dictionary in bursts:
		b.age += dt
	bursts = bursts.filter(func(b: Dictionary) -> bool: return b.age < BURST_T)
	for tag: Dictionary in tags:
		tag.age += dt
		var info: Dictionary = sim.get_agent(tag.id)
		if info.is_empty():
			tag.age = TAG_TIME
		else:
			tag.pos = info.position
	tags = tags.filter(func(tag: Dictionary) -> bool: return tag.age < TAG_TIME)
	var near := view.grow(SIZE * 2.0)
	cells = sim.get_infected(near, a)
	carriers = sim.get_carriers(near, a) if zoom >= FINE_ZOOM else PackedFloat32Array()
	visible = sim.get_phage_count() > 0 or not cells.is_empty() or not bursts.is_empty() or not carriers.is_empty() or not tags.is_empty()
	free_mm.visible = visible
	if not visible:
		return
	mat.set_shader_parameter("px", 1.0 / zoom)
	inner_mat.set_shader_parameter("px", 1.0 / zoom)
	var side := maxf(SIZE, 6.0 / zoom)
	free_mm.multimesh.buffer = sim.build_phage_buffer(near, a, side, CAP_FREE)
	free_mm.multimesh.visible_instance_count = sim.get_phage_drawn()
	_plant_phages()
	_build_inner()
	queue_redraw()
	_cap.queue_redraw()


# Each infected cell's phage, planted where it landed.
func _plant_phages() -> void:
	var buf := PackedFloat32Array()
	buf.resize(CAP_FIXED * 12)
	buf.fill(0.0)
	var n := 0
	var side := SIZE
	if zoom >= SCENE_ZOOM:
		for k in range(0, cells.size(), CELL):
			if n >= CAP_FIXED:
				break
			if cells[k + 10] > 2.5:
				continue # (woken from inside: nothing on the membrane)
			var e := _edge(k)
			var nrm: Vector2 = e[1]
			var s := cells[k + 5]
			# It lands rocking, feeling for a receptor, then stands up.
			var settle := clampf(1.0 - s / ATTACH, 0.0, 1.0)
			nrm = nrm.rotated(0.45 * settle * settle * sin(s * 4.5 + cells[k + 6]))
			var pos: Vector2 = e[0] + nrm * side * 0.36
			var i := n * 12
			buf[i] = side
			buf[i + 3] = pos.x
			buf[i + 5] = side
			buf[i + 7] = pos.y
			buf[i + 8] = nrm.angle()
			buf[i + 9] = smoothstep(ATTACH, FIRE, s)
			buf[i + 10] = clampf((s - FIRE) / (INJECT - FIRE), 0.0, 1.0)
			# Beaten, the empty shell lets go.
			var fate := cells[k + 10]
			var left := 1.0 if fate < 0.5 else clampf(((CUT_NEW if fate < 1.5 else CUT_OLD) - s) / 1.2, 0.0, 1.0)
			buf[i + 11] = 0.5 + 0.5 * left * (0.99 if s < INJECT else 0.86)
			n += 1
	fixed_mm.multimesh.buffer = buf
	fixed_mm.multimesh.visible_instance_count = n


# Where the phage landed on cell k: world point on the membrane, world normal.
func _edge(k: int) -> Array:
	var c := Vector2(cells[k], cells[k + 1])
	var h := cells[k + 2]
	var sw := cells[k + 9]
	var ha := cells[k + 3] * sw
	var hb := cells[k + 4] * sw
	var d := Vector2.from_angle(cells[k + 6])
	var r := 1.0 / sqrt(d.x * d.x / (ha * ha) + d.y * d.y / (hb * hb))
	# (The drawn membrane breathes around this ellipse: the base sits just in.)
	return [c + (d * r * 0.93).rotated(h), d.rotated(h)]


func _draw() -> void:
	if not visible:
		return
	if not carriers.is_empty():
		_immune_strips()
	if zoom >= SCENE_ZOOM:
		var left := SCENE_CAP
		for k in range(0, cells.size(), CELL):
			if left <= 0:
				break
			if cells[k + 10] > 0.5 and cells[k + 10] < 2.5:
				_cut_scene(k)
				left -= 1
			elif cells[k + 10] < 3.5:
				_scene(k)
				left -= 1
	var detail := BURST_DETAIL if zoom >= BURST_FINE_ZOOM else 0
	for b: Dictionary in bursts:
		_burst(b, detail > 0)
		detail -= 1


# What is happening to the cell nearest the middle of the view, under it:
# the four steps with the current one lit (screen pixels). On a node of its
# own, above the scan's marks and the neighbouring cells.
func _caption() -> void:
	if not visible:
		return
	_marks()
	if zoom < CAPTION_ZOOM:
		return
	var mid: Vector2 = host.cam.position
	var best := -1
	# (Following one cell: only that cell, not a neighbour that wanders in.)
	var near: float = 14.0 if host.following else 90.0 / zoom * 3.0
	for k in range(0, cells.size(), CELL):
		var d := mid.distance_to(Vector2(cells[k], cells[k + 1]))
		if d < near:
			near = d
			best = k
	if best < 0:
		return
	var s := cells[best + 5]
	var burst := cells[best + 7]
	var fate := cells[best + 10]
	var marks := [0.0, ATTACH, INJECT, burst - 1.2, burst]
	var labels: Array = STAGES
	var hot := DANGER
	if fate > 3.5:
		var h0 := cells[best + 11]
		labels = STAGES_GIANT
		marks = [0.0, ATTACH, INJECT, burst - 1.2, burst]
		if h0 >= 0.0:
			var taken := minf(h0 + host.giant_layer.takeover, burst - 1.6)
			labels = STAGES_STOLEN
			hot = Color(0.06, 0.56, 0.52)
			marks = [0.0, minf(h0, taken - 0.4), taken, burst - 1.2, burst]
	elif fate > 2.5:
		marks = [INJECT, INJECT + 0.8, WOKEN_OUT, burst - 1.2, burst]
		labels = STAGES_RULE if cells[best + 6] > 0.5 else STAGES_WOKEN
	elif fate > 1.5:
		marks = [0.0, ATTACH, INJECT, 2.9, CUT_OLD]
		labels = STAGES_KNOWN
	elif fate > 0.5:
		marks = [0.0, ATTACH, INJECT, SNIP + 0.6, CUT_NEW]
		labels = STAGES_CUT
	var stage := 3
	for j in 3:
		if s < marks[j + 1]:
			stage = j
			break
	var f: Font = Ui.sans(600)
	var c := Vector2(cells[best], cells[best + 1])
	var below := maxf(cells[best + 3], cells[best + 4]) * cells[best + 9] * zoom + 26.0
	var cap := _cap
	cap.draw_set_transform(c, 0.0, Vector2.ONE / zoom)
	var step := 74.0
	var x0 := -step * 1.5
	cap.draw_style_box(_caption_box, Rect2(-158.0, below - 16.0, 316.0, 72.0))
	var dim := Color(INK, 0.32)
	for j in labels.size():
		var at := Vector2(x0 + step * j, below)
		var lit := smoothstep(marks[j], marks[j] + 0.3, s) if j > 0 else 1.0
		var col: Color = dim.lerp(hot, lit)
		# The line to the next step fills as this one runs.
		if j < 3:
			var done := clampf((s - marks[j]) / (marks[j + 1] - marks[j]), 0.0, 1.0)
			var from := at + Vector2(7.0, 0.0)
			var to := at + Vector2(step - 7.0, 0.0)
			cap.draw_line(from, to, dim, 1.5, true)
			if done > 0.0:
				cap.draw_line(from, from.lerp(to, done), hot, 1.5, true)
		cap.draw_circle(at, lerpf(3.0, 5.0, lit) if j == stage else 3.0, col)
		var w := f.get_string_size(labels[j][0], HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		cap.draw_string(f, at + Vector2(-w * 0.5, 22.0), labels[j][0], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)
	var line: String = labels[stage][1]
	var lw := f.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	var fade := smoothstep(marks[stage], marks[stage] + 0.35, s) if stage > 0 else 1.0
	cap.draw_string(f, Vector2(-lw * 0.5, below + 44.0), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.13, 0.16, 0.25, fade))


# Who has just been infected: a small chevron over each new case (screen
# pixels), and the named tags.
func _marks() -> void:
	var cap := _cap
	var shown := 0
	for k in range(0, cells.size(), CELL):
		var s := cells[k + 5]
		if s > MARK_TIME or shown >= MARK_CAP or cells[k + 10] == 3.0:
			continue
		shown += 1
		var fate := cells[k + 10]
		var col: Color = MEMORY if fate > 0.5 and fate < 2.5 else (Color(0.5, 0.3, 0.8) if fate > 3.5 else DANGER)
		var a := clampf(MARK_TIME - s, 0.0, 1.0)
		var y := -maxf(cells[k + 3], cells[k + 4]) * cells[k + 9] * zoom - 7.0 - 2.5 * sin(t * 4.0 + cells[k + 6])
		cap.draw_set_transform(Vector2(cells[k], cells[k + 1]), 0.0, Vector2.ONE / zoom)
		var pts := PackedVector2Array([Vector2(-6.0, y - 7.0), Vector2(0.0, y), Vector2(6.0, y - 7.0)])
		cap.draw_polyline(pts, Color(1.0, 1.0, 1.0, 0.8 * a), 4.2, true)
		cap.draw_polyline(pts, Color(col, a), 2.2, true)
	var f: Font = Ui.sans(600)
	for tag: Dictionary in tags:
		var a: float = clampf(TAG_TIME - float(tag.age), 0.0, 1.0)
		var col: Color = tag.col
		var r: float = maxf(6.0 * zoom, 7.0)
		var from := Vector2(r, -r) * 0.72
		var elbow := from + Vector2(26.0, -26.0)
		var w := f.get_string_size(tag.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		cap.draw_set_transform(tag.pos, 0.0, Vector2.ONE / zoom)
		cap.draw_polyline(PackedVector2Array([from, elbow, elbow + Vector2(14.0, 0.0)]), Color(col, a), 1.6, true)
		cap.draw_circle(from, 2.6, Color(col, a))
		cap.draw_rect(Rect2(elbow + Vector2(14.0, -13.0), Vector2(w + 16.0, 26.0)), Color(1.0, 1.0, 1.0, 0.92 * a))
		cap.draw_string(f, elbow + Vector2(22.0, 5.0), tag.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(col.darkened(0.25), a))
	cap.draw_set_transform(Vector2.ZERO)


# The inside of an infected cell, in the cell's own frame. The replication
# follows T4's: the nucleus turns, the phage's DNA piles up in a growing
# tangle, the cell's protein machinery (beaded strands) goes over to phage
# parts; heads bud off, take in a strand of DNA, and tails then fibres dock.
func _scene(k: int) -> void:
	var c := Vector2(cells[k], cells[k + 1])
	var h := cells[k + 2]
	var ha := cells[k + 3]
	var hb := cells[k + 4]
	var s := cells[k + 5]
	var burst := cells[k + 7]
	var sw := cells[k + 9]
	var seed := fposmod(cells[k + 6], TAU) * 13.0
	var rep := clampf((s - INJECT) / (burst - INJECT), 0.0, 1.0)
	var nuc := Vector2(-0.24 * ha, 0.0) * sw
	var nuc_r := 0.42 * minf(ha, hb) * sw
	var fine := zoom >= FINE_ZOOM
	draw_set_transform(c, h)
	if rep > 0.0:
		_cytoplasm(ha * sw, hb * sw, rep, seed)
		var turn := smoothstep(0.0, 0.2, rep)
		var beat := 0.5 + 0.5 * sin(t * 2.4)
		_soft_spot(nuc, nuc_r * (1.5 + 0.08 * beat), Color(DANGER, 0.5 * turn))
		if fine:
			_polysomes(ha * sw, hb * sw, rep, seed)
			_tangle(nuc, nuc_r, rep, seed)
			_packaging(ha * sw, hb * sw, nuc, nuc_r, rep, seed)
		else:
			var made := int(8.0 * smoothstep(0.3, 0.9, rep))
			for j in made:
				var fa := fposmod(j * 2.399963 + seed, TAU)
				var fr := sqrt((j + 0.5) / 8.0) * 0.8
				_soft_spot(Vector2(cos(fa) * ha * sw * fr, sin(fa) * hb * sw * fr), 0.7, Color(DANGER, 0.7))
	# The thread of DNA, from the phage to the nucleus, then drawn in.
	if cells[k + 10] > 2.5:
		_excise(nuc, nuc_r, s, seed)
	elif s >= FIRE and s < INJECT + 1.6:
		_thread(k, nuc, nuc_r, s, sw)
	# The last moments: holes open in the membrane, from the inside out.
	if rep > 0.86 and fine:
		_pores(ha * sw, hb * sw, smoothstep(0.86, 1.0, rep), seed)
	draw_set_transform(Vector2.ZERO)


func _soft_spot(at: Vector2, r: float, col: Color) -> void:
	draw_texture_rect(_soft, Rect2(at - Vector2.ONE * r, Vector2.ONE * r * 2.0), false, col)


# The cell's fluid, stirred up: pale patches slowly going round.
func _cytoplasm(a: float, b: float, rep: float, seed: float) -> void:
	for j in 4:
		var f := seed + j * 1.7
		var at := Vector2(cos(f + t * 0.17) * a * 0.55, sin(f * 1.3 + t * 0.13) * b * 0.55)
		_soft_spot(at, minf(a, b) * (0.55 + 0.12 * sin(f)), Color(DANGER.lightened(0.45), 0.1 + 0.14 * rep))


func _thread(k: int, nuc: Vector2, _nuc_r: float, s: float, sw: float) -> void:
	var ha := cells[k + 3] * sw
	var hb := cells[k + 4] * sw
	var d := Vector2.from_angle(cells[k + 6])
	var start := d * 0.93 / sqrt(d.x * d.x / (ha * ha) + d.y * d.y / (hb * hb))
	var reach := smoothstep(FIRE, INJECT, s) # how far its head has run
	var tail := smoothstep(INJECT, INJECT + 1.6, s) # how much has gone into the nucleus
	var to := nuc
	var across := (to - start).orthogonal().normalized()
	var pts := PackedVector2Array()
	for j in 81:
		var u := j / 80.0
		if u > reach:
			break
		if u < tail:
			continue
		var env := sin(u * PI)
		var wig := sin(u * 13.0 - t * 4.0) * 0.46 * env + sin(u * 31.0 + t * 2.6) * 0.13 * env
		pts.append(start.lerp(to, u) + across * wig)
	if pts.size() >= 2:
		draw_polyline(pts, Color(DANGER, 0.22), 0.38, true)
		draw_polyline(pts, DANGER, 0.11, true)
		_soft_spot(pts[-1], 0.42, Color(DANGER.lightened(0.35), 0.9))


# One point of the phage's DNA tangle (0..1 along it).
func _tangle_at(nuc: Vector2, r: float, u: float, seed: float, turns: float) -> Vector2:
	var f := u * TAU * turns + seed
	var rr := r * (0.28 + 0.5 * (0.5 + 0.5 * sin(f * 0.37 + seed + t * 0.13)) + 0.1 * sin(f * 2.3 - t * 0.21))
	return nuc + Vector2(cos(f + 0.4 * sin(f * 0.61 + t * 0.09)), sin(f * 0.97)) * rr


# The phage's DNA, copied over and over: a long tangle that thickens, its
# copying forks running along it.
func _tangle(nuc: Vector2, r: float, rep: float, seed: float) -> void:
	var grown := smoothstep(0.0, 0.5, rep)
	var turns := 1.5 + 9.0 * grown
	var n := 40 + int(320.0 * grown * clampf(zoom / 16.0, 0.4, 1.0)) # (fewer points farther out: a crowd of these is costly)
	var pts := PackedVector2Array()
	pts.resize(n)
	for j in n:
		pts[j] = _tangle_at(nuc, r, float(j) / (n - 1), seed, turns)
	var w := maxf(0.05, 0.8 / zoom)
	draw_polyline(pts, Color(DANGER.lightened(0.3), 0.3), w * 3.0, true)
	draw_polyline(pts, Color(DANGER.darkened(0.12), 0.9), w, true)
	for j in 3:
		var u := fposmod(t * 0.045 + j / 3.0 + seed, 1.0)
		_soft_spot(_tangle_at(nuc, r, u, seed, turns), 0.26, Color(1.0, 0.78, 0.84, 0.9))


# Protein factories: short strands strung with ribosomes, turning out parts.
func _polysomes(a: float, b: float, rep: float, seed: float) -> void:
	var on := smoothstep(0.05, 0.3, rep)
	var w := maxf(0.035, 0.6 / zoom)
	for j in 9:
		var f := seed * 1.3 + j * 2.399963
		var home := Vector2(cos(f) * a * 0.68, sin(f) * b * 0.68)
		home += Vector2(sin(t * 0.21 + f), cos(t * 0.17 + f * 1.4)) * 0.35
		var dir := Vector2.from_angle(f * 1.9 + 0.5 * sin(t * 0.19 + f))
		var side := dir.orthogonal()
		var pts := PackedVector2Array()
		for m in 15:
			var u := m / 14.0 - 0.5
			pts.append(home + dir * u * 1.8 + side * sin(u * 7.0 + t * 0.8 + f) * 0.2)
		draw_polyline(pts, Color(INK, 0.3 * on), w, true)
		for m in 5:
			var v := fposmod(m / 5.0 + t * 0.07, 1.0)
			draw_circle(pts[int(v * 14.0)], 0.09, Color(INK, 0.55 * on * sin(v * PI)))


# Strands of DNA reeled from the tangle into the heads filling now.
func _packaging(a: float, b: float, nuc: Vector2, nuc_r: float, rep: float, seed: float) -> void:
	var w := maxf(0.04, 0.7 / zoom)
	for j in TOTAL:
		var st := _new_phage(a, b, nuc, nuc_r, rep, seed, j)
		var fill: float = st[3]
		if float(st[2]) <= 0.0 or fill <= 0.0 or fill >= 1.0:
			continue
		var to: Vector2 = st[0]
		var from := nuc + (to - nuc).normalized() * nuc_r * 0.6
		var mid := from.lerp(to, 0.5) + (to - from).orthogonal().normalized() * sin(t * 0.9 + j) * 0.5
		var pts := PackedVector2Array()
		for m in 25:
			var u := m / 24.0
			pts.append(from.lerp(mid, u).lerp(mid.lerp(to, u), u))
		var a2 := sin(fill * PI)
		draw_polyline(pts, Color(DANGER, 0.75 * a2), w, true)
		var bead := fposmod(t * 1.2 + j * 0.37, 1.0)
		_soft_spot(pts[int(bead * 24.0)], 0.2, Color(1.0, 0.78, 0.84, 0.9 * a2))


# The j-th new phage of a cell, in the cell's frame: [position, angle, scale,
# DNA in the head 0..1, tail 0..1]. It buds at the nucleus and moves out to
# its place; they come slowly, then faster and faster.
func _new_phage(a: float, b: float, nuc: Vector2, nuc_r: float, rep: float, seed: float, j: int) -> Array:
	var born := 0.3 + 0.56 * pow(float(j) / TOTAL, 0.72)
	var f := float(j)
	var fa := fposmod(f * 2.399963 + seed, TAU)
	var fr := sqrt((f + 0.5) / TOTAL) * 0.86
	var home := Vector2(cos(fa) * a * fr, sin(fa) * b * fr)
	var off := home - nuc
	if off.length() < nuc_r * 1.1:
		home = nuc + off.normalized() * nuc_r * 1.1
	var scale := smoothstep(born, born + 0.05, rep)
	var start := nuc + (home - nuc).normalized() * nuc_r * 0.85
	var at := start.lerp(home, smoothstep(born, born + 0.2, rep))
	at += Vector2(sin(t * 0.7 + f * 1.3), cos(t * 0.6 + f * 2.1)) * 0.14
	at *= 1.0 + 0.05 * smoothstep(0.9, 1.0, rep) # crowded against the membrane
	return [at, fa + f + 0.6 * sin(t * 0.3 + f), scale, smoothstep(born + 0.03, born + 0.1, rep), smoothstep(born + 0.09, born + 0.17, rep)]


# Every new phage in view as a sprite (phage.gdshader, inner = true), and the
# loose tails waiting for a head.
func _build_inner() -> void:
	var buf := PackedFloat32Array()
	buf.resize(CAP_INNER * 12)
	buf.fill(0.0)
	var n := 0
	if zoom >= FINE_ZOOM:
		for k in range(0, cells.size(), CELL):
			var s := cells[k + 5]
			var burst := cells[k + 7]
			if s < INJECT or (cells[k + 10] > 0.5 and cells[k + 10] < 2.5) or cells[k + 10] > 3.5:
				continue
			var rep := clampf((s - INJECT) / (burst - INJECT), 0.0, 1.0)
			var sw := cells[k + 9]
			var a := cells[k + 3] * sw
			var b := cells[k + 4] * sw
			var c := Vector2(cells[k], cells[k + 1])
			var h := cells[k + 2]
			var seed := fposmod(cells[k + 6], TAU) * 13.0
			var nuc := Vector2(-0.24 * cells[k + 3], 0.0) * sw
			var nuc_r := 0.42 * minf(cells[k + 3], cells[k + 4]) * sw
			for j in TOTAL:
				if n >= CAP_INNER:
					break
				var st := _new_phage(a, b, nuc, nuc_r, rep, seed, j)
				var scale: float = st[2]
				if scale <= 0.0:
					continue
				var at: Vector2 = c + (st[0] as Vector2).rotated(h)
				_put_inner(buf, n, at, fposmod(float(st[1]) + h, TAU), NEW_SIDE * (0.5 + 0.5 * scale), st[4], 1.0 - float(st[3]), 0.49 * scale)
				n += 1
			# Loose tails: they thin out as heads take them.
			var on := smoothstep(0.2, 0.4, rep) * (1.0 - smoothstep(0.75, 0.95, rep))
			for j in 8:
				if n >= CAP_INNER or on <= 0.0:
					break
				var f := seed + j * 2.399963
				var at := Vector2(cos(f) * a * 0.6, sin(f) * b * 0.6) + Vector2(sin(t * 0.33 + f), cos(t * 0.29 + f)) * 0.5
				_put_inner(buf, n, c + at.rotated(h), 20.0 + fposmod(f * 3.0 + 0.5 * sin(t * 0.3 + f) + h, TAU), NEW_SIDE, 1.0, 0.0, 0.49 * on)
				n += 1
	inner_mm.multimesh.buffer = buf
	inner_mm.multimesh.visible_instance_count = n


func _put_inner(buf: PackedFloat32Array, n: int, at: Vector2, ang: float, side: float, tail: float, empty: float, a: float) -> void:
	var i := n * 12
	buf[i] = side
	buf[i + 3] = at.x
	buf[i + 5] = side
	buf[i + 7] = at.y
	buf[i + 8] = ang
	buf[i + 9] = tail
	buf[i + 10] = empty
	buf[i + 11] = a


# The holin's holes: soft light through the membrane, spreading.
func _pores(a: float, b: float, u: float, seed: float) -> void:
	for j in 10:
		var f := seed + j * 2.399963
		var open := smoothstep(0.1 * (j % 5), 0.1 * (j % 5) + 0.6, u)
		if open <= 0.0:
			continue
		_soft_spot(Vector2(cos(f) * a, sin(f) * b), 0.5 + 1.1 * open, Color(1.0, 0.94, 0.96, 0.8 * open))


# A cell beating the phage (level 16). The DNA comes in as usual, but stops
# short of the nucleus; scissor proteins (Cas) crawl along it and bite it to
# pieces. The first time, one piece is carried to the nucleus and set into
# the cell's own memory strip; with the memory there, it all goes faster and
# nothing is kept.
func _cut_scene(k: int) -> void:
	var c := Vector2(cells[k], cells[k + 1])
	var h := cells[k + 2]
	var sw := cells[k + 9]
	var ha := cells[k + 3] * sw
	var hb := cells[k + 4] * sw
	var first := cells[k + 10] < 1.5
	var s := cells[k + 5]
	# (The known phage runs through the same steps three times as fast.)
	var u := s if first or s < INJECT else INJECT + (s - INJECT) * 3.0
	var nuc := Vector2(-0.24 * ha, 0.0)
	var nuc_r := 0.42 * minf(ha, hb)
	var d := Vector2.from_angle(cells[k + 6])
	var start := d * 0.93 / sqrt(d.x * d.x / (ha * ha) + d.y * d.y / (hb * hb))
	var end := start.lerp(nuc, 0.72)
	draw_set_transform(c, h)
	var reach := smoothstep(FIRE, INJECT, u)
	var across := (end - start).orthogonal().normalized()
	var line := func(a: float) -> Vector2:
		var env := sin(a * PI)
		return start.lerp(end, a) + across * (sin(a * 11.0 - t * 2.4) * 0.34 * env + sin(a * 27.0 + t * 1.7) * 0.1 * env)
	if u < SNIP:
		var pts := PackedVector2Array()
		for j in 61:
			var a := j / 60.0
			if a > reach:
				break
			pts.append(line.call(a))
		if pts.size() >= 2:
			draw_polyline(pts, Color(DANGER, 0.22), 0.55, true)
			draw_polyline(pts, DANGER, 0.17, true)
	else:
		_pieces(line, across, nuc, nuc_r, u, first)
	# The scissors come in from the cytoplasm and walk the strand.
	var off := 1.0 - smoothstep(SNIP + 0.5, SNIP + 1.8, u)
	if u >= INJECT and off > 0.0:
		for j in 4:
			var want := 0.14 + 0.24 * j
			var run := smoothstep(INJECT + 0.15 * j, SNIP - 0.3, u)
			var side := Vector2.from_angle(cells[k + 6] + 1.2 + j * 1.9) * minf(ha, hb) * 0.8
			var at: Vector2 = side.lerp(line.call(want), smoothstep(0.0, 0.6, run))
			var ahead := (line.call(want + 0.04) - line.call(want - 0.04)).normalized() as Vector2
			var bite := smoothstep(SNIP - 0.25, SNIP, u) * (1.0 - smoothstep(SNIP + 0.25, SNIP + 0.6, u))
			_cas(at + ahead.orthogonal() * 0.12, ahead.orthogonal(), bite, off)
	if first:
		var store := smoothstep(SNIP + 2.6, 7.0, u)
		_memory_strip(nuc, nuc_r, smoothstep(SNIP, SNIP + 1.0, u), store)
		var glow := smoothstep(7.0, 7.4, u) * (1.0 - smoothstep(7.4, 8.0, u))
		if glow > 0.0:
			_soft_spot(nuc, nuc_r * 2.4, Color(MEMORY, 0.55 * glow))
	draw_set_transform(Vector2.ZERO)


# After the bite: five pieces drift apart and dissolve; the middle one, the
# first time, is carried over to the memory strip.
func _pieces(line: Callable, across: Vector2, nuc: Vector2, nuc_r: float, u: float, first: bool) -> void:
	var apart := smoothstep(SNIP, SNIP + 1.2, u)
	var gone := 1.0 - smoothstep(SNIP + 1.0, SNIP + 2.4, u)
	var goal: Vector2 = _strip_at(nuc, nuc_r, 1)
	for j in 5:
		var kept := first and j == 2
		var a0 := j / 5.0 + 0.012
		var a1 := (j + 1) / 5.0 - 0.012
		var mid: Vector2 = line.call((a0 + a1) * 0.5)
		var fly := across * (j - 2) * 0.55 * apart + Vector2(sin(j * 2.3 + t * 0.4), cos(j * 1.7 + t * 0.5)) * 0.2 * apart
		var move := smoothstep(SNIP + 0.8, SNIP + 2.6, u) if kept else 0.0
		var shrink := 1.0 - 0.75 * move
		var pts := PackedVector2Array()
		for m in 13:
			var p: Vector2 = line.call(lerpf(a0, a1, m / 12.0))
			pts.append(mid.lerp(goal, move) + fly * (1.0 - move) + (p - mid) * shrink)
		var o := 1.0 if kept else gone
		if o <= 0.0:
			continue
		draw_polyline(pts, Color(DANGER, 0.22 * o), 0.5, true)
		draw_polyline(pts, Color(DANGER, o), 0.17, true)
		if kept:
			_soft_spot(pts[6], 0.8, Color(MEMORY.lightened(0.3), 0.8 * move))


# A scissor protein: a round body and two jaws, closing as `bite` goes to 1.
func _cas(at: Vector2, dir: Vector2, bite: float, a: float) -> void:
	_soft_spot(at - dir * 0.22, 1.0, Color(MEMORY, 0.3 * a))
	draw_circle(at - dir * 0.22, 0.42, Color(MEMORY, 0.65 * a))
	var w := maxf(0.11, 1.4 / zoom)
	for j in 2:
		var sign := 1.0 if j == 0 else -1.0
		var f := sign * lerpf(0.75, 0.1, bite)
		var pts := PackedVector2Array()
		for m in 7:
			var v := m / 6.0
			pts.append(at + dir.rotated(f * (1.0 - 0.45 * v) + sign * 0.5 * sin(v * PI) * (1.0 - bite)) * 0.95 * v)
		draw_polyline(pts, Color(MEMORY.darkened(0.25), a), w, true)


# Where element m of a cell's memory strip sits.
func _strip_at(nuc: Vector2, nuc_r: float, m: int) -> Vector2:
	return nuc + Vector2.from_angle(-2.25 + 0.22 * m) * nuc_r * 1.22


# The memory strip: repeats and stored pieces of DNA, by the nucleus.
func _memory_strip(nuc: Vector2, nuc_r: float, a: float, fresh: float) -> void:
	if a <= 0.0:
		return
	var w := maxf(0.1, 1.5 / zoom)
	var pts := PackedVector2Array()
	for m in 41:
		pts.append(nuc + Vector2.from_angle(-2.25 + 0.22 * 8.0 * m / 40.0) * nuc_r * 1.22)
	draw_polyline(pts, Color(MEMORY, 0.35 * a), 0.34, true)
	for m in 9:
		var at := _strip_at(nuc, nuc_r, m)
		if m % 2 == 0:
			draw_circle(at, 0.15, Color(MEMORY.darkened(0.2), 0.95 * a))
		else:
			var len := 0.26 * (fresh if m == 1 else 1.0)
			if len <= 0.0:
				continue
			var along := (at - nuc).orthogonal().normalized()
			draw_line(at - along * len, at + along * len, Color(DANGER, 0.95 * a), w, true)


# Every cell with the memory wears the strip by its nucleus; a cell carrying
# a phage has a violet stretch on its DNA.
func _immune_strips() -> void:
	for k in range(0, carriers.size(), 6):
		var ha := carriers[k + 3]
		var hb := carriers[k + 4]
		var nuc := Vector2(-0.24 * ha, 0.0)
		var nuc_r := 0.42 * minf(ha, hb)
		draw_set_transform(Vector2(carriers[k], carriers[k + 1]), carriers[k + 2])
		if carriers[k + 5] > 0.5:
			_latent_mark(nuc, nuc_r, 1.0)
		else:
			_memory_strip(nuc, nuc_r, 1.0, 1.0)
	draw_set_transform(Vector2.ZERO)


# The phage's stretch of DNA, lying along the cell's own.
func _latent_mark(nuc: Vector2, r: float, a: float) -> void:
	var w := maxf(0.13, 1.8 / zoom)
	var pts := PackedVector2Array()
	for m in 21:
		var v := m / 20.0
		pts.append(nuc + Vector2.from_angle(-0.9 + 1.8 * v) * r * (0.62 + 0.05 * sin(v * 18.0 + t * 0.8)))
	draw_polyline(pts, Color(LATENT, 0.28 * a), w * 2.6, true)
	draw_polyline(pts, Color(LATENT, 0.95 * a), w, true)


# Woken: the stretch lifts off the DNA, curls into a ring, and is copied.
func _excise(nuc: Vector2, r: float, s: float, seed: float) -> void:
	var u := smoothstep(INJECT, WOKEN_OUT, s)
	var o := 1.0 - smoothstep(WOKEN_OUT, WOKEN_OUT + 1.6, s)
	if o <= 0.0:
		return
	var w := maxf(0.13, 1.8 / zoom)
	var span := lerpf(1.8, TAU, u)
	var rho := lerpf(r * 0.62, r * 0.62 * 1.8 / TAU, u)
	var centre := nuc + Vector2.RIGHT.rotated(sin(seed)) * r * lerpf(0.0, 0.75, u)
	var pts := PackedVector2Array()
	for m in 41:
		var v := m / 40.0
		pts.append(centre + Vector2.from_angle(-span * 0.5 + span * v + t * 0.6 * u) * rho)
	draw_polyline(pts, Color(LATENT, 0.28 * o), w * 2.6, true)
	draw_polyline(pts, Color(LATENT, 0.95 * o), w, true)
	if u > 0.6:
		_soft_spot(centre, 0.9, Color(LATENT.lightened(0.3), 0.5 * o))


# The burst: a flash, the torn membrane flying apart, the cell's insides
# spilling out (the new phages are real particles, already on their way).
func _burst(b: Dictionary, fine: bool) -> void:
	var u: float = b.age / BURST_T
	var fade := 1.0 - u
	var pos: Vector2 = b.pos
	var r: float = b.r
	var out := 1.0 - exp(-1.6 * b.age)
	if zoom < 0.7:
		_soft_spot(pos, r * (2.0 + 3.6 * out), Color(DANGER.lightened(0.4), fade * fade * 0.4))
		return
	# The cell's insides, still cell-shaped for a moment, then thinning out.
	var flash: float = clampf(1.0 - b.age / 0.5, 0.0, 1.0)
	if flash > 0.0:
		_soft_spot(pos, r * (1.6 + 0.4 * (1.0 - flash)), Color(1.0, 0.86, 0.9, flash * flash * 0.7))
	# Cytoplasm: a pale cloud thinning out.
	_soft_spot(pos, r * (1.7 + 1.6 * out), Color(DANGER.lightened(0.5), fade * fade * 0.26))
	var seed: float = b.seed
	if not fine:
		# From afar: the same bits, as soft spots flying out.
		for j in 5:
			var f := seed + j * 2.399963
			var dir := Vector2.from_angle(j * TAU / 5.0 + sin(f) * 0.4)
			_soft_spot(pos + dir * r * (1.0 + 1.3 * out), r * 0.3, Color(INK, fade * 0.5))
		return
	var w := maxf(0.14, 1.2 / zoom)
	# The membrane shatters; each piece curls up on itself into a little
	# closed vesicle as it drifts off (seen in T4 lysis under the microscope).
	for j in 11:
		var f := seed + j * 2.399963
		var dir := Vector2.from_angle(j * TAU / 11.0 + sin(f) * 0.25)
		var dist := r * (1.0 + (0.5 + 0.8 * fposmod(f, 1.0)) * out)
		var span := 0.42 + 0.22 * sin(f * 2.0)
		var curl := smoothstep(0.1, 0.75, u)
		var rho := lerpf(r, r * span / TAU, curl) # same length, tighter and tighter
		var sweep := r * span / rho
		var centre := pos + dir * (dist - rho)
		var pts := PackedVector2Array()
		for m in 10:
			pts.append(centre + dir.rotated(-sweep * 0.5 + sweep * m / 9.0 + out * 1.4 * sin(f * 3.0)) * rho)
		draw_polyline(pts, Color(INK, fade * 0.75), w, true)
	for j in 14:
		var f := seed * 0.7 + j * 1.618
		var dir := Vector2.from_angle(f * 2.1)
		_soft_spot(pos + dir * r * (0.3 + (0.7 + 1.0 * fposmod(f, 1.0)) * out), maxf(0.2, 1.6 / zoom), Color(DANGER.lightened(0.3), fade * 0.5))
