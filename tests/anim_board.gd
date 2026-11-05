extends SceneTree
# Every behaviour animation side by side, drawn straight through the organism
# shader with forced states (no simulation): idle, feeding, hunting, biting,
# fleeing, hurt; a division at four moments; a dying shell at four moments;
# and one cell at macro / group / micro size. Saves proofs/anim_board_*.png.
# Run: tools/run_test.sh tests/anim_board.gd

const CELL := Color(0.42, 0.8, 0.88)
const HUNTER := Color(0.95, 0.55, 0.45)
const SIZE := 250.0


var mm: MultiMesh
var n := 0
var labels: Array = []


func _initialize() -> void:
	root.add_child(preload("res://tests/test_window.gd").new())
	_run.call_deferred()


# kind as the kernel packs it: (speed in 5 bits + 32 * lineage signature
# + 1024 * stroke phase in 12 bits) / 2^22; the stroke runs with real time.
func _kind(speed: float, sig: int) -> float:
	var ph := float(int(fposmod(Time.get_ticks_msec() / 1000.0 * 6.0, TAU) / TAU * 4096.0) & 4095)
	return (round(speed * 31.0) + 32.0 * sig + 1024.0 * ph) / 4194304.0


func _add(pos: Vector2, size: float, col: Color, kind: float, cy: float, cz: float, cw: float, text: String) -> void:
	mm.set_instance_transform_2d(n, Transform2D(0.0, Vector2(size, size), 0.0, pos))
	mm.set_instance_color(n, Color(col, kind))
	mm.set_instance_custom_data(n, Color(-0.5 + 8.0 * float(n + 2), cy, cz, cw))
	n += 1
	var l := Label.new()
	l.text = text
	l.visible = text != ""
	l.position = pos + Vector2(-60, size * 0.36)
	l.add_theme_color_override("font_color", Color(0.2, 0.3, 0.35))
	labels.append(l)


func _cell(pos: Vector2, state: int, predator: bool, text: String, size := SIZE, w_override := -1.0, frac := 0.7) -> void:
	var genes := 9 | (8 << 4) | (6 << 8) | ((10 if predator else 3) << 12) | (7 << 16) | (9 << 20)
	var w := (1.0 if predator else 0.0) + 2.0 * 3.0 + 16.0 * 8.0 + 256.0 * 15.0 + 4096.0 * 6.0
	if w_override >= 0.0:
		w = w_override
	var sz := size * (1.5 if state == 5 else 1.0)
	_add(pos, sz, HUNTER if predator else CELL, _kind(0.5, 7), frac + 2.0 * state, float(genes), w, text)


func _run() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.95, 0.97, 0.98)
	bg.size = Vector2(1920, 1080)
	root.add_child(bg)
	mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.use_custom_data = true
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	mm.mesh = q
	mm.instance_count = 32
	var inst := MultiMeshInstance2D.new()
	inst.multimesh = mm
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/organism.gdshader")
	inst.material = mat
	root.add_child(inst)
	# Row 1: behaviours (engulfing at two closures, via the energy slot).
	var y := 160.0
	_cell(Vector2(170, y), 0, false, "游动 idle")
	_cell(Vector2(480, y), 1, false, "进食 eat")
	_cell(Vector2(790, y), 2, true, "捕食 hunt")
	_cell(Vector2(1100, y), 7, true, "吞噬 0.25", SIZE, -1.0, 0.25)
	_cell(Vector2(1410, y), 7, true, "吞噬 0.85", SIZE, -1.0, 0.85)
	_cell(Vector2(1720, y), 4, false, "受伤 hurt")
	# Row 2: division.
	y = 500.0
	var xs := [210.0, 640.0, 1070.0, 1500.0]
	var splits := [0.2, 0.45, 0.7, 0.92]
	for i in 4:
		_cell(Vector2(xs[i], y), 5, false, "分裂 %.2f" % splits[i], SIZE, 2.0 * round(splits[i] * 4000.0))
	# Row 3: a meal digesting (prey drawn first, inside), then dying shells.
	y = 860.0
	var gs := [0.08, 0.45, 0.85]
	for i in 3:
		var at := Vector2(170 + i * 300, y)
		var shrink := 1.0 - 0.55 * clampf((gs[i] - 0.1) / 0.9, 0.0, 1.0)
		_add(at + Vector2(8, -4), SIZE * 0.72 * shrink, CELL, _kind(0.0, 3), gs[i] + 16.0, 0.0, 0.0, "")
		_cell(at, 9, true, "消化 %.2f" % gs[i], SIZE, -1.0, gs[i])
	var fades := [0.7, 0.3]
	for i in 2:
		_add(Vector2(1150 + i * 300, y), 220.0, CELL, 9.0, fades[i], 0.0, 0.0, "死亡 %.2f" % (1.0 - fades[i]))
	mm.visible_instance_count = n
	for l in labels:
		root.add_child(l)
	if "--clip" in OS.get_cmdline_user_args():
		# Strokes advance like the kernel's (about 6 rad/s); for a movie.
		for f in 240:
			_tick_strokes(f / 60.0)
			await process_frame
		quit()
		return
	for shot in 2:
		for i in 12:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://proofs/anim_board_%d.png" % shot))
	quit()


func _tick_strokes(t: float) -> void:
	for i in n:
		var c := mm.get_instance_color(i)
		if c.a >= 1.0:
			continue
		var low := int(round(c.a * 4194304.0)) % 1024
		var ph := float(int(fposmod(t * 6.0 + i * 0.7, TAU) / TAU * 4096.0) & 4095)
		c.a = (low + 1024.0 * ph) / 4194304.0
		mm.set_instance_color(i, c)
