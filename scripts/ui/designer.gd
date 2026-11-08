extends Control
# Life designer: a bright biotech lab over the dish. Four pages (top tabs,
# keys 1-4):
#   基因组    specimen tank | giant holographic DNA (the genes) | gene editor
#   行为规则  library of behaviour pieces | how decks run | deck
#   物种库    saved designs: load, delete
#   规则手册  every condition and action explained
# The footer (budget, readouts, save, release) stays on every page.
#
# It opens with a dive: the camera has closed in on a cell, its nucleus swells
# past the screen, the chromosomes inside drift into the specimen tank and
# the DNA unrolls across the lab (INTRO_LEN). Leaving plays it backwards while
# the camera pulls out (OUTRO_LEN). Neither can be skipped.

signal closed
# The designed species, ready for SimCore.add_species (+ "name").
signal released(params: Dictionary)
# The outro has reached the point where the camera should start pulling out.
signal pull_out(releasing: bool)
signal intro_done

const INTRO_LEN := 2.5
const OUTRO_LEN := 2.2
const PULL_AT := 0.85 # outro time when the camera starts pulling out
const PORTAL_MAX := 1250.0
const DIVE_NUCLEUS := 260.0 # nucleus radius while the chromosomes are on screen
const SPECIMEN_R := 80.0
const NUCLEUS_R := 48.0
# The genome stage (shaders/genome_stage.gdshader), screen pixels.
const STAGE_CENTER := Vector2(946, 500)
const STAGE_LEN := 5600.0
const NG := 8 # genes
const STAGE_CODING := 2880.0 # eight genes, 360 px each: about two and a half in view
const STAGE_AMP := 95.0
const STAGE_WAVE := 420.0
const STAGE_ANGLE := -0.1
const STAGE_HALF_VIEW := 514.0 # the open lab between the side panels
# A gene edit's timing (shaders/genome_stage.gdshader: CUT, STAG, LEAD, INS).
const EDIT_CUT := 0.08
const EDIT_STAG := 0.4
const EDIT_LEAD := 0.14
const EDIT_INS := 0.3
const EDIT_LEN := EDIT_CUT + EDIT_LEAD + EDIT_STAG + EDIT_INS
# The whole-genome navigator under the strand.
const NAV_RECT := Rect2(452, 846, 988, 16)
const GENE_CODES := ["SPD", "SEN", "SHL", "ATK", "FER", "MET", "NEU", "THM"]
# The lab's palette: graphite and steel, one accent for what is selected.
const LAB_GREY := Color(0.42, 0.48, 0.53)
const LAB_INK := Color(0.17, 0.22, 0.26)

const SWATCHES := [Color(0.48, 0.62, 1.0), Color(0.36, 0.8, 0.62), Color(1.0, 0.62, 0.42), Color(0.82, 0.52, 0.95), Color(0.98, 0.78, 0.3)]
const BUDGET := 18.0
# A campaign level's rules (LevelRunner sets them before opening): budget,
# star_budget, genes_open (indices), fixed {index: level}, pages_open, and
# design (the last design tried in this level). Empty in the sandbox.
static var level_rules := {}
var budget_max := BUDGET
static var designs := 0 # how many species released this session (names A-01, A-02 ...)
# What was on the bench when the designer was last closed without releasing.
static var draft := {}

const DeckEditor := preload("res://scripts/ui/deck_editor.gd")
const GENES := [
	["速度", "SPEED", "提高移动速度。等级越高，游动时消耗的能量越多。"],
	["感知", "SENSE", "扩大感知范围，可以更早发现食物和危险，但会增加能量消耗，也更容易被捕食者发现。"],
	["外壳", "SHELL", "更厚的外壳可以抵挡攻击，但会增加重量，降低移动速度。"],
	["攻击", "ATTACK", "提高攻击能力。可以用来捕食或自卫，但攻击器官需要消耗能量。"],
	["繁殖", "FERTILITY", "缩短繁殖间隔，加快种群增长。不过，新生个体携带的初始能量会减少。"],
	["代谢", "METABOLISM", "降低日常能量消耗，让细胞在食物不足时存活更久。不过，分裂前需要积累更多能量。"],
	["神经", "NEURAL", "增加可使用的行为规则数量。等级越高，可以设置的规则越多，但维持神经系统也需要更多能量。\n规则卡槽：3 / 4 / 5 / 6 / 8"],
	["耐温", "THERMAL", "扩大细胞能够适应的水温范围。耐温范围越宽，维持成本越高。\n最适温度可以单独设置，不消耗基因预算。"],
]
const GENE_SUMMARY := [
	"提高细胞的游动速度，但移动时会消耗更多能量。",
	"扩大感知范围，但维持更耗能，也更容易被捕食者发现。",
	"更厚的外壳可以抵挡攻击，但会增加重量，降低速度。",
	"提高攻击能力，可以用来捕食或自卫，但需要消耗能量。",
	"加快繁殖，但新生个体携带的初始能量会减少。",
	"降低日常能耗，但分裂前需要积累更多能量。",
	"增加行为规则数量，但维持神经系统也需要更多能量。",
	"扩大适应的水温范围，但维持成本也会提高。",
]

var genes := [2.0, 2.0, 1.0, 1.0, 3.0, 3.0, 3.0, 3.0]
# The water it likes best (deg C): chosen freely, it costs no budget.
var temp_opt := 12.0
var temp_slider: Control
# Chapter 7 (寿命, DECISIONS Q232): how long its cells live, ×0.5..×2; a long
# life divides dearer, a short one cheaper. A slider under fertility, open
# where the level says (life_open), costing no budget.
var life := 1.0
var life_slider: Control
# Chapter 8: born with a symbiont (真核, 8-2 on: euk_open) and acid
# tolerance 0..1 (耐酸, acid_open), neither costing budget.
var euk := false
var euk_pill: Widgets.Pill
var acid_tol := 0.0
var acid_slider: Control
var mutates := true # natural mutation (off = the line stays exactly as designed)
var resp := Resp.ANAEROBIC # chapter 6: how it breathes (a switch from 6-4: Resp)
var resp_pill: Widgets.Pill
var organs: Array = [] # installed organ ids (scripts/organs.gd)
var organ_bay: Control # the organ slots on the genome page (levels with organ_slots)
var state_bar: Control # the state map over the deck (levels with states)
var sp_slots: Array = [] # level 8: a design per species slot
var cur_slot := 0
var slot_tabs: Array = []
var mutate_pill: Widgets.Pill
var deck_editor: Control
var deck_scroll: ScrollContainer
var slot_label: Label
var add_button: Widgets.Pill
# The rules page has two modes (2026-10-29): "simple" picks a personality and
# one 保守 <-> 激进 slider (scripts/personas.gd); "advanced" is the card
# editor with the piece library (from Personas.ADVANCED_OPENS). The mode the
# player last chose sticks for the session.
static var last_mode := "simple"
var rules_mode := "simple"
var persona := "standard" # "" = edited by hand in advanced mode
var bold := 0.5
var lib_box: Control # the piece library (advanced)
var persona_picker: Control # the personalities (simple)
var mode_simple: Widgets.Pill
var mode_adv: Widgets.Pill
var undo_pill: Widgets.Pill
var reset_pill: Widgets.Pill
var name_edit: LineEdit
var toast: Label
var pages := {}
var virus_bench: Control # level 18
const VirusBench := preload("res://scripts/ui/virus_bench.gd")
var body_bench: Control # level 21
# The sandbox (DECISIONS 沙盒补全 Q277): the virus and body pages are there
# too; the body only counts with 多细胞 on, the virus goes to the dish with
# its target picked.
static var multicell := false
static var virus_target := -1
var multi_pill: Widgets.Pill
# 本关要点: the level's goal and features over the page, on request.
var points_panel: GlassPanel
var points_pill: Widgets.Pill
const SANDBOX_VIRUS := {burst = 3, speed = 3, shell = 3, stick = 3, temperate = false}
const BodyBench := preload("res://scripts/ui/body_bench.gd")
var page := "genome"
var tab_buttons := {}
var piece_chips: Array = [] # the behaviour library's pieces (PieceChip)
var library_box: HFlowContainer
var library: Array = []
var specimen: MultiMeshInstance2D
var rings: Control
var chamber: GlassPanel
var budget_meter: Control
var budget_label: Label
var go: Widgets.Pill
var go_hint: Label
var name_label: Label
var swatch_buttons: Array = []
var gene_sliders: Array = []
var cost_labels := {}
var panels: Array = []
var backdrop: ColorRect
var spin := 0.0
var color: Color = SWATCHES[0]
# Genome art: eased levels, a highlight per gene, the gene under the mouse.
var shown := []
var glow := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
var hover_gene := -1
var sel_gene := 0
# The cell the camera dived into: {name, color, genes, deck}; empty = none.
var ref_info := {}
var ref_button: Widgets.Pill
# Transition state.
var dive: Control
var dive_center := Vector2(960, 540)
var dive_r0 := 14.0
var busy := true
var tl := 0.0 # time since opening
var ot := -1.0 # time since leaving began; < 0 = not leaving
var _releasing := {}
var _pulled := false
# Genome art. The nucleus and chromosomes are retained nodes (drawn once,
# then moved); the DNA is a shader; labels redraw only when something changes.
var genome: GenomeView
var portal: Node2D
var stage: ColorRect
var stage_mat: ShaderMaterial
var stage_labels: Control
var ticker: Label
var tank_fx: Control
var ring_arc: Node2D
var gene_rows: Array = []
var _label_key := ""
# Stage motion: the lens slides to the selected gene, the selection wipes
# across it, a level change flashes it and spins the strand up.
var focus_x := 0.0
# Where the strand is (its position at the view centre) and the trip to the
# next selected gene: the farther the gene, the longer the run.
var view_x := 0.0
var travel_from := 0.0
var travel_t := 1.0
var travel_dur := 1.0
# The mouse on the stage: a lens of its own, drag-to-scrub with inertia and a
# magnetic snap, wheel and click; the room's parallax; click ripples.
var mouse_pos := Vector2(-9999, -9999)
var mouse_on := 0.0
var parallax := Vector2.ZERO
var ripple_x := 0.0
var ripple_p := Vector2(-9999, -9999)
var ripple_t := 99.0
var dragging := false
var drag_moved := 0.0
var drag_vel := 0.0
var coasting := false
var run_speed := 0.0
# Arrival lock-on, the readout typing in.
var lock_t := 9.0
var type_t := 9.0
# Gene edits on the stage: a level change cuts the gene's stretch of DNA
# out of both backbones, peels it away left to right like tape and presses
# the new level's stretch in behind it (shaders/genome_stage.gdshader,
# whose timing EDIT_* mirrors).
# bp_lv is the level the pairs show, bp_from the one being peeled off; a
# change during an edit hurries it and follows straight on.
var bp_lv := []
var bp_from := []
# The organ insertion site (2026-10-29: "器官装上的话，DNA 也要有个地方插入
# 碱基对"): right of the eight genes, one site per organ slot of the level.
# An empty site is a gap in the ladder; installing an organ presses its base
# pairs into the site, taking it out lifts them away (genome_stage.gdshader,
# the gene edit's timing), and the strand runs there to show it.
const ORGAN_GAP := 90.0
const ORGAN_W := 260.0
var org_ids := [-1.0, -1.0, -1.0, -1.0] # Organs.LIST index per site, -1 empty
var org_old := [-1.0, -1.0, -1.0, -1.0] # what is being lifted out
var org_t := [99.0, 99.0, 99.0, 99.0]
var _org_init := false
var organ_focus := -1 # the site the strand was brought to (-1: a gene)
var travel_to := 0.0
var edit_t := [99.0, 99.0, 99.0, 99.0, 99.0, 99.0, 99.0, 99.0]
var cursor_fx: Control
var wipe := 1.0
var pulse := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
var rot_speed := 0.9
var helix_phase := 0.0
var _karyo_key := ""
var _ticker_t := 0.0


# Called before the designer enters the tree: the cell under the camera and
# where (and how big) its nucleus is on screen.
func setup(reference: Dictionary, center: Vector2, nucleus_r: float) -> void:
	ref_info = reference
	dive_center = center
	dive_r0 = nucleus_r


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop = ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bm := ShaderMaterial.new()
	bm.shader = preload("res://shaders/glass.gdshader")
	# The dish behind, drained and frosted: a big cell under it used to show
	# through as a pink smudge in the middle of the rules page (2-5 review).
	bm.set_shader_parameter("tint", Color(0.97, 0.99, 1.0, 0.88))
	bm.set_shader_parameter("blur", 5.5)
	bm.set_shader_parameter("desat", 0.9)
	bm.set_shader_parameter("radius", 0.0)
	bm.set_shader_parameter("bracket", 0.0)
	bm.set_shader_parameter("edge", Color(0, 0, 0, 0))
	backdrop.material = bm
	add_child(backdrop)
	backdrop.resized.connect(func() -> void: bm.set_shader_parameter("size", backdrop.size))
	_build_stage()
	_build_top()
	_build_tank()
	_build_gene_panel()
	pages.genome = panels.slice(1)
	var n := panels.size()
	_build_library()
	_build_deck()
	pages.rules = panels.slice(n)
	_build_handbook()
	_build_species_library()
	_build_footer()
	_build_virus_page()
	_build_body_page()
	_update_pieces()
	if not level_rules.is_empty():
		budget_max = float(level_rules.budget)
		if level_rules.has("design"):
			_apply_design(level_rules.design)
		_enforce_rules()
		_init_slots()
	elif not draft.is_empty():
		_apply_design(draft)
	shown = genes.duplicate()
	focus_x = _gene_x(sel_gene)
	view_x = focus_x
	travel_from = view_x
	travel_to = view_x
	_refresh()
	# The dive overlay sits above everything and eats input while it plays.
	dive = Control.new()
	dive.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dive.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dive)
	portal = GenomeView.Nucleus.new()
	portal.visible = false
	dive.add_child(portal)
	genome = GenomeView.new()
	dive.add_child(genome)
	cursor_fx = Control.new()
	cursor_fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cursor_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cursor_fx.draw.connect(_draw_cursor_fx)
	dive.add_child(cursor_fx)
	ring_arc = Node2D.new()
	ring_arc.draw.connect(func() -> void:
		ring_arc.draw_arc(Vector2.ZERO, 124.0, 0.0, TAU * 0.6, 48, Color(Ui.ACCENT, 0.5), 1.2, true))
	rings.add_child(ring_arc)
	backdrop.modulate.a = 0.0
	specimen.modulate.a = 0.0
	rings.modulate.a = 0.0
	tank_fx.modulate.a = 0.0
	stage_labels.modulate.a = 0.0
	stage_mat.set_shader_parameter("reveal", 0.0)
	for p in panels:
		p.modulate.a = 0.0
		if p in pages.rules or p in pages.handbook or p in pages.library:
			p.visible = false
	# Panels sweep in left to right as the chromosomes settle.
	var d := 1.7
	for p in panels:
		if p.visible:
			p.appear(d)
			d += 0.05


func _place(p: Control, l: float, t: float, r: float, b: float) -> void:
	p.anchor_left = 0.0
	p.anchor_top = 0.0
	p.anchor_right = 0.0
	p.anchor_bottom = 0.0
	p.offset_left = l
	p.offset_top = t
	p.offset_right = r
	p.offset_bottom = b


func _panel(l: float, t: float, r: float, b: float, padding := Vector4(18, 14, 18, 16)) -> GlassPanel:
	var p := GlassPanel.new(padding)
	# (The room's colours drained through the panels too: no pink smudge.)
	p.mat.set_shader_parameter("desat", 0.9)
	add_child(p)
	_place(p, l, t, r, b)
	panels.append(p)
	return p


func _vbox(parent: Control, sep := 8) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(v)
	return v


