extends Control
# The virus bench (level 18): four traits share a budget of points, a switch
# for what it does on landing, and the phage itself, large, changing shape as
# the numbers change. What it means in plain numbers is written beside it.

signal changed

const POINTS := 12
const MAX_LEVEL := 5
# key, name, what the level means.
const TRAITS := [
	["burst", "爆发量", "一只细胞放出 %d 个新病毒"],
	["speed", "复制速度", "扎中后 %d 秒撑破细胞"],
	["shell", "外壳结实度", "在水里能存 %d 秒，游得也慢"],
	["stick", "附着率", "碰到细胞时，抓住的机会 %d%%（外壳越结实越低）"],
]
# Level 19's virus works on a giant's factory, not on a cell.
const TRAITS_V := [
	["burst", "爆发量", "工厂被夺走时，最多放出 %d 个噬毒体"],
	["speed", "复制速度", "闯进工厂后 %d 秒夺走它"],
	["shell", "外壳结实度", "在水里能存 %d 秒，游得也慢"],
	["stick", "附着率", "碰到目标时，抓住的机会 %d%%（外壳越结实越低）"],
]
const LIFE := preload("res://shaders/phage.gdshader")
const INK := Vector3(0.33, 0.26, 0.52) # (the defaults in phage.gdshader)
const SHELL := Vector3(0.74, 0.68, 0.88)
const DNA := Vector3(0.86, 0.17, 0.34)

var virus := {burst = 3, speed = 3, shell = 3, stick = 3, temperate = false}
var pips := {}
var notes := {}
var left_label: Label
var mode_lytic: Button
var mode_latent: Button
var mat: ShaderMaterial
var stage: Node2D
var line_label: Label
var virophage := false
var traits: Array = TRAITS


func setup(start: Dictionary, is_virophage := false) -> void:
	virus.merge(start, true)
	virophage = is_virophage
	traits = TRAITS_V if virophage else TRAITS
	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.add_theme_constant_override("separation", 36)
	add_child(h)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_stretch_ratio = 1.1
	v.add_theme_constant_override("separation", 14)
	h.add_child(v)
	v.add_child(Ui.label("设计一种噬毒体" if virophage else "设计一种病毒", Ui.SIZE_TITLE + 2, Ui.INK, Ui.sans(700)))
	left_label = Ui.label("", 15, Ui.ACCENT, Ui.sans(600))
	v.add_child(left_label)
	for t: Array in traits:
		_row(v, t)
	v.add_child(Ui.label("投放之后" if virophage else "扎中细胞之后", 15, Ui.INK, Ui.sans(600)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	mode_lytic = Widgets.Pill.new("马上裂解", 120, Ui.sans(600))
	mode_latent = Widgets.Pill.new("先潜伏", 120, Ui.sans(600))
	mode_lytic.pressed.connect(func() -> void: _set_mode(false))
	mode_latent.pressed.connect(func() -> void: _set_mode(true))
	row.add_child(mode_lytic)
	row.add_child(mode_latent)
	line_label = Ui.label("", 13, Ui.INK_SOFT, Ui.sans(500))
	line_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(line_label)
	var view := Control.new()
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(view)
	stage = Node2D.new()
	view.add_child(stage)
	view.resized.connect(func() -> void: stage.position = view.size * 0.5)
	_build_preview()
	_refresh()


func _row(v: VBoxContainer, t: Array) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	v.add_child(box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	var name_l := Ui.label(t[1], 15, Ui.INK, Ui.sans(600))
	name_l.custom_minimum_size = Vector2(110, 0)
	row.add_child(name_l)
	var list := []
	for k in MAX_LEVEL:
		var b := Widgets.Pill.new(str(k + 1), 38, Ui.mono())
		var key: String = t[0]
		var lvl: int = k + 1
		b.pressed.connect(func() -> void: set_trait(key, lvl))
		row.add_child(b)
		list.append(b)
	pips[t[0]] = list
	var note := Ui.label("", 13, Ui.INK_FAINT, Ui.sans(500))
	box.add_child(note)
	notes[t[0]] = note


func used() -> int:
	return int(virus.burst) + int(virus.speed) + int(virus.shell) + int(virus.stick)


func set_trait(key: String, lvl: int) -> void:
	if used() - int(virus[key]) + lvl > POINTS:
		Audio.sfx("ui_deny")
		return
	virus[key] = lvl
	Audio.sfx("gene_up", -8.0, 0.9 + 0.08 * lvl)
	_refresh()
	changed.emit()


func _set_mode(on: bool) -> void:
	virus.temperate = on
	Audio.sfx("ui_click", -8.0)
	_refresh()
	changed.emit()


func _refresh() -> void:
	var spare := POINTS - used()
	left_label.text = "点数 %d / %d%s" % [used(), POINTS, "　还有 %d 点没用" % spare if spare > 0 else ""]
	for t: Array in traits:
		var key: String = t[0]
		for k in MAX_LEVEL:
			pips[key][k].active = k + 1 == int(virus[key])
	var p: Dictionary = LevelEval.virus_params(virus)
	notes.burst.text = traits[0][2] % int(p["yield"])
	notes.speed.text = traits[1][2] % int(p.burst)
	notes.shell.text = traits[2][2] % int(p.life)
	notes.stick.text = traits[3][2] % roundi(float(p.stick) * 100.0)
	mode_lytic.active = not virus.temperate
	mode_latent.active = virus.temperate
	line_label.text = "马上裂解：留在水里，碰到巨毒囊或工厂才起作用。\n先潜伏：也会接入健康细胞的基因，传给后代；巨毒囊被吞下时才醒。" if virophage else "马上裂解：扎中就开始复制，到时间撑破细胞。\n先潜伏：多数接进对手的基因，不马上杀它，要等它挨饿或受热才发作。"
	if mat:
		var look: Dictionary = look_of(virus, virophage)
		for key: String in look:
			mat.set_shader_parameter(key, look[key])


# The shape a design shows (shaders/phage.gdshader).
static func look_of(v: Dictionary, virophage := false) -> Dictionary:
	if v.is_empty():
		return {head = 1.0, tail = 1.0, legs = 1.0, crystal = 0.0, fit = 1.0, bare = 0.0, ink = INK, shell = SHELL, dna = DNA}
	if virophage:
		return {head = 0.86 + 0.12 * float(v.burst), tail = 1.0, legs = 1.0, crystal = (float(v.shell) - 1.0) / 4.0, fit = 0.7, bare = 1.0,
			ink = Vector3(0.05, 0.42, 0.4), shell = Vector3(0.62, 0.88, 0.84), dna = Vector3(0.08, 0.62, 0.56)}
	return {head = 0.7 + 0.13 * float(v.burst), tail = 1.12 - 0.05 * float(v.burst), legs = 0.66 + 0.14 * float(v.stick), crystal = (float(v.shell) - 1.0) / 4.0, fit = 1.28}


func _build_preview() -> void:
	mat = ShaderMaterial.new()
	mat.shader = LIFE
	mat.set_shader_parameter("px", 1.0)
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = 1
	mm.set_instance_transform_2d(0, Transform2D(0.0, Vector2(430.0, 430.0), 0.0, Vector2.ZERO))
	mm.set_instance_custom_data(0, Color(-PI * 0.5, 0.0, 0.0, 0.995))
	var node := MultiMeshInstance2D.new()
	node.multimesh = mm
	node.material = mat
	stage.add_child(node)
