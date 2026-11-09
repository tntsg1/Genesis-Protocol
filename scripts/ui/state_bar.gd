extends Control
# The state map over the deck (DECISIONS 第十一轮 Q15): the four states as
# circles in a row. Solid: in use (its cards exist; forage always) — click to
# edit its cards, × to remove it. Dashed +: open here, not in use — click to
# add it (up to the neural gene's limit). Grey: opens in a later level.
# An arrow runs from a state to every state one of its cards switches to.

var ed: Control # the deck editor
var level_id := ""
var max_states := 1
var toast: Callable
var hits := {} # "st0".."st3", "x1".."x3" -> Rect2
var _hover := -1

const GAP := 150.0
const R := 20.0


func _init() -> void:
	custom_minimum_size = Vector2(0, 112)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _center(st: int) -> Vector2:
	# Four across the bar's width, under the caption row.
	var gap := minf(GAP, (size.x - 90.0) / 4.0)
	return Vector2(44.0 + st * gap, 58.0)


func _process(_delta: float) -> void:
	var h := -1
	var m := get_local_mouse_position()
	for st in 5:
		if _center(st).distance_to(m) < R + 6.0:
			h = st
	if h != _hover:
		_hover = h
		queue_redraw()


func _gui_input(e: InputEvent) -> void:
	if not (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT):
		return
	accept_event()
	for st in [1, 2, 3, 4]:
		if hits.has("x%d" % st) and hits["x%d" % st].has_point(e.position):
			ed.remove_state(st)
			toast.call("已删除「%s」状态及其规则。按 Ctrl+Z 撤销。" % Rules.STATES[st][0])
			return
	for st in Rules.STATES.size(): # (all five: the spore state is the fifth, chapter 7)
		if not _shown(st) or _center(st).distance_to(e.position) >= R + 6.0:
			continue
		var used: Array = ed.states_used()
		if used.has(st):
			ed.set_state(st)
		elif not Rules.state_open(st, level_id):
			toast.call("「%s」状态将在第 %s 关解锁。" % [Rules.STATES[st][0], Rules.STATES[st][3]])
		elif used.size() >= max_states:
			toast.call("最多只能设置 %d 个状态。提高神经等级可以增加上限。" % max_states)
		else:
			ed.add_state(st)
			toast.call({Rules.S_SLEEP: "已添加「休眠」状态。默认规则：休眠 20 秒后返回觅食。", Rules.S_ALERT: "已添加「警戒」状态。默认规则：猎手靠近 → 逃离，警戒 20 秒后返回觅食。", Rules.S_BREED: "已添加「繁殖期」状态。默认规则：逃离、分裂、游向藻团，40 秒后返回觅食。", Rules.S_SPORE: "已添加「芽孢」状态。默认规则：天黑了 → 进入芽孢，天亮了 → 进入觅食（会先发芽约 8 秒）。"}.get(st, "已添加「%s」状态。" % Rules.STATES[st][0]))
		queue_redraw()
		return


# A state whose level isn't in the game yet stays off the map (a "2-4 关"
# placeholder read as missing content, review round 4).
func _shown(st: int) -> bool:
	if Rules.state_open(st, level_id):
		return true
	var at: String = Rules.STATES[st][3]
	return Levels.ALL.any(func(l: Dictionary) -> bool: return l.id == at)


