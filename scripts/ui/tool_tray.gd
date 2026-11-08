class_name ToolTray
extends GlassPanel
# The intervention tools (2026-10-29: the four dock buttons read as "看不出是
# 干什么的、变灰不知道为什么、放在底栏不合适"). Their own tray at the lower
# right, apart from the view buttons: a header with the biomass points (and
# a bar to the cap), then one card per tool: an icon, the name and its key,
# one line saying what it does or, when it cannot be used, exactly why (not
# open in this level / short by N points / cooling down), the cost, a
# cooldown ring. The card being placed lights up and says how to place it.
# Hover gives the full explanation. Clicking a card picks the tool.

const IV := preload("res://scripts/interventions.gd")
const KINDS := ["nutrient", "membrane", "heat", "current", "phage", "irritant", "iron", "brine", "stir"]
const DESC := {
	nutrient = "点击培养皿中的位置，投放一团营养物质，吸引附近的细胞。",
	membrane = "按住拖出一道膜，45 秒内谁也过不去",
	heat = "点一下放一块 +12°C 热斑，40 秒",
	current = "按住拖出方向，水流把生物送过去",
	phage = "点一下投放一团你设计的病毒",
	irritant = "点它的头部：缩回头冠，嘴里的吐出来",
	iron = "点一下撒铁粉，吸掉那片水里的氧气",
	brine = "点一下撒盐，那片水 60 秒不结冰",
	stir = "点一下搅动泥层，把氧气带下去",
}
const TIP := {
	nutrient = "营养投放\n点击培养皿中的位置，投放一团营养物质，吸引附近的细胞。\n藻团靠营养生长；也可以直接在培养皿上点右键投放。",
	membrane = "隔离膜\n按住左键拖出一道膜（最长 360 µm），45 秒内任何细胞都穿不过去。\n用来护住一片藻场、隔开捕食者，或做对照：一边有、一边没有。",
	heat = "局部升降温\n点击放一块直径 380 µm 的热斑（+12°C）或冷斑（−12°C），持续 40 秒。\n选中后再按一次快捷键切换升温 / 降温。\n偏离最适水温的生物会多耗能，也会游向更舒服的水。",
	current = "洋流引导\n按住从起点拖向终点：拖得越长水流越快（最快 70 µm/s），持续 30 秒。\n用来把生物送到远处的藻场，或把它们冲离危险。",
	phage = "投放病毒\n在点击处放一团你设计的病毒（80 个，半径 90 µm）。\n它只扎绒游丝。外壳结实的能在水里等很久。",
	irritant = "刺激头冠\n在喷口守卫头部附近（170 µm 以内）点一下，放一小团刺激物。\n真实的轮虫被碰到会把头冠缩回去：约 6 秒内它吸不了水、吞不了群体。\n嘴里正嚼着群体时刺激它，它会把群体原样吐出来，白掉一截能量。\n头部 400 µm 内裂了甲的群体趁机脱身，之后 12 秒它都不会再吸。\n20 秒内再刺激，它会慢慢习惯，缩回的时间一次比一次短。点不到头部、头冠已缩着都不扣点数。",
	iron = "撒铁粉
在点击处撒一片铁粉（半径 220 µm），40 秒内把那里的氧气吸掉，变成一块临时的无氧水。
原型是远古海洋里的铁：地球上最早的氧气，先被海水里的铁吸收，沉成了一层层红色的条带状铁矿。",
	stir = "搅动泥层\n在点击处把泥水搅一搅（半径 200 µm），30 秒内上层的氧气被带进深处，硫化氢被冲淡。\n用来让好氧的生命往下探，或把怕氧的对手赶走。原型是沼泽里被风浪、动物翻动的泥。",
	brine = "撒盐\n在点击处撒一片盐（半径 170 µm），60 秒内那里的水不会结冰，长夜里是一块临时避难所。\n原型是海冰里的盐水通道：海水结冰时盐被挤出来，留下不结冰的细小水道，冰下微生物就住在那里。",
}

var host: Node2D
var cards := {}
var points_label: Label
var bar: Control


func _init() -> void:
	super(Vector4(14, 10, 14, 12))


