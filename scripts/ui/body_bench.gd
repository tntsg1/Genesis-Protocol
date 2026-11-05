extends Control
# The body bench (level 21) as a microinjection rig: the body lies in a
# darkfield scope, a glass needle puts each block in, and the gene strip under
# the scope is rewritten with every change (somatic blocks carry regA switched
# on, germ blocks glsA, as in Volvox). Blocks are dragged the same way rule
# cards are, with undo. What the shape comes to is worked out as it changes
# (Colony.stats, the same numbers the kernel gets): read off on gauges, and a
# small tank tries it in the stream before the release. Level 22 adds armour
# (chitin synthase, chs) and store blocks (perilipin, plin, which coats the oil
# droplets), when the level lists them in colony.kinds.

signal changed

const ColonyLayer := preload("res://scripts/colony_layer.gd")
const GRID_W := 13 # room for a body one block wide, twelve long
const GRID_H := 9
const STEP := 56.0
const TINT := Color(0.36, 0.76, 0.56)
const NAMES := {1: "鞭毛块", 6: "生殖块", 7: "甲块", 8: "储能块", 9: "再生块"}
const GENE := {1: "regA", 6: "glsA", 7: "chs", 8: "plin", 9: "piwi"}
const ROLE := {1: "体细胞", 6: "生殖细胞", 7: "角质层", 8: "储存细胞", 9: "干细胞"}
const WHAT := {1: "在外缘才划得动水。被四面包住的鞭毛不起作用。", 6: "不会游，只管生。前面要有别的块挡砂砾。",
	7: "猎手咬到它只掉一点点能量。要在外缘才挡得到。", 8: "怀子时多出来的能量存进去，荒年里饿了再取。",
	9: "一团干细胞：身体里有一块好的，全身咬残的块都长回得快 12 倍。"}
# The darkfield, now slate glass (DARK is kept for what is drawn inside it).
const DARK := Color(0.016, 0.05, 0.066)
const SLATE := Color(0.085, 0.15, 0.19)
const GLOW := Color(0.56, 0.95, 0.9)
const SEG := {1: Color(0.36, 0.92, 0.84), 6: Color(0.78, 0.95, 0.42), 7: Color(0.86, 0.78, 0.62), 8: Color(1.0, 0.93, 0.6), 9: Color(0.98, 0.78, 0.86)} # lime, as the germ cell's core; horn; oil; stem cells
# What is wrong is said in the theme's own colour, never orange: bright and
# pulsing on the glass, deepened on the light panels.
const ALERT := Color(0.62, 1.0, 1.0)
const ALERT_INK := Color("086f84")
const SCOPE := Vector2(880, 600)
const ZOOM_MAX := 1.7
const BP := 96 # base pairs a block's gene stands for

var cells: Array = []
var kinds: Array = [Colony.FLAG, Colony.GERM] # the blocks this level offers
var tiles := {} # kind -> its palette tile (the guide points at them)
var specimen := "5-2  ·  VOLVOX"
var undo_stack: Array = []
var redo_stack: Array = []
var stream := 28.0
var gest := 25.0
var regrow := 180.0 # seconds a broken block takes to grow back alone (level 23)
var regen_x := 12.0 # how much faster with a working regeneration block
var star_blocks := 0
var trip := 660.0 # µm from the release to the goal's edge
var board: Board
var scope: Scope
var strand: Strand
var gauges: Gauges
var tank: Tank
var meter: Meter
var note: Label
var undo_btn: Button
var redo_btn: Button


func setup(start: Array, colony: Dictionary, stars: int, to_goal: float) -> void:
	cells = _shifted(start)
	stream = (colony.stream as Vector2).length()
	star_blocks = stars
	trip = to_goal
	gest = float(colony.gest)
	regrow = float(colony.get("regrow", regrow))
	regen_x = float(colony.get("regen", regen_x))
	kinds = colony.get("kinds", kinds)
	specimen = colony.get("specimen", specimen)
	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.add_theme_constant_override("separation", 22)
	add_child(h)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 270
	left.add_theme_constant_override("separation", 12)
	h.add_child(left)
	left.add_child(Ui.label("拼一个身体", Ui.SIZE_TITLE + 2, Ui.INK, Ui.sans(700)))
	left.add_child(Ui.label("MICROINJECTION · BODY PLAN", 11, Ui.INK_FAINT, Ui.mono("Medium")))
	meter = Meter.new()
	meter.bench = self
	left.add_child(meter)
	left.add_child(Ui.caption("基因片段", "GENE CASSETTES"))
	# (Four kinds: smaller tiles, and the controls the two cards most need.)
	var many := kinds.size() > 2
	for t: int in kinds:
		tiles[t] = Tile.new(t, WHAT[t], many)
		left.add_child(tiles[t])
	left.add_child(Ui.caption("操作", "CONTROLS"))
	var hints := VBoxContainer.new()
	hints.add_theme_constant_override("separation", 8)
	left.add_child(hints)
	var specs := [["in", "拖进视野", "注入新块"], ["swap", "拖到另一块上", "两块交换"], ["click", "点一下", "换成下一种块"], ["out", "右键，或拖出视野", "删除这一块"], ["link", "连成一片", "3 到 12 块"]]
	if many:
		specs = [specs[0], specs[2], specs[3]]
	for spec: Array in specs:
		hints.add_child(Hint.new(spec[0], spec[1], spec[2]))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	left.add_child(row)
	undo_btn = Widgets.Pill.new("撤销  Ctrl+Z", 128, Ui.sans(500))
	undo_btn.pressed.connect(undo)
	row.add_child(undo_btn)
	redo_btn = Widgets.Pill.new("重做  Ctrl+Y", 128, Ui.sans(500))
	redo_btn.pressed.connect(redo)
	row.add_child(redo_btn)
	note = Ui.label("", 13, ALERT_INK, Ui.sans(700))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(note)
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 12)
	h.add_child(mid)
	scope = Scope.new()
	scope.bench = self
	scope.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	mid.add_child(scope)
	board = scope.board
	board.bench = self
	strand = Strand.new()
	strand.bench = self
	strand.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	mid.add_child(strand)
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 400
	right.add_theme_constant_override("separation", 10)
	h.add_child(right)
	gauges = Gauges.new()
	gauges.bench = self
	right.add_child(gauges)
	right.add_child(Ui.caption("试游 · 3 倍速", "FLOW TANK"))
	tank = Tank.new()
	tank.bench = self
	right.add_child(tank)
	_refresh()
	scope.boot = 0.0
	board.assemble()


# Blueprints may be anywhere; the grid wants them in its middle.
func _shifted(start: Array) -> Array:
	if start.is_empty():
		return [[5, 4, Colony.GERM], [6, 4, Colony.FLAG], [7, 4, Colony.FLAG]]
	var lo := Vector2i(100, 100)
	var hi := Vector2i(-100, -100)
	for c: Array in start:
		lo = Vector2i(mini(lo.x, int(c[0])), mini(lo.y, int(c[1])))
		hi = Vector2i(maxi(hi.x, int(c[0])), maxi(hi.y, int(c[1])))
	var at := Vector2i((GRID_W - 1 - (hi.x - lo.x)) / 2, (GRID_H - 1 - (hi.y - lo.y)) / 2) - lo
	var out := []
	for c: Array in start:
		out.append([int(c[0]) + at.x, int(c[1]) + at.y, int(c[2])])
	return out


func _say(text: String, at := Vector2i(-1, -1)) -> void:
	note.text = text
	Audio.sfx("ui_deny")
	if at != Vector2i(-1, -1) and scope:
		scope.deny(at, text)


func _commit(next: Array, at := Vector2i(-1, -1)) -> void:
	undo_stack.append(cells)
	redo_stack.clear()
	cells = next
	note.text = ""
	Audio.sfx("gene_up", -8.0, 1.0)
	_refresh()
	if at != Vector2i(-1, -1):
		scope.inject(at)
	changed.emit()


func undo() -> void:
	if undo_stack.is_empty():
		return
	redo_stack.append(cells)
	cells = undo_stack.pop_back()
	note.text = ""
	Audio.sfx("gene_up", -10.0, 0.86)
	_refresh()
	changed.emit()


func redo() -> void:
	if redo_stack.is_empty():
		return
	undo_stack.append(cells)
	cells = redo_stack.pop_back()
	note.text = ""
	Audio.sfx("gene_up", -10.0, 0.94)
	_refresh()
	changed.emit()


func _index(at: Vector2i) -> int:
	for k in cells.size():
		if int(cells[k][0]) == at.x and int(cells[k][1]) == at.y:
			return k
	return -1


# Would this layout be allowed? "" if so, or why not.
static func refuse(next: Array) -> String:
	if next.size() > Colony.MAX_BLOCKS:
		return "最多 %d 块。" % Colony.MAX_BLOCKS
	if next.size() < Colony.MIN_BLOCKS:
		return "至少 %d 块。" % Colony.MIN_BLOCKS
	if not Colony.connected(next):
		return "块要连成一片，这样会断开。"
	return ""


# A new block from the palette: on a block it changes that block's type.
func place(at: Vector2i, type: int) -> bool:
	var next: Array = cells.duplicate(true)
	var k := _index(at)
	if k >= 0:
		if int(next[k][2]) == type:
			return false
		next[k][2] = type
	else:
		next.append([at.x, at.y, type])
		var touching := false
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			touching = touching or _index(at + d) >= 0
		if not touching:
			_say("新块要贴着身体放。", at)
			return false
	var why := refuse(next)
	if why != "":
		_say(why, at)
		return false
	_commit(next, at)
	return true


