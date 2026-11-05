extends Node2D
# Analysis mode (GDD 9.3): the dish as a scientific diagram. Every organism
# in view gets a dashed ring for how far it sees and a line to whatever its
# current behaviour aims at, coloured by behaviour. Rings are one MultiMesh,
# lines one batched draw per colour, so a thousand organisms stay cheap.

const CAPACITY := 3000
# Line colour per SimCore action (wander, seek, graze, hunt, bite, flee,
# scavenge, rest, divide, follow, signal, comfort); transparent = no line.
const ACTION_COLORS := [
	Color(0, 0, 0, 0), Color("4c9a4e"), Color("4c9a4e"), Color("d0566a"), Color("d0566a"),
	Color("e08a3c"), Color("7d8790"), Color(0, 0, 0, 0), Color("c9a227"), Color("3f7fd0"),
	Color(0, 0, 0, 0), Color("b04fc4"), Color("2fa39a"), Color("5f8fb0"),
]
const ACTION_NAMES := ["", "觅食", "进食", "追捕", "追捕", "逃离", "食腐", "", "分裂", "跟随", "", "避寒避热", "循味", "散开"]

var host: Node2D
var rings: MultiMeshInstance2D
var ring_mat: ShaderMaterial
var amount := 0.0 # 0..1, eases in and out
var on := false
var _lines := {} # colour index -> PackedVector2Array


func setup(showcase: Node2D) -> void:
	host = showcase
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = CAPACITY
	mm.visible_instance_count = 0
	rings = MultiMeshInstance2D.new()
	rings.multimesh = mm
	ring_mat = ShaderMaterial.new()
	ring_mat.shader = preload("res://shaders/analysis_ring.gdshader")
	rings.material = ring_mat
	add_child(rings)
	visible = false


func set_on(v: bool) -> void:
	on = v
	if on:
		visible = true


func tick(delta: float, alpha: float, view: Rect2) -> void:
	amount = move_toward(amount, 1.0 if on else 0.0, delta / Ui.T_MID)
	if amount <= 0.0:
		visible = false
		return
	visible = true
	ring_mat.set_shader_parameter("fade", amount)
	ring_mat.set_shader_parameter("vision", smoothstep(1.4, 2.6, host.cam.zoom.x))
	var sim: SimCore = host.sim
	var r := view.grow(80.0)
	rings.multimesh.buffer = sim.build_analysis_buffer(r, alpha, CAPACITY)
	rings.multimesh.visible_instance_count = sim.get_analysis_count()
	# Target lines, already grouped by action in the kernel.
	_lines.clear()
	var groups := sim.get_analysis_lines(r, alpha)
	for act in groups.size():
		if act < ACTION_COLORS.size() and ACTION_COLORS[act].a > 0.0 and not groups[act].is_empty():
			_lines[act] = groups[act]
	queue_redraw()


func _draw() -> void:
	var w: float = 1.4 / host.cam.zoom.x
	for act in _lines:
		var col: Color = ACTION_COLORS[act]
		col.a = 0.8 * amount
		draw_multiline(_lines[act], col, w)