func _ready() -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	body.add_child(v)
	var head := HBoxContainer.new()
	head.add_child(Ui.caption("干预工具", "TOOLS"))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var pl := Ui.label("生物质点", 11, Ui.INK_FAINT, Ui.sans(500))
	pl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(pl)
	points_label = Ui.label("60", 15, Ui.GOOD, Ui.mono("Medium"))
	head.add_child(points_label)
	head.mouse_filter = Control.MOUSE_FILTER_PASS
	head.tooltip_text = "生物质点：用这些工具都要花它。\n你的生物越多，攒得越快（最多存 300 点）。"
	v.add_child(head)
	bar = Control.new()
	bar.custom_minimum_size = Vector2(0, 4)
	bar.draw.connect(_draw_bar)
	v.add_child(bar)
	for k: String in KINDS:
		var c := Card.new(k, self)
		v.add_child(c)
		cards[k] = c


func _process(_delta: float) -> void:
	if host == null:
		return
	points_label.text = "不限" if host.iv.unlimited() else "%d" % int(host.iv.points)
	# (Only where there is a virus to drop.)
	var lv: Dictionary = host.level_runner.level if host.level_runner else {}
	# The sandbox: every tool (DECISIONS 沙盒补全 Q276).
	if host.level_runner == null:
		for k: String in KINDS:
			cards[k].visible = true
		bar.queue_redraw()
		return
	cards.phage.visible = lv.get("interventions", []).has("phage")
	# (Chapter 6's iron dust takes the phage's place and key.)
	cards.iron.visible = lv.get("interventions", []).has("iron")
	cards.stir.visible = lv.get("interventions", []).has("stir")
	# (Chapter 7's salt takes the warm/cold spot's place and key.)
	cards.brine.visible = lv.get("interventions", []).has("brine")
	cards.heat.visible = not cards.brine.visible
	# (Level 24's irritant takes the current's place and key.)
	cards.irritant.visible = lv.get("interventions", []).has("irritant")
	cards.current.visible = not cards.irritant.visible
	bar.queue_redraw()


func _draw_bar() -> void:
	var w := bar.size.x
	var k: float = clampf(host.iv.points / host.iv.MAX_POINTS, 0.0, 1.0) if host else 0.0
	bar.draw_rect(Rect2(0, 1, w, 2), Color(Ui.INK, 0.1))
	bar.draw_rect(Rect2(0, 1, w * k, 2), Color(Ui.GOOD, 0.85))
	# Ticks at each tool's cost: what the points buy right now.
	for kind: String in KINDS:
		var x: float = w * ToolTray.IV.SPECS[kind].cost / host.iv.MAX_POINTS if host else 0.0
		bar.draw_line(Vector2(x, 0), Vector2(x, 4), Color(Ui.INK, 0.35), 1.0)