func _hbox(parent: Control, sep := 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(h)
	return h


func _spacer(parent: Control) -> void:
	var s := Control.new()
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(s)


func _build_top() -> void:
	var p := _panel(24, 18, 1896, 74, Vector4(20, 10, 14, 10))
	var h := _hbox(p.body, 16)
	var v := _vbox(h, 0)
	v.add_child(Ui.label("生命设计器", Ui.SIZE_TITLE + 2, Ui.INK, Ui.sans(700)))
	v.add_child(Ui.label("LIFE DESIGNER  /  SPECIMEN A-%02d" % (designs + 1), 10, Ui.INK_FAINT, Ui.mono()))
	_spacer(h)
	# Level 8: which species is on the bench.
	for k in (level_rules.get("species", []) as Array).size():
		var sl: Dictionary = level_rules.species[k]
		var b := Widgets.Pill.new("%s · %s" % ["ABC"[mini(k, 2)], sl.label], 120, Ui.sans(700))
		b.active = k == 0
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var idx := k
		b.pressed.connect(func() -> void: _switch_slot(idx))
		h.add_child(b)
		slot_tabs.append(b)
	if not slot_tabs.is_empty():
		_spacer(h)
	var rules_tab := "行为预设  2" if str(level_rules.get("id", "")) == "1-1" else "行为规则  2"
	var tab_specs: Array = [["genome", "基因组  1"], ["rules", rules_tab], ["library", "物种库  3"], ["handbook", "规则手册  4"]]
	if level_rules.has("virus") or level_rules.is_empty():
		tab_specs.insert(0 if not level_rules.is_empty() else tab_specs.size(), ["virus", "病毒设计"])
	if level_rules.has("colony") or level_rules.is_empty():
		tab_specs.insert(0 if not level_rules.is_empty() else tab_specs.size(), ["body", "身体"])
	for spec in tab_specs:
		var b := Widgets.Pill.new(spec[1], 116, Ui.sans(600))
		var key: String = spec[0]
		b.active = key == "genome"
		b.visible = not level_rules.has("virus") or (level_rules.pages_open as Array).has(key)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.pressed.connect(func() -> void: show_page(key))
		h.add_child(b)
		tab_buttons[key] = b
	_spacer(h)
	# In a level: its goal and features while designing (本关要点), and the
	# guide again, from the start.
	if not level_rules.is_empty() and not Levels.by_id(str(level_rules.get("id", ""))).is_empty():
		var pts := Widgets.Pill.new("本关要点", 96, Ui.sans(600))
		pts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pts.tooltip_text = "这一关的目标、星星和特点：设计时对照着看"
		pts.pressed.connect(func() -> void: toggle_points())
		h.add_child(pts)
		points_pill = pts
	if not level_rules.is_empty():
		var guide := Widgets.Pill.new("查看引导", 96, Ui.sans(500))
		guide.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		guide.tooltip_text = "从头再走一遍这一关的引导"
		guide.pressed.connect(func() -> void:
			var runner: Node = get_parent().get("level_runner") if get_parent() else null
			if runner == null:
				runner = get_tree().current_scene.get("level_runner")
			if runner:
				runner.replay_tutorial()
				show_page("genome"))
		h.add_child(guide)
	var back := Widgets.Pill.new("返回培养皿   Esc", 150, Ui.sans(500))
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(close)
	h.add_child(back)


# Level 21: the player builds the body block by block; the rest of the
# design stays where it was, on the other pages.
func _build_body_page() -> void:
	pages.body = []
	var sandbox := level_rules.is_empty()
	if not level_rules.has("colony") and not sandbox:
		return
	var p := _panel(120, 110, 1800, 930, Vector4(30, 22, 30, 22))
	pages.body = [p]
	body_bench = BodyBench.new()
	body_bench.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	body_bench.size_flags_vertical = Control.SIZE_EXPAND_FILL
	p.body.add_child(body_bench)
	body_bench.setup(level_rules.get("design", {}).get("blocks", []), level_rules.get("colony", SandboxWorld.COLONY), int(level_rules.get("star_blocks", 0)), float(level_rules.get("trip", 660.0)))
	body_bench.changed.connect(_refresh)
	if sandbox:
		p.visible = false # (the genome page comes first; the body page is a tab)
		return
	show_page.call_deferred("body")


# Level 18: the virus bench is the page; the cells are given.
func _build_virus_page() -> void:
	pages.virus = []
	var sandbox := level_rules.is_empty()
	if not level_rules.has("virus") and not sandbox:
		return
	var p := _panel(200, 110, 1720, 930, Vector4(36, 26, 36, 26))
	pages.virus = [p]
	virus_bench = VirusBench.new()
	virus_bench.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	virus_bench.size_flags_vertical = Control.SIZE_EXPAND_FILL
	p.body.add_child(virus_bench)
	virus_bench.setup(level_rules.get("virus", SANDBOX_VIRUS), level_rules.get("virophage", false))
	if sandbox:
		p.visible = false
		_virus_target_row((virus_bench.get_child(0) as Control).get_child(0) as Control)
		return
	show_page.call_deferred("virus")
	if (level_rules.pages_open as Array).size() > 1:
		return # (level 19: the cells are the player's too)
	# The footer keeps only 投放: the gene budget and the rest are about cells.
	var row: Node = go
	while row != null and row.get_parent() != null and not (row.get_parent() is HBoxContainer and row.get_parent().get_parent() != null and row.get_parent().get_child_count() > 3):
		row = row.get_parent()
	if row != null and row.get_parent() != null:
		for c: Node in row.get_parent().get_children():
			if c != row and c is CanvasItem:
				(c as CanvasItem).modulate.a = 0.0
				(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE if c is Control else 0


func _build_library() -> void:
	var p := _panel(24, 92, 404, 948)
	persona_picker = preload("res://scripts/ui/persona_picker.gd").new()
	p.body.add_child(persona_picker)
	persona_picker.picked.connect(_pick_persona)
	persona_picker.bold_changed.connect(_set_bold)
	var v := _vbox(p.body, 12)
	lib_box = v
	v.add_child(Ui.caption("行为零件库", "BEHAVIOUR LIBRARY"))
	v.add_child(Ui.label("零件从第 1-3 关起可以使用" if rules_readonly() else "拖到右侧的规则卡上；或先选中一张卡再点击零件", 11, Ui.INK_FAINT, Ui.sans()))
	# In a level, pieces that open later sit greyed in their own small group
	# at the bottom ("第 X 关解锁"); the ones new in this level say 新.
	var lid := level_id()
	var later := []
	for section in [["条件", "IF", "cond"], ["动作", "THEN", "act"]]:
		var head := _hbox(v, 8)
		head.add_child(Ui.label(section[0], 13, Ui.INK_SOFT, Ui.sans(600)))
		head.add_child(Ui.label(section[1], 10, Ui.ACCENT, Ui.mono("Medium")))
		var flow := _flow(v)
		# (A section with nothing open yet is hidden below.)
		flow.child_entered_tree.connect(func(_n: Node) -> void: head.visible = true)
		head.visible = false
		var kind: String = section[2]
		var names := []
		if kind == "cond":
			for c in range(1, Rules.CONDS.size()):
				names.append([c, Rules.CONDS[c][0], Rules.CONDS[c][6]])
		else:
			for a in Rules.ACTS.size():
				names.append([a, Rules.ACTS[a][0], Rules.ACTS[a][1]])
		for spec in names:
			var b := PieceChip.new(kind, spec[0], spec[1])
			piece_chips.append(b)
			if not Rules.piece_open(kind, spec[0], lid) or rules_readonly():
				b.locked = true
				b.tooltip_text = "%s
%s" % [Rules.opens_text(kind, spec[0]) if not Rules.piece_open(kind, spec[0], lid) else "本关只能看，不能改", spec[2]]
			else:
				b.tooltip_text = spec[2]
				b.fresh = Rules.piece_new(kind, spec[0], lid)
			b.pressed.connect(func() -> void:
				if b.locked:
					_toast(b.tooltip_text.get_slice("
", 0))
				else:
					deck_editor.apply_piece(b.kind, b.id))
			if not Rules.piece_open(kind, spec[0], lid):
				later.append(b)
			else:
				flow.add_child(b)
	# Pieces whose level isn't in the game yet stay out of sight (a column of
	# grey "later" chips read as clutter, review round 5).
	var soon := later.filter(func(b: PieceChip) -> bool:
		var at: String = (Rules.COND_OPENS if b.kind == "cond" else Rules.ACT_OPENS)[b.id]
		return Levels.ALL.any(func(l: Dictionary) -> bool: return l.id == at))
	if not soon.is_empty():
		var head := _hbox(v, 8)
		head.add_child(Ui.label("后面的关卡解锁", 12, Ui.INK_FAINT, Ui.sans(600)))
		head.add_child(Ui.label("LATER", 10, Ui.INK_FAINT, Ui.mono("Medium")))
		var flow := _flow(v)
		for b: PieceChip in soon:
			flow.add_child(b)
	var unseen := Control.new()
	unseen.visible = false
	v.add_child(unseen)
	for b: PieceChip in later:
		if b.get_parent() == null:
			unseen.add_child(b)
	var note := _vbox(v, 4)
	note.add_child(Ui.caption("提示", "HINT"))
	note.add_child(Ui.label("规则从上往下检查，第一张条件满足、\n动作也做得到的卡生效；都不满足就漫游。\n\n把零件拖到卡上的空格里　·　拖 ⋮⋮ 调整顺序\nCtrl+Z 撤销　·　完整说明见“规则手册”", 12, Ui.INK_SOFT, Ui.sans()))


# The genome stage: the lab grid, the giant DNA and its labels, full screen
# behind the panels.
func _build_stage() -> void:
	stage = ColorRect.new()
	stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage_mat = ShaderMaterial.new()
	stage_mat.shader = preload("res://shaders/genome_stage.gdshader")
	stage_mat.set_shader_parameter("center", STAGE_CENTER)
	stage_mat.set_shader_parameter("len", STAGE_LEN)
	stage_mat.set_shader_parameter("coding", STAGE_CODING)
	stage_mat.set_shader_parameter("amp", STAGE_AMP)
	stage_mat.set_shader_parameter("angle", STAGE_ANGLE)
	stage_mat.set_shader_parameter("wavelength", STAGE_WAVE)
	stage.material = stage_mat
	add_child(stage)
	stage.resized.connect(func() -> void: stage_mat.set_shader_parameter("size", stage.size))
	stage_labels = Control.new()
	stage_labels.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage_labels.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage_labels.draw.connect(_draw_stage_labels)
	add_child(stage_labels)
	ticker = Ui.label("", 12, Ui.ACCENT, Ui.mono("Medium"))
	ticker.position = Vector2(452, 884)
	stage_labels.add_child(ticker)


# Axis position of gene k's middle, and its point on screen.
func _gene_x(k: int) -> float:
	return -STAGE_CODING * 0.5 + STAGE_CODING / float(NG) * (k + 0.5)


func _gene_anchor(k: int) -> Vector2:
	return STAGE_CENTER + Vector2(_gene_x(k) - view_x, 0.0).rotated(STAGE_ANGLE)


# The shader's lens(): the focused gene swells (shaders/genome_stage.gdshader).
func _lens(x: float) -> float:
	var s := STAGE_CODING / float(NG)
	return 0.86 + 0.34 * exp(-pow((x - focus_x) / (s * 0.85), 2.0))


func _stage_gene_at(screen: Vector2) -> int:
	var q := (screen - STAGE_CENTER).rotated(-STAGE_ANGLE)
	var x := q.x + view_x
	if absf(q.y) > STAGE_AMP * 1.6 or absf(q.x) > STAGE_HALF_VIEW or absf(x) > STAGE_CODING * 0.5:
		return -1
	return clampi(int((x + STAGE_CODING * 0.5) / (STAGE_CODING / float(NG))), 0, NG - 1)


# The navigator: gene k's tick, and the gene nearest a point on it.
func _nav_x(strand_x: float) -> float:
	var left := -STAGE_CODING * 0.5
	var right := _right_end() + (ORGAN_W * 0.5 if _sites() > 0 else 0.0)
	return NAV_RECT.position.x + (strand_x - left) / (right - left) * NAV_RECT.size.x


func _nav_gene_at(screen: Vector2) -> int:
	if not NAV_RECT.grow(10.0).has_point(screen):
		return -1
	var left := -STAGE_CODING * 0.5
	var right := _right_end() + (ORGAN_W * 0.5 if _sites() > 0 else 0.0)
	var sx := left + (screen.x - NAV_RECT.position.x) / NAV_RECT.size.x * (right - left)
	if sx > STAGE_CODING * 0.5:
		return -1 # the organ sites (clicked through _nav_organ_at)
	return clampi(int((sx + STAGE_CODING * 0.5) / (STAGE_CODING / float(NG))), 0, NG - 1)


func _nav_organ_at(screen: Vector2) -> int:
	if _sites() == 0 or not NAV_RECT.grow(10.0).has_point(screen):
		return -1
	for k in _sites():
		if absf(screen.x - _nav_x(_organ_x(k))) < 14.0:
			return k
	return -1


func _gui_input(event: InputEvent) -> void:
	if busy or page != "genome":
		return
	if event is InputEventMouseMotion:
		mouse_pos = event.position
		if dragging:
			# Scrub along the strand; remember the speed for the throw.
			var along: float = event.relative.rotated(-STAGE_ANGLE).x
			view_x = clampf(view_x - along, -STAGE_CODING * 0.5, _right_end())
			drag_moved += absf(along)
			drag_vel = lerpf(drag_vel, -along / maxf(get_process_delta_time(), 1e-3), 0.4)
			travel_t = travel_dur
		hover_gene = _stage_gene_at(event.position)
		mouse_default_cursor_shape = Control.CURSOR_DRAG if dragging else (Control.CURSOR_POINTING_HAND if _on_strand(mouse_pos) else Control.CURSOR_ARROW)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				var site := _nav_organ_at(mb.position)
				if site >= 0:
					focus_organ(site)
					return
				var k := _karyo_gene_at(mb.position)
				if k < 0:
					k = _nav_gene_at(mb.position)
				if k >= 0:
					select_gene(k)
					return
				if _on_strand(mb.position):
					dragging = true
					coasting = false
					drag_moved = 0.0
					drag_vel = 0.0
			elif dragging:
				dragging = false
				if drag_moved < 6.0:
					# A click: a ripple runs along the strand; pick that gene.
					var q := (mb.position - STAGE_CENTER).rotated(-STAGE_ANGLE)
					ripple_x = q.x + view_x
					ripple_p = mb.position
					ripple_t = 0.0
					var g := _stage_gene_at(mb.position)
					if g >= 0:
						select_gene(g)
				else:
					coasting = true
		elif mb.pressed and _on_strand(mb.position) and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			select_gene(clampi(sel_gene + (-1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1), 0, NG - 1))


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		mouse_pos = Vector2(-9999, -9999)


func _on_strand(screen: Vector2) -> bool:
	var q := (screen - STAGE_CENTER).rotated(-STAGE_ANGLE)
	return absf(q.x) < STAGE_HALF_VIEW and absf(q.y) < 250.0


func _karyo_gene_at(screen: Vector2) -> int:
	if chamber == null:
		return -1
	var ky := _specimen_center().y + TANK_BOTTOM + 92.0
	var w7 := (chamber.size.x - 36.0) / float(NG)
	for k in GENES.size():
		var x := chamber.position.x + 18.0 + w7 * (k + 0.5)
		if Rect2(x - w7 * 0.5, ky - 32.0, w7, 74.0).has_point(screen):
			return k
	return -1


func select_gene(k: int) -> void:
	if k != sel_gene or organ_focus >= 0:
		wipe = 0.0
		type_t = 0.0
	organ_focus = -1
	_travel(_gene_x(k))
	sel_gene = k
	glow[k] = 1.0
	for j in gene_rows.size():
		gene_rows[j].selected = j == k


# Bring organ site k to the middle of the lab (an organ went in or out).
func focus_organ(k: int) -> void:
	if k != organ_focus:
		type_t = 0.0
	organ_focus = k
	_travel(_organ_x(k))


func _sites() -> int:
	return mini(organ_slots(), 4)


func _organ_x0() -> float:
	return STAGE_CODING * 0.5 + ORGAN_GAP


func _organ_x(k: int) -> float:
	return _organ_x0() + ORGAN_W * (k + 0.5)


# The strand's far right end the view may go to: the last organ site.
func _right_end() -> float:
	return _organ_x(_sites() - 1) if _sites() > 0 else STAGE_CODING * 0.5


func _travel(to: float) -> void:
	travel_to = to
	var hops := absf(to - view_x) / (STAGE_CODING / float(NG))
	if hops > 0.005:
		# Run along the strand to it; the strand spins up for the trip.
		travel_from = view_x
		travel_t = 0.0
		travel_dur = clampf(0.45 + 0.17 * hops, 0.45, 1.5)
		rot_speed = maxf(rot_speed, 1.6 + 0.9 * hops)
		coasting = false


# Labels on the stage: a tag per gene with a leader to its segment, the
# selected gene's readout card, the map header. Static unless something moves.
func _draw_stage_labels() -> void:
	var ci := stage_labels
	var across := Vector2(0, 1).rotated(STAGE_ANGLE)
	for k in GENES.size():
		var off := absf(_gene_x(k) - view_x)
		var vis := 1.0 - smoothstep(STAGE_HALF_VIEW - 120.0, STAGE_HALF_VIEW + 20.0, off)
		if vis <= 0.0:
			continue
		var a := _gene_anchor(k)
		var side := -1.0 if k % 2 == 0 else 1.0
		var lit := k == sel_gene or k == hover_gene
		var col: Color = Ui.ACCENT if k == sel_gene else (LAB_INK if lit else LAB_GREY)
		col.a = vis
		var amp := STAGE_AMP * _lens(_gene_x(k))
		var from := a + across * side * amp * 1.4
		var to := from + across * side * 46.0
		ci.draw_line(from, to, Color(col, (0.9 if lit else 0.5) * vis), 1.0, true)
		ci.draw_rect(Rect2(from - Vector2(2.5, 2.5), Vector2(5, 5)), Color(col, 0.9 * vis))
		var tag := to + Vector2(-34.0, -6.0 if side < 0.0 else 16.0)
		ci.draw_string(Ui.mono("Medium"), tag, "%s·%02d" % [GENE_CODES[k], k + 1], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(col, 0.85 * vis))
		ci.draw_string(Ui.sans(700), tag + Vector2(0, 17), GENES[k][0], HORIZONTAL_ALIGNMENT_LEFT, -1, 14 if lit else 13, col)
		ci.draw_string(Ui.mono("Medium"), tag + Vector2(32, 17), "Lv %s" % _lv(genes[k]), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(Ui.INK_SOFT, 0.9 * vis))
		if k == sel_gene:
			var box := Rect2(tag - Vector2(8, 16), Vector2(96, 28 if side < 0.0 else 28)).grow(2.0)
			_brackets(ci, box, col)
	_draw_organ_tags(ci, across)
	_draw_navigator(ci)
	# The selected gene's (or organ site's) readout, top left of the stage.
	# It types in, line after line, when a new one is picked.
	var g := sel_gene
	var col: Color = Ui.ACCENT.darkened(0.15)
	var o := Vector2(452, 116)
	var pairs := int(2.0 + 2.0 * genes[g])
	var lines := [
		["GENOME MAP  ·  LOCUS %s-%02d" % [GENE_CODES[g], g + 1], Ui.mono("Medium"), 11, Ui.ACCENT, 0.0],
		["%s  %s" % [GENES[g][0], GENES[g][1]], Ui.sans(700), 22, col, 30.0],
		["Lv %s   ·   碱基对 %d   ·   %s" % [_lv(genes[g]), pairs, cost_labels[g].text.get_slice("   ", 1)], Ui.mono("Medium"), 12, Ui.INK, 54.0],
		[GENE_SUMMARY[g], Ui.sans(), 12, Ui.INK_SOFT, 76.0],
	]
	if organ_focus >= 0:
		var k := organ_focus
		if k < organs.size():
			var org := Organs.by_id(organs[k])
			lines = [
				["GENOME MAP  ·  ORGAN SITE ORG-%02d" % (k + 1), Ui.mono("Medium"), 11, Ui.ACCENT, 0.0],
				["%s  %s" % [org.name, org.en], Ui.sans(700), 22, col, 30.0],
				["器官基因   ·   碱基对 %d   ·   插入位点 %d / %d" % [ORGAN_PAIRS, k + 1, _sites()], Ui.mono("Medium"), 12, Ui.INK, 54.0],
				[org.desc, Ui.sans(), 12, Ui.INK_SOFT, 76.0],
			]
		else:
			lines = [
				["GENOME MAP  ·  ORGAN SITE ORG-%02d" % (k + 1), Ui.mono("Medium"), 11, Ui.ACCENT, 0.0],
				["空的插入位点  EMPTY SITE", Ui.sans(700), 22, Color(Ui.INK_SOFT, 1.0), 30.0],
				["插入位点 %d / %d   ·   没有碱基对" % [k + 1, _sites()], Ui.mono("Medium"), 12, Ui.INK, 54.0],
				["在左下角“器官”里装一个器官，它的基因会插进这里。", Ui.sans(), 12, Ui.INK_SOFT, 76.0],
			]
	var budget := int(type_t * 90.0)
	for line in lines:
		var text: String = line[0]
		var n := mini(text.length(), budget)
		budget -= text.length()
		if n <= 0:
			break
		var shown_text := text.substr(0, n) + ("▌" if n < text.length() else "")
		ci.draw_string(line[1], o + Vector2(0, line[4]), shown_text, HORIZONTAL_ALIGNMENT_LEFT, 440, line[2], line[3])
	ci.draw_line(o + Vector2(0, 88), o + Vector2(300.0 * clampf(type_t / 0.5, 0.0, 1.0), 88), Color(Ui.LINE_STRONG, 0.6), 1.0)
	# Whole-genome readouts, top right of the stage.
	var total := 0
	for k in GENES.size():
		total += int(2.0 + 2.0 * genes[k])
	var r := Vector2(1290, 116)
	ci.draw_string(Ui.mono("Medium"), r, "LOCI %d  ·  BP %d" % [NG, total], HORIZONTAL_ALIGNMENT_RIGHT, 150, 11, Ui.ACCENT)
	ci.draw_string(Ui.mono("Medium"), r + Vector2(0, 18), "GC %d%%" % _gc_percent(), HORIZONTAL_ALIGNMENT_RIGHT, 150, 11, Ui.INK_SOFT)


# Organ sites on the stage: a tag over each (the organ's name, or 插入位点 ·
# 空), with a leader down to the site; the focused one bracketed.
const ORGAN_PAIRS := 8


func _draw_organ_tags(ci: CanvasItem, across: Vector2) -> void:
	for k in _sites():
		var off := absf(_organ_x(k) - view_x)
		var vis := 1.0 - smoothstep(STAGE_HALF_VIEW - 120.0, STAGE_HALF_VIEW + 20.0, off)
		if vis <= 0.0:
			continue
		var a := STAGE_CENTER + Vector2(_organ_x(k) - view_x, 0.0).rotated(STAGE_ANGLE)
		var full := k < organs.size()
		var lit := k == organ_focus
		var col: Color = Ui.ACCENT if full else LAB_GREY
		col.a = vis
		var amp := STAGE_AMP * _lens(_organ_x(k))
		var from := a - across * amp * 1.45
		var to := from - across * 52.0
		ci.draw_line(from, to, Color(col, 0.8 * vis), 1.0, true)
		ci.draw_rect(Rect2(from - Vector2(2.5, 2.5), Vector2(5, 5)), Color(col, 0.9 * vis))
		var tag := to + Vector2(-40.0, -26.0)
		ci.draw_string(Ui.mono("Medium"), tag, "ORG·%02d" % (k + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(col, 0.85 * vis))
		var name: String = Organs.by_id(organs[k]).name if full else "插入位点 · 空"
		ci.draw_string(Ui.sans(700), tag + Vector2(0, 17), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 14 if lit else 13, col if full else Color(Ui.INK_SOFT, vis))
		if lit:
			var w := Ui.sans(700).get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
			_brackets(ci, Rect2(tag - Vector2(8, 14), Vector2(maxf(w, 60.0) + 16.0, 38)), col)


# The whole genome in one line: a tick per gene, the window the lab is
# looking through, the selected gene in the accent. Click to jump.
func _draw_navigator(ci: CanvasItem) -> void:
	var r := NAV_RECT
	var y := r.get_center().y
	ci.draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), Color(LAB_GREY, 0.6), 1.0)
	for k in GENES.size():
		var x := _nav_x(_gene_x(k))
		var on := k == sel_gene
		ci.draw_line(Vector2(x, y - (6.0 if on else 3.0)), Vector2(x, y + (6.0 if on else 3.0)), Ui.ACCENT if on else LAB_GREY, 2.0 if on else 1.0)
		ci.draw_string(Ui.mono("Medium"), Vector2(x - 20.0, r.position.y - 4.0), GENE_CODES[k], HORIZONTAL_ALIGNMENT_CENTER, 40, 9, Ui.ACCENT if on else Ui.INK_FAINT)
	for k in _sites():
		var x := _nav_x(_organ_x(k))
		var on := k == organ_focus
		var full := k < organs.size()
		var c: Color = Ui.ACCENT if full else LAB_GREY
		if full:
			ci.draw_rect(Rect2(x - 3.0, y - 3.0, 6.0, 6.0), c)
		else:
			ci.draw_rect(Rect2(x - 3.0, y - 3.0, 6.0, 6.0), c, false, 1.0)
		if on:
			ci.draw_line(Vector2(x, y - 7.0), Vector2(x, y + 7.0), Ui.ACCENT, 2.0)
		ci.draw_string(Ui.mono("Medium"), Vector2(x - 20.0, r.position.y - 4.0), "ORG%d" % (k + 1), HORIZONTAL_ALIGNMENT_CENTER, 40, 9, Ui.ACCENT if on or full else Ui.INK_FAINT)
	var w0 := maxf(_nav_x(view_x - STAGE_HALF_VIEW), r.position.x)
	var w1 := minf(_nav_x(view_x + STAGE_HALF_VIEW), r.end.x)
	var win := Rect2(w0, y - 7.0, w1 - w0, 14.0)
	ci.draw_rect(win, Color(Ui.ACCENT, 0.08))
	_brackets(ci, win, Color(Ui.ACCENT, 0.9))
	ci.draw_string(Ui.mono("Medium"), Vector2(r.end.x - 160.0, r.end.y + 14.0), "← → 切换基因", HORIZONTAL_ALIGNMENT_RIGHT, 160, 9, Ui.INK_FAINT)


# A gene's base pairs at a level: how many, and which sequence.
static func _pairs(lv: float) -> int:
	return roundi(2.0 + 2.0 * lv)


static func _ver(lv: float) -> int:
	return roundi(lv * 2.0)


# Gene edits: start one when a gene's level differs from what its pairs
# show (sliders, mutation, loading a design all land here); a change in the
# middle of one runs it faster and follows on when it is done.
func _tick_edits(delta: float) -> void:
	if bp_lv.size() != NG:
		bp_lv = genes.duplicate()
		bp_from = genes.duplicate()
	for k in NG:
		if edit_t[k] < EDIT_LEN:
			edit_t[k] += delta * (2.5 if genes[k] != bp_lv[k] else 1.0)
		elif genes[k] != bp_lv[k]:
			bp_from[k] = bp_lv[k]
			bp_lv[k] = genes[k]
			edit_t[k] = 0.0
		else:
			edit_t[k] = minf(edit_t[k] + delta, 99.0)
	for k in 4:
		var want := -1.0
		if k < _sites() and k < organs.size():
			want = float(Organs.index_of(organs[k]))
		if _org_init and want != org_ids[k]:
			org_old[k] = org_ids[k]
			org_t[k] = 0.0
			focus_organ(k)
		org_ids[k] = want
		org_t[k] = minf(org_t[k] + delta, 99.0)
	_org_init = true


# Whether new pair j (of n) of gene k has locked in yet.
func _pair_in(k: int, j: int, n: int) -> bool:
	var s := EDIT_CUT + EDIT_LEAD + (float(j) + 0.5) / float(n) * EDIT_STAG
	return edit_t[k] >= s + EDIT_INS * 0.7


func _tick_cursor_fx() -> void:
	if mouse_on > 0.01 or lock_t < 1.2 or dragging or coasting:
		cursor_fx.queue_redraw()
	elif cursor_fx.get_meta("dirty", false):
		cursor_fx.queue_redraw()
	cursor_fx.set_meta("dirty", mouse_on > 0.01 or lock_t < 1.2 or dragging or coasting)


# The holographic cursor (reticle + what it is pointing at), the lock-on
# brackets when the strand arrives.
func _draw_cursor_fx() -> void:
	if busy or page != "genome":
		return
	var ci := cursor_fx
	var glo := Color(0.1, 0.78, 0.9)
	# Lock-on: four corners close in on the selected gene.
	if lock_t < 1.2:
		var e := 1.0 - pow(1.0 - clampf(lock_t / 0.35, 0.0, 1.0), 3.0)
		var a := 1.0 - _ease((lock_t - 0.6) / 0.5)
		var hx := STAGE_CODING / 14.0 * lerpf(1.7, 1.0, e)
		var hy := STAGE_AMP * 1.55 * lerpf(1.7, 1.0, e)
		ci.draw_set_transform(STAGE_CENTER, STAGE_ANGLE, Vector2.ONE)
		var col := Color(Ui.ACCENT, a)
		for c in [Vector2(-hx, -hy), Vector2(hx, -hy), Vector2(hx, hy), Vector2(-hx, hy)]:
			var sx := -signf(c.x) * 18.0
			var sy := -signf(c.y) * 18.0
			ci.draw_line(c, c + Vector2(sx, 0), col, 2.0)
			ci.draw_line(c, c + Vector2(0, sy), col, 2.0)
		ci.draw_string(Ui.mono("Medium"), Vector2(hx - 64.0, -hy - 6.0), "LOCKED", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col)
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if mouse_on < 0.01 and not dragging:
		return
	var m := mouse_pos
	var a := maxf(mouse_on, 1.0 if dragging else 0.0)
	var spin_a := spin * 1.4
	ci.draw_arc(m, 20.0, 0.0, TAU, 32, Color(glo, 0.25 * a), 5.0, true)
	ci.draw_arc(m, 20.0, 0.0, TAU, 32, Color(Ui.ACCENT, 0.9 * a), 1.2, true)
	for k in 4:
		var d := Vector2.from_angle(spin_a + PI * 0.5 * k)
		ci.draw_line(m + d * 24.0, m + d * 31.0, Color(Ui.ACCENT, 0.9 * a), 1.5, true)
	ci.draw_circle(m, 1.8, Color(Ui.ACCENT, a))
	# What the reticle is on.
	var text := "拖动浏览 · 松开吸附" if dragging else _probe_text(m)
	var tp := m + Vector2(36.0, -10.0)
	var tw := Ui.mono("Medium").get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	ci.draw_rect(Rect2(tp + Vector2(-6, -14), Vector2(tw + 12, 20)), Color(1, 1, 1, 0.75 * a))
	ci.draw_rect(Rect2(tp + Vector2(-6, -14), Vector2(tw + 12, 20)), Color(Ui.ACCENT, 0.6 * a), false, 1.0)
	ci.draw_string(Ui.mono("Medium"), tp, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(LAB_INK, a))


# The base pair under the reticle: gene, pair number, the pair itself.
func _probe_text(screen: Vector2) -> String:
	var q := (screen - STAGE_CENTER).rotated(-STAGE_ANGLE)
	var x := q.x + view_x
	if absf(x) > STAGE_CODING * 0.5:
		return "非编码区 · NON-CODING"
	var seg := STAGE_CODING / float(NG)
	var g := clampi(int((x + STAGE_CODING * 0.5) / seg), 0, NG - 1)
	var x0 := -STAGE_CODING * 0.5 + seg * g
	var n := _pairs(genes[g])
	var j := clampi(int((x - x0) / seg * n), 0, n - 1)
	var b := GenomeArt.base_of(g, j, _ver(genes[g]))
	return "%s·%02d   BP %02d   %s–%s" % [GENE_CODES[g], g + 1, j + 1, GenomeArt.BASE_LETTERS[b], GenomeArt.BASE_LETTERS[b ^ 1]]


func _lv(v: float) -> String:
	return str(v).trim_suffix(".0")


# Share of G–C pairs across the genome (the same bases the shader draws).
func _gc_percent() -> int:
	var gc := 0
	var all := 0
	for k in GENES.size():
		for j in _pairs(genes[k]):
			all += 1
			if GenomeArt.base_of(k, j, _ver(genes[k])) >= 2:
				gc += 1
	return roundi(100.0 * gc / maxf(all, 1.0))


func _brackets(ci: CanvasItem, r: Rect2, col: Color) -> void:
	var l := 7.0
	for c in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		var sx := 1.0 if c.x == r.position.x else -1.0
		var sy := 1.0 if c.y == r.position.y else -1.0
		ci.draw_line(c, c + Vector2(l * sx, 0), col, 1.4)
		ci.draw_line(c, c + Vector2(0, l * sy), col, 1.4)


# Left: the specimen tank, the karyotype, name and colour, reference.
func _build_tank() -> void:
	chamber = _panel(24, 92, 420, 948, Vector4(18, 14, 18, 14))
	var v := _vbox(chamber.body, 6)
	var head := _hbox(v, 8)
	head.add_child(Ui.caption("样本培养舱", "SPECIMEN TANK"))
	_spacer(head)
	name_label = Ui.label("采集者", 12, Ui.INK_SOFT, Ui.sans(500))
	head.add_child(name_label)
	var row := _hbox(v, 6)
	for k in SWATCHES.size():
		var sw := Swatch.new(SWATCHES[k])
		var idx := k
		sw.pressed.connect(func() -> void:
			color = SWATCHES[idx]
			for j in swatch_buttons.size():
				swatch_buttons[j].selected = j == idx)
		sw.selected = k == 0
		row.add_child(sw)
		swatch_buttons.append(sw)
	_spacer(row)
	name_edit = LineEdit.new()
	name_edit.text = "设计物种 A-%02d" % (designs + 1)
	name_edit.max_length = 12
	name_edit.custom_minimum_size = Vector2(170, 30)
	name_edit.add_theme_font_override("font", Ui.sans(600))
	name_edit.add_theme_font_size_override("font_size", 14)
	name_edit.add_theme_color_override("font_color", Ui.INK)
	var nsb := StyleBoxFlat.new()
	nsb.bg_color = Color(1, 1, 1, 0.5)
	nsb.border_color = Color(Ui.LINE_STRONG, 0.5)
	nsb.set_border_width_all(1)
	nsb.set_corner_radius_all(6)
	nsb.content_margin_left = 8
	nsb.content_margin_right = 8
	name_edit.add_theme_stylebox_override("normal", nsb)
	var fsb := nsb.duplicate()
	fsb.border_color = Ui.ACCENT
	name_edit.add_theme_stylebox_override("focus", fsb)
	name_edit.tooltip_text = "物种名（点击修改）"
	row.add_child(name_edit)
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(fill)
	# Organ slots (chapter 2 on): in place of the fitness forecast.
	if organ_slots() > 0:
		organ_bay = preload("res://scripts/ui/organ_bay.gd").new()
		organ_bay.setup(organ_slots(), level_id(), _toast)
		organ_bay.changed.connect(func() -> void:
			var was: int = deck_editor.diet
			_set_organs(organ_bay.organs)
			if rules_mode == "simple" and persona != "":
				# Simple mode: the personality follows the new body (a grazer's
				# set <-> a predator's), or falls back to the standard one.
				if not Personas.available(level_id(), int(deck_editor.diet), organs).any(func(q: Dictionary) -> bool: return q.id == persona):
					persona = "standard"
				_apply_persona(false)
				_refresh_personas()
			else:
				_swap_diet_deck(was))
		v.add_child(organ_bay)
	# (A level with organs needs the room; its reference cell is someone else.)
	if not ref_info.is_empty() and organ_bay == null:
		ref_button = Widgets.Pill.new("参考这只细胞：%s" % ref_info.name, 0, Ui.sans(500))
		ref_button.custom_minimum_size = Vector2(0, 36)
		ref_button.tooltip_text = "把它的基因和规则复制过来作为起点（仍然是你的新物种）"
		ref_button.pressed.connect(apply_reference)
		v.add_child(ref_button)
	# The organism itself: one instance of the real organism shader.
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.use_custom_data = true
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	mm.mesh = quad
	mm.instance_count = 1
	specimen = MultiMeshInstance2D.new()
	specimen.multimesh = mm
	var sm := ShaderMaterial.new()
	sm.shader = preload("res://shaders/organism.gdshader")
	sm.set_shader_parameter("bare_nucleus", 1.0)
	specimen.material = sm
	add_child(specimen)
	# Tank glass, scale, karyotype: static, redrawn only on change.
	rings = Control.new()
	rings.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rings.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rings.draw.connect(_draw_rings)
	add_child(rings)
	# Bubbles and the scan ring: the only per-frame drawing in the tank.
	tank_fx = Control.new()
	tank_fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tank_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tank_fx.draw.connect(_draw_tank_fx)
	add_child(tank_fx)


# Right: the gene editor. Sliders stay the main control; each row lights its
# segment of the DNA and its chromosome.
func _build_gene_panel() -> void:
	var p := _panel(1476, 92, 1896, 948)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	p.body.add_child(scroll)
	var v := _vbox(scroll, 4)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var head := _hbox(v, 8)
	head.add_child(Ui.caption("基因编辑", "GENE EDITOR"))
	var instruction := Ui.label("点击 DNA 片段选择基因，也可以直接拖动右侧滑块调整等级。", 11, Ui.INK_FAINT, Ui.sans())
	instruction.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	instruction.custom_minimum_size.x = 340
	v.add_child(instruction)
	for k in GENES.size():
		var gr := GeneRow.new(Ui.ACCENT)
		v.add_child(gr)
		gene_rows.append(gr)
		var idx := k
		gr.picked.connect(func() -> void: select_gene(idx))
		var cell := _vbox(gr, 0)
		var top := _hbox(cell, 6)
		top.add_child(Ui.label("%02d" % (k + 1), 11, Ui.ACCENT, Ui.mono("Medium")))
		top.add_child(Ui.label(GENES[k][0], 14, Ui.INK, Ui.sans(600)))
		top.add_child(Ui.label(GENE_CODES[k], 10, Ui.INK_FAINT, Ui.mono("Medium")))
		_spacer(top)
		var cost := Ui.label("", 12, Ui.INK_SOFT, Ui.mono())
		top.add_child(cost)
		cost_labels[k] = cost
		var slider := GeneSlider.new(genes[k])
		gene_sliders.append(slider)
		slider.changed.connect(func(val: float) -> void:
			Audio.sfx("gene_up", -2.0, 0.75 + 0.12 * val)
			genes[idx] = val
			select_gene(idx)
			pulse[idx] = 1.0
			rot_speed = 1.8
			if idx == 6:
				deck_editor.slots = Rules.slots(val)
				deck_editor._sync_views()
			_refresh())
		cell.add_child(slider)
		if k == 4:
			life_slider = LifeSlider.new(life)
			life_slider.changed.connect(func(val: float) -> void:
				life = val
				select_gene(4)
				_refresh())
			life_slider.visible = rule_open("life_open")
			cell.add_child(life_slider)
		if k == 7:
			temp_slider = TempSlider.new(temp_opt)
			temp_slider.changed.connect(func(val: float) -> void:
				temp_opt = val
				select_gene(7)
				_refresh())
			cell.add_child(temp_slider)
			acid_slider = AcidSlider.new(acid_tol)
			acid_slider.changed.connect(func(val: float) -> void:
				acid_tol = val
				select_gene(7)
				_refresh())
			acid_slider.visible = rule_open("acid_open")
			cell.add_child(acid_slider)
		var desc := Ui.label(GENES[k][2], 13, Ui.INK_SOFT, Ui.sans())
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.custom_minimum_size.x = 340
		cell.add_child(desc)
	gene_rows[0].selected = true


# Rules page, middle: how a deck runs.
func _flow(parent: Control) -> HFlowContainer:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 8)
	parent.add_child(flow)
	return flow


# The campaign level being designed for ("" in the sandbox).
func level_id() -> String:
	# Developer mode can open everything, as in the sandbox.
	return "" if DevMode.on(DevMode.all_genes) else str(level_rules.get("id", ""))


# Organ slots in this level (0 in chapter 1). The sandbox is everything open
# (2026-10-30: "沙盒模式就是全开的模式"): the full four, every organ.
const SANDBOX_SLOTS := 4
const SANDBOX_GENES_MAX := 32.0 # eight genes from 1 to 5


func organ_slots() -> int:
	if level_rules.is_empty():
		return SANDBOX_SLOTS
	return int(level_rules.get("organ_slots", 0))


# Organs installed: the body (diet, size), which pieces can be used, the bay.
func _set_organs(ids: Array) -> void:
	organs = ids.duplicate()
	if organ_bay and organ_bay.organs != organs:
		organ_bay.set_organs(organs)
	var p := Organs.apply({diet = 0}, organs)
	deck_editor.diet = int(p.diet)
	deck_editor._sync_views()
	name_label.text = ["采集者", "捕食者", "化能生命", "生产者"][clampi(int(p.diet), 0, 3)]
	_update_pieces()
	_refresh()


# Library pieces: grey when the level has not opened them, or when they need
# an organ that is not installed (it says which).
func _update_pieces() -> void:
	var lid := level_id()
	for b: PieceChip in piece_chips:
		var spec: Array = Rules.CONDS[b.id] if b.kind == "cond" else Rules.ACTS[b.id]
		var help: String = spec[6] if b.kind == "cond" else spec[1]
		var need := Organs.needed_for(b.kind, b.id)
		if not Rules.piece_open(b.kind, b.id, lid):
			b.locked = true
			b.tooltip_text = "%s
%s" % [Rules.opens_text(b.kind, b.id), help]
		elif rules_readonly():
			b.locked = true
			b.tooltip_text = "本关只能看，不能改
%s" % help
		elif lid != "" and need != "" and not organs.has(need):
			b.locked = true
			b.tooltip_text = "需要器官：%s（在基因组页装上）
%s" % [Organs.by_id(need).name, help]
		else:
			b.locked = false
			b.tooltip_text = help


# A level that only shows the deck (1-2): read it, run it, change nothing.
func rules_readonly() -> bool:
	return bool(level_rules.get("rules_readonly", false))


# The deck a design starts from: the level's own, else the default.
# A cnidocyst in or out changes what the cell eats: a deck the player has not
# touched yet follows (grazer's set <-> the predator's: see prey -> hunt, lurk
# when low), so installing one doesn't leave a deck that can't feed.
# (Review round 3: editing two cards right after the organ was one step too many.)
func _swap_diet_deck(was: int) -> void:
	var now: int = deck_editor.diet
	if now == was or level_id() == "" or not sp_slots.is_empty():
		return
	var texts := func(d: Array) -> Array: return d.map(func(c: Dictionary) -> String: return Rules.card_text(c))
	var base: Array = start_deck() if was == 0 else _fit_deck(Rules.default_deck(1))
	if texts.call(deck_editor.deck) != texts.call(base):
		return
	deck_editor.edit(func() -> void: deck_editor.deck = _fit_deck(Rules.default_deck(1)) if now == 1 else start_deck())
	_toast("已切换为捕食者规则，发现猎物后会主动追捕。" if now == 1 else "已恢复原来的觅食规则，重新以藻团为食。")


func start_deck() -> Array:
	var d: Array = (level_rules.deck as Array).duplicate(true) if level_rules.has("deck") else Rules.default_deck(0)
	return _fit_deck(d)


# No hunters in the level: a "hunter near -> flee" card there only raised
# "what hunter?" (review rounds 5-6).
func _fit_deck(d: Array) -> Array:
	if level_id() != "" and not _has_hunters():
		d = d.filter(func(c: Dictionary) -> bool: return c.act != Rules.A_FLEE)
	return d


func _has_hunters() -> bool:
	for sp: Dictionary in (Levels.by_id(level_id()).get("world", {}) as Dictionary).get("species", []):
		if int(sp.get("params", sp).get("diet", 0)) == 1:
			return true
	return not sp_slots.is_empty()


func _build_deck() -> void:
	var p := _panel(428, 92, 1896, 948, Vector4(24, 16, 24, 16))
	var v := _vbox(p.body, 12)
	var head := _hbox(v, 8)
	var cap := Ui.caption("行为规则", "BEHAVIOUR DECK")
	head.add_child(cap)
	# Simple | advanced: a two-way switch beside the title.
	var gap := Control.new()
	gap.custom_minimum_size.x = 18
	head.add_child(gap)
	mode_simple = Widgets.Pill.new("性格预设", 96, Ui.sans(600))
	mode_simple.pressed.connect(func() -> void: set_rules_mode("simple"))
	head.add_child(mode_simple)
	mode_adv = Widgets.Pill.new("高级编辑", 96, Ui.sans(600))
	mode_adv.pressed.connect(func() -> void: set_rules_mode("advanced"))
	head.add_child(mode_adv)
	for b: Control in [mode_simple, mode_adv]:
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_spacer(head)
	slot_label = Ui.label("", 12, Ui.ACCENT, Ui.mono("Medium"))
	slot_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(slot_label)
	undo_pill = Widgets.Pill.new("撤销  Ctrl+Z", 108, Ui.sans(500))
	undo_pill.pressed.connect(func() -> void: deck_editor.undo())
	head.add_child(undo_pill)
	reset_pill = Widgets.Pill.new("恢复默认", 84, Ui.sans(500))
	reset_pill.pressed.connect(func() -> void: deck_editor.set_deck(start_deck(), true))
	head.add_child(reset_pill)
	# The state map (from the level that opens states; the sandbox too).
	var states_here := Rules.state_open(Rules.S_SLEEP, level_id())
	if states_here:
		state_bar = preload("res://scripts/ui/state_bar.gd").new()
		state_bar.level_id = level_id()
		state_bar.toast = _toast
		v.add_child(state_bar)
	deck_scroll = ScrollContainer.new()
	deck_scroll.custom_minimum_size = Vector2(1420, 690 - (122 if states_here else 0))
	deck_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(deck_scroll)
	deck_editor = DeckEditor.new()
	deck_editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	deck_scroll.add_child(deck_editor)
	deck_editor.changed.connect(_refresh)
	if state_bar:
		state_bar.ed = deck_editor
		deck_editor.changed.connect(state_bar.queue_redraw)
		deck_editor.state_changed.connect(state_bar.queue_redraw)
	add_button = Widgets.Pill.new("+  添加规则", 0, Ui.sans(600))
	add_button.custom_minimum_size = Vector2(0, 44)
	add_button.pressed.connect(func() -> void:
		deck_editor.selected = -1
		var k: int = deck_editor.add_card()
		if k >= 0:
			_scroll_to_card(k))
	v.add_child(add_button)
	deck_editor.slots = Rules.slots(genes[6])
	if state_bar:
		state_bar.max_states = Rules.max_states(genes[6])
		state_bar.queue_redraw()
	deck_editor.logic = Rules.logic_open(level_id())
	deck_editor.set_deck(start_deck())
	set_rules_mode(last_mode if Personas.advanced_open(level_id()) else "simple", true)


# --- rules page modes ---------------------------------------------------------------

func set_rules_mode(m: String, quiet := false) -> void:
	if m == "advanced" and not Personas.advanced_open(level_id()):
		_toast("高级编辑在第 %s 关开放：先用性格预设就够了" % Personas.ADVANCED_OPENS)
		return
	if not quiet:
		last_mode = m
	rules_mode = m
	var adv := m == "advanced"
	mode_simple.active = not adv
	mode_adv.active = adv
	mode_adv.modulate.a = 1.0 if Personas.advanced_open(level_id()) else 0.45
	mode_adv.tooltip_text = "逐张修改规则卡：拖零件、改顺序、加卡" if Personas.advanced_open(level_id()) else "第 %s 关开放" % Personas.ADVANCED_OPENS
	lib_box.visible = adv
	persona_picker.visible = not adv
	deck_editor.readonly = rules_readonly() or not adv
	add_button.visible = adv and not rules_readonly()
	undo_pill.visible = adv and not rules_readonly()
	reset_pill.visible = adv and not rules_readonly()
	if state_bar:
		state_bar.visible = adv
	if not adv:
		deck_editor.set_state(Rules.S_FORAGE)
		deck_editor.selected = -1
		_refresh_personas()
	deck_editor._sync_views()
	for k in deck_editor.views.size():
		deck_editor.views[k].queue_redraw()


# The personalities this level and body allow; the picked one lit (none when
# the deck was edited by hand).
func _refresh_personas() -> void:
	var items := Personas.available(level_id(), int(deck_editor.diet), organs)
	if persona != "" and not items.any(func(q: Dictionary) -> bool: return q.id == persona):
		persona = "standard"
		bold = 0.5
		_apply_persona(false)
	elif persona != "" and _persona_deck_texts() != _deck_texts(deck_editor.deck):
		persona = ""
	persona_picker.set_list(items, persona)
	persona_picker.slider.set_value(bold)
	persona_picker.slider.modulate.a = 1.0 if persona != "" else 0.45
	persona_picker.summary.text = Personas.summary(deck_editor.deck, bold) if persona != "" else "现在是在“高级编辑”里改过的规则；点一种性格会换掉它。"
	persona_picker.note.text = "想逐张改规则：点右边的“高级编辑”。" if Personas.advanced_open(level_id()) else "高级编辑：第 %s 关开放，届时可以自己修改每条行为规则。" % Personas.ADVANCED_OPENS


func _deck_texts(d: Array) -> Array:
	return d.map(func(c: Dictionary) -> String: return Rules.card_text(c))


# The standard personality: the level's deck, or the predator's set once a
# cnidocyst is in.
func _persona_base() -> Array:
	var base := start_deck()
	if int(deck_editor.diet) == 1 and not base.any(func(c: Dictionary) -> bool: return c.act == Rules.A_HUNT):
		base = _fit_deck(Rules.default_deck(1))
	return base


func _persona_deck() -> Array:
	var d := _fit_deck(Personas.build(persona, _persona_base(), bold))
	return d.slice(0, deck_editor.slots)


func _persona_deck_texts() -> Array:
	return _deck_texts(_persona_deck())


func _apply_persona(record: bool) -> void:
	if persona == "":
		return
	deck_editor.set_deck(_persona_deck(), record)


func _pick_persona(id: String) -> void:
	if rules_readonly():
		return
	var was := persona
	persona = id
	_apply_persona(true)
	Audio.sfx("ui_click", -6.0)
	if was == "":
		_toast("已换成“%s”。之前改过的规则，可以在高级编辑里按 Ctrl+Z 撤回。" % Personas.by_id(id).name)
	_refresh_personas()


func _set_bold(v: float, done: bool) -> void:
	if persona == "" or rules_readonly():
		return
	bold = v
	_apply_persona(done)
	persona_picker.summary.text = Personas.summary(deck_editor.deck, bold)


func _scroll_to_card(k: int) -> void:
	await get_tree().process_frame
	var y: float = deck_editor._target_y(k)
	var t := Ui.tween(deck_scroll)
	t.tween_property(deck_scroll, "scroll_vertical", int(maxf(0.0, y - 40.0)), Ui.T_MID)


# --- rule handbook page ----------------------------------------------------------

func _build_handbook() -> void:
	var p := _panel(24, 92, 1896, 948, Vector4(28, 20, 28, 20))
	pages.handbook = [p]
	var h := _hbox(p.body, 36)
	var left := _vbox(h, 12)
	left.custom_minimum_size.x = 520
	left.add_child(Ui.caption("规则怎么运行", "HOW A DECK RUNS"))
	var flow := FlowDiagram.new()
	left.add_child(flow)
	left.add_child(Ui.label("每个生命每秒检查自己的卡组 15 次。\n从第 1 张开始往下看：条件都成立、动作此刻也做得到，\n这张卡就生效，后面的不再检查。一张也不生效时，它会漫游。\n\n“做得到”的意思：比如“游向藻团”需要视野里真的有藻团，\n“分裂”需要攒够一个新身体的能量且冷却结束。\n做不到时不算失败，直接看下一张。", 13, Ui.INK_SOFT, Ui.sans()))
	left.add_child(Ui.caption("遗传与变异", "INHERITANCE"))
	left.add_child(Ui.label("分裂时，后代复制母体的整副卡组。少数后代会变异：\n阈值漂移（最常见）、两张卡换序、复制一张、删掉一张、\n或把某个条件 / 动作换成另一个零件。\n卡槽数由神经基因决定，神经变小时最下面的卡会被遗忘。", 13, Ui.INK_SOFT, Ui.sans()))
	for spec in [["条件", "CONDITIONS", "cond"], ["动作", "ACTIONS", "act"]]:
		var col := _vbox(h, 10)
		col.custom_minimum_size.x = 600
		col.add_child(Ui.caption(spec[0], spec[1]))
		if spec[2] == "cond":
			for c in range(1, Rules.CONDS.size()):
				col.add_child(_handbook_row(Rules.CONDS[c][0], Rules.CONDS[c][6], "阈值 " + _range_text(c) if Rules.has_threshold(c) else ""))
		else:
			for a in Rules.ACTS.size():
				col.add_child(_handbook_row(Rules.ACTS[a][0], Rules.ACTS[a][1], ""))


func _range_text(c: int) -> String:
	var spec: Array = Rules.CONDS[c]
	return "%s – %s" % [Rules.threshold_text(c, spec[2]), Rules.threshold_text(c, spec[3])]


func _handbook_row(title: String, text: String, extra: String) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	var top := _hbox(v, 10)
	top.add_child(Ui.label(title, 15, Ui.INK, Ui.sans(700)))
	if extra != "":
		top.add_child(Ui.label(extra, 11, Ui.ACCENT, Ui.mono("Medium")))
	v.add_child(Ui.label(text, 12, Ui.INK_SOFT, Ui.sans()))
	return v


# --- species library page --------------------------------------------------------

func _build_species_library() -> void:
	var p := _panel(24, 92, 1896, 948, Vector4(28, 20, 28, 20))
	pages.library = [p]
	var v := _vbox(p.body, 14)
	var head := _hbox(v, 10)
	head.add_child(Ui.caption("物种库", "SPECIES LIBRARY"))
	_spacer(head)
	head.add_child(Ui.label("保存过的设计会一直留在这里；载入后可以继续修改再投放", 12, Ui.INK_FAINT, Ui.sans()))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(1800, 760)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	library_box = HFlowContainer.new()
	library_box.add_theme_constant_override("h_separation", 18)
	library_box.add_theme_constant_override("v_separation", 18)
	library_box.custom_minimum_size.x = 1790
	scroll.add_child(library_box)
	library = SpeciesLibrary.load_all()
	_fill_library()


func _fill_library() -> void:
	for c in library_box.get_children():
		c.queue_free()
	if library.is_empty():
		library_box.add_child(Ui.label("还没有保存的设计。在“生命设计”页点底部的“保存到物种库”。", 14, Ui.INK_FAINT, Ui.sans(500)))
		return
	for k in library.size():
		var card := _library_card(k, library[k])
		library_box.add_child(card)


func _library_card(k: int, d: Dictionary) -> Control:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.62)
	sb.border_color = Color(Ui.LINE_STRONG, 0.5)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(10)
	for side in ["left", "right", "top", "bottom"]:
		sb.set("content_margin_" + side, 16)
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(420, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	var head := _hbox(v, 8)
	head.add_child(Widgets.Chip.new(d.color, 14))
	head.add_child(Ui.label(d.name, 17, Ui.INK, Ui.sans(700)))
	_spacer(head)
	head.add_child(Ui.label("%d 张规则" % d.deck.size(), 11, Ui.INK_FAINT, Ui.mono()))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	v.add_child(grid)
	for g in GENES.size():
		var row := _hbox(grid, 6)
		var n := Ui.label(GENES[g][0], 11, Ui.INK_SOFT, Ui.sans(500))
		n.custom_minimum_size.x = 30
		row.add_child(n)
		var m := Widgets.Meter.new(Ui.ACCENT, 3)
		m.custom_minimum_size.x = 120
		m.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		m.set_ratio((float(d.genes[g]) - 1.0) / 4.0)
		row.add_child(m)
	for cd in d.deck.slice(0, 4):
		v.add_child(Ui.label("·  " + Rules.card_text(cd), 11, Ui.INK_SOFT, Ui.sans()))
	if d.deck.size() > 4:
		v.add_child(Ui.label("…还有 %d 张" % (d.deck.size() - 4), 11, Ui.INK_FAINT, Ui.sans()))
	var row2 := _hbox(v, 8)
	_spacer(row2)
	var del := Widgets.Pill.new("删除", 70, Ui.sans(500))
	del.pressed.connect(func() -> void:
		library.remove_at(k)
		SpeciesLibrary.save_all(library)
		_fill_library()
		_toast("已从物种库删除"))
	row2.add_child(del)
	var load_b := Widgets.Pill.new("载入编辑", 96, Ui.sans(600))
	load_b.active = true
	load_b.pressed.connect(func() -> void: load_design(d))
	row2.add_child(load_b)
	return p


func save_design() -> void:
	var d := _design()
	# Same name replaces the older save.
	for k in library.size():
		if library[k].name == d.name:
			library.remove_at(k)
			break
	library.insert(0, d)
	var ok := SpeciesLibrary.save_all(library)
	_fill_library()
	_toast("已保存到物种库：" + d.name if ok else "保存失败")


func load_design(d: Dictionary) -> void:
	_apply_design(d, true)
	show_page("genome")
	_toast("已载入：" + d.name)


func _apply_design(d: Dictionary, record := false) -> void:
	_set_genes(d.genes)
	_set_temp_opt(float(d.get("temp_opt", 12.0)))
	_set_mutates(bool(d.get("mutates", true)))
	_set_resp(int(d.get("resp", level_rules.get("resp", Resp.ANAEROBIC))))
	life = float(d.get("life", 1.0))
	if life_slider:
		life_slider.value = life
		life_slider.queue_redraw()
	acid_tol = float(d.get("acid_tol", 0.0))
	if acid_slider:
		acid_slider.value = acid_tol
		acid_slider.queue_redraw()
	_set_euk(bool(d.get("euk", false)))
	_set_organs(d.get("organs", []))
	color = d.color
	name_edit.text = d.name
	for j in swatch_buttons.size():
		swatch_buttons[j].selected = SWATCHES[j].is_equal_approx(color)
	persona = str(d.get("persona", persona))
	bold = float(d.get("bold", bold))
	deck_editor.set_deck(d.deck, record)
	_enforce_rules()
	if persona_picker and rules_mode == "simple":
		_refresh_personas()


# In a campaign level: locked genes sit at the level's fixed values and
# cannot be moved, locked pages show when they open, the budget is the
# level's own with the low-budget star marked on the bar.
func _enforce_rules() -> void:
	if level_rules.is_empty():
		return
	var open: Array = range(GENES.size()) if DevMode.on(DevMode.all_genes) else level_rules.genes_open
	var fixed: Dictionary = level_rules.fixed
	for k in GENES.size():
		var locked := not open.has(k)
		if locked and fixed.has(k):
			genes[k] = float(fixed[k])
		if k < gene_sliders.size():
			gene_sliders[k].value = genes[k]
			gene_sliders[k].locked = locked
			gene_rows[k].modulate.a = 0.72 if locked else 1.0
			gene_rows[k].tooltip_text = "本关未开放：这个基因固定在 Lv %s" % _lv(genes[k]) if locked else ""
	if temp_slider:
		temp_slider.visible = open.has(7)
		# A level may fix the preferred temperature (the strain as sampled).
		var tf: Variant = level_rules.get("temp_fixed")
		if tf != null:
			_set_temp_opt(float(tf))
		temp_slider.mouse_filter = Control.MOUSE_FILTER_IGNORE if tf != null else Control.MOUSE_FILTER_STOP
		temp_slider.modulate.a = 0.55 if tf != null else 1.0
		temp_slider.tooltip_text = "本关固定：最适水温 %d°C" % int(tf) if tf != null else "最适水温（不花预算）"
	for key in tab_buttons:
		var ok: bool = level_rules.pages_open.has(key)
		tab_buttons[key].modulate.a = 1.0 if ok else 0.45
		tab_buttons[key].tooltip_text = "" if ok else "后面的关卡开放"
	deck_editor.slots = Rules.slots(genes[6])
	if state_bar:
		state_bar.max_states = Rules.max_states(genes[6])
		state_bar.queue_redraw()
	if budget_meter:
		# (The sandbox has no limit: the bar is every gene at its top.)
		budget_meter.max_v = SANDBOX_GENES_MAX if level_rules.is_empty() else budget_max
		budget_meter.limit = not level_rules.is_empty()
		budget_meter.star_v = float(level_rules.star_budget)
	_refresh()


func _set_genes(g: Array) -> void:
	genes = []
	for k in GENES.size():
		genes.append(clampf(roundf(float(g[k]) * 2.0) / 2.0, 1.0, 5.0) if k < g.size() else (2.5 if k == 7 else 3.0))
	for k in gene_sliders.size():
		gene_sliders[k].value = genes[k]
		glow[k] = 1.0
	deck_editor.slots = Rules.slots(genes[6])
	if state_bar:
		state_bar.max_states = Rules.max_states(genes[6])
		state_bar.queue_redraw()
	_refresh()


# Copy the dived-into cell's genome and rules onto the bench. Name and colour
# stay the player's: it is still a new species.
func _set_temp_opt(v: float) -> void:
	temp_opt = clampf(roundf(v), -5.0, 45.0)
	if temp_slider:
		temp_slider.value = temp_opt
		temp_slider.queue_redraw()


func apply_reference() -> void:
	if ref_info.is_empty():
		return
	_set_genes(ref_info.genes)
	_set_temp_opt(float(ref_info.get("temp_opt", 12.0)))
	var deck := []
	for c in ref_info.deck:
		deck.append(Rules.card(c.c1, c.t1, c.c2, c.t2, c.act))
	deck_editor.set_deck(deck, true)
	show_page("genome")
	_toast("已参考 %s 的基因与 %d 张规则卡" % [ref_info.name, deck.size()])


func _design() -> Dictionary:
	return {name = name_edit.text.strip_edges() if name_edit.text.strip_edges() != "" else "未命名物种",
		color = color, genes = genes.duplicate(), deck = deck_editor.deck.duplicate(true), temp_opt = temp_opt, mutates = mutates, resp = resp, life = life, euk = euk, acid_tol = acid_tol,
		organs = organs.duplicate(), persona = persona, bold = bold, blocks = body_bench.cells.duplicate(true) if body_bench and body_counts() else []}


# A switch a level opens (resp_open, life_open, euk_open, acid_open); the
# sandbox has them all (DECISIONS 沙盒补全).
func rule_open(key: String) -> bool:
	return level_rules.is_empty() or DevMode.on(DevMode.all_genes) or bool(level_rules.get(key, false))


# Chapter 6: the respiration switch, shown where a level opens it (6-4 on).
func resp_open() -> bool:
	return rule_open("resp_open")


func _set_resp(r: int) -> void:
	resp = r
	if resp_pill:
		resp_pill.visible = resp_open()
		resp_pill.text = "呼吸：%s" % Resp.name_of(r)
		resp_pill.tooltip_text = Resp.LIST[clampi(r, 0, 3)][2]
	_refresh()


func _set_euk(on: bool) -> void:
	euk = on
	if euk_pill:
		euk_pill.visible = rule_open("euk_open")
		euk_pill.text = "真核：带共生菌" if on else "真核：不带"
		euk_pill.active = on
	_refresh()


func _set_mutates(on: bool) -> void:
	mutates = on
	if mutate_pill:
		mutate_pill.text = "自然变异：开" if on else "自然变异：关"
		mutate_pill.active = on


func show_page(key: String) -> void:
	if key == page:
		return
	if not level_rules.is_empty() and not level_rules.pages_open.has(key):
		return # locked in this level (the tab says so)
	for p in pages[page]:
		p.disappear()
	var old: String = page
	page = key
	for k in tab_buttons:
		tab_buttons[k].active = k == key
	get_tree().create_timer(Ui.T_FAST).timeout.connect(func() -> void:
		for p in pages[old]:
			if old != page:
				p.visible = false)
	# The lab (DNA, tank, specimen) belongs to the genome page.
	var lab := key == "genome"
	for node: CanvasItem in [stage, stage_labels, specimen, rings, tank_fx, genome]:
		if key == "virus" or key == "body":
			node.visible = false # (the cells are given here: no lab at all)
			continue
		var tw := Ui.tween(node)
		if lab:
			node.visible = true
		tw.tween_property(node, "modulate:a", 1.0 if lab else 0.0, Ui.T_MID)
		if not lab:
			tw.tween_callback(func() -> void: node.visible = page == "genome")
	var d := 0.08
	for p in pages[key]:
		p.visible = true
		p.appear(d)
		d += 0.05


func _toast(text: String) -> void:
	# The toast takes the hint's place for a moment, then gives it back (a
	# faded toast that kept its text used to push 投放 off screen).
	toast.text = text
	toast.visible = true
	go_hint.visible = false
	toast.modulate.a = 1.0
	var t := Ui.tween(toast)
	t.tween_interval(1.8)
	t.tween_property(toast, "modulate:a", 0.0, Ui.T_SLOW)
	t.tween_callback(func() -> void:
		toast.visible = false
		toast.text = ""
		go_hint.visible = true)


func _build_footer() -> void:
	var p := _panel(24, 966, 1896, 1056, Vector4(22, 12, 14, 12))
	var h := _hbox(p.body, 28)
	var bv := _vbox(h, 4)
	bv.custom_minimum_size.x = 420
	var bh := _hbox(bv, 8)
	bh.add_child(Ui.label("基因预算", 13, Ui.INK_SOFT, Ui.sans(600)))
	bh.add_child(Ui.label("GENE BUDGET", 10, Ui.INK_FAINT, Ui.mono("Medium")))
	_spacer(bh)
	budget_label = Ui.label("", 15, Ui.INK, Ui.mono("Medium"))
	bh.add_child(budget_label)
	budget_meter = BudgetBar.new()
	bv.add_child(budget_meter)
	for spec in [["energy", "预计耗能", "/s"], ["divide", "分裂所需能量", ""], ["speed", "游速", " µm/s"], ["sight", "视野", " µm"]]:
		var r := Widgets.Readout.new(spec[1], 17, "%.2f" if spec[0] == "energy" else "%d", spec[2])
		r.judged = false
		# What each number means (playtest review: "这些数没有解释").
		r.tooltip_text = {energy = "每秒大约要消耗的能量（不动时更少）：越低，同样的食物撑得越久",
			divide = "攒够这么多能量才分裂一次：越低，生得越快。
规则卡上的“能量 100%”指的就是这么多",
			speed = "全速游动的速度（微米 / 秒）：越快，越早到达，也越耗能",
			sight = "能看见多远的食物、猎物和猎手（微米）"}[spec[0]]
		r.mouse_filter = Control.MOUSE_FILTER_STOP
		h.add_child(r)
		cost_labels[spec[0]] = r
	# The hint and the toast share one column that takes whatever width is
	# left and wraps inside it: however long they get, the buttons stay put.
	var msg := VBoxContainer.new()
	msg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	msg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	msg.clip_contents = true
	h.add_child(msg)
	go_hint = Ui.label("", 14, Ui.WARN, Ui.sans(700))
	go_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	go_hint.custom_minimum_size.x = 1.0
	go_hint.max_lines_visible = 2
	msg.add_child(go_hint)
	toast = Ui.label("", 13, Ui.GOOD, Ui.sans(600))
	toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toast.custom_minimum_size.x = 1.0
	toast.max_lines_visible = 2
	toast.visible = false
	msg.add_child(toast)
	# Natural mutation on / off: off makes a control for "does mutation help?".
	mutate_pill = Widgets.Pill.new("", 136, Ui.sans(600))
	mutate_pill.custom_minimum_size.y = 44
	mutate_pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mutate_pill.tooltip_text = "开：后代会随机突变（基因、最适水温、规则卡）
关：后代和你设计的一模一样，适合做对照实验"
	mutate_pill.pressed.connect(func() -> void: _set_mutates(not mutates))
	h.add_child(mutate_pill)
	_set_mutates(mutates)
	resp_pill = Widgets.Pill.new("", 124, Ui.sans(600))
	resp_pill.custom_minimum_size.y = 44
	resp_pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	resp_pill.pressed.connect(func() -> void:
		_set_resp(Resp.next(resp))
		_toast("呼吸方式：%s。%s" % [Resp.name_of(resp), Resp.LIST[resp][2]]))
	h.add_child(resp_pill)
	_set_resp(resp)
	# The sandbox: whether the body page's blocks make the species.
	if level_rules.is_empty():
		multi_pill = Widgets.Pill.new("", 112, Ui.sans(600))
		multi_pill.custom_minimum_size.y = 44
		multi_pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		multi_pill.tooltip_text = "开：投放的是在「身体」页用方块拼成的多细胞生物（团藻那样）；关：单细胞"
		multi_pill.pressed.connect(func() -> void:
			multicell = not multicell
			_sync_multi()
			_refresh()
			_toast("多细胞：开。去「身体」页拼它的身体。" if multicell else "多细胞：关，投放单细胞。"))
		h.add_child(multi_pill)
	euk_pill = Widgets.Pill.new("", 124, Ui.sans(600))
	euk_pill.custom_minimum_size.y = 44
	euk_pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	euk_pill.tooltip_text = "带共生菌（真核）：一出生体内就有紫光游丝。有氧时产能大增，但更大、更慢、更耗能，没氧的地方反而吃亏"
	euk_pill.pressed.connect(func() -> void:
		_set_euk(not euk)
		_toast("真核：带着共生菌出生，有氧时产能大增，但更大更慢。" if euk else "真核：不带共生菌。"))
	h.add_child(euk_pill)
	_set_euk(euk)
	_sync_multi()
	var save_b := Widgets.Pill.new("保存到物种库", 140, Ui.sans(600))
	save_b.custom_minimum_size.y = 44
	save_b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	save_b.pressed.connect(save_design)
	h.add_child(save_b)
	go = Widgets.Pill.new("投放到培养皿   ▸", 220, Ui.sans(700))
	go.active = true
	go.custom_minimum_size.y = 44
	go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	go.pressed.connect(release)
	h.add_child(go)


# --- live ------------------------------------------------------------------------

func _refresh() -> void:
	if budget_label == null:
		return # still building (the deck editor reports its first deck early)
	var used := 0.0
	if resp_open():
		used += Resp.cost(resp)
	for k in genes.size():
		used += genes[k] - 1.0
		if k == 6:
			cost_labels[k].text = "Lv %s   %d 个卡槽" % [_lv(genes[k]), Rules.slots(genes[k])]
			continue
		if k == 7:
			cost_labels[k].text = "Lv %s   %d ± %d°C" % [_lv(genes[k]), roundi(temp_opt), roundi(3.0 + 4.0 * (genes[k] - 1.0))]
			continue
		var delta: String = ["游动耗能", "感知维持", "体重", "器官维持", "分裂提前", "基础代谢"][k]
		var pct: int = int((genes[k] - 1.0) * [12, 5, 6, 8, 9, -9][k])
		cost_labels[k].text = "Lv %s   %s %+d%%" % [_lv(genes[k]), delta, pct]
	budget_label.text = ("%d · 不限" % int(used)) if level_rules.is_empty() else "%d / %d" % [int(used), int(budget_max)]
	# Error prevention: an over-budget design cannot be released (the
	# sandbox has no budget: 2026-10-30 "取消上限").
	var over := used > budget_max and not DevMode.on(DevMode.free_budget) and not level_rules.is_empty()
	var n_cards: int = deck_editor.deck.size() if deck_editor else 0
	var slots_now := Rules.slots(genes[6])
	var too_many := n_cards > slots_now
	var n_states: int = deck_editor.states_used().size() if deck_editor else 1
	var states_over := n_states > Rules.max_states(genes[6])
	var need: Array = (level_rules.get("require_organs", []) as Array).filter(func(id: String) -> bool: return not organs.has(id))
	var banned: Array = (level_rules.get("forbid_organs", []) as Array).filter(func(id: String) -> bool: return organs.has(id))
	if go:
		var blocked := over or too_many or states_over or not need.is_empty() or not banned.is_empty()
		go.disabled = blocked
		go.active = not blocked
		go.modulate.a = 0.45 if blocked else 1.0
		if not need.is_empty():
			go_hint.text = "本关需要安装「%s」。请先到基因组页面左下角的器官槽安装。" % Organs.by_id(need[0]).name
		elif not banned.is_empty():
			go_hint.text = "这关要当猎物，先把%s卸下来。" % Organs.by_id(banned[0]).name
		elif over:
			go_hint.text = "基因预算超出 %d 点，请降低部分基因等级。" % int(used - budget_max)
		elif states_over:
			go_hint.text = "当前使用了 %d 个状态，但神经 Lv %s 只能支持 %d 个。请删除多余状态或提高神经等级。" % [n_states, _lv(genes[6]), Rules.max_states(genes[6])]
		elif too_many:
			go_hint.text = "规则卡超出 %d 张，请删除部分规则卡或提高神经等级。" % (n_cards - slots_now)
		elif level_rules.has("star_shots"):
			go_hint.text = "第三颗星看投放次数，不看基因预算"
		elif body_bench and not level_rules.is_empty():
			var extra: int = body_bench.cells.size() - int(level_rules.star_blocks)
			go_hint.text = "✓ 身体在 %d 块以内" % int(level_rules.star_blocks) if extra <= 0 else "第三颗星：身体再少 %d 块（可以先过关）" % extra
			go_hint.add_theme_color_override("font_color", Ui.INK_SOFT)
		elif not level_rules.is_empty() and used <= float(level_rules.star_budget):
			go_hint.text = ("低预算挑战：基因消耗不超过 %d 点。" if level_id() == "1-1" else "✓ 已满足低预算挑战（不超过 %d 点）") % int(level_rules.star_budget)
		elif not level_rules.is_empty():
			# Where the star line is from here: the guide's plan may sit above it.
			go_hint.text = "低预算挑战：基因消耗不超过 %d 点。" % int(level_rules.star_budget) if level_id() == "1-1" else "还需减少 %d 点基因消耗才能获得低预算星。你也可以先完成主要目标。" % int(used - float(level_rules.star_budget))
		else:
			go_hint.text = ""
	if slot_label:
		slot_label.text = "规则卡槽：%d / %d" % [n_cards, slots_now]
		add_button.disabled = n_cards >= slots_now
		add_button.modulate.a = 0.45 if n_cards >= slots_now else 1.0
		# (Where the neural gene is locked, raising it is no way out: say what is.)
		var neural_open: bool = DevMode.on(DevMode.all_genes) or (level_rules.get("genes_open", range(8)) as Array).has(6)
		add_button.text = "+  添加规则" if n_cards < slots_now else ("卡槽已满：提高神经基因可以多放几张" if neural_open else "卡槽已满：删掉一张用不上的卡再加")
	budget_label.add_theme_color_override("font_color", Ui.WARN if over else Ui.INK)
	budget_meter.used = used
	if level_rules.is_empty():
		# The sandbox: no limit, the bar spans every gene at its top.
		budget_meter.max_v = maxf(SANDBOX_GENES_MAX, ceilf(used))
		budget_meter.limit = false
	budget_meter.queue_redraw()
	var r := 5.5
	var base: float = 0.45 * (1.3 - 0.09 * genes[5])
	var upkeep: float = 0.05 * genes[1] + 0.08 * genes[3] + 0.06 * genes[2] + 0.03 * (genes[6] - 3.0)
	cost_labels["energy"].set_value(base + upkeep)
	cost_labels["divide"].set_value(r * r * (2.6 - 0.22 * genes[4]) + 0.6 * r * r)
	cost_labels["speed"].set_value((18.0 + 14.0 * genes[0]) * (1.0 - 0.04 * genes[2]))
	cost_labels["sight"].set_value(30.0 + 24.0 * genes[1])
	if body_bench and body_counts():
		var bs: Dictionary = Colony.stats(body_bench.cells)
		cost_labels["divide"].set_value(bs.energy)
		cost_labels["speed"].set_value(bs.speed)


func _process(delta: float) -> void:
	spin += delta
	if chamber == null or specimen == null:
		return
	_tick_transition(delta)
	for k in GENES.size():
		shown[k] = lerpf(shown[k], genes[k], minf(1.0, delta * 7.0))
		var hold := 0.0
		if gene_sliders[k]._hover > 0.5 or gene_sliders[k]._drag or hover_gene == k:
			hold = 0.75
		glow[k] = maxf(hold, glow[k] * exp(-1.0 * delta))
	_update_stage(delta)
	var c := _specimen_center()
	var radius := SPECIMEN_R
	var side := radius / 0.15
	var heading := wrapf(spin * 0.35, -PI, PI)
	var mm := specimen.multimesh
	mm.set_instance_transform_2d(0, Transform2D(0.0, Vector2(side, side), 0.0, c))
	var q := func(t: float) -> int: return clampi(roundi((t - 1.0) / 4.0 * 15.0), 0, 15)
	var packed: int = q.call(genes[0]) | q.call(genes[1]) << 4 | q.call(genes[2]) << 8 | q.call(genes[3]) << 12 | q.call(genes[4]) << 16 | q.call(genes[5]) << 20
	var swim := 0.35 + 0.15 * sin(spin * 1.3)
	# The kernel's packing: (speed in 5 bits + 32 * lineage signature
	# + 1024 * stroke phase in 12 bits) / 2^22.
	var stroke_q := float(int(fposmod(spin * 4.0, TAU) / TAU * 4096.0) & 4095)
	# Red carries the installed organs too (organism.gdshader): it grows them.
	mm.set_instance_color(0, Color(color.r + 2.0 * Organs.mask(organs), color.g, color.b, (roundf(swim * 31.0) + 32.0 * 7.0 + 1024.0 * stroke_q) / 4194304.0))
	var neural_q: int = q.call(genes[6])
	mm.set_instance_custom_data(0, Color(heading + 8.0 * 7.0, 0.85, float(packed), 0.0 + 2.0 * 3.0 + 16.0 * 8.0 + 256.0 * 15.0 + 4096.0 * neural_q))
	ring_arc.position = c
	ring_arc.rotation = spin * 0.4
	tank_fx.queue_redraw()
	_update_genome()


func _update_stage(delta: float) -> void:
	# The run along the strand (ease in-out), the lens riding at the centre;
	# the wipe, flash and spin-up ease out.
	var before := view_x
	var moving := travel_t < travel_dur
	if moving:
		travel_t = minf(travel_t + delta, travel_dur)
		var u := travel_t / travel_dur
		var e := 4.0 * u * u * u if u < 0.5 else 1.0 - pow(-2.0 * u + 2.0, 3.0) / 2.0
		view_x = lerpf(travel_from, travel_to, e)
		if travel_t >= travel_dur:
			lock_t = 0.0
	elif coasting:
		# A throw: glide on, then snap to the nearest gene like a magnet.
		view_x = clampf(view_x + drag_vel * delta, -STAGE_CODING * 0.5, _right_end())
		drag_vel *= exp(-3.2 * delta)
		if absf(drag_vel) < 160.0:
			coasting = false
			if view_x > STAGE_CODING * 0.5 + ORGAN_GAP * 0.5 and _sites() > 0:
				focus_organ(clampi(int((view_x - _organ_x0()) / ORGAN_W), 0, _sites() - 1))
			else:
				var seg := STAGE_CODING / float(NG)
				select_gene(clampi(roundi((view_x + STAGE_CODING * 0.5) / seg - 0.5), 0, NG - 1))
	moving = moving or coasting or dragging
	focus_x = view_x
	run_speed = lerpf(run_speed, clampf(absf(view_x - before) / maxf(delta, 1e-4) / 2400.0, 0.0, 1.0), 1.0 - exp(-10.0 * delta))
	# Mouse: its lens fades in over the strand; the room leans away from it.
	var over := _on_strand(mouse_pos) and not dragging
	mouse_on = lerpf(mouse_on, 1.0 if over else 0.0, 1.0 - exp(-9.0 * delta))
	var lean := (mouse_pos - STAGE_CENTER) * -0.025 if mouse_pos.x > -9000.0 else Vector2.ZERO
	parallax = parallax.lerp(lean, 1.0 - exp(-4.0 * delta))
	ripple_t += delta
	lock_t += delta
	if type_t < 2.0:
		type_t += delta
		stage_labels.queue_redraw()
	_tick_cursor_fx()
	_tick_edits(delta)
	stage_mat.set_shader_parameter("mouse", mouse_pos)
	stage_mat.set_shader_parameter("mouse_on", mouse_on)
	stage_mat.set_shader_parameter("ripple_x", ripple_x)
	stage_mat.set_shader_parameter("ripple_p", ripple_p)
	stage_mat.set_shader_parameter("ripple_t", ripple_t)
	stage_mat.set_shader_parameter("speed", run_speed)
	stage_mat.set_shader_parameter("parallax", parallax)
	wipe = minf(1.0, wipe + delta / 0.45)
	for k in GENES.size():
		pulse[k] *= exp(-3.0 * delta)
	rot_speed = lerpf(rot_speed, 0.9, 1.0 - exp(-1.6 * delta))
	helix_phase += rot_speed * delta
	stage_mat.set_shader_parameter("phase", helix_phase)
	var nn := PackedFloat32Array()
	var vn := PackedFloat32Array()
	var no := PackedFloat32Array()
	var vo := PackedFloat32Array()
	for k in NG:
		nn.append(_pairs(bp_lv[k]))
		vn.append(_ver(bp_lv[k]))
		no.append(_pairs(bp_from[k]))
		vo.append(_ver(bp_from[k]))
	stage_mat.set_shader_parameter("n_new", nn)
	stage_mat.set_shader_parameter("v_new", vn)
	stage_mat.set_shader_parameter("n_old", no)
	stage_mat.set_shader_parameter("v_old", vo)
	stage_mat.set_shader_parameter("edit_t", PackedFloat32Array(edit_t))
	stage_mat.set_shader_parameter("organ_sites", _sites())
	stage_mat.set_shader_parameter("organ_x0", _organ_x0())
	stage_mat.set_shader_parameter("organ_w", ORGAN_W)
	stage_mat.set_shader_parameter("organ_id", PackedFloat32Array(org_ids))
	stage_mat.set_shader_parameter("organ_old", PackedFloat32Array(org_old))
	stage_mat.set_shader_parameter("organ_t", PackedFloat32Array(org_t))
	stage_mat.set_shader_parameter("pulse", PackedFloat32Array(pulse))
	stage_mat.set_shader_parameter("hover", hover_gene)
	stage_mat.set_shader_parameter("sel", sel_gene)
	stage_mat.set_shader_parameter("focus_x", focus_x)
	stage_mat.set_shader_parameter("shift", view_x)
	stage_mat.set_shader_parameter("wipe", wipe)
	# Labels and karyotype redraw only when what they show changes (the
	# labels also follow the lens while it slides).
	var key := "%d|%d|%s|%s|%d" % [sel_gene, hover_gene, str(genes), str(organs), organ_focus]
	if key != _label_key or moving:
		_label_key = key
		stage_labels.queue_redraw()
	var kkey := "%d|%.0f|" % [sel_gene, temp_opt]
	for k in GENES.size():
		kkey += "%.2f," % shown[k]
	if kkey != _karyo_key:
		_karyo_key = kkey
		rings.queue_redraw()
	# The selected gene's sequence and its complement along the bottom of the
	# stage, a read head stepping across it.
	_ticker_t += delta
	if _ticker_t > 0.14:
		_ticker_t = 0.0
		# While the gene is being edited, letters appear as their pairs lock in.
		var lv: float = bp_lv[sel_gene]
		var n := _pairs(lv)
		var head := int(spin / 0.14) % n
		var top := ""
		var bot := ""
		for j in n:
			var b := GenomeArt.base_of(sel_gene, j, _ver(lv))
			var placed := _pair_in(sel_gene, j, n)
			var l: String = GenomeArt.BASE_LETTERS[b] if placed else "·"
			var r: String = GenomeArt.BASE_LETTERS[b ^ 1] if placed else "·"
			top += ("[%s]" % l) if j == head else (" %s " % l)
			bot += ("[%s]" % r) if j == head else (" %s " % r)
		ticker.text = "5′ %s 3′     %s-%02d · %d bp · READ %02d
3′ %s 5′" % [top, GENE_CODES[sel_gene], sel_gene + 1, n, head + 1, bot]


# Place the genome: in the tank cell's nucleus once settled, otherwise along
# the dive; and unroll the stage's DNA with it.
func _update_genome() -> void:
	if tl >= INTRO_LEN and ot < 0.0:
		portal.visible = false
		genome.position = _nucleus_center()
		genome.scale = Vector2.ONE * (NUCLEUS_R / GenomeView.BASE_R)
		genome.update(shown, glow, spin, 1.0, sel_gene)
		return
	var portal_t := 0.0 # 0 = the cell's own nucleus, 1 = past the screen edge
	var portal_a := 0.0
	var morph := 0.0 # 0 = big, mid-screen; 1 = settled in the tank nucleus
	var unroll := 0.0 # the stage DNA, 0 = a point, 1 = across the lab
	if ot >= 0.0:
		portal_t = 1.0 - _ease((ot - 0.55) / 0.9)
		portal_a = _ease(ot / 0.4) * (1.0 - _ease((ot - 1.35) / 0.25))
		morph = 1.0 - _ease((ot - 0.05) / 0.65)
		unroll = 1.0 - _ease(ot / 0.7)
	else:
		portal_t = _ease((tl - 1.0) / 0.85)
		portal_a = _ease((tl - 0.85) / 0.2) * (1.0 - _ease((tl - 1.7) / 0.5))
		morph = _ease((tl - 1.7) / 0.7)
		unroll = _ease((tl - 1.45) / 0.95)
	var mid := dive_center
	var r := dive_r0 * pow(PORTAL_MAX / dive_r0, portal_t)
	# The portal is the dived cell's nucleus swelling past the screen.
	portal.visible = portal_a > 0.0
	portal.position = mid
	portal.scale = Vector2.ONE * (r / GenomeView.BASE_R)
	portal.rotation = spin * 0.03
	portal.modulate.a = portal_a
	# Chromosomes ride inside it, then glide into the tank, where the cell's
	# own nucleus gathers round them.
	var big := minf(r * 0.9, DIVE_NUCLEUS)
	genome.visible = (virus_bench == null and body_bench == null) or (page == "genome" and (level_rules.is_empty() or (level_rules.pages_open as Array).size() > 1))
	genome.position = mid.lerp(_nucleus_center(), morph)
	genome.scale = Vector2.ONE * (lerpf(big, NUCLEUS_R, morph) / GenomeView.BASE_R)
	genome.modulate.a = _ease((r - dive_r0 * 1.5) / 30.0)
	genome.update(shown, glow, spin, _ease((morph - 0.15) / 0.5), sel_gene)
	stage_mat.set_shader_parameter("reveal", unroll)
	stage.modulate.a = 1.0 if ot < 0.0 else 1.0 - _ease((ot - 0.5) / 0.4)


func _specimen_center() -> Vector2:
	return chamber.position + Vector2(chamber.size.x * 0.5, 330.0)


# The nucleus sits a little behind the middle of the body, turning with it.
func _nucleus_center() -> Vector2:
	var side := SPECIMEN_R / 0.15
	return _specimen_center() + Vector2(-0.04 * side * 0.5, 0.0).rotated(wrapf(spin * 0.35, -PI, PI))


const TANK_HALF_W := 128.0
const TANK_TOP := 150.0 # above the cell centre
const TANK_BOTTOM := 175.0


# The tank: glass cylinder, liquid line, scale, base plate with a biohazard
# mark, and the karyotype below. Static; redrawn on gene changes.
func _draw_rings() -> void:
	if chamber == null:
		return
	var ci := rings
	var c := _specimen_center()
	var ink := Color(0.03, 0.5, 0.62)
	var glo := Color(0.1, 0.78, 0.9)
	var top := c.y - TANK_TOP
	var bot := c.y + TANK_BOTTOM
	var l := c.x - TANK_HALF_W
	var rr := c.x + TANK_HALF_W
	# Liquid and glass.
	ci.draw_rect(Rect2(l, top + 22.0, rr - l, bot - top - 22.0), Color(glo, 0.07))
	for x in [l, rr]:
		ci.draw_line(Vector2(x, top), Vector2(x, bot), Color(glo, 0.25), 5.0)
		ci.draw_line(Vector2(x, top), Vector2(x, bot), Color(ink, 0.8), 1.2)
	_ellipse(ci, Vector2(c.x, top), TANK_HALF_W, 14.0, Color(ink, 0.7), 1.2)
	_ellipse(ci, Vector2(c.x, top + 22.0), TANK_HALF_W, 14.0, Color(glo, 0.6), 1.0)
	_ellipse(ci, Vector2(c.x, bot), TANK_HALF_W, 14.0, Color(ink, 0.8), 1.2)
	ci.draw_line(Vector2(l + 10.0, top + 30.0), Vector2(l + 10.0, bot - 20.0), Color(1, 1, 1, 0.55), 3.0)
	# Scale on the right of the glass.
	for k in 15:
		var y := top + 30.0 + k * (bot - top - 50.0) / 14.0
		var w := 9.0 if k % 5 == 0 else 5.0
		ci.draw_line(Vector2(rr + 6.0, y), Vector2(rr + 6.0 + w, y), Color(ink, 0.6), 1.0)
	ci.draw_string(Ui.mono(), Vector2(rr + 18.0, top + 34.0), "100", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Ui.INK_FAINT)
	ci.draw_string(Ui.mono(), Vector2(rr + 18.0, bot - 16.0), "0 µm", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Ui.INK_FAINT)
	# Base plate: warning stripes, biohazard mark, containment class.
	var plate := Rect2(l - 14.0, bot + 12.0, (rr - l) + 28.0, 26.0)
	ci.draw_rect(plate, Color(1, 1, 1, 0.55))
	ci.draw_rect(plate, Color(ink, 0.6), false, 1.0)
	for k in 9:
		var x := plate.position.x + 6.0 + k * 11.0
		ci.draw_line(Vector2(x, plate.end.y - 4.0), Vector2(x + 8.0, plate.position.y + 4.0), Color(Ui.WARN, 0.85), 3.0)
	_biohazard(ci, Vector2(plate.end.x - 70.0, plate.get_center().y), 8.5, Color(Ui.WARN.darkened(0.2), 0.95))
	ci.draw_string(Ui.mono("Medium"), Vector2(plate.end.x - 54.0, plate.get_center().y + 4.0), "BSL-2", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Ui.INK)
	# Karyotype: the seven chromosomes side by side, selected one bracketed.
	var ky := bot + 92.0
	ci.draw_string(Ui.sans(600), Vector2(chamber.position.x + 18.0, ky - 44.0), "染色体组型", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Ui.INK_SOFT)
	ci.draw_string(Ui.mono("Medium"), Vector2(chamber.position.x + 96.0, ky - 44.0), "KARYOTYPE  2n = %d" % (NG * 2), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Ui.ACCENT)
	var w7 := (chamber.size.x - 36.0) / float(NG)
	for k in GENES.size():
		var x := chamber.position.x + 18.0 + w7 * (k + 0.5)
		var lv: float = shown[k]
		var col: Color = Ui.ACCENT if k == sel_gene else LAB_GREY
		GenomeArt.chromosome(ci, Vector2(x, ky), -PI * 0.5, 22.0 + 4.0 * lv, col, lv, 0.0, 1.0, true)
		ci.draw_string(Ui.sans(500 if k != sel_gene else 700), Vector2(x - w7 * 0.5, ky + 34.0), GENES[k][0], HORIZONTAL_ALIGNMENT_CENTER, w7, 10,
			col.darkened(0.3) if k == sel_gene else Ui.INK_FAINT)
		if k == sel_gene:
			_brackets(ci, Rect2(x - w7 * 0.5 + 3.0, ky - 30.0, w7 - 6.0, 70.0), col.darkened(0.2))
	# How this genome would fare in each of the dish's waters.
	var fy := ky + 66.0
	if organ_bay:
		return # the organ slots take this place
	var x0 := chamber.position.x + 18.0
	var wbar := chamber.size.x - 36.0
	ci.draw_string(Ui.sans(600), Vector2(x0, fy), "各水域适应度预测", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Ui.INK_SOFT)
	ci.draw_string(Ui.mono("Medium"), Vector2(x0 + 110.0, fy), "FITNESS", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Ui.ACCENT)
	var waters := _waters()
	for w_i in waters.size():
		var wtr: Dictionary = waters[w_i]
		var f := Ecology.fitness(genes, temp_opt, wtr)
		var y := fy + 20.0 + w_i * 20.0
		ci.draw_string(Ui.sans(500), Vector2(x0, y + 4.0), wtr.name, HORIZONTAL_ALIGNMENT_LEFT, 96, 11, Ui.INK_SOFT)
		var track := Rect2(x0 + 100.0, y - 2.0, wbar - 150.0, 4.0)
		ci.draw_rect(track, Color(LAB_GREY, 0.2))
		var good := f > 0.8
		ci.draw_rect(Rect2(track.position, Vector2(track.size.x * f, 4.0)), Ui.ACCENT if good else (Ui.WARN if f > 0.5 else Ui.ALERT))
		ci.draw_string(Ui.mono("Medium"), Vector2(track.end.x + 8.0, y + 4.0), "%d%%" % roundi(f * 100.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Ui.INK)


# The waters the forecast weighs: a level's own dish (and its announced cold
# front) in the campaign, the sample dish's zones in the sandbox.
func _waters() -> Array:
	var layout: Dictionary = Ecology.EUROPA_SAMPLE
	var lv: Dictionary = {}
	var id := str(level_rules.get("id", ""))
	for l: Dictionary in Levels.ALL:
		if l.id == id:
			lv = l
	if not lv.is_empty() and lv.world.layout is Dictionary:
		layout = lv.world.layout
	var waters := [{name = "本关水域 %d°C" % roundi(layout.base.temp) if not lv.is_empty() else "开阔水域", temp = layout.base.temp, acid = layout.base.acid}]
	for z: Dictionary in layout.zones:
		waters.append({name = z.name, temp = z.temp, acid = z.acid})
	for e: Dictionary in lv.get("events", []):
		if e.kind == "chill":
			waters.append({name = "寒潮后 %d°C" % roundi(e.to), temp = e.to, acid = layout.base.acid})
	return waters


func _ellipse(ci: CanvasItem, c: Vector2, rx: float, ry: float, col: Color, w: float) -> void:
	var pts := PackedVector2Array()
	for k in 49:
		var a := TAU * k / 48.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	ci.draw_polyline(pts, col, w, true)


# The biohazard trefoil, flat: three rings round a hub.
func _biohazard(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	for k in 3:
		var a := -PI * 0.5 + TAU * k / 3.0
		ci.draw_arc(c + Vector2.from_angle(a) * r * 0.55, r * 0.55, 0.0, TAU, 20, col, 1.6, true)
	ci.draw_arc(c, r * 0.32, 0.0, TAU, 16, col, 1.6, true)


# Rising bubbles and the scan ring travelling up and down the tank.
func _draw_tank_fx() -> void:
	if chamber == null:
		return
	var ci := tank_fx
	var c := _specimen_center()
	var top := c.y - TANK_TOP + 26.0
	var bot := c.y + TANK_BOTTOM - 6.0
	var glo := Color(0.1, 0.78, 0.9)
	for k in 14:
		var h := fposmod(sin(k * 12.9898) * 43758.5453, 1.0)
		var y := bot - fposmod(spin * (18.0 + 14.0 * h) + h * 400.0, bot - top)
		var x := c.x + (h - 0.5) * TANK_HALF_W * 1.7 + sin(spin * 1.5 + k) * 3.0
		ci.draw_arc(Vector2(x, y), 1.5 + 2.5 * h, 0.0, TAU, 10, Color(glo, 0.5), 1.0, true)
	var sy := c.y + sin(spin * 0.7) * (TANK_TOP - 30.0)
	_ellipse(ci, Vector2(c.x, sy), TANK_HALF_W - 2.0, 12.0, Color(glo, 0.25), 5.0)
	_ellipse(ci, Vector2(c.x, sy), TANK_HALF_W - 2.0, 12.0, Color(glo, 0.9), 1.2)


func release() -> void:
	if go.disabled or busy:
		return
	designs += 1
	draft = {}
	# Two species (level 8): both go, the first one carrying the others.
	if sp_slots.size() > 1:
		sp_slots[cur_slot] = _design()
		var all := sp_slots.map(func(d: Dictionary) -> Dictionary: return _params_from(d))
		var first: Dictionary = all[0]
		first.extra = all.slice(1)
		first.designs = sp_slots.duplicate(true)
		_leave(first)
		return
	var params := _params_from(_design())
	if virus_bench:
		params.virus = virus_bench.virus.duplicate()
	_leave(params)


# 本关要点 (the briefing again, compact): the goal, the stars, the features.
func toggle_points() -> void:
	if points_panel and is_instance_valid(points_panel):
		points_panel.queue_free()
		points_panel = null
		if points_pill:
			points_pill.active = false
		return
	var l := Levels.by_id(str(level_rules.get("id", "")))
	if l.is_empty():
		return
	points_panel = GlassPanel.new(Vector4(24, 18, 24, 18))
	add_child(points_panel)
	points_panel.anchor_left = 0.5
	points_panel.anchor_right = 0.5
	points_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	points_panel.offset_top = 96
	points_panel.custom_minimum_size = Vector2(720, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	points_panel.body.add_child(v)
	v.add_child(Ui.caption("本关要点 · %s %s" % [str(l.id), str(l.get("name", ""))], "KEY POINTS"))
	Briefing.fill_goal(v, l, 672.0)
	if not (l.get("threats", []) as Array).is_empty():
		v.add_child(Ui.caption("这关的特点", "WHAT TO KNOW"))
		Briefing.fill_features(v, l, 672.0, true)
	var close_b := Widgets.Pill.new("收起", 90, Ui.sans(500))
	close_b.pressed.connect(func() -> void: toggle_points())
	v.add_child(close_b)
	if points_pill:
		points_pill.active = true
	points_panel.appear(0.0)


# The body bench's blocks make the species (a level with one; the sandbox
# with 多细胞 on).
func body_counts() -> bool:
	return not level_rules.is_empty() or multicell


func _sync_multi() -> void:
	if multi_pill:
		multi_pill.text = "多细胞：开" if multicell else "多细胞：关"
		multi_pill.active = multicell


# The sandbox's virus page: which species in the dish it infects, and a
# button that hands the design to 投放病毒 (key 5).
func _virus_target_row(p: Control) -> void:
	var host: Node = get_tree().current_scene if is_inside_tree() else null
	p.add_child(Ui.label("感染谁（沙盒）", 15, Ui.INK, Ui.sans(600)))
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 8)
	p.add_child(row)
	var picks: Array = []
	var labels: Array = host.get("labels") if host and host.get("labels") != null else []
	for k in labels.size():
		var b := Widgets.Pill.new(str(labels[k]), 0, Ui.sans(500))
		b.custom_minimum_size = Vector2(Ui.sans(500).get_string_size(str(labels[k]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 26, 32)
		b.active = k == virus_target
		var idx := k
		b.pressed.connect(func() -> void:
			virus_target = idx
			for j in picks.size():
				(picks[j] as Widgets.Pill).active = j == idx)
		picks.append(b)
		row.add_child(b)
	var apply := Widgets.Pill.new("用这种病毒（投放病毒 5）", 0, Ui.sans(600))
	apply.custom_minimum_size = Vector2(230, 32)
	apply.active = true
	apply.pressed.connect(func() -> void:
		if virus_target < 0 or virus_target >= labels.size():
			_toast("先选它感染哪个物种。")
			return
		host.sandbox_world.set_virus(virus_bench.virus.duplicate(), virus_target)
		_toast("已设好：按 5 在培养皿里投放这种病毒，它只感染「%s」。" % str(labels[virus_target])))
	p.add_child(apply)


# Species parameters for SimCore from a design: organs shape the body;
# mutation keeps to the pieces open here.
func _params_from(d: Dictionary) -> Dictionary:
	var g: Array = d.genes
	var params := Organs.apply({
		name = d.name, color = d.color, radius = 5.5,
		speed = g[0], vision = g[1], armor = g[2], attack = g[3],
		fertility = g[4], efficiency = g[5], neural = g[6], lifespan = 90.0, cohesion = 0.2,
		temp_opt = d.get("temp_opt", 12.0), temp_tol = g[7], mutates = d.get("mutates", true),
		deck = d.deck,
	}, d.get("organs", []))
	params.merge(Rules.masks(level_id(), d.get("organs", [])), true)
	# Chapter 7: the life slider.
	var lf: float = float(d.get("life", 1.0)) if rule_open("life_open") else 1.0
	params.life = lf
	params.lifespan = float(params.lifespan) * lf
	params.slow_divide = LifeSlider.divide_cost(lf)
	# Chapter 8: a eukaryote (born with its symbiont), acid tolerance.
	params.eukaryote = bool(d.get("euk", false)) and rule_open("euk_open")
	params.acid_tol = float(d.get("acid_tol", 0.0)) if rule_open("acid_open") else 0.0
	# Chapter 6: how it breathes (the level's fixed way until the switch opens).
	params.resp = int(d.get("resp", Resp.ANAEROBIC)) if resp_open() else int(level_rules.get("resp", 0))
	if not (d.get("blocks", []) as Array).is_empty():
		params.blocks = d.blocks
	return params


func _init_slots() -> void:
	var specs: Array = level_rules.get("species", [])
	if specs.size() < 2:
		return
	var saved: Array = (level_rules.get("design", {}) as Dictionary).get("designs", [])
	for k in specs.size():
		if k < saved.size():
			sp_slots.append(saved[k])
		elif k == 0 and not specs[0].has("organs") and not specs[0].has("role"):
			var d0 := _design()
			d0.name = specs[0].get("name", d0.name)
			sp_slots.append(d0)
		else:
			# The level's starting point for this slot (e.g. the predator).
			var d := _design()
			var spec: Dictionary = specs[k]
			d.name = spec.get("name", "设计物种 %s" % "ABC"[mini(k, 2)])
			d.color = SWATCHES[(k * 2) % SWATCHES.size()]
			d.organs = (spec.get("organs", []) as Array).duplicate()
			d.genes = (spec.get("genes", d.genes) as Array).duplicate()
			d.deck = (spec.get("deck", Rules.default_deck(1 if d.organs.has("cnido") else 0)) as Array).duplicate(true)
			if spec.has("resp"):
				d.resp = int(spec.resp)
			# Chapter 6: a role the player named before keeps their name and colour.
			var lk := CampaignSave.look(str(spec.get("role", "")))
			if not lk.is_empty():
				d.name = lk.name
				d.color = lk.color
			sp_slots.append(d)
	cur_slot = 0
	_apply_design(sp_slots[0])


# Level 8: one design per species slot (A, B), swapped in and out of the
# editor by the tabs in the top bar.
func _switch_slot(k: int) -> void:
	if k == cur_slot or k >= sp_slots.size():
		return
	sp_slots[cur_slot] = _design()
	cur_slot = k
	_apply_design(sp_slots[k])
	if deck_editor.cur_state != Rules.S_FORAGE:
		deck_editor.set_state(Rules.S_FORAGE)
	for j in slot_tabs.size():
		slot_tabs[j].active = j == k
	_toast("正在设计：%s" % level_rules.species[k].label)


func close() -> void:
	if busy:
		return
	draft = _design()
	_leave({})


func _leave(params: Dictionary) -> void:
	busy = true
	_releasing = params
	ot = 0.0
	dive.mouse_filter = Control.MOUSE_FILTER_STOP
	if name_edit.has_focus():
		name_edit.release_focus()
	for p in panels:
		if p.visible:
			p.disappear()


# --- dive transition ---------------------------------------------------------------

static func _ease(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


func _tick_transition(delta: float) -> void:
	if ot >= 0.0:
		ot += delta
		backdrop.modulate.a = 1.0 - _ease((ot - 0.6) / 0.7)
		var out := 1.0 - _ease(ot / 0.3)
		specimen.modulate.a = out
		rings.modulate.a = out
		tank_fx.modulate.a = out
		stage_labels.modulate.a = out
		if ot >= PULL_AT and not _pulled:
			_pulled = true
			pull_out.emit(not _releasing.is_empty())
		if ot >= OUTRO_LEN:
			set_process(false)
			if not _releasing.is_empty():
				released.emit(_releasing)
			closed.emit()
			queue_free()
			return
		return
	if tl >= INTRO_LEN:
		return
	tl += delta
	backdrop.modulate.a = _ease((tl - 1.15) / 0.7)
	var settle := _ease((tl - 1.95) / 0.45)
	specimen.modulate.a = settle
	rings.modulate.a = settle
	tank_fx.modulate.a = settle
	stage_labels.modulate.a = _ease((tl - 2.1) / 0.35)
	if tl >= INTRO_LEN:
		busy = false
		dive.mouse_filter = Control.MOUSE_FILTER_IGNORE
		intro_done.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if busy:
		get_viewport().set_input_as_handled()
		return
	var k := event as InputEventKey
	if name_edit.has_focus():
		if k.keycode == KEY_ESCAPE or k.keycode == KEY_ENTER:
			name_edit.release_focus()
			get_viewport().set_input_as_handled()
		return
	if k.keycode == Keys.code("designer"):
		close() # the same key that opened it (Tab) puts it away
		get_viewport().set_input_as_handled()
		return
	match k.keycode:
		KEY_ESCAPE: close()
		KEY_Z when k.ctrl_pressed: deck_editor.undo()
		KEY_DELETE when not deck_editor.readonly: deck_editor.remove_card(deck_editor.selected)
		KEY_LEFT when page == "genome": select_gene(maxi(sel_gene - 1, 0))
		KEY_RIGHT when page == "genome": select_gene(mini(sel_gene + 1, NG - 1))
		KEY_1: show_page("genome")
		KEY_2: show_page("rules")
		KEY_3: show_page("library")
		KEY_4: show_page("handbook")
		_: return
	get_viewport().set_input_as_handled()


# A gene level slider: five notches, a knob that eases to where you drag.
class GeneSlider extends Control:
	signal changed(value: float)
	var value := 1.0
	var locked := false:
		set(v):
			locked = v
			mouse_default_cursor_shape = Control.CURSOR_FORBIDDEN if v else Control.CURSOR_POINTING_HAND
			queue_redraw()
	var _shown := 1.0
	var _drag := false
	var _hover := 0.0

	func _init(v: float) -> void:
		value = v
		_shown = v
		custom_minimum_size = Vector2(320, 26)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	func _x_of(v: float) -> float:
		return 8.0 + (size.x - 16.0) * (v - 1.0) / 4.0

	func _gui_input(event: InputEvent) -> void:
		if locked:
			return
		if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			_drag = event.pressed
			_set_from(event.position.x)
		elif event is InputEventMouseMotion and _drag:
			_set_from(event.position.x)

	func _set_from(px: float) -> void:
		var v := clampf(1.0 + (px - 8.0) / (size.x - 16.0) * 4.0, 1.0, 5.0)
		v = roundf(v * 2.0) / 2.0
		if v != value:
			value = v
			changed.emit(v)

	func _process(delta: float) -> void:
		var h := 1.0 if get_global_rect().has_point(get_global_mouse_position()) or _drag else 0.0
		if absf(_shown - value) > 0.001 or absf(_hover - h) > 0.001:
			_shown = lerpf(_shown, value, minf(1.0, delta * 14.0))
			_hover = lerpf(_hover, h, minf(1.0, delta / Ui.T_FAST))
			queue_redraw()

	func _draw() -> void:
		var y := size.y * 0.5
		draw_line(Vector2(8, y), Vector2(size.x - 8, y), Color(Ui.LINE, 0.6), 2.0, true)
		draw_line(Vector2(8, y), Vector2(_x_of(_shown), y), Ui.ACCENT, 2.0, true)
		for k in 5:
			var x := _x_of(1.0 + k)
			draw_line(Vector2(x, y - 5), Vector2(x, y + 5), Ui.LINE_STRONG if 1.0 + k > _shown else Ui.ACCENT, 1.0, true)
		var kx := _x_of(_shown)
		if locked:
			# A small padlock in place of the knob.
			draw_rect(Rect2(Vector2(kx - 5, y - 2), Vector2(10, 8)), Ui.INK_FAINT, true)
			draw_arc(Vector2(kx, y - 2), 3.5, PI, TAU, 10, Ui.INK_FAINT, 1.4, true)
			return
		draw_circle(Vector2(kx, y), 9.0 + _hover * 2.0, Color(Ui.ACCENT, 0.15))
		draw_circle(Vector2(kx, y), 6.0, Color.WHITE)
		draw_arc(Vector2(kx, y), 6.0, 0, TAU, 24, Ui.ACCENT, 1.6, true)


# The preferred water temperature, -5 to 45 deg C: a cold-to-hot track with
# the dish's waters marked on it.
class LifeSlider extends Control:
	signal changed(value: float)
	const LO := 0.5
	const HI := 2.0
	var value := 1.0
	var _drag := false

	# What dividing costs at a life of `v` (×1 at ×1): dearer for a long life.
	static func divide_cost(v: float) -> float:
		return 1.0 + 0.4 * (v - 1.0) if v >= 1.0 else 1.0 - 0.4 * (1.0 - v)

	func _init(v: float) -> void:
		value = v
		custom_minimum_size = Vector2(320, 26)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		tooltip_text = "寿命（不花预算）：活得越久，分裂需要的能量越多；寿命短，分裂更便宜"

	func _x_of(v: float) -> float:
		return 8.0 + (size.x - 16.0) * (v - LO) / (HI - LO)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			_drag = event.pressed
			_set_from(event.position.x)
		elif event is InputEventMouseMotion and _drag:
			_set_from(event.position.x)

	func _set_from(px: float) -> void:
		var v := snappedf(clampf(LO + (px - 8.0) / (size.x - 16.0) * (HI - LO), LO, HI), 0.1)
		if v != value:
			value = v
			queue_redraw()
			changed.emit(v)

	func _draw() -> void:
		var y := size.y * 0.5
		draw_line(Vector2(_x_of(LO), y), Vector2(_x_of(HI), y), Color(Ui.ACCENT, 0.35), 3.0)
		draw_line(Vector2(_x_of(1.0), y - 5.0), Vector2(_x_of(1.0), y + 5.0), Color(Ui.INK_FAINT, 0.8), 1.0)
		var kx := _x_of(value)
		draw_circle(Vector2(kx, y), 6.0, Color.WHITE)
		draw_arc(Vector2(kx, y), 6.0, 0, TAU, 24, Ui.ACCENT, 1.6, true)
		draw_string(Ui.mono("Medium"), Vector2(kx + 9.0, y - 4.0), "寿命 ×%.1f · 分裂所需 ×%.2f" % [value, divide_cost(value)], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Ui.INK)


# Chapter 8: acid tolerance 0..1 (耐酸), costing no budget: acid hurts less,
# the upkeep is more.
class AcidSlider extends Control:
	signal changed(value: float)
	var value := 0.0
	var _drag := false

	func _init(v: float) -> void:
		value = v
		custom_minimum_size = Vector2(320, 26)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		tooltip_text = "耐酸（不花预算）：越耐酸，酸水伤害越小，但平时越耗能"

	func _x_of(v: float) -> float:
		return 8.0 + (size.x - 16.0) * v

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			_drag = event.pressed
			_set_from(event.position.x)
		elif event is InputEventMouseMotion and _drag:
			_set_from(event.position.x)

	func _set_from(px: float) -> void:
		var v := snappedf(clampf((px - 8.0) / (size.x - 16.0), 0.0, 1.0), 0.1)
		if v != value:
			value = v
			queue_redraw()
			changed.emit(v)

	func _draw() -> void:
		var y := size.y * 0.5
		draw_line(Vector2(_x_of(0.0), y), Vector2(_x_of(1.0), y), Color(0.75, 0.85, 0.35, 0.45), 3.0)
		var kx := _x_of(value)
		draw_circle(Vector2(kx, y), 6.0, Color.WHITE)
		draw_arc(Vector2(kx, y), 6.0, 0, TAU, 24, Ui.ACCENT, 1.6, true)
		draw_string(Ui.mono("Medium"), Vector2(minf(kx + 9.0, size.x - 190.0), y - 4.0), "耐酸 %d%% · 酸伤 -%d%% · 耗能 +%d%%" % [roundi(value * 100.0), roundi(value * 85.0), roundi(value * 35.0)], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Ui.INK)


class TempSlider extends Control:
	signal changed(value: float)
	const LO := -5.0
	const HI := 45.0
	var value := 12.0
	var _drag := false

	func _init(v: float) -> void:
		value = v
		custom_minimum_size = Vector2(320, 24)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		tooltip_text = "最适水温（不花预算）"

	func _x_of(v: float) -> float:
		return 8.0 + (size.x - 16.0) * (v - LO) / (HI - LO)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			_drag = event.pressed
			_set_from(event.position.x)
		elif event is InputEventMouseMotion and _drag:
			_set_from(event.position.x)

	func _set_from(px: float) -> void:
		var v := roundf(clampf(LO + (px - 8.0) / (size.x - 16.0) * (HI - LO), LO, HI))
		if v != value:
			value = v
			queue_redraw()
			changed.emit(v)

	func _draw() -> void:
		var y := size.y * 0.5
		var n := 24
		for k in n:
			var a := _x_of(LO + (HI - LO) * k / n)
			var b := _x_of(LO + (HI - LO) * (k + 1) / n)
			var t := (k + 0.5) / n
			draw_line(Vector2(a, y), Vector2(b, y), Color(0.5, 0.75, 0.98).lerp(Color(1.0, 0.6, 0.35), t), 3.0)
		for mark in [[1.0, "冰"], [12.0, "开阔"], [19.0, "酸池"], [36.0, "热泉"]]:
			var x := _x_of(mark[0])
			draw_line(Vector2(x, y - 5.0), Vector2(x, y + 5.0), Color(Ui.INK_FAINT, 0.8), 1.0)
		var kx := _x_of(value)
		draw_circle(Vector2(kx, y), 6.0, Color.WHITE)
		draw_arc(Vector2(kx, y), 6.0, 0, TAU, 24, Ui.ACCENT, 1.6, true)
		draw_string(Ui.mono("Medium"), Vector2(kx + 9.0, y - 4.0), "%d°C" % roundi(value), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Ui.INK)


# One gene in the editor: a soft plate that lights up when its gene is
# selected; clicking anywhere on it selects the gene.
class GeneRow extends MarginContainer:
	signal picked
	var color: Color
	var selected := false:
		set(v):
			selected = v
			queue_redraw()

	func _init(c: Color) -> void:
		color = c
		mouse_filter = Control.MOUSE_FILTER_PASS
		for side in ["left", "right", "top", "bottom"]:
			add_theme_constant_override("margin_" + side, 8 if side in ["left", "right"] else 6)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			picked.emit()

	func _draw() -> void:
		if selected:
			draw_rect(Rect2(Vector2.ZERO, size), Color(color, 0.1))
			draw_rect(Rect2(0, 0, 3, size.y), color.darkened(0.15))


# A behaviour piece in the library: click to add, or drag onto a card.
class PieceChip extends Widgets.Pill:
	var kind := "cond"
	var id := 0
	var locked := false: # opens in a later level: grey, cannot be used
		set(v):
			locked = v
			modulate.a = 0.42 if v else 1.0
			mouse_default_cursor_shape = Control.CURSOR_FORBIDDEN if v else Control.CURSOR_DRAG
	var fresh := false: # opens in this level: a 新 tag, pulsing for a while
		set(v):
			fresh = v
			_fresh_t = 0.0
			queue_redraw()
	var _fresh_t := 0.0

	func _init(k: String, i: int, t: String) -> void:
		super(t, 0, Ui.sans(500))
		kind = k
		id = i
		custom_minimum_size.x = label_font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 28
		mouse_default_cursor_shape = Control.CURSOR_DRAG

	func _process(delta: float) -> void:
		super(delta)
		if fresh and _fresh_t < 6.0:
			_fresh_t += delta
			queue_redraw()

	func _draw() -> void:
		super()
		if not fresh:
			return
		# The 新 tag on the top-right corner; it pulses for the first seconds.
		var c := Vector2(size.x - 4, 3)
		var pulse := maxf(0.0, sin(_fresh_t * 4.0)) * clampf(1.0 - _fresh_t / 6.0, 0.0, 1.0)
		if pulse > 0.0:
			draw_circle(c, 9.0 + 5.0 * pulse, Color(Ui.ACCENT, 0.18 * pulse))
		draw_circle(c, 9.0, Ui.ACCENT)
		draw_string(Ui.sans(700), c + Vector2(-5.5, 4.5), "新", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)

	func _get_drag_data(_at: Vector2) -> Variant:
		if locked:
			return null
		var preview := Widgets.Pill.new(text, custom_minimum_size.x, label_font)
		preview.active = true
		preview.size = custom_minimum_size
		set_drag_preview(preview)
		return {piece = kind, id = id}


# The deck's execution order as a small diagram (handbook page).
class FlowDiagram extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(500, 210)

	func _draw() -> void:
		var f := Ui.sans(600)
		var y := 10.0
		var boxes := [["卡 1", "条件成立？做得到？"], ["卡 2", "条件成立？做得到？"], ["……", ""]]
		for k in boxes.size():
			var r := Rect2(10, y, 300, 46)
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(1, 1, 1, 0.7)
			sb.border_color = Ui.LINE_STRONG
			sb.set_border_width_all(1)
			sb.set_corner_radius_all(8)
			draw_style_box(sb, r)
			draw_string(f, Vector2(24, y + 29), boxes[k][0], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Ui.INK)
			draw_string(Ui.sans(), Vector2(92, y + 29), boxes[k][1], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Ui.INK_SOFT)
			if k < 2:
				draw_line(Vector2(310, y + 23), Vector2(370, y + 23), Ui.ACCENT, 1.5, true)
				draw_string(f, Vector2(316, y + 18), "是", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Ui.ACCENT)
				var sb2 := StyleBoxFlat.new()
				sb2.bg_color = Ui.ACCENT
				sb2.set_corner_radius_all(8)
				draw_style_box(sb2, Rect2(370, y + 8, 110, 30))
				draw_string(f, Vector2(384, y + 28), "执行这张卡", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
				draw_line(Vector2(80, y + 46), Vector2(80, y + 68), Ui.LINE_STRONG, 1.5, true)
				draw_string(Ui.sans(), Vector2(88, y + 62), "否", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Ui.INK_FAINT)
			y += 68.0
		draw_string(f, Vector2(10, y + 4), "一张都不生效 → 漫游", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Ui.INK_SOFT)


# Gene budget as 16 segments; used ones fill with the accent.
class BudgetBar extends Control:
	var used := 0.0
	var max_v := BUDGET
	var star_v := -1.0 # campaign: the low-budget star line
	var limit := true # false in the sandbox: never shown as over

	func _init() -> void:
		custom_minimum_size = Vector2(0, 10)

	func _draw() -> void:
		var n := int(max_v)
		var gap := 4.0
		var w := (size.x - gap * (n - 1)) / n
		for k in n:
			var fill := clampf(used - k, 0.0, 1.0)
			var r := Rect2(k * (w + gap), 0, w, size.y)
			draw_rect(r, Color(Ui.LINE, 0.35), true)
			if fill > 0.0:
				draw_rect(Rect2(r.position, Vector2(w * fill, size.y)), Ui.WARN if limit and used > max_v else Ui.ACCENT, true)
		# (A star line at the very end says nothing, and would sit on the count.)
		if star_v > 0.0 and star_v < max_v - 0.01:
			var x := star_v * (w + gap) - gap * 0.5
			draw_line(Vector2(x, -4), Vector2(x, size.y + 4), Ui.INK, 1.2, true)
			var c := Vector2(x, -9)
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -4), c + Vector2(4, 0), c + Vector2(0, 4), c + Vector2(-4, 0)]), Ui.INK)


# A round colour swatch; the chosen one wears an accent ring.
class Swatch extends Button:
	var color := Color.WHITE
	var selected := false:
		set(v):
			selected = v
			queue_redraw()

	func _init(c: Color) -> void:
		color = c
		flat = true
		focus_mode = Control.FOCUS_NONE
		custom_minimum_size = Vector2(22, 22)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		for st in ["normal", "hover", "pressed", "focus", "hover_pressed"]:
			add_theme_stylebox_override(st, StyleBoxEmpty.new())
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)

	func _draw() -> void:
		var c := size * 0.5
		if selected or is_hovered():
			draw_arc(c, 10.0, 0, TAU, 32, Ui.ACCENT if selected else Ui.LINE_STRONG, 1.6, true)
		draw_circle(c, 7.0, color)
