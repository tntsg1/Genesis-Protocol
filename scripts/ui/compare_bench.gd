extends Control
# Side-by-side control experiment (DECISIONS, after the first playtest): the
# same dish twice, same seed, left your design, right the same design with
# one gene changed. Both run together (pause / 1x / 3x / 8x), the cameras
# move together (wheel zooms, drag pans), each side reports live; at the
# end both population curves are laid over each other and the difference
# is put in one sentence.

signal finished(choice: String, design: Dictionary) # back / retry_variant / rerun

const TICK := 1.0 / 15.0
const DishView := preload("res://scripts/dish_view.gd")
const GENE_NAMES := ["速度", "感知", "外壳", "攻击", "繁殖", "代谢", "神经", "耐温"]

var level: Dictionary
var base_design: Dictionary # {params, genes, used, design}
var gene := 0
var delta := 1.0
var seed := 1
var runs: Array = [] # two LevelEval.prepare() runs
var views: Array = []
var readouts: Array = [] # per side: [population, zone/first, status]
var speed := 3.0
var paused := false
var acc := 0.0
var done := false
var time_label: Label
var speed_pills := {}
var result_panel: GlassPanel
var cam_pos := Vector2(1100, 1100)
var cam_zoom := 0.42
var _drag := false


func setup(l: Dictionary, design: Dictionary, g: int, d: float, run_seed: int) -> void:
	level = l
	base_design = design
	gene = g
	delta = d
	seed = run_seed


# gene -1 = natural mutation on / off (chapter 1 level 4: does mutation help?).
func _variant_genes() -> Array:
	var genes: Array = base_design.genes.duplicate()
	if gene >= 0:
		genes[gene] = clampf(float(genes[gene]) + delta, 1.0, 5.0)
	return genes


func _base_mutates() -> bool:
	return bool(base_design.params.get("mutates", true))


# The question the bench answers: "假如把速度从 Lv 2 升到 Lv 3，会怎样？"
func _question() -> String:
	if gene < 0:
		return "假如把自然变异%s，会怎样？" % ("关掉" if _base_mutates() else "打开")
	return "假如把%s从 Lv %d %s到 Lv %d，会怎样？" % [GENE_NAMES[gene], int(base_design.genes[gene]), "升" if delta > 0 else "降", int(_variant_genes()[gene])]


# What differs, for one side, in words: "繁殖 Lv 3" / "自然变异 开".
func _what(side: int) -> String:
	if gene < 0:
		var on := _base_mutates() != (side == 1)
		return "自然变异 %s" % ("开" if on else "关")
	var g: Array = base_design.genes if side == 0 else _variant_genes()
	return "%s Lv %d" % [GENE_NAMES[gene], int(g[gene])]


func _design_for(genes: Array, side := 0) -> Dictionary:
	var p: Dictionary = base_design.params.duplicate(true)
	if gene < 0 and side == 1:
		p.mutates = not _base_mutates()
	for k in 8:
		p[["speed", "vision", "armor", "attack", "fertility", "efficiency", "neural", "temp_tol"][k]] = genes[k]
	var used := 0.0
	for v in genes:
		used += float(v) - 1.0
	return {params = p, used = used}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.955, 0.972, 0.985)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var designs := [_design_for(base_design.genes), _design_for(_variant_genes(), 1)]
	var top := HBoxContainer.new()
	top.position = Vector2(40, 22)
	top.custom_minimum_size.x = get_viewport_rect().size.x - 80
	top.add_theme_constant_override("separation", 16)
	add_child(top)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 0)
	tv.add_child(Ui.caption("对照实验", "CONTROL EXPERIMENT · %s" % level.id))
	tv.add_child(Ui.label(_question(), 20, Ui.INK, Ui.sans(700)))
	tv.add_child(Ui.label("这是替你多跑的一盘假设，不会改动你的方案：左边照你这次的方案，右边只改这一处，同一个培养皿、其余完全相同。", 13, Ui.INK_SOFT, Ui.sans(500)))
	top.add_child(tv)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	time_label = Ui.label("", 22, Ui.INK, Ui.mono("Medium"))
	time_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(time_label)
	for spec in [["II", 0.0], ["1×", 1.0], ["3×", 3.0], ["8×", 8.0]]:
		var b := Widgets.Pill.new(spec[0], 50)
		var v: float = spec[1]
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.pressed.connect(func() -> void: _set_speed(v))
		top.add_child(b)
		speed_pills[v] = b
	var stop := Widgets.Pill.new("结束对照  Esc", 0, Ui.sans(500))
	stop.custom_minimum_size = Vector2(140, 34)
	stop.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	stop.pressed.connect(_end)
	top.add_child(stop)
	var vs := get_viewport_rect().size
	var w := (vs.x - 40.0 * 2 - 24.0) * 0.5
	var h := vs.y - 120.0 - 40.0
	for side in 2:
		var run := LevelEval.prepare(level, designs[side], seed)
		runs.append(run)
		var box := Control.new()
		box.position = Vector2(40 + side * (w + 24.0), 104)
		box.size = Vector2(w, h)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(box)
		var svc := SubViewportContainer.new()
		svc.stretch = true
		svc.size = box.size
		svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(svc)
		var svp := SubViewport.new()
		svp.size = Vector2i(box.size)
		svp.transparent_bg = false
		svc.add_child(svp)
		var view: Node2D = DishView.new()
		svp.add_child(view)
		view.setup(run.sim)
		views.append(view)
		# The side's card over its dish.
		var card := GlassPanel.new(Vector4(16, 10, 16, 12))
		card.position = Vector2(14, 14)
		box.add_child(card)
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 2)
		card.body.add_child(cv)
		cv.add_child(Ui.label("%s　%s" % ["你的方案" if side == 0 else "假设", _what(side)], 16, Ui.INK if side == 0 else Ui.ACCENT, Ui.sans(700)))
		var pop := Ui.label("", 24, Ui.INK, Ui.mono("Medium"))
		cv.add_child(pop)
		var line2 := Ui.label("", 12, Ui.INK_SOFT, Ui.sans(500))
		cv.add_child(line2)
		var status := Ui.label("", 12, Ui.GOOD, Ui.sans(600))
		cv.add_child(status)
		readouts.append([pop, line2, status])
	_fit_cameras()
	_set_speed(3.0)
	modulate.a = 0.0
	Ui.tween(self).tween_property(self, "modulate:a", 1.0, Ui.T_MID)


