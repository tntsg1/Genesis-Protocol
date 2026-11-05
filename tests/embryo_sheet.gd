extends SceneTree
# A germ block's embryo (shaders/colony.gdshader) at 15 points of its clock,
# close up, on the dish's pale ground: proofs/embryo_cleave.png (e 0..0.5)
# and proofs/embryo_turn.png (0.5..1); proofs/embryo_seams.png puts each stage's
# last moment (top row) over the next one's first (middle row), the same block.
# Run: tools/run_test.sh tests/embryo_sheet.gd

const COLS := 5
const STEP := 380.0
const SIDE := 760.0

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


func _show(es: Array, phases := []) -> void:
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
		buf[o + 12] = 1.0 / 128.0
		buf[o + 13] = phases[k] if not phases.is_empty() else fposmod(k * 0.13, 1.0)
		buf[o + 14] = es[k]
		labels[k].text = "e %.3f" % es[k]
	mm.multimesh.buffer = buf
	mm.multimesh.visible_instance_count = 15


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://proofs/%s.png" % name))


func _run() -> void:
	var a := []
	var b := []
	for k in 15:
		a.append(0.5 * k / 14.0 * 0.999)
		b.append(0.5 + 0.5 * k / 14.0)
	_show(a)
	await create_timer(0.3).timeout
	await _shot("embryo_cleave")
	_show(b)
	await create_timer(0.3).timeout
	await _shot("embryo_turn")
	var seams := [0.0, 0.32, 0.5, 0.61, 0.7]
	var es := []
	var ps := []
	for row in 3:
		for k in 5:
			es.append(1.0 if row == 2 else seams[k] + (0.0006 if row == 1 else -0.0006 if k > 0 else 0.0))
			ps.append(fposmod(k * 0.21 + (0.37 if row == 2 else 0.0), 1.0))
	es[5] = 0.004
	_show(es, ps)
	await create_timer(0.3).timeout
	await _shot("embryo_seams")
	quit()