# A block dragged within the grid: onto another it swaps, onto water it moves.
func move(from: Vector2i, to: Vector2i) -> bool:
	if from == to:
		return false
	var k := _index(from)
	if k < 0:
		return false
	var next: Array = cells.duplicate(true)
	var other := _index(to)
	if other >= 0:
		var t: int = next[k][2]
		next[k][2] = next[other][2]
		next[other][2] = t
		if int(next[k][2]) == int(next[other][2]):
			_say("两块一样，不用换。", to)
			return false
	else:
		next[k][0] = to.x
		next[k][1] = to.y
	var why := refuse(next)
	if why != "":
		_say(why, to)
		return false
	_commit(next, to)
	return true


# A click: the next kind of block this level offers.
func toggle(at: Vector2i) -> bool:
	var k := _index(at)
	if k < 0:
		return false
	var i := kinds.find(int(cells[k][2]))
	return place(at, int(kinds[(i + 1) % kinds.size()]))


func remove(at: Vector2i) -> bool:
	var k := _index(at)
	if k < 0:
		return false
	var next: Array = cells.duplicate(true)
	next.remove_at(k)
	var why := refuse(next)
	if why != "":
		_say(why, at)
		return false
	_commit(next, at)
	return true


func _refresh() -> void:
	undo_btn.disabled = undo_stack.is_empty()
	redo_btn.disabled = redo_stack.is_empty()
	var s: Dictionary = Colony.stats(cells)
	meter.queue_redraw()
	gauges.show_stats(s)
	board.rebuild()
	strand.rebuild()
	tank.rebuild()


func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventKey and event.pressed and event.ctrl_pressed:
		if event.keycode == KEY_Y or (event.keycode == KEY_Z and event.shift_pressed):
			redo()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_Z:
			undo()
			get_viewport().set_input_as_handled()


# The blocks front first, top to bottom: the order the gene strip reads them.
func segments() -> Array:
	var s: Array = cells.duplicate()
	s.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) > int(b[0]) or (int(a[0]) == int(b[0]) and int(a[1]) < int(b[1])))
	return s


# Blocks and jelly the way the dish draws them, for the board and the tank.
class Body extends Node2D:
	var blocks: MultiMeshInstance2D
	var skin: Sprite2D
	var skin_mat: ShaderMaterial
	var mat: ShaderMaterial
	var scale_px := 1.0 # screen pixels per µm
	var dark := 1.0

	func _init() -> void:
		mat = ShaderMaterial.new()
		mat.shader = preload("res://shaders/colony.gdshader")
		skin_mat = ShaderMaterial.new()
		skin_mat.shader = preload("res://shaders/colony_skin.gdshader")
		skin = Sprite2D.new()
		skin.material = skin_mat
		skin.centered = true
		add_child(skin)
		blocks = ColonyLayer.sprites(Colony.MAX_BLOCKS, mat)
		add_child(blocks)

	func show_cells(cells: Array, swim: float) -> void:
		var body := Colony.centred(cells)
		var side := Colony.skin_side(cells)
		var tex := Colony.bake_skin(cells, 64)
		var white := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		white.fill(Color.WHITE)
		skin.texture = ImageTexture.create_from_image(white)
		skin.scale = Vector2.ONE * side * scale_px
		skin.self_modulate = TINT
		skin_mat.set_shader_parameter("skin", tex)
		skin_mat.set_shader_parameter("side", side * scale_px)
		skin_mat.set_shader_parameter("range", Colony.SKIN_RANGE * scale_px)
		skin_mat.set_shader_parameter("px", 1.0)
		skin_mat.set_shader_parameter("dark", dark)
		mat.set_shader_parameter("px", 1.0)
		mat.set_shader_parameter("dark", dark)
		place_blocks(cells, swim)

	# Only the blocks (the jelly stays): `grown` maps a grid cell to how far
	# that block has grown in, 0..1 and a little over as it settles.
	func place_blocks(cells: Array, swim: float, grown := {}) -> void:
		var body := Colony.centred(cells)
		var mm := blocks.multimesh
		mm.visible_instance_count = body.size()
		var quad := Colony.BLOCK * scale_px * 2.2
		for k in body.size():
			var b := body[k]
			var g: float = grown.get(Vector2i(cells[k][0], cells[k][1]), 1.0)
			var open := 0
			for d: Array in [[1, 0, 1], [-1, 0, 2], [0, 1, 4], [0, -1, 8]]:
				var hit := false
				for o in body:
					if absf(o.x - b.x - d[0]) < 0.1 and absf(o.y - b.y - d[1]) < 0.1:
						hit = true
				if not hit:
					open |= d[2]
			# (The shader's kinds: 0 flagellum, 1 germ, 3 armour, 4 store, shown full.)
			var kind: int = {Colony.GERM: 1, Colony.ARMOR: 3, Colony.STORE: 4, Colony.REGEN: 5}.get(int(b.z), 0)
			mm.set_instance_transform_2d(k, Transform2D(Vector2(quad * g, 0), Vector2(0, quad * g), Vector2(b.x, b.y) * Colony.BLOCK * scale_px))
			mm.set_instance_color(k, Color(TINT, swim))
			mm.set_instance_custom_data(k, Color((kind + 8.0 * open) / 128.0, fposmod(k * 0.37, 1.0), 1.0 if kind == 4 else 0.0, 0.0))


# The instruments' slate glass (shaders/scope_glass) and the beat warnings
# pulse to.
class Fx:
	static func glass(owner: Control, sz: Vector2, focus_a := 0.0) -> ShaderMaterial:
		var m := ShaderMaterial.new()
		m.shader = preload("res://shaders/scope_glass.gdshader")
		m.set_shader_parameter("size", sz)
		m.set_shader_parameter("focus", sz * 0.5)
		m.set_shader_parameter("focus_r", sz.x * 0.4)
		m.set_shader_parameter("focus_a", focus_a)
		var r := ColorRect.new()
		r.material = m
		r.show_behind_parent = true
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.size = sz
		owner.add_child(r)
		return m

	static func beat() -> float:
		return 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.0055)

	# A rectangle's outline as moving dashes ("marching ants").
	static func ants(ci: CanvasItem, r: Rect2, col: Color, t: float, w := 1.5) -> void:
		var pts := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
		var dash := 7.0
		var gap := 5.0
		var off := fposmod(t * 22.0, dash + gap)
		for k in 4:
			var a: Vector2 = pts[k]
			var b: Vector2 = pts[(k + 1) % 4]
			var len := a.distance_to(b)
			var dir := (b - a) / len
			var x := off - (dash + gap)
			while x < len:
				var x0 := maxf(x, 0.0)
				var x1 := minf(x + dash, len)
				if x1 > x0:
					ci.draw_line(a + dir * x0, a + dir * x1, col, w, true)
				x += dash + gap


# How many blocks, as a row of slots: the star's line marked on it.
class Meter extends Control:
	var bench: Node

	func _init() -> void:
		custom_minimum_size = Vector2(270, 62)

	func _draw() -> void:
		var cells: Array = bench.cells
		var n := cells.size()
		draw_string(Ui.mono("SemiBold"), Vector2(0, 24), "%02d" % n, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Ui.INK)
		draw_string(Ui.sans(500), Vector2(40, 24), "/ %d 块" % Colony.MAX_BLOCKS, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Ui.INK_FAINT)
		if bench.star_blocks > 0:
			var over: bool = n > int(bench.star_blocks)
			draw_string(Ui.sans(600), Vector2(0, 24), "%d 块以内得一星" % bench.star_blocks, HORIZONTAL_ALIGNMENT_RIGHT, 270, 12, Ui.INK_SOFT if over else Ui.GOOD)
		# (Slots coloured by kind, in the palette's order.)
		var order := []
		for t: int in bench.kinds:
			for c: Array in cells:
				if int(c[2]) == t:
					order.append(t)
		var w := 270.0 / Colony.MAX_BLOCKS
		for k in Colony.MAX_BLOCKS:
			var r := Rect2(k * w + 1.5, 36, w - 3.0, 14)
			if k < n:
				var col: Color = SEG[int(order[k])] if k < order.size() else SEG[Colony.FLAG]
				draw_rect(r, col.darkened(0.25))
				draw_rect(Rect2(r.position, Vector2(r.size.x, 3)), Color(1, 1, 1, 0.45))
			else:
				draw_rect(r, Color(Ui.INK, 0.07))
		if bench.star_blocks > 0:
			var x: float = bench.star_blocks * w
			draw_line(Vector2(x, 31), Vector2(x, 55), Ui.INK, 1.5)


# The block palette: dragged onto the scope.
class Tile extends HBoxContainer:
	var type := 1
	var text := ""

	func _init(t: int, what: String, compact := false) -> void:
		type = t
		text = NAMES[t]
		custom_minimum_size = Vector2(270, 68 if compact else 84)
		add_theme_constant_override("separation", 12)
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_DRAG
		var art := Control.new()
		art.custom_minimum_size = Vector2(76, 76)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.draw.connect(func() -> void:
			# A drop on a slide: slate glass, lit from the top-left.
			art.draw_circle(Vector2(38, 38), 37, SLATE)
			art.draw_circle(Vector2(38, 38), 30, Color(TINT, 0.08))
			art.draw_arc(Vector2(38, 38), 36, PI * 1.05, PI * 1.6, 24, Color(0.75, 0.97, 1.0, 0.55), 1.6, true)
			art.draw_arc(Vector2(38, 38), 37, 0, TAU, 48, Color(SEG[t], 0.5), 1.2, true))
		add_child(art)
		var one := Body.new()
		one.scale_px = 1.75
		one.position = Vector2(38, 38)
		art.add_child(one)
		one.show_cells([[0, 0, t]], 0.5)
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_theme_constant_override("separation", 2)
		add_child(v)
		var top := HBoxContainer.new()
		top.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(top)
		var a := Ui.label(text, 15, Ui.INK, Ui.sans(700))
		a.mouse_filter = Control.MOUSE_FILTER_IGNORE
		top.add_child(a)
		var g := Ui.label("  %s · %s" % [GENE[t], ROLE[t]], 11, (SEG[t] as Color).darkened(0.45), Ui.sans(600))
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		g.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		top.add_child(g)
		var b := Ui.label(what, 12 if compact else 13, Ui.INK_SOFT, Ui.sans(500))
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(b)

	func _get_drag_data(_at: Vector2) -> Variant:
		var preview := Widgets.Pill.new(text, 120, Ui.sans(600))
		preview.active = true
		set_drag_preview(preview)
		return {block = type}