func _fit_cameras() -> void:
	for v: Node2D in views:
		v.cam.position = cam_pos
		v.cam.zoom = Vector2(cam_zoom, cam_zoom)


func _set_speed(s: float) -> void:
	paused = s <= 0.0
	if not paused:
		speed = s
	for v in speed_pills:
		speed_pills[v].active = (paused and v == 0.0) or (not paused and v == speed)


func _process(dt: float) -> void:
	if not done and not paused:
		acc += dt * speed
		var steps := 0
		while acc >= TICK and steps < 8:
			for run: Dictionary in runs:
				if run.t < float(level.time_limit) and not run.eval.extinct:
					LevelEval.advance(run, TICK)
			acc -= TICK
			steps += 1
		if steps >= 8:
			acc = 0.0
	for k in 2:
		views[k].render(acc / TICK, dt)
		_update_readout(k)
	var t: float = runs[0].t
	time_label.text = "T+%02d:%02d / %02d:00" % [int(t) / 60, int(t) % 60, int(level.time_limit / 60.0)]
	if not done:
		var all_done := true
		for run: Dictionary in runs:
			if run.t < float(level.time_limit) and not run.eval.extinct:
				all_done = false
		if all_done:
			_finish()


func _update_readout(k: int) -> void:
	var ev: LevelEval = runs[k].eval
	var r: Array = readouts[k]
	r[0].text = "%d 只" % ev.alive
	if level.goal.kind == "zone_count":
		r[1].text = "光照区 %d / %d　·　第一只抵达 %s" % [ev.zone_now, int(level.goal.n), ("%.0f 秒" % ev.first_in) if ev.first_in >= 0.0 else "—"]
	else:
		r[1].text = "目标 第 %d 分钟 ≥ %d 只" % [int(level.time_limit / 60.0), int(level.goal.n)]
	if ev.extinct:
		r[2].text = "灭绝"
		r[2].add_theme_color_override("font_color", Ui.ALERT)
	elif ev.goal_met:
		r[2].text = "目标已达成 ✓"
	else:
		r[2].text = ""


func _finish() -> void:
	done = true
	for run: Dictionary in runs:
		run.eval.finish()
	CampaignSave.add_research(3)
	result_panel = GlassPanel.new(Vector4(28, 22, 28, 22))
	result_panel.anchor_left = 0.5
	result_panel.anchor_right = 0.5
	result_panel.anchor_top = 0.5
	result_panel.anchor_bottom = 0.5
	result_panel.offset_left = -520
	result_panel.offset_right = 520
	result_panel.offset_top = -300
	result_panel.offset_bottom = 300
	add_child(result_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	result_panel.body.add_child(v)
	v.add_child(Ui.caption("对照结果", "RESULT"))
	var verdict := Ui.label(_verdict(), 20, Ui.INK, Ui.sans(700))
	verdict.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	verdict.custom_minimum_size.x = 980
	v.add_child(verdict)
	var chart := TwoCurves.new()
	chart.runs = runs
	chart.level = level
	chart.labels = ["你的方案（%s）" % _what(0), "假设（%s）" % _what(1)]
	chart.custom_minimum_size = Vector2(980, 300)
	v.add_child(chart)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 12)
	v.add_child(foot)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(sp)
	var again := Widgets.Pill.new("换个培养皿再对照一次", 0, Ui.sans(500))
	again.custom_minimum_size = Vector2(200, 40)
	again.pressed.connect(_rerun)
	foot.add_child(again)
	var back := Widgets.Pill.new("返回报告", 0, Ui.sans(500))
	back.custom_minimum_size = Vector2(120, 40)
	back.pressed.connect(func() -> void: _leave("back"))
	foot.add_child(back)
	var use := Widgets.Pill.new("采用右边的方案再试本关", 0, Ui.sans(600))
	use.custom_minimum_size = Vector2(230, 40)
	use.active = true
	use.pressed.connect(func() -> void: _leave("retry_variant"))
	foot.add_child(use)
	result_panel.appear()


