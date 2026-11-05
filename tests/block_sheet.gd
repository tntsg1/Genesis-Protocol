extends SceneTree
# Level 22's new blocks close up (shaders/colony.gdshader): armour with its
# open sides and a bite healing (top two rows), stores from full to drawn dry
# (bottom row): proofs/blocks_22.png. Level 23's (cracks, the regeneration
# block, blocks growing back): proofs/blocks_23.png.
# Run: tools/run_test.sh tests/block_sheet.gd

const COLS := 5
const STEP := 380.0
const SIDE := 600.0

var mm: MultiMeshInstance2D
var labels: Array[Label] = []


func _initialize() -> void:
	root.add_child(preload("res://tests/test_window.gd").new())
	var bg := ColorRect.new()
	bg.color = Color(0.9, 0.93, 0.91)
	bg.size = Vector2(1920, 1080)
	root.add_child(bg)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/colony.gdshader")
	mat.set_shader_parameter("seeds", Colony.embryo_seeds())
	mat.set_shader_parameter("gon", Colony.embryo_gonidia())
	mat.set_shader_parameter("px", 1.0)
	mm = preload("res://scripts/colony_layer.gd").sprites(15, mat)
	root.add_child(mm)
	for k in 15:
		var l := Label.new()
		l.add_theme_color_override("font_color", Color(0.2, 0.3, 0.26))
		l.position = Vector2(200 + (k % COLS) * STEP - 30, 200 + (k / COLS) * 340 + 150)
		root.add_child(l)
		labels.append(l)
	_run.call_deferred()


func _show(kinds: Array, opens: Array, zs: Array, ws := []) -> void:
	var buf := PackedFloat32Array()
	buf.resize(16 * 15)
	for k in 15:
		var o := k * 16
		buf[o] = SIDE
		buf[o + 3] = 200 + (k % COLS) * STEP
		buf[o + 5] = SIDE
		buf[o + 7] = 200 + (k / COLS) * 340
		buf[o + 8] = 0.4
		buf[o + 9] = 0.66
		buf[o + 10] = 0.46
		buf[o + 11] = 0.5
		buf[o + 12] = (kinds[k] + 8.0 * opens[k]) / 128.0
		buf[o + 13] = fposmod(k * 0.13, 1.0)
		buf[o + 14] = zs[k]
		buf[o + 15] = ws[k] if not ws.is_empty() else 0.0
		labels[k].text = "%s 开%d z %.2f w %.2f" % [{0: "鞭", 1: "生", 3: "甲", 4: "储", 5: "再"}[kinds[k]], opens[k], zs[k], buf[o + 15]]
	mm.multimesh.buffer = buf
	mm.multimesh.visible_instance_count = 15


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://proofs/%s.png" % name))


func _run() -> void:
	var kinds := []
	var opens := []
	var zs := []
	var sides := [1, 2, 4, 3, 0]
	for k in 5:
		kinds.append(3)
		opens.append(sides[k])
		zs.append(0.0)
	for k in 5:
		kinds.append(3)
		opens.append(2)
		zs.append(1.0 - k * 0.25)
	for k in 5:
		kinds.append(4)
		opens.append(0)
		zs.append(1.0 - k * 0.25)
	_show(kinds, opens, zs)
	await create_timer(0.3).timeout
	await _shot("blocks_22")
	# Level 23: armour cracking, the regeneration block, a flagellum block
	# broken and growing back.
	kinds = [3, 3, 3, 5, 5, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1]
	opens = [2, 2, 2, 0, 3, 2, 2, 2, 2, 2, 0, 0, 0, 0, 0]
	zs = []
	zs.resize(15)
	zs.fill(0.0)
	var ws := [0.5 + 0.24 * 0.34, 0.5 + 0.24 * 0.68, 0.74, 0.0, 0.0]
	for g in [0.0, 0.15, 0.4, 0.65, 0.9]:
		ws.append(0.75 + 0.25 * (1.0 - g))
	for g in [0.0, 0.15, 0.4, 0.65, 0.9]:
		ws.append(0.75 + 0.25 * (1.0 - g))
	_show(kinds, opens, zs, ws)
	await create_timer(0.3).timeout
	await _shot("blocks_23")
	quit()