# One tool: icon, name + key, what it does (or why not), cost, cooldown.
class Card extends Control:
	var kind: String
	var tray: ToolTray
	var _hover := 0.0
	var _ping := 0.0
	var _was_ready := true

	func _init(k: String, t: ToolTray) -> void:
		kind = k
		tray = t
		custom_minimum_size = Vector2(318, 68 if k == "nutrient" else 54)
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		tooltip_text = ToolTray.TIP[k]

	func ping() -> void:
		_ping = 1.0

	func _gui_input(e: InputEvent) -> void:
		var mb := e as InputEventMouseButton
		if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			Audio.sfx("ui_click", -4.0, randf_range(0.97, 1.04))
			tray.host.dock_action(kind)
			accept_event()

	func _process(delta: float) -> void:
		var over := get_global_rect().has_point(GlassPanel.mouse(get_viewport()))
		_hover = move_toward(_hover, 1.0 if over else 0.0, delta / 0.12)
		_ping = maxf(0.0, _ping - delta * 1.6)
		var host: Node2D = tray.host
		if host:
			var ready: bool = host.iv.ready_to_use(kind)
			if ready and not _was_ready:
				_ping = 1.0
			_was_ready = ready
		queue_redraw()

	# What the card's second line says, and in which colour.
	func _state() -> Array:
		var host: Node2D = tray.host
		var iv: Node = host.iv
		var spec: Dictionary = ToolTray.IV.SPECS[kind]
		var key := Keys.name_of(Keys.code(kind if tray.host.level_runner == null else Card.key_of(kind)))
		if host.mode == kind:
			match kind:
				"nutrient": return ["左键点培养皿投放 · Esc 取消", Ui.ACCENT]
				"membrane": return ["按住左键拖出膜 · Esc 取消", Ui.ACCENT]
				"heat": return ["左键放%s斑 · 再按 %s 换成%s" % ["冷" if iv.cold else "热", key, "升温" if iv.cold else "降温"], Ui.ACCENT]
				"current": return ["按住从起点拖向终点 · Esc 取消", Ui.ACCENT]
				"irritant": return ["左键点它的头部 · Esc 取消", Ui.ACCENT]
				"iron": return ["左键点培养皿撒铁粉 · Esc 取消", Ui.ACCENT]
				"stir": return ["左键点泥里搅动 · Esc 取消", Ui.ACCENT]
				"brine": return ["左键点培养皿撒盐 · Esc 取消", Ui.ACCENT]
		if not iv.open_here(kind):
			var lr: Node = iv.host.level_runner
			if lr != null and int(lr.level.index) >= int(spec.opens):
				return ["本关不可用", Ui.INK_FAINT]
			return ["第 %d 关开放" % int(spec.opens), Ui.INK_FAINT]
		if not iv.unlimited():
			if iv.points < spec.cost:
				return ["生物质点不够，还差 %d 点" % ceili(spec.cost - iv.points), Ui.WARN.darkened(0.25)]
			var cd: float = iv.cooldown.get(kind, 0.0)
			if cd > 0.0:
				return ["冷却中，%.1f 秒后可用" % cd, Ui.INK_SOFT]
		var d: String = ToolTray.DESC[kind]
		if kind == "heat" and iv.cold:
			d = "点一下放一块 −12°C 冷斑，40 秒"
		return [d, Ui.INK_SOFT]

	func _draw() -> void:
		var host: Node2D = tray.host
		if host == null:
			return
		var iv: Node = host.iv
		var spec: Dictionary = ToolTray.IV.SPECS[kind]
		var open: bool = iv.open_here(kind)
		var ready: bool = iv.ready_to_use(kind)
		var active: bool = host.mode == kind
		var r := Rect2(Vector2.ZERO, size)
		var dim := 1.0 if ready or active else (0.45 if not open else 0.7)
		# Ground: hover, the tool in hand, a ping when it becomes usable.
		if active:
			draw_rect(r, Color(Ui.ACCENT, 0.12))
			draw_rect(Rect2(0, 0, 3, size.y), Ui.ACCENT)
		elif _hover > 0.0:
			draw_rect(r, Color(Ui.ACCENT, 0.06 * _hover))
		if _ping > 0.0:
			draw_rect(r, Color(Ui.ACCENT, 0.18 * _ping), false, 1.5)
		draw_line(Vector2(0, size.y - 0.5), Vector2(size.x, size.y - 0.5), Color(Ui.INK, 0.08), 1.0)
		# Icon.
		var ic := Vector2(26, size.y * 0.5)
		var ink := Color(Ui.INK if open else Ui.INK_FAINT, dim)
		var acc := Color(Ui.ACCENT if open else Ui.INK_FAINT, dim)
		draw_circle(ic, 19, Color(acc, 0.1 * dim))
		draw_arc(ic, 19, 0, TAU, 40, Color(acc, 0.5 * dim), 1.2, true)
		_icon(ic, ink, acc, iv.cold)
		# Name, key badge, second line.
		var f := Ui.sans(600)
		var name: String = spec.name
		if kind == "heat":
			name = "局部降温" if iv.cold else "局部升温"
		draw_string(f, Vector2(54, 22), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, ink)
		var nw := f.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		var key := Keys.name_of(Keys.code(kind if tray.host.level_runner == null else Card.key_of(kind)))
		var km := Ui.mono("Medium")
		var kw := km.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 10
		var kr := Rect2(54 + nw + 8, 9, kw, 17)
		draw_rect(kr, Color(Ui.INK, 0.05 * dim))
		draw_rect(kr, Color(Ui.INK, 0.35 * dim), false, 1.0)
		draw_string(km, kr.position + Vector2(5, 13), key, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, ink)
		var st := _state()
		if kind == "nutrient" and st[0] == ToolTray.DESC.nutrient:
			draw_multiline_string(Ui.sans(), Vector2(54, 39), st[0], HORIZONTAL_ALIGNMENT_LEFT, size.x - 54 - 52, 11, -1, Color(st[1], maxf(dim, 0.85)))
		else:
			draw_string(Ui.sans(), Vector2(54, 42), st[0], HORIZONTAL_ALIGNMENT_LEFT, size.x - 54 - 52, 11, Color(st[1], maxf(dim, 0.85)))
		# Cost at the right, ringed by the cooldown.
		var cc := Vector2(size.x - 24, size.y * 0.5)
		var short: bool = iv.points < spec.cost and open and not iv.unlimited()
		var cost_col := Color(Ui.WARN.darkened(0.25) if short else ink, dim if not short else 1.0)
		var cs := "免费" if iv.unlimited() else "%d" % int(spec.cost)
		var cw := km.get_string_size(cs, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		draw_string(km, cc + Vector2(-cw * 0.5, 2), cs, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, cost_col)
		if not iv.unlimited():
			draw_string(Ui.sans(), cc + Vector2(-6, 15), "点", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(Ui.INK_FAINT, dim))
		var cd: float = iv.cooldown.get(kind, 0.0)
		draw_arc(cc, 17, 0, TAU, 40, Color(Ui.INK, 0.1 * dim), 1.5, true)
		if cd > 0.0 and open:
			var k := cd / float(spec.cool)
			draw_arc(cc, 17, -PI * 0.5, -PI * 0.5 + TAU * k, 40, Color(Ui.ACCENT, 0.9), 2.0, true)

	# The irritant answers to the current's key.
	static func key_of(k: String) -> String:
		if k == "iron" or k == "stir":
			return "phage"
		if k == "brine":
			return "heat"
		return "current" if k == "irritant" else k

	# A small drawing of what the tool does.
	func _icon(c: Vector2, ink: Color, acc: Color, cold: bool) -> void:
		match kind:
			"brine":
				# Salt grains (small squares).
				for p in [Vector2(-9, -7), Vector2(-2, -10), Vector2(6, -8), Vector2(-6, 0), Vector2(3, -2), Vector2(9, 1), Vector2(-9, 7), Vector2(-1, 6), Vector2(7, 8)]:
					draw_rect(Rect2(c + p - Vector2(1.6, 1.6), Vector2(3.2, 3.2)), Color(0.55, 0.78, 0.95, ink.a))
				draw_arc(c, 13.0, PI * 0.1, PI * 0.9, 12, Color(ink, 0.5), 1.2, true)
			"stir":
				# A swirl through the mud line.
				for i in 3:
					draw_arc(c, 4.0 + i * 4.0, i * 1.7, i * 1.7 + PI * 1.3, 14, Color(ink, 0.85 - i * 0.2), 1.4, true)
				draw_line(c + Vector2(-12, 8), c + Vector2(12, 8), Color(0.55, 0.42, 0.3, ink.a), 1.6)
			"iron":
				# Rust grains settling.
				for p in [Vector2(-9, -8), Vector2(-2, -11), Vector2(6, -9), Vector2(-6, -2), Vector2(2, -4), Vector2(9, -1), Vector2(-10, 5), Vector2(-3, 4), Vector2(5, 6), Vector2(0, 11), Vector2(-7, 11), Vector2(8, 11)]:
					draw_circle(c + p, 1.7, Color(0.72, 0.36, 0.2, ink.a))
				draw_line(c + Vector2(-12, 14), c + Vector2(12, 14), Color(ink, 0.6), 1.3)
			"irritant":
				# A corona drawn in (two closed lobes, cilia folded) and grains.
				for s in [-1.0, 1.0]:
					draw_arc(c + Vector2(s * 4.5, -1), 4.5, PI, TAU, 10, ink, 1.3, true)
					for i in 3:
						var a := PI + (i + 1) * PI / 4.0
						var p := c + Vector2(s * 4.5, -1) + Vector2.from_angle(a) * 4.5
						draw_line(p, p + Vector2.from_angle(a) * 2.0, Color(ink, 0.6), 1.0, true)
				draw_line(c + Vector2(-9, -1), c + Vector2(-6, 9), ink, 1.3, true)
				draw_line(c + Vector2(9, -1), c + Vector2(6, 9), ink, 1.3, true)
				for p in [Vector2(-11, -10), Vector2(-5, -12), Vector2(3, -13), Vector2(10, -9), Vector2(12, -3)]:
					draw_circle(c + p, 1.3, acc)
			"nutrient":
				# A drop, and the grains spreading from it.
				var pts := PackedVector2Array()
				for i in 25:
					var a := PI * 0.5 + TAU * i / 24.0
					var rr := 7.0
					var p := Vector2(cos(a), sin(a)) * rr
					if sin(a) < 0.0:
						p.x *= 1.0 + sin(a) * 0.85
						p.y *= 1.6
					pts.append(c + Vector2(0, 2) + p)
				draw_colored_polygon(pts, Color(acc, 0.35))
				draw_polyline(pts, ink, 1.3, true)
				for p in [Vector2(-11, 7), Vector2(11, 6), Vector2(-8, 11), Vector2(9, 11), Vector2(0, 13)]:
					draw_circle(c + p, 1.3, acc)
			"phage":
				# A head on a short tail, fibres spread.
				var pts := PackedVector2Array()
				for i in 7:
					var a := TAU * i / 6.0 + PI * 0.5
					pts.append(c + Vector2(0, -5) + Vector2(cos(a), sin(a)) * 7.0)
				draw_polyline(pts, ink, 1.3, true)
				draw_line(c + Vector2(0, 2), c + Vector2(0, 11), ink, 1.6)
				draw_line(c + Vector2(0, 11), c + Vector2(-8, 14), acc, 1.2)
				draw_line(c + Vector2(0, 11), c + Vector2(8, 14), acc, 1.2)
			"membrane":
				# A bilayer: two rows of heads with their tails between.
				for row in [-4.0, 4.0]:
					for i in 6:
						var x := -12.5 + i * 5.0
						draw_circle(c + Vector2(x, row), 2.0, acc)
						draw_line(c + Vector2(x, row * 0.75), c + Vector2(x, row * 0.15), Color(ink, 0.6), 1.0)
			"heat":
				# A thermometer; red bulb warm, blue cold.
				var col := Color(0.35, 0.6, 1.0, ink.a) if cold else Color(0.95, 0.45, 0.25, ink.a)
				draw_line(c + Vector2(0, -11), c + Vector2(0, 5), ink, 6.0)
				draw_line(c + Vector2(0, -11), c + Vector2(0, 5), Color(1, 1, 1, ink.a), 3.6)
				draw_line(c + Vector2(0, -2 if cold else -8), c + Vector2(0, 6), col, 2.4)
				draw_circle(c + Vector2(0, 8), 4.6, ink)
				draw_circle(c + Vector2(0, 8), 3.4, col)
				for i in 3:
					draw_line(c + Vector2(4, -8 + i * 4), c + Vector2(7, -8 + i * 4), Color(ink, 0.6), 1.0)
			"current":
				# Three streamlines with an arrowhead.
				for i in 3:
					var y := -6.0 + i * 6.0
					var pts := PackedVector2Array()
					for s in 9:
						var x := -12.0 + s * 3.0
						pts.append(c + Vector2(x, y + sin(s * 0.8 + i) * 1.6))
					draw_polyline(pts, acc if i == 1 else Color(ink, 0.6), 1.4, true)
				draw_line(c + Vector2(12, 0), c + Vector2(7, -4), acc, 1.6, true)
				draw_line(c + Vector2(12, 0), c + Vector2(7, 4), acc, 1.6, true)