# One plain sentence comparing the two runs on what the level asks for.
func _verdict() -> String:
	var a: LevelEval = runs[0].eval
	var b: LevelEval = runs[1].eval
	var name := ("%s自然变异" % ("关掉" if _base_mutates() else "打开")) if gene < 0 else "%s %s" % [GENE_NAMES[gene], "升一级" if delta > 0 else "降一级"]
	var parts := []
	if a.goal_met != b.goal_met:
		parts.append("右边%s目标" % ("达成了" if b.goal_met else "没能达成"))
	if level.goal.kind == "zone_count":
		if a.first_in >= 0.0 and b.first_in >= 0.0:
			var d := b.first_in - a.first_in
			if absf(d) < 1.0:
				parts.append("第一只几乎同时抵达")
			else:
				parts.append("第一只抵达%s %.0f 秒" % ["提前" if d < 0 else "推迟", absf(d)])
		elif a.first_in >= 0.0 or b.first_in >= 0.0:
			parts.append("只有%s抵达了光照区" % ("右边" if b.first_in >= 0.0 else "你的方案"))
	var pa := maxi(a.alive, 1)
	var change := (float(b.alive) - float(a.alive)) / float(pa) * 100.0
	parts.append("结束时右边的种群%s %d%%（%d → %d 只）" % ["多了" if change >= 0 else "少了", absi(roundi(change)), a.alive, b.alive])
	return "%s：%s。" % [name, "，".join(parts)]


func _rerun() -> void:
	_leave("rerun")


func _end() -> void:
	if not done:
		_finish()
		return
	_leave("back")


func _leave(choice: String) -> void:
	var d: Dictionary = base_design.design.duplicate(true)
	d.genes = _variant_genes()
	if gene < 0:
		d.mutates = not _base_mutates()
	finished.emit(choice, d)
	var t := Ui.tween(self)
	t.tween_property(self, "modulate:a", 0.0, Ui.T_MID)
	t.tween_callback(queue_free)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process_unhandled_input(false)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			cam_zoom = clampf(cam_zoom * 1.15, 0.3, 6.0)
			_fit_cameras()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			cam_zoom = clampf(cam_zoom / 1.15, 0.3, 6.0)
			_fit_cameras()
		elif mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			_drag = mb.pressed
	elif event is InputEventMouseMotion and _drag:
		cam_pos -= (event as InputEventMouseMotion).relative / cam_zoom
		cam_pos = cam_pos.clamp(Vector2(0, 0), Vector2(2200, 2200))
		_fit_cameras()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_ESCAPE:
				_end()
			KEY_SPACE:
				_set_speed(0.0 if not paused else speed)
			KEY_1:
				_set_speed(1.0)
			KEY_2:
				_set_speed(3.0)
			KEY_3:
				_set_speed(8.0)
			_:
				return
		get_viewport().set_input_as_handled()


class TwoCurves extends Control:
	var runs: Array
	var level: Dictionary
	var labels: Array

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r := Rect2(Vector2(40, 24), size - Vector2(50, 46))
		draw_rect(r, Color(1, 1, 1, 0.55), true)
		var top := 10.0
		for run: Dictionary in runs:
			for p: Array in run.eval.curve:
				top = maxf(top, float(p[1]))
		var limit: float = level.time_limit
		for k in 5:
			var y := r.end.y - r.size.y * k / 4.0
			draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), Color(Ui.LINE, 0.4), 1.0)
			draw_string(Ui.mono(), Vector2(0, y + 4), "%d" % int(top * k / 4.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Ui.INK_FAINT)
		for m in int(limit / 60.0) + 1:
			var x := r.position.x + r.size.x * m * 60.0 / limit
			draw_string(Ui.mono(), Vector2(x - 8, r.end.y + 16), "%d:00" % m, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Ui.INK_FAINT)
		var cols := [Color(Ui.INK_SOFT, 0.9), Ui.ACCENT]
		for side in 2:
			var pts := PackedVector2Array()
			for p: Array in runs[side].eval.curve:
				pts.append(Vector2(r.position.x + r.size.x * float(p[0]) / limit, r.end.y - r.size.y * float(p[1]) / top))
			if pts.size() > 1:
				draw_polyline(pts, cols[side], 2.4, true)
			draw_rect(Rect2(r.position + Vector2(10 + side * 230, -18), Vector2(14, 4)), cols[side], true)
			draw_string(Ui.sans(600), r.position + Vector2(30 + side * 230, -12), labels[side], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, cols[side])