func _draw() -> void:
	hits.clear()
	var used: Array = ed.states_used()
	var f := Ui.sans(600)
	# Arrows: from each state to where its cards switch.
	var links := {}
	for cd: Dictionary in ed.deck:
		var to := Rules.target_state(cd.act)
		var from := int(cd.get("st", 0))
		if to >= 0 and to != from:
			links["%d>%d" % [from, to]] = [from, to]
	for key: String in links:
		var a: Vector2 = _center(links[key][0])
		var b: Vector2 = _center(links[key][1])
		var up := -1.0 if links[key][0] < links[key][1] else 1.0 # there above, back below
		var mid := (a + b) * 0.5 + Vector2(0, up * (16.0 + absf(b.x - a.x) * 0.08))
		var pts := PackedVector2Array()
		for k in 17:
			var t := k / 16.0
			pts.append(a.lerp(mid, t).lerp(mid.lerp(b, t), t))
		# Trim to the circles' edges.
		var line := PackedVector2Array()
		for p in pts:
			if p.distance_to(a) > R + 2.0 and p.distance_to(b) > R + 4.0:
				line.append(p)
		if line.size() >= 2:
			draw_polyline(line, Color(Ui.ACCENT, 0.75), 1.5, true)
			var tip := line[line.size() - 1]
			var dir := (tip - line[line.size() - 2]).normalized()
			var side := dir.orthogonal()
			draw_colored_polygon(PackedVector2Array([tip + dir * 6.0, tip - dir * 3.0 + side * 4.5, tip - dir * 3.0 - side * 4.5]), Color(Ui.ACCENT, 0.9))
	for st in 5:
		if not _shown(st):
			continue
		var c := _center(st)
		var name: String = Rules.STATES[st][0]
		var open := Rules.state_open(st, level_id)
		var on := used.has(st)
		var cur: bool = ed.cur_state == st
		var col := Ui.ACCENT if open else Ui.INK_FAINT
		var hov := 1.0 if _hover == st else 0.0
		if on:
			draw_circle(c, R + 3.0 * hov, Color(col, 0.9 if cur else 0.18 + 0.1 * hov))
			draw_arc(c, R + 3.0 * hov, 0, TAU, 32, col, 1.5, true)
			var n: int = ed.deck.filter(func(cd: Dictionary) -> bool: return int(cd.get("st", 0)) == st).size()
			var ns := str(n)
			var nw := Ui.mono("SemiBold").get_string_size(ns, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
			draw_string(Ui.mono("SemiBold"), c + Vector2(-nw * 0.5, 5), ns, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE if cur else col)
			if st != Rules.S_FORAGE:
				var xr := Rect2(c + Vector2(R - 2, -R - 6), Vector2(14, 14))
				hits["x%d" % st] = xr
				var xc := xr.get_center()
				var a := 0.35 + 0.65 * hov
				draw_line(xc - Vector2(3.5, 3.5), xc + Vector2(3.5, 3.5), Color(Ui.ALERT, a), 1.3, true)
				draw_line(xc + Vector2(-3.5, 3.5), xc + Vector2(3.5, -3.5), Color(Ui.ALERT, a), 1.3, true)
		else:
			# Dashed: can be added (or grey: later).
			for k in 16:
				var a0 := TAU * k / 16.0
				draw_arc(c, R, a0, a0 + TAU / 16.0 * 0.55, 4, Color(col, 0.4 + 0.4 * hov), 1.2, true)
			if open:
				draw_string(f, c + Vector2(-5, 6), "+", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(col, 0.6 + 0.4 * hov))
		var nw2 := f.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		draw_string(f, c + Vector2(-nw2 * 0.5, R + 20.0), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Ui.INK if on else (Ui.INK_SOFT if open else Ui.INK_FAINT))
		if on:
			# The number in the circle, said once under it (review: "数字是编号？").
			var n2: int = ed.deck.filter(func(cd: Dictionary) -> bool: return int(cd.get("st", 0)) == st).size()
			var ct := "%d 张卡" % n2
			var cw := f.get_string_size(ct, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
			draw_string(f, c + Vector2(-cw * 0.5, R + 34.0), ct, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Ui.INK_FAINT)
		if not open:
			var tag := "%s 关" % Rules.STATES[st][3]
			var tw := Ui.mono().get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
			draw_string(Ui.mono(), c + Vector2(-tw * 0.5, R + 34.0), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Ui.INK_FAINT)
	# The caption row above the circles: how many states, which one is open.
	var cap := "状态 %d / %d" % [used.size(), max_states]
	draw_string(Ui.mono("Medium"), Vector2(4, 14), cap, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Ui.ACCENT)
	var cs := "当前显示「%s」状态的规则。点击圆圈切换状态，点击虚线圆圈添加新状态。" % Rules.STATES[ed.cur_state][0]
	draw_string(Ui.sans(500), Vector2(84, 14), cs, HORIZONTAL_ALIGNMENT_LEFT, size.x - 90.0, 12, Ui.INK_SOFT)