# One control, as a small card: a drawn glyph, what you do, what it does.
class Hint extends Control:
	var kind := ""
	var act := ""
	var does := ""

	func _init(k: String, a: String, d: String) -> void:
		kind = k
		act = a
		does = d
		custom_minimum_size = Vector2(270, 44)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var box := StyleBoxFlat.new()
		box.bg_color = Color(1, 1, 1, 0.42)
		box.border_color = Color(Ui.ACCENT, 0.16)
		box.set_border_width_all(1)
		box.set_corner_radius_all(6)
		draw_style_box(box, Rect2(Vector2.ZERO, size))
		draw_rect(Rect2(0, 8, 2, size.y - 16), Color(Ui.ACCENT, 0.7))
		_glyph(Vector2(24, size.y * 0.5))
		draw_string(Ui.sans(700), Vector2(48, 27), act, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Ui.INK)
		var aw := Ui.sans(700).get_string_size(act, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		draw_string(Ui.sans(500), Vector2(48 + aw + 10, 27), does, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Ui.INK_SOFT)

	func _sq(at: Vector2, s: float, col: Color, fill := false) -> void:
		draw_rect(Rect2(at - Vector2.ONE * s * 0.5, Vector2.ONE * s), col, fill, -1.0 if fill else 1.4)

	# Each glyph about 22 px, in ink and accent.
	func _glyph(c: Vector2) -> void:
		var ink := Color(Ui.INK, 0.85)
		var acc := Ui.ACCENT
		match kind:
			"in":
				_sq(c + Vector2(4, 0), 12.0, Color(acc, 0.25), true)
				_sq(c + Vector2(4, 0), 12.0, acc)
				draw_line(c + Vector2(-11, 0), c + Vector2(0, 0), ink, 1.6, true)
				draw_polyline(PackedVector2Array([c + Vector2(-4, -4), c + Vector2(0, 0), c + Vector2(-4, 4)]), ink, 1.6, true)
			"swap":
				_sq(c + Vector2(-6, 3), 9.0, acc)
				_sq(c + Vector2(6, -3), 9.0, Color(SEG[Colony.GERM].darkened(0.35)), true)
				draw_arc(c, 9.0, PI * 1.1, PI * 1.75, 10, ink, 1.4, true)
				draw_arc(c, 9.0, PI * 0.1, PI * 0.75, 10, ink, 1.4, true)
			"click":
				var p := PackedVector2Array([c + Vector2(-5, -9), c + Vector2(-5, 7), c + Vector2(-1, 3), c + Vector2(2, 9), c + Vector2(4, 8), c + Vector2(1, 2), c + Vector2(6, 2)])
				draw_colored_polygon(p, Color(1, 1, 1, 0.9))
				p.append(p[0])
				draw_polyline(p, ink, 1.3, true)
				draw_arc(c + Vector2(-5, -9), 5.0, 0, TAU, 16, Color(acc, 0.8), 1.2, true)
			"out":
				_sq(c + Vector2(-4, 0), 12.0, Color(Ui.INK, 0.35))
				draw_line(c + Vector2(-8, -4), c + Vector2(0, 4), ALERT_INK, 1.6, true)
				draw_line(c + Vector2(0, -4), c + Vector2(-8, 4), ALERT_INK, 1.6, true)
				draw_line(c + Vector2(4, 0), c + Vector2(12, 0), ink, 1.6, true)
				draw_polyline(PackedVector2Array([c + Vector2(8, -4), c + Vector2(12, 0), c + Vector2(8, 4)]), ink, 1.6, true)
			"link":
				for k in 3:
					_sq(c + Vector2(-8 + k * 8, 0), 7.5, Color(acc, 0.3 + 0.25 * k), true)
					_sq(c + Vector2(-8 + k * 8, 0), 7.5, acc)


# The darkfield: slate glass with the light pooled under the body, drifting
# specks, the reticle and its readouts, and the needle. The grid itself is the
# Board inside it, framed by a camera that eases in on the body (with room
# round it to add blocks) every time the body changes, and holds still while a
# block is being dragged.
class Scope extends Control:
	var bench: Node
	var board: Board
	var top: Control
	var glass: ShaderMaterial
	var specks := []
	var glow: GradientTexture2D
	var needle_tip := Vector2.ZERO
	var park := Vector2.ZERO
	var flash := 0.0
	var flash_at := Vector2.ZERO
	var tw: Tween
	var ghosts := [] # [centre, type, seconds]: blocks drawn back out
	var ripples := [] # [centre, seconds]: rings off a block just put in
	var sparks := [] # [position, velocity, life 1..0]
	var denied := 0.0
	var deny_at := Vector2.ZERO
	var deny_text := ""
	var boot := 1.0 # the scope coming on, 0..1
	var zoom := 0.0 # 0 until first framed
	var zoom_to := 1.0
	var focus := Vector2.ZERO # board point at the middle of the view
	var focus_to := Vector2.ZERO

	func _init() -> void:
		custom_minimum_size = SCOPE
		clip_contents = true
		mouse_filter = Control.MOUSE_FILTER_PASS
		glass = Fx.glass(self, SCOPE, 0.5)
		board = Board.new()
		add_child(board)
		top = Control.new()
		top.mouse_filter = Control.MOUSE_FILTER_IGNORE
		top.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		top.draw.connect(_draw_top)
		add_child(top)
		for k in 54:
			specks.append(Vector3(randf() * SCOPE.x, randf() * SCOPE.y, randf()))
		glow = glow_tex()
		park = Vector2(SCOPE.x - 190, SCOPE.y - 160)
		needle_tip = park

	# A soft round light, for glows.
	static func glow_tex() -> GradientTexture2D:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 128
		t.height = 128
		return t

	# The body spans grid cells lo..hi: frame it with a cell and a half of
	# water all round, as large as that allows.
	func frame(lo: Vector2, hi: Vector2) -> void:
		var cells := hi - lo + Vector2.ONE
		zoom_to = clampf(minf(SCOPE.x / ((cells.x + 3.0) * STEP), SCOPE.y / ((cells.y + 3.0) * STEP)), 0.9, ZOOM_MAX)
		focus_to = (lo + hi + Vector2.ONE) * 0.5 * STEP
		if zoom == 0.0:
			zoom = zoom_to
			focus = focus_to
		_place()

	func _place() -> void:
		board.scale = Vector2.ONE * zoom
		board.position = SCOPE * 0.5 - focus * zoom

	func cell_size() -> float:
		return STEP * maxf(zoom, 0.1)

	func cell_centre(c: Vector2i) -> Vector2:
		return board.position + (Vector2(c) + Vector2(0.5, 0.5)) * cell_size()

	func cell_rect(c: Vector2i) -> Rect2:
		return Rect2(board.position + Vector2(c) * cell_size(), Vector2.ONE * cell_size())

	# The needle goes to the block that changed, and back; the block lands
	# with a ring through the water and a few motes off it.
	func inject(c: Vector2i) -> void:
		if tw:
			tw.kill()
		var to := cell_centre(c)
		tw = create_tween()
		tw.tween_property(self, "needle_tip", to, 0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_callback(func() -> void:
			flash = 1.0
			flash_at = to
			ripples.append([to, 0.0])
			ripples.append([to, -0.12])
			for k in 16:
				var a := randf() * TAU
				var v := Vector2(cos(a), sin(a)) * randf_range(60.0, 190.0)
				sparks.append([to + v.normalized() * cell_size() * 0.3, v, 1.0]))
		tw.tween_interval(0.14)
		tw.tween_property(self, "needle_tip", park, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

	# A block taken out: it shrinks away up the needle.
	func ghost(c: Vector2i, type: int) -> void:
		ghosts.append([cell_centre(c), type, 0.0])

	# Not allowed: the cell is crossed out, the needle stops short and backs off.
	func deny(c: Vector2i, why := "") -> void:
		denied = 1.0
		deny_at = cell_centre(c)
		deny_text = why
		if tw:
			tw.kill()
		var near := deny_at + (park - deny_at).normalized() * 34.0
		tw = create_tween()
		tw.tween_property(self, "needle_tip", near, 0.14).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(self, "needle_tip", near + Vector2(7, -3), 0.05)
		tw.tween_property(self, "needle_tip", near, 0.05)
		tw.tween_property(self, "needle_tip", park, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

	# Each time the page comes up the scope comes on and the body is put
	# together again, a block at a time.
	func _notification(what: int) -> void:
		if what == NOTIFICATION_VISIBILITY_CHANGED and is_visible_in_tree() and board.bench != null:
			boot = 0.0
			board.assemble()
			bench.strand.retype()

	func _process(dt: float) -> void:
		if not is_visible_in_tree():
			return
		boot = minf(boot + dt / 0.9, 1.0)
		denied = maxf(denied - dt * 0.7, 0.0)
		# The camera, held while a block is in the hand.
		if zoom > 0.0 and not get_viewport().gui_is_dragging():
			var k := 1.0 - exp(-dt * 5.0)
			zoom = lerpf(zoom, zoom_to, k)
			focus = focus.lerp(focus_to, k)
			_place()
		for g: Array in ghosts:
			g[2] = float(g[2]) + dt
		ghosts = ghosts.filter(func(g: Array) -> bool: return float(g[2]) < 0.5)
		for r: Array in ripples:
			r[1] = float(r[1]) + dt
		ripples = ripples.filter(func(r: Array) -> bool: return float(r[1]) < 0.7)
		for p: Array in sparks:
			p[0] = (p[0] as Vector2) + (p[1] as Vector2) * dt
			p[1] = (p[1] as Vector2) * exp(-dt * 4.0)
			p[2] = float(p[2]) - dt * 1.6
		sparks = sparks.filter(func(p: Array) -> bool: return float(p[2]) > 0.0)
		# The needle: steady at rest (a hand's tremor), over the cell a block
		# is being dragged to.
		if tw == null or not tw.is_running():
			var t := Time.get_ticks_msec() * 0.001
			var aim := park + Vector2(sin(t * 1.3) * 1.5, cos(t * 1.7) * 1.2)
			if get_viewport().gui_is_dragging() and board.inside(board.hover):
				aim = cell_centre(board.hover) + Vector2(0.46, -0.16) * cell_size()
			needle_tip = needle_tip.lerp(aim, 1.0 - exp(-dt * 10.0))
		var drift: float = bench.stream * STEP / Colony.BLOCK * 0.5
		for k in specks.size():
			var s: Vector3 = specks[k]
			s.x -= drift * (0.5 + s.z) * dt
			if s.x < -4.0:
				s = Vector3(SCOPE.x + 4.0, randf() * SCOPE.y, randf())
			specks[k] = s
		flash = maxf(flash - dt * 2.4, 0.0)
		# The light follows the body.
		var mid: Vector2 = board.position + board.body.position * zoom
		glass.set_shader_parameter("focus", mid)
		glass.set_shader_parameter("focus_r", maxf(board.span.x, board.span.y) * zoom * 0.75 + 90.0)
		glass.set_shader_parameter("flash", flash)
		queue_redraw()
		top.queue_redraw()

	func _draw() -> void:
		# Light under the body, as a lit specimen throws it, breathing.
		var mid: Vector2 = board.position + board.body.position * zoom
		var span: Vector2 = board.span * zoom * 1.7 + Vector2.ONE * 150.0
		var t := Time.get_ticks_msec() * 0.001
		draw_texture_rect(glow, Rect2(mid - span * 0.5, span), false, Color(TINT, 0.12 + 0.03 * sin(t * 1.1)))
		for s: Vector3 in specks:
			var a := 0.08 + 0.24 * s.z
			if s.z > 0.8:
				draw_line(Vector2(s.x, s.y), Vector2(s.x + 6.0 + 10.0 * s.z, s.y), Color(GLOW, a * 0.6), 1.0)
			draw_circle(Vector2(s.x, s.y), 0.6 + 1.1 * s.z, Color(GLOW, a))

	func _draw_top() -> void:
		var f := Ui.mono("Medium")
		var t := Time.get_ticks_msec() * 0.001
		var cs := cell_size()
		# The reticle.
		var c := SCOPE * 0.5
		top.draw_line(Vector2(0, c.y), Vector2(SCOPE.x, c.y), Color(GLOW, 0.05), 1.0)
		top.draw_line(Vector2(c.x, 0), Vector2(c.x, SCOPE.y), Color(GLOW, 0.05), 1.0)
		for k in range(-15, 16):
			var l := 7.0 if k % 5 == 0 else 3.5
			top.draw_line(Vector2(c.x + k * 28.0, c.y - l), Vector2(c.x + k * 28.0, c.y + l), Color(GLOW, 0.16), 1.0)
			if absi(k) <= 10:
				top.draw_line(Vector2(c.x - l, c.y + k * 28.0), Vector2(c.x + l, c.y + k * 28.0), Color(GLOW, 0.16), 1.0)
		for corner: Vector2 in [Vector2(14, 14), Vector2(SCOPE.x - 14, 14), Vector2(14, SCOPE.y - 14), Vector2(SCOPE.x - 14, SCOPE.y - 14)]:
			var sx := 1.0 if corner.x < c.x else -1.0
			var sy := 1.0 if corner.y < c.y else -1.0
			top.draw_line(corner, corner + Vector2(18 * sx, 0), Color(GLOW, 0.75), 1.5)
			top.draw_line(corner, corner + Vector2(0, 18 * sy), Color(GLOW, 0.75), 1.5)
		var ink := Color(GLOW, 0.75)
		var faint := Color(GLOW, 0.42)
		top.draw_string(f, Vector2(26, 36), "DARKFIELD  ×%d" % (roundi(40.0 * zoom) * 10), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, ink)
		top.draw_string(f, Vector2(26, 54), "FOCUS %+.1f µm" % (0.4 * sin(t * 0.7) + 6.0 * (zoom - zoom_to)), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, faint)
		top.draw_string(f, Vector2(SCOPE.x - 326, 36), "SPECIMEN " + bench.specimen, HORIZONTAL_ALIGNMENT_RIGHT, 300, 12, ink)
		top.draw_string(f, Vector2(SCOPE.x - 326, 54), "BODY PLAN  rev.%02d" % (bench.undo_stack.size() + 1), HORIZONTAL_ALIGNMENT_RIGHT, 300, 11, faint)
		# One block's length, for scale.
		var y := SCOPE.y - 26.0
		top.draw_line(Vector2(26, y), Vector2(26 + cs, y), ink, 2.0)
		top.draw_line(Vector2(26, y - 5), Vector2(26, y + 5), ink, 1.0)
		top.draw_line(Vector2(26 + cs, y - 5), Vector2(26 + cs, y + 5), ink, 1.0)
		top.draw_string(f, Vector2(34 + cs, y + 4), "%d µm" % Colony.BLOCK, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, ink)
		# The stream, and the way the body heads.
		var fx := SCOPE.x - 262.0
		for k in 3:
			var x := fx + fposmod(-t * 18.0 + k * 9.0, 27.0)
			top.draw_polyline(PackedVector2Array([Vector2(x + 5, y - 5), Vector2(x, y), Vector2(x + 5, y + 5)]), Color(GLOW, 0.3 + 0.2 * k), 1.5)
		top.draw_string(Ui.sans(600), Vector2(fx + 34, y + 5), "水流 %.0f µm/s，推向喷口" % bench.stream, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, ink)
		var ax := SCOPE.x - 26.0 - 6.0 * fposmod(t * 0.8, 1.0)
		top.draw_string(Ui.sans(700), Vector2(SCOPE.x - 330, c.y - 12), "前进", HORIZONTAL_ALIGNMENT_RIGHT, 274, 13, Color(GLOW, 0.85))
		top.draw_polyline(PackedVector2Array([Vector2(ax - 8, c.y - 23), Vector2(ax, c.y - 17), Vector2(ax - 8, c.y - 11)]), Color(GLOW, 0.85), 1.6, true)
		# Where the pointer is.
		var hv: Vector2i = board.hover
		if board.inside(hv):
			var r := cell_rect(hv)
			var a := Color(GLOW, 0.95)
			for k in 4:
				var p := r.position + Vector2(r.size.x * (k & 1), r.size.y * (k >> 1))
				var dx := 1.0 if (k & 1) == 0 else -1.0
				var dy := 1.0 if (k >> 1) == 0 else -1.0
				top.draw_line(p, p + Vector2(12 * dx, 0), a, 1.5)
				top.draw_line(p, p + Vector2(0, 12 * dy), a, 1.5)
			top.draw_string(f, r.position + Vector2(0, -6), "X%02d Y%02d" % [hv.x, hv.y], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, a)
		_draw_alerts(t)
		# Where it went in, what came out, and what was refused.
		if flash > 0.0:
			top.draw_texture_rect(glow, Rect2(flash_at - Vector2.ONE * cs * 0.9, Vector2.ONE * cs * 1.8), false, Color(GLOW, 0.55 * flash))
		for r: Array in ripples:
			var u := float(r[1]) / 0.7
			if u > 0.0:
				var e := 1.0 - (1.0 - u) * (1.0 - u)
				top.draw_arc(r[0], cs * (0.35 + 1.5 * e), 0, TAU, 64, Color(GLOW, 0.55 * (1.0 - u)), 1.5 + 1.5 * (1.0 - u), true)
		for p: Array in sparks:
			var life := float(p[2])
			top.draw_circle(p[0], 1.0 + 1.4 * life, Color(GLOW, 0.85 * life))
		for g: Array in ghosts:
			var gt := float(g[2]) / 0.5
			var half := cs * 0.5 * (1.0 - 0.75 * gt)
			var col: Color = SEG[int(g[1])]
			top.draw_arc(g[0], half, 0.0, TAU, 48, Color(col, 0.7 * (1.0 - gt)), 1.5, true)
			top.draw_texture_rect(glow, Rect2(g[0] - Vector2.ONE * half * 1.6, Vector2.ONE * half * 3.2), false, Color(col, 0.35 * (1.0 - gt)))
		if denied > 0.0:
			# Crossed out in the theme's own light, with a shudder.
			var at := deny_at + Vector2(sin(t * 60.0) * 3.0 * denied * denied, 0)
			top.draw_texture_rect(glow, Rect2(at - Vector2.ONE * cs, Vector2.ONE * cs * 2.0), false, Color(ALERT, 0.35 * denied))
			top.draw_arc(at, cs * 0.42, 0, TAU, 48, Color(ALERT, denied), 2.0, true)
			var h := cs * 0.2
			top.draw_line(at - Vector2(h, h), at + Vector2(h, h), Color(ALERT, denied), 2.4, true)
			top.draw_line(at + Vector2(-h, h), at + Vector2(h, -h), Color(ALERT, denied), 2.4, true)
			if deny_text != "":
				var font := Ui.sans(700)
				var w := font.get_string_size(deny_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 24.0
				var p := Vector2(clampf(at.x - w * 0.5, 16.0, SCOPE.x - w - 16.0), clampf(at.y + cs * 0.5 + 12.0, 72.0, SCOPE.y - 70.0))
				var a := minf(denied * 2.0, 1.0)
				var chip := Rect2(p, Vector2(w, 26))
				top.draw_rect(chip, Color(SLATE.darkened(0.3), 0.85 * a))
				top.draw_rect(chip, Color(ALERT, 0.8 * a), false, 1.0)
				top.draw_string(font, p + Vector2(12, 18), deny_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(ALERT, a))
		_draw_needle()
		# Coming on: dark, then a line of light runs down the field.
		if boot < 1.0:
			var e := 1.0 - boot
			top.draw_rect(Rect2(Vector2.ZERO, SCOPE), Color(0.02, 0.05, 0.07, 0.8 * e * e))
			var sy := boot * SCOPE.y
			top.draw_texture_rect(glow, Rect2(Vector2(-SCOPE.x * 0.2, sy - 26.0), Vector2(SCOPE.x * 1.4, 52.0)), false, Color(GLOW, 0.22 * e))
			top.draw_line(Vector2(0, sy), Vector2(SCOPE.x, sy), Color(GLOW, 0.75 * e), 1.0)

	# What is wrong with a block, on the block: its outline marching, its
	# corners pulsing, and a small outlined tag in its lower-left corner that
	# leaves the block itself in view.
	func _draw_alerts(t: float) -> void:
		var pulse := Fx.beat()
		var font := Ui.sans(700)
		for m: Array in board.marks:
			var at: Vector2i = m[2]
			if board.born.has(at):
				continue
			var r := cell_rect(at).grow(-3.0)
			var mid := r.get_center()
			var rad := r.size.x * 0.5
			top.draw_texture_rect(glow, r.grow(r.size.x * 0.25), false, Color(ALERT, 0.06 + 0.1 * pulse))
			# A ring of dashes turning round the cell, and a ring breathing out.
			var n := 16
			for k in n:
				var a0 := t * 0.9 + k * TAU / n
				top.draw_arc(mid, rad, a0, a0 + TAU / n * 0.55, 8, Color(ALERT, 0.65 + 0.35 * pulse), 1.5, true)
			top.draw_arc(mid, rad + 3.0 + 3.0 * pulse, 0.0, TAU, 64, Color(ALERT, 0.25 + 0.3 * (1.0 - pulse)), 2.0, true)
			var w := font.get_string_size(m[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 16.0
			var chip := Rect2(r.position + Vector2(5, r.size.y - 22), Vector2(w, 17))
			top.draw_rect(chip, Color(SLATE.darkened(0.35), 0.72))
			top.draw_rect(chip, Color(ALERT, 0.75 + 0.25 * pulse), false, 1.0)
			top.draw_circle(chip.position + Vector2(7, 8.5), 2.2, Color(ALERT, 0.6 + 0.4 * pulse))
			top.draw_string(font, chip.position + Vector2(12, 13), m[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, ALERT)

	# A pulled glass micropipette: fine at the tip, wide where it leaves view.
	func _draw_needle() -> void:
		var dir := Vector2(1.0, -0.3).normalized()
		var n := Vector2(-dir.y, dir.x)
		var tip := needle_tip
		var base := tip + dir * 520.0
		var shoulder := tip + dir * 70.0
		var pts := PackedVector2Array([tip + n * 0.7, shoulder + n * 4.5, base + n * 13.0, base - n * 13.0, shoulder - n * 4.5, tip - n * 0.7])
		top.draw_colored_polygon(pts, Color(0.72, 0.95, 1.0, 0.14))
		top.draw_polyline(PackedVector2Array([tip + n * 0.7, shoulder + n * 4.5, base + n * 13.0]), Color(0.78, 1.0, 1.0, 0.75), 1.2, true)
		top.draw_polyline(PackedVector2Array([tip - n * 0.7, shoulder - n * 4.5, base - n * 13.0]), Color(0.78, 1.0, 1.0, 0.4), 1.2, true)
		top.draw_line(shoulder + n * 2.6 + dir * 20.0, base + n * 8.0, Color(1, 1, 1, 0.22), 2.0, true)
		# The bore, and a bead of what it carries near the tip.
		top.draw_line(shoulder + n * 0.8, base + n * 2.5, Color(1, 1, 1, 0.16), 1.0, true)
		top.draw_circle(tip + dir * 26.0, 2.2, Color(TINT.lightened(0.3), 0.75))
		top.draw_circle(tip, 1.6, Color(1, 1, 1, 0.85))
		top.draw_texture_rect(glow, Rect2(tip - Vector2.ONE * 9.0, Vector2.ONE * 18.0), false, Color(GLOW, 0.35))


class Board extends Control:
	var bench: Node
	var body: Body
	var hover := Vector2i(-1, -1)
	var dragging_from := Vector2i(-1, -1)
	var overlay: Control
	var marks := []
	var span := Vector2.ZERO
	var was := {} # cell -> type, as last drawn
	var born := {} # cell -> seconds since it went in (below 0: still waiting)
	var glow: GradientTexture2D

	func _init() -> void:
		custom_minimum_size = Vector2(GRID_W, GRID_H) * STEP
		size = custom_minimum_size
		mouse_filter = Control.MOUSE_FILTER_STOP
		body = Body.new()
		body.scale_px = STEP / Colony.BLOCK
		add_child(body)
		overlay = Control.new()
		overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		overlay.draw.connect(_draw_marks)
		add_child(overlay)
		glow = Scope.glow_tex()

	func cell_at(at: Vector2) -> Vector2i:
		return Vector2i(int(floor(at.x / STEP)), int(floor(at.y / STEP)))

	func inside(c: Vector2i) -> bool:
		return c.x >= 0 and c.y >= 0 and c.x < GRID_W and c.y < GRID_H

	func rebuild() -> void:
		var lo := Vector2(100, 100)
		var hi := Vector2(-100, -100)
		for c: Array in bench.cells:
			lo = lo.min(Vector2(c[0], c[1]))
			hi = hi.max(Vector2(c[0], c[1]))
		body.position = (lo + hi + Vector2.ONE) * 0.5 * STEP
		span = (hi - lo + Vector2.ONE) * STEP
		if bench.scope:
			bench.scope.frame(lo, hi)
		# What went in, what changed kind, and what went out.
		var now := {}
		for c: Array in bench.cells:
			var at := Vector2i(c[0], c[1])
			now[at] = int(c[2])
			if not was.is_empty() and (not was.has(at) or int(was[at]) != int(c[2])):
				born[at] = 0.0
		for at: Vector2i in was:
			if not now.has(at) and bench.scope:
				bench.scope.ghost(at, int(was[at]))
		was = now
		body.show_cells(bench.cells, 0.5)
		_grow(0.0)
		queue_redraw()

	# Every block grows in again, front to back: the page coming up.
	func assemble() -> void:
		born.clear()
		for c: Array in bench.cells:
			born[Vector2i(c[0], c[1])] = -0.05 * (GRID_W - int(c[0])) - 0.025 * int(c[1]) - 0.25
		_grow(0.0)

	func _grow(dt: float) -> void:
		if born.is_empty():
			return
		var grown := {}
		for at: Vector2i in born.keys():
			born[at] = float(born[at]) + dt
			var t := clampf(float(born[at]) / 0.42, 0.0, 1.0)
			if t >= 1.0:
				born.erase(at)
				continue
			# Out past full size, and back: it settles.
			var u := t - 1.0
			grown[at] = 0.0 if t <= 0.0 else 1.0 + 2.7 * u * u * u + 1.7 * u * u
		body.place_blocks(bench.cells, 0.5, grown)
		overlay.queue_redraw()

	func _process(dt: float) -> void:
		_grow(dt)
		if hover != Vector2i(-1, -1) and not get_viewport().gui_is_dragging() and not Rect2(Vector2.ZERO, size).has_point(get_local_mouse_position()):
			hover = Vector2i(-1, -1)
			queue_redraw()
		if dragging_from != Vector2i(-1, -1):
			var off := not Rect2(Vector2.ZERO, size).has_point(get_local_mouse_position())
			bench.note.text = "松手会删除这一块，按 Esc 取消" if off else ""

	func _get_drag_data(at: Vector2) -> Variant:
		var c := cell_at(at)
		if bench._index(c) < 0:
			return null
		dragging_from = c
		var preview := Widgets.Pill.new(NAMES[Colony.type_at(bench.cells, c.x, c.y)], 120, Ui.sans(600))
		preview.active = true
		set_drag_preview(preview)
		return {from = c}

	func _can_drop_data(at: Vector2, data: Variant) -> bool:
		if not (data is Dictionary) or not (data.has("block") or data.has("from")):
			return false
		var c := cell_at(at)
		if c != hover:
			hover = c
			queue_redraw()
		return inside(c)

	func _drop_data(at: Vector2, data: Variant) -> void:
		var c := cell_at(at)
		if data.has("from"):
			bench.move(data.from, c)
		else:
			bench.place(c, int(data.block))
		dragging_from = Vector2i(-1, -1)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseMotion and not get_viewport().gui_is_dragging():
			var c := cell_at(event.position)
			if c != hover:
				hover = c
				queue_redraw()
		if event is InputEventMouseButton and not event.pressed and not get_viewport().gui_is_dragging():
			var c := cell_at(event.position)
			if event.button_index == MOUSE_BUTTON_LEFT:
				bench.toggle(c)
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				bench.remove(c)

	func _notification(what: int) -> void:
		# Dragged off the grid: that block goes. Esc takes the drag back.
		if what == NOTIFICATION_DRAG_END:
			if dragging_from != Vector2i(-1, -1) and not get_viewport().gui_is_drag_successful() and not Input.is_action_pressed("ui_cancel"):
				bench.remove(dragging_from)
			dragging_from = Vector2i(-1, -1)

	# A counting chamber's ruling: fine lines, a cross at each corner, the
	# border drawn three times.
	func _draw() -> void:
		var w := GRID_W * STEP
		var h := GRID_H * STEP
		# (Hairlines: one pixel however far the camera is in.)
		var line := Color(GLOW, 0.08)
		for k in GRID_W + 1:
			draw_line(Vector2(k * STEP, 0), Vector2(k * STEP, h), line, -1.0)
		for k in GRID_H + 1:
			draw_line(Vector2(0, k * STEP), Vector2(w, k * STEP), line, -1.0)
		for i in GRID_W + 1:
			for j in GRID_H + 1:
				var p := Vector2(i, j) * STEP
				draw_line(p - Vector2(2.5, 0), p + Vector2(2.5, 0), Color(GLOW, 0.26), -1.0)
				draw_line(p - Vector2(0, 2.5), p + Vector2(0, 2.5), Color(GLOW, 0.26), -1.0)
		for k in 3:
			draw_rect(Rect2(Vector2(-3 + k * 3, -3 + k * 3), Vector2(w + 6 - k * 6, h + 6 - k * 6)), Color(GLOW, 0.16 - k * 0.04), false, -1.0)
		if inside(hover):
			draw_circle((Vector2(hover) + Vector2(0.5, 0.5)) * STEP, STEP * 0.5 - 2.0, Color(Ui.ACCENT, 0.16))
		# What is wrong with a block is marked on the block (by the child
		# drawn above the body).
		marks.clear()
		for c: Array in bench.cells:
			var r := Rect2(Vector2(c[0], c[1]) * STEP, Vector2.ONE * STEP)
			var why := ""
			if int(c[2]) == Colony.GERM and Colony.exposed(bench.cells, c[0], c[1]):
				why = "没遮挡"
			elif int(c[2]) == Colony.FLAG and Colony.inner(bench.cells, c[0], c[1]):
				why = "被包住"
			elif int(c[2]) == Colony.ARMOR and Colony.inner(bench.cells, c[0], c[1]):
				why = "挡不到"
			if why != "":
				marks.append([r.position + Vector2(STEP * 0.5, STEP - 6.0), why, Vector2i(c[0], c[1])])
		overlay.queue_redraw()
		if bench.scope:
			bench.scope.top.queue_redraw()

	func _draw_marks() -> void:
		# A new block lights up as it grows.
		for at: Vector2i in born:
			var t := clampf(float(born[at]) / 0.42, 0.0, 1.0)
			if t > 0.0:
				var c := (Vector2(at) + Vector2(0.5, 0.5)) * STEP
				overlay.draw_texture_rect(glow, Rect2(c - Vector2.ONE * STEP, Vector2.ONE * STEP * 2.0), false, Color(GLOW, 0.5 * (1.0 - t)))
		# Each block's own outline, faint; the one under the pointer brighter.
		# (A block with something wrong is marked by the scope, above.)
		for c: Array in bench.cells:
			var at := Vector2i(c[0], c[1])
			if born.has(at) or marks.any(func(m: Array) -> bool: return m[2] == at):
				continue
			overlay.draw_arc((Vector2(at) + Vector2(0.5, 0.5)) * STEP, STEP * 0.5 - 2.0, 0.0, TAU, 48, Color(GLOW, 0.65 if at == hover else 0.2), -1.0)


# The body's genes as a strip under the scope: one stretch per block, front
# first, on a slowly turning double helix. A stretch that changed is cut out
# and its letters settle again.
class Strand extends Control:
	var bench: Node
	var segs := []
	var keys := []
	var fresh := []
	const W := 880.0
	const H := 150.0
	const PAD := 22.0

	func _init() -> void:
		custom_minimum_size = Vector2(W, H)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var g := Fx.glass(self, Vector2(W, H), 0.18)
		g.set_shader_parameter("focus_r", W * 0.6)
		g.set_shader_parameter("caustic", 0.5)

	func rebuild() -> void:
		var next: Array = bench.segments()
		var next_keys := []
		var next_fresh := []
		for b: Array in next:
			var key := "%d,%d,%d" % [b[0], b[1], b[2]]
			next_keys.append(key)
			next_fresh.append(1.0 if keys.is_empty() or not keys.has(key) else 0.0)
		segs = next
		keys = next_keys
		fresh = next_fresh

	func retype() -> void:
		for k in fresh.size():
			fresh[k] = 1.0 + 0.06 * k

	func _process(dt: float) -> void:
		if not is_visible_in_tree():
			return
		for k in fresh.size():
			fresh[k] = maxf(float(fresh[k]) - dt * 0.9, 0.0)
		queue_redraw()

	func _draw() -> void:
		var f := Ui.mono("Medium")
		var t := Time.get_ticks_msec() * 0.001
		var n := segs.size()
		if n == 0:
			return
		draw_string(f, Vector2(PAD, 24), "GENOME", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(GLOW, 0.8))
		draw_string(Ui.sans(600), Vector2(PAD + 62, 24), "体型基因", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(GLOW, 0.8))
		draw_string(Ui.sans(500), Vector2(PAD + 130, 24), "%d 段 · %s bp" % [n, _thousands(n * BP)], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(GLOW, 0.45))
		# Each gene's count, right to left in the palette's order.
		var right := W - PAD
		var ks: Array = bench.kinds.duplicate()
		ks.reverse()
		for kind: int in ks:
			var c := 0
			for b: Array in segs:
				c += 1 if int(b[2]) == kind else 0
			var txt := "%s ×%d" % [GENE[kind], c]
			draw_string(f, Vector2(right - 90, 24), txt, HORIZONTAL_ALIGNMENT_RIGHT, 90, 11, SEG[kind])
			right -= f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 18.0
		var x0 := PAD
		var span := (W - PAD * 2.0) / n
		var cy := 66.0
		var amp := 15.0
		# The rungs first, then the two backbones over them.
		for k in n:
			var col: Color = SEG[int(segs[k][2])]
			var lit: float = minf(fresh[k], 1.0)
			# The block under the pointer, picked out here too.
			if Vector2i(segs[k][0], segs[k][1]) == bench.board.hover:
				draw_rect(Rect2(x0 + k * span + 1.0, 36, span - 2.0, 100), Color(col, 0.12))
				draw_rect(Rect2(x0 + k * span + 1.0, 36, span - 2.0, 100), Color(col, 0.6), false, 1.0)
				lit = maxf(lit, 0.35)
			var a0 := x0 + k * span + 3.0
			var a1 := x0 + (k + 1) * span - 3.0
			var x := a0
			while x < a1:
				var th := x * 0.09 - t * 1.4
				var ya := cy + amp * sin(th)
				var yb := cy + amp * sin(th + 2.4)
				draw_line(Vector2(x, ya), Vector2(x, yb), Color(col, 0.22 + 0.5 * lit), 1.0)
				x += 7.0
			for s in 2:
				var pts := PackedVector2Array()
				var cols := PackedColorArray()
				x = a0
				while x <= a1:
					var th := x * 0.09 - t * 1.4 + 2.4 * s
					pts.append(Vector2(x, cy + amp * sin(th)))
					cols.append(Color(col.lightened(0.5 * lit), 0.3 + 0.6 * (0.5 + 0.5 * cos(th))))
					x += 3.0
				draw_polyline_colors(pts, cols, 1.8, true)
			# A cut on each side of a stretch just put in.
			if lit > 0.0:
				for e: float in [a0 - 3.0, a1 + 3.0]:
					draw_line(Vector2(e, cy - 26), Vector2(e, cy + 26), Color(1, 1, 1, 0.8 * lit), 1.5)
			var mid := x0 + (k + 0.5) * span
			var gene: String = GENE[int(segs[k][2])]
			draw_string(f, Vector2(mid - 40, 106), gene, HORIZONTAL_ALIGNMENT_CENTER, 80, 11, Color(col, 0.9))
			var letters := bases(segs[k], 6 if span < 64.0 else 9)
			if lit > 0.0:
				var shown := ""
				for i in letters.length():
					shown += letters[i] if randf() > lit else "ACGT"[randi() % 4]
				letters = shown
			draw_string(f, Vector2(mid - 40, 128), letters, HORIZONTAL_ALIGNMENT_CENTER, 80, 11, Color(GLOW, 0.6 + 0.4 * lit))
		# The reading head, sweeping along.
		var head := x0 + fposmod(t * 90.0, W - PAD * 2.0)
		draw_line(Vector2(head, 40), Vector2(head, 92), Color(GLOW, 0.25), 1.0)
		draw_line(Vector2(PAD, 140), Vector2(W - PAD, 140), Color(GLOW, 0.1), 1.0)

	# A block's stretch of sequence, the same every time for the same block.
	static func bases(b: Array, n := 9) -> String:
		var out := "ATG" if int(b[2]) == Colony.GERM else ""
		var h := int(b[0]) * 7349 + int(b[1]) * 1931 + int(b[2]) * 271 + 17
		while out.length() < n:
			h = (h * 1103515245 + 12345) & 0x7fffffff
			out += "ACGT"[(h >> 16) & 3]
		return out

	static func _thousands(v: int) -> String:
		return "%d,%03d" % [v / 1000, v % 1000] if v >= 1000 else str(v)


# What the shape comes to, read off as instruments: thrust against the stream,
# whips that work, how clean a clump is eaten, the young and the grit. What is
# wrong is marked on the blocks; here there is only one line on what to do
# about it, the most pressing thing first.
class Gauges extends Control:
	var bench: Node
	var s := {}
	var shown := {thrust = 0.0, keep = 0.0}
	var sweep := 1.0 # a light run along the bars after a change, 0..1
	var said := ""
	var said_t := 1.0 # the advice line coming in, 0..1
	const W := 400.0

	func _init() -> void:
		custom_minimum_size = Vector2(W, 486)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func show_stats(stats: Dictionary) -> void:
		s = stats
		if shown.thrust == 0.0:
			shown.thrust = float(s.speed)
			shown.keep = float(s.keep)
		else:
			sweep = 0.0
		var next := advice()[0] as String
		if next != said:
			said = next
			said_t = 0.0
		queue_redraw()

	# [the one thing to do, whether it is a problem]
	func advice() -> Array:
		var net: float = float(s.speed) - float(bench.stream)
		if net < Colony.MIN_NET:
			if int(s.walled) > 0:
				return ["把被包住的鞭毛块挪到外缘，推力就够了", true]
			if int(s.width) > 3:
				return ["身体收窄一格：阻力小了，才顶得住水流", true]
			return ["外缘再加鞭毛块，推力才顶得住水流", true]
		if int(s.germ) == 0:
			return ["放几个生殖块：没有它，一个后代也留不下", true]
		if int(s.unsafe) > 0:
			return ["把没遮挡的生殖块挪到别的块后面", true]
		if int(s.germ) == 1:
			return ["再放一个生殖块：每代只生 1 个，数量涨不起来", true]
		if bench.kinds.has(Colony.REGEN):
			if int(s.regen) == 0:
				return ["放一个再生块：全身咬残的块都长回得快 %d 倍" % roundi(bench.regen_x), true]
			if int(s.armor_walled) > 0:
				return ["被包住的甲块挡不到猎手：挪到外缘", true]
			return ["有再生块：全身的伤 %d 秒长回" % roundi(bench.regrow / bench.regen_x), false]
		if bench.kinds.has(Colony.ARMOR):
			if int(s.armor_walled) > 0:
				return ["被包住的甲块挡不到猎手：挪到外缘", true]
			if int(s.armor) == 0:
				return ["外缘放几块甲：巨噬者咬到甲只掉一点点", true]
			if int(s.store) == 0:
				return ["放一个储能块：荒年里饿了才有存粮", true]
			return ["外缘 %d 块甲，储能 %d 块：巨噬者多从后面追来" % [int(s.armor), int(s.store)], false]
		return ["这个身体能到上游，约 %d 秒" % roundi(bench.trip / maxf(net, 0.1)), false]

	func _process(dt: float) -> void:
		if s.is_empty() or not is_visible_in_tree():
			return
		var k := 1.0 - exp(-dt * 9.0)
		shown.thrust = lerpf(shown.thrust, float(s.speed), k)
		shown.keep = lerpf(shown.keep, float(s.keep), k)
		sweep = minf(sweep + dt / 0.7, 1.0)
		said_t = minf(said_t + dt / 0.35, 1.0)
		queue_redraw()

	func _row(y: float, title: String, value: String, unit: String, col: Color, bad := false) -> void:
		var x := 0.0
		if bad:
			draw_circle(Vector2(4, y - 5), 3.0 + 1.2 * Fx.beat(), Color(ALERT_INK, 0.35 + 0.5 * Fx.beat()))
			draw_circle(Vector2(4, y - 5), 2.2, ALERT_INK)
			x = 14.0
		draw_string(Ui.sans(600), Vector2(x, y), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Ui.INK)
		var uw := Ui.sans(500).get_string_size(unit, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		# Numbers in the instrument face, words in the reading face.
		if value.to_utf8_buffer().size() == value.length():
			draw_string(Ui.mono("SemiBold"), Vector2(0, y + 2), value, HORIZONTAL_ALIGNMENT_RIGHT, W - uw - 6.0, 22, col)
		else:
			draw_string(Ui.sans(700), Vector2(0, y + 1), value, HORIZONTAL_ALIGNMENT_RIGHT, W - uw - 6.0, 15, col)
		draw_string(Ui.sans(500), Vector2(W - uw, y + 2), unit, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Ui.INK_FAINT)

	# A bar filled to `frac`, with the change sweep running along it.
	func _bar(r: Rect2, frac: float, col: Color, hatched := false) -> void:
		draw_rect(r, Color(Ui.INK, 0.07))
		var fill := Rect2(r.position, Vector2(clampf(frac, 0.0, 1.0) * r.size.x, r.size.y))
		if fill.size.x <= 0.5:
			return
		draw_rect(fill, col)
		if hatched:
			# Short of what it needs: stripes running along it.
			var off := fposmod(Time.get_ticks_msec() * 0.02, 8.0)
			var x := fill.position.x - r.size.y + off - 8.0
			while x < fill.end.x:
				var a := Vector2(maxf(x, fill.position.x), fill.end.y)
				var b := Vector2(minf(x + r.size.y, fill.end.x), fill.position.y)
				if b.x > a.x:
					draw_line(a, b, Color(1, 1, 1, 0.28), 2.0, true)
				x += 8.0
		draw_rect(Rect2(fill.position, Vector2(fill.size.x, 2)), Color(1, 1, 1, 0.5))
		if sweep < 1.0:
			var sx := fill.position.x + fill.size.x * sweep
			for k in 6:
				var w := 3.0 + k * 4.0
				draw_rect(Rect2(Vector2(clampf(sx - w, fill.position.x, fill.end.x), fill.position.y), Vector2(minf(w, sx - fill.position.x), fill.size.y)), Color(1, 1, 1, 0.07 * (1.0 - sweep)))

	func _draw() -> void:
		if s.is_empty():
			return
		var sans := Ui.sans(500)
		var mono := Ui.mono("Medium")
		var pulse := Fx.beat()
		draw_string(Ui.sans(700), Vector2(0, 18), "这个身体能做到", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Ui.INK)
		draw_string(mono, Vector2(0, 18), "READOUT", HORIZONTAL_ALIGNMENT_RIGHT, W, 11, Ui.INK_FAINT)
		# 0. The one thing to do.
		var adv := advice()
		var bad: bool = adv[1]
		var card := Rect2(0, 32, W, 54)
		var box := StyleBoxFlat.new()
		box.bg_color = Color(ALERT_INK, 0.07 + 0.04 * pulse) if bad else Color(Ui.GOOD, 0.08)
		box.border_color = Color(ALERT_INK, 0.35 + 0.3 * pulse) if bad else Color(Ui.GOOD, 0.35)
		box.set_border_width_all(1)
		box.set_corner_radius_all(6)
		draw_style_box(box, card)
		draw_rect(Rect2(card.position + Vector2(0, 6), Vector2(3, card.size.y - 12)), ALERT_INK if bad else Ui.GOOD)
		draw_string(Ui.mono("SemiBold"), card.position + Vector2(16, 20), "怎么改" if bad else "可以投放", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, ALERT_INK if bad else Ui.GOOD)
		# The line types itself in when it changes.
		var line: String = adv[0]
		var n := ceili(line.length() * said_t)
		draw_string(Ui.sans(700), card.position + Vector2(16, 42), line.substr(0, n), HORIZONTAL_ALIGNMENT_LEFT, W - 28.0, 15, Ui.INK)
		var stream: float = bench.stream
		var net: float = float(s.speed) - stream
		var ok := net >= Colony.MIN_NET
		# 1. Thrust against the stream.
		var y := 124.0
		_row(y, "推力 / 水流", "%.0f / %.0f" % [shown.thrust, stream], "µm/s", Ui.GOOD if ok else ALERT_INK, not ok)
		var top := maxf(60.0, maxf(float(s.speed), stream) * 1.25)
		var bar := Rect2(0, y + 16, W, 10)
		_bar(bar, shown.thrust / top, Ui.GOOD if ok else ALERT_INK, not ok)
		draw_rect(Rect2(bar.position + Vector2(stream / top * W, 0), Vector2(Colony.MIN_NET / top * W, bar.size.y)), Color(ALERT_INK, 0.12))
		var sx := stream / top * W
		draw_line(Vector2(sx, y + 11), Vector2(sx, y + 31), Ui.INK, 2.0)
		draw_string(sans, Vector2(sx - 30, y + 44), "水流", HORIZONTAL_ALIGNMENT_CENTER, 60, 11, Ui.INK_SOFT)
		var there := " · 约 %d 秒到上游" % roundi(bench.trip / maxf(net, 0.1)) if not bench.kinds.has(Colony.ARMOR) else " · 顶得住水流"
		var verdict := "净速 %.0f µm/s%s" % [net, there] if ok else ("净速 %.0f µm/s，至少要 %.0f" % [net, Colony.MIN_NET] if net >= -0.5 else "净速 %.0f µm/s：会被冲向喷口" % net)
		draw_string(Ui.sans(600), Vector2(0, y + 62), verdict, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Ui.INK_SOFT)
		_sep(y + 78)
		# 2. Whips.
		y = 236.0
		var walled: int = s.walled
		_row(y, "鞭毛块", "%d" % int(s.rim), "块在划水" if walled == 0 else "块在划水 · %d 块被包住" % walled, Ui.INK if walled == 0 else ALERT_INK, walled > 0)
		var flags := int(s.rim) + walled
		for k in flags:
			var r := Rect2(k * 26.0, y + 14, 22, 8)
			if k < int(s.rim):
				draw_rect(r, SEG[Colony.FLAG].darkened(0.2))
				draw_rect(Rect2(r.position, Vector2(r.size.x, 2)), Color(1, 1, 1, 0.45))
			else:
				draw_rect(r, Color(ALERT_INK, 0.08 + 0.1 * pulse))
				draw_rect(r, Color(ALERT_INK, 0.5 + 0.4 * pulse), false, 1.0)
		_sep(y + 36)
		# 3. How much of a clump it keeps; or (level 22) the armour.
		y = 300.0
		if bench.kinds.has(Colony.ARMOR):
			_armour_row(y)
		else:
			_keep_row(y)
		_sep(y + 54)
		# 4. The young.
		y = 386.0
		var germ: int = s.germ
		_row(y, "每代子体", "%d" % germ, "个", Ui.INK if germ > 1 else ALERT_INK, germ <= 1)
		if germ > 0:
			var eat: float = s.eat_time
			var total: float = eat + bench.gest
			var a: float = W * eat / total
			draw_rect(Rect2(0, y + 14, a - 1.0, 10), Color(Ui.ACCENT, 0.55))
			draw_rect(Rect2(a + 1.0, y + 14, W - a - 1.0, 10), SEG[Colony.GERM].darkened(0.15))
			draw_rect(Rect2(0, y + 14, W, 2), Color(1, 1, 1, 0.4))
			draw_string(sans, Vector2(0, y + 40), "吃饱 %d 秒" % roundi(eat), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Ui.INK_SOFT)
			draw_string(sans, Vector2(0, y + 40), "怀子 %d 秒" % roundi(bench.gest), HORIZONTAL_ALIGNMENT_RIGHT, W, 11, Ui.INK_SOFT)
		else:
			draw_rect(Rect2(0, y + 14, W, 10), Color(Ui.INK, 0.07))
		_sep(y + 54)
		# 5. Grit; or, where the stores matter more (level 22), the stores.
		y = 470.0
		var unsafe: int = s.unsafe
		if bench.kinds.has(Colony.REGEN):
			var heal: float = bench.regrow / bench.regen_x if int(s.regen) > 0 else bench.regrow
			_row(y, "伤口长回", "%d" % roundi(heal), "秒" if unsafe == 0 else "秒 · %d 个生殖块没遮挡" % unsafe, Ui.INK if int(s.regen) > 0 and unsafe == 0 else ALERT_INK, int(s.regen) == 0 or unsafe > 0)
		elif bench.kinds.has(Colony.STORE):
			var st: int = s.store
			_row(y, "储能", "%d" % st, "块" if unsafe == 0 else "块 · %d 个生殖块没遮挡" % unsafe, Ui.INK if st > 0 and unsafe == 0 else ALERT_INK, st == 0 or unsafe > 0)
		else:
			_row(y, "砂砾防护", "全部挡住" if unsafe == 0 else "%d 块没遮挡" % unsafe, "", Ui.GOOD if unsafe == 0 else ALERT_INK, unsafe > 0)

	# Level 21: how much of a clump it keeps, by width.
	func _keep_row(y: float) -> void:
		var sans := Ui.sans(500)
		_row(y, "每团藻吃下", "%d" % roundi(100.0 * shown.keep), "%", Ui.INK)
		for k in 3:
			var r := Rect2(k * (W / 3.0) + 1.0, y + 14, W / 3.0 - 2.0, 10)
			var lit := int(s.width) > k
			draw_rect(r, Color(Ui.ACCENT, 0.85) if lit else Color(Ui.INK, 0.07))
			if lit:
				draw_rect(Rect2(r.position, Vector2(r.size.x, 2)), Color(1, 1, 1, 0.45))
			if k == mini(int(s.width), 3) - 1:
				draw_rect(r.grow(2.0), Ui.INK, false, 1.5)
			draw_string(sans, Vector2(r.position.x, y + 40), "宽 %d 格 %d%%" % [k + 1, roundi(100.0 * minf(1.0, Colony.TUNE.keep + Colony.TUNE.keep_w * k))], HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 11, Ui.INK_SOFT if lit else Ui.INK_FAINT)

	# Level 22: the rim a hunter can bite, armour against open blocks.
	func _armour_row(y: float) -> void:
		var armor: int = s.armor
		var gaps: int = s.gaps
		var walled: int = s.armor_walled
		var rim := armor - walled + gaps
		_row(y, "外缘护甲", "%d / %d" % [armor - walled, rim], "格" if walled == 0 else "格 · %d 块甲被包住" % walled, Ui.INK if walled == 0 and armor > 0 else ALERT_INK, walled > 0 or armor == 0)
		var w := minf(26.0, W / maxf(rim, 1.0))
		for k in rim:
			var r := Rect2(k * w, y + 14, w - 4.0, 10)
			if k < armor - walled:
				draw_rect(r, SEG[Colony.ARMOR].darkened(0.25))
				draw_rect(Rect2(r.position, Vector2(r.size.x, 2)), Color(1, 1, 1, 0.45))
			else:
				draw_rect(r, Color(Ui.INK, 0.12), false, 1.0)
		draw_string(Ui.sans(500), Vector2(0, y + 40), "巨噬者咬离它最近的外缘块，多从后面追来：咬在甲上只掉一点点，别的一口一大块", HORIZONTAL_ALIGNMENT_LEFT, W, 11, Ui.INK_SOFT)

	func _sep(y: float) -> void:
		draw_line(Vector2(0, y), Vector2(W, y), Color(Ui.INK, 0.08), 1.0)


# A strip of water with the vent at the left end and the algae at the right: the
# body tries it, over and over. The vent is heat haze, not a colour: pale,
# shimmering, its temperature read off.
class Tank extends Control:
	var bench: Node
	var body: Body
	var x := 0.0
	var speed := 0.0
	var streaks := PackedVector2Array()
	var trail := PackedVector2Array()
	const W := 400.0
	const H := 230.0
	const HOT := 70.0
	var haze: GradientTexture2D

	func _init() -> void:
		custom_minimum_size = Vector2(W, H)
		clip_contents = true
		var g := Fx.glass(self, Vector2(W, H), 0.0)
		g.set_shader_parameter("caustic", 0.7)
		var gr := Gradient.new()
		gr.set_color(0, Color(0.88, 0.98, 1.0, 0.42))
		gr.set_color(1, Color(0.88, 0.98, 1.0, 0.0))
		haze = GradientTexture2D.new()
		haze.gradient = gr
		haze.width = 64
		haze.height = 4
		body = Body.new()
		body.scale_px = 0.8
		add_child(body)
		for k in 34:
			streaks.append(Vector2(randf() * W, randf() * H))

	func rebuild() -> void:
		var s: Dictionary = Colony.stats(bench.cells)
		speed = s.speed - bench.stream
		body.show_cells(bench.cells, clampf(s.speed / 60.0, 0.1, 1.0))
		x = W * 0.42
		trail.clear()

	func _process(dt: float) -> void:
		if not is_visible_in_tree():
			return
		# (Three times real speed: a slow gain still shows.)
		x += speed * 3.0 * dt
		if x > W + 60.0 or x < HOT * 0.5:
			x = W * 0.42
			trail.clear()
		body.position = Vector2(x, H * 0.5 + sin(Time.get_ticks_msec() * 0.0012) * 6.0)
		trail.append(body.position)
		if trail.size() > 40:
			trail.remove_at(0)
		var flow: float = bench.stream * 3.0
		for k in streaks.size():
			streaks[k].x -= flow * dt * (0.8 + 0.4 * fposmod(k * 0.37, 1.0))
			if streaks[k].x < 0.0:
				streaks[k] = Vector2(W, randf() * H)
		queue_redraw()

	func _draw() -> void:
		var t := Time.get_ticks_msec() * 0.001
		# The vent: haze, and heat rising off it in wavering lines.
		draw_texture_rect(haze, Rect2(0, 0, HOT * 1.9, H), false)
		for k in 7:
			var pts := PackedVector2Array()
			var bx := 6.0 + k * 9.0
			for j in 24:
				var yy := H - j * (H / 23.0)
				pts.append(Vector2(bx + sin(yy * 0.07 + t * 3.0 + k * 1.7) * (3.0 + j * 0.15), yy))
			draw_polyline(pts, Color(0.92, 1.0, 1.0, 0.16 - k * 0.018), 1.2, true)
		for p in streaks:
			var a := 0.14 + 0.16 * clampf((p.x - HOT) / W, 0.0, 1.0)
			draw_line(p, p + Vector2(22, 0), Color(GLOW, a), 1.0)
		# Where it has been.
		if trail.size() > 1:
			var cols := PackedColorArray()
			for k in trail.size():
				cols.append(Color(GLOW, 0.22 * float(k) / trail.size()))
			draw_polyline_colors(trail, cols, 2.0, true)
		var f := Ui.mono("Medium")
		draw_string(Ui.sans(700), Vector2(12, 24), "喷口", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.92, 1.0, 1.0, 0.95))
		draw_string(f, Vector2(12, 40), "%d°C" % (82 + roundi(sin(t * 2.1))), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.92, 1.0, 1.0, 0.6))
		draw_string(Ui.sans(700), Vector2(W - 52, 24), "上游", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(GLOW, 0.85))
		draw_string(f, Vector2(W - 80, 40), "ALGAE ▸", HORIZONTAL_ALIGNMENT_RIGHT, 68, 10, Color(GLOW, 0.5))
		var net: float = speed
		var col := Color(GLOW, 0.8) if net >= Colony.MIN_NET else Color(ALERT, 0.6 + 0.4 * Fx.beat())
		draw_string(f, Vector2(12, H - 12), "NET %+.0f µm/s" % net, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)
		draw_string(f, Vector2(0, H - 12), "×3", HORIZONTAL_ALIGNMENT_RIGHT, W - 12, 10, Color(GLOW, 0.45))
