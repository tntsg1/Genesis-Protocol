extends Control
# Ecology report (R). Opens over the dish on frosted glass: population of
# every species since the start (lines draw themselves in), how each one has
# died, and a few plain facts read straight from the record. Facts only:
# explanations ("why") belong to the experiment reports of M4.

signal closed

const CAUSE_COLORS := [Color("f0b85a"), Color("ee8a8f"), Color("bccbd6"), Color("e98a52"), Color("b9c74a")]
const CAUSE_NAMES := ["饥饿", "被捕食", "衰老", "温度", "酸度"]

var host: Node2D
var history: Array
var stats: Dictionary
var chart: Control
var reveal := 0.0
var hover_x := -1.0


func setup(showcase: Node2D, hist: Array) -> void:
	host = showcase
	history = hist.duplicate()
	stats = host.sim.get_stats()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bm := ShaderMaterial.new()
	bm.shader = preload("res://shaders/glass.gdshader")
	bm.set_shader_parameter("tint", Color(0.95, 0.98, 1.0, 0.45))
	bm.set_shader_parameter("blur", 4.0)
	bm.set_shader_parameter("radius", 0.0)
	bm.set_shader_parameter("bracket", 0.0)
	bm.set_shader_parameter("edge", Color(0, 0, 0, 0))
	backdrop.material = bm
	backdrop.resized.connect(func() -> void: bm.set_shader_parameter("size", backdrop.size))
	add_child(backdrop)
	backdrop.modulate.a = 0.0
	Ui.tween(backdrop).tween_property(backdrop, "modulate:a", 1.0, Ui.T_MID)

	var panel := GlassPanel.new(Vector4(28, 20, 28, 24))
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -660
	panel.offset_right = 660
	panel.offset_top = -400
	panel.offset_bottom = 400
	add_child(panel)
	panel.appear(0.05)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	panel.body.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	v.add_child(head)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 0)
	head.add_child(hv)
	hv.add_child(Ui.label("生态报告", 24, Ui.INK, Ui.sans(700)))
	var t := int(stats.time)
	hv.add_child(Ui.label("ECOLOGY REPORT  ·  EUR-01  ·  T+%02d:%02d  ·  %d 个生命  ·  %d 条谱系" % [t / 60, t % 60, stats.count, stats.lineages], 11, Ui.INK_FAINT, Ui.mono("Medium")))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var close_b := Widgets.Pill.new("关闭   R / Esc", 140, Ui.sans(500))
	close_b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close_b.pressed.connect(close)
	head.add_child(close_b)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 28)
	v.add_child(body)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 10)
	body.add_child(left)
	left.add_child(Ui.caption("种群变化", "POPULATION"))
	chart = Control.new()
	chart.custom_minimum_size = Vector2(800, 420)
	chart.mouse_filter = Control.MOUSE_FILTER_PASS
	chart.draw.connect(_draw_chart)
	chart.mouse_exited.connect(func() -> void: hover_x = -1.0)
	chart.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseMotion:
			hover_x = (e as InputEventMouseMotion).position.x)
	left.add_child(chart)
	var legend := HBoxContainer.new()
	legend.add_theme_constant_override("separation", 18)
	left.add_child(legend)
	for i in host.labels.size():
		var item := HBoxContainer.new()
		item.add_theme_constant_override("separation", 6)
		item.add_child(Widgets.Chip.new(host.species_color(i), 10))
		item.add_child(Ui.label(host.labels[i], 12, Ui.INK_SOFT, Ui.sans(500)))
		legend.add_child(item)
	left.add_child(Ui.caption("记录到的事实", "FACTS"))
	for f in _facts():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.add_child(Widgets.Chip.new(Ui.ACCENT, 8))
		row.add_child(Ui.label(f, 13, Ui.INK, Ui.sans(500)))
		left.add_child(row)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 14)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	right.add_child(Ui.caption("物种与死因", "SPECIES & CAUSES OF DEATH"))
	var per: Array = stats.species
	for i in per.size():
		right.add_child(_species_card(i, per[i]))
	var key := HBoxContainer.new()
	key.add_theme_constant_override("separation", 14)
	right.add_child(key)
	for k in CAUSE_NAMES.size():
		var item := HBoxContainer.new()
		item.add_theme_constant_override("separation", 6)
		item.add_child(Widgets.Chip.new(CAUSE_COLORS[k], 10))
		item.add_child(Ui.label(CAUSE_NAMES[k], 11, Ui.INK_SOFT, Ui.sans(500)))
		key.add_child(item)

	var tw := create_tween()
	tw.tween_interval(0.25)
	tw.tween_method(func(x: float) -> void:
		reveal = x
		chart.queue_redraw(), 0.0, 1.0, 1.0).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _peak(i: int) -> Array:
	var best := 0
	var at := 0.0
	for h in history:
		if i < h[1].size() and h[1][i] > best:
			best = h[1][i]
			at = h[0]
	return [best, at]


func _species_card(i: int, st: Dictionary) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	v.add_child(top)
	top.add_child(Widgets.Chip.new(host.species_color(i), 12))
	top.add_child(Ui.label(host.labels[i], 15, Ui.INK, Ui.sans(700)))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	var pk := _peak(i)
	top.add_child(Ui.label("现存 %d  ·  峰值 %d  ·  出生 %d" % [st.alive, pk[0], st.births], 12, Ui.INK_SOFT, Ui.mono()))
	var deaths := [int(st.starved), int(st.eaten), int(st.aged), int(st.get("temp", 0)), int(st.get("acid", 0))]
	var bar := Control.new()
	bar.custom_minimum_size = Vector2(0, 12)
	bar.draw.connect(func() -> void:
		var total: float = float(deaths.reduce(func(a: int, b: int) -> int: return a + b, 0))
		bar.draw_rect(Rect2(Vector2.ZERO, bar.size), Color(Ui.LINE, 0.25))
		if total <= 0.0:
			return
		var x := 0.0
		for k in deaths.size():
			var w: float = bar.size.x * deaths[k] / total * reveal
			bar.draw_rect(Rect2(x, 0, w, bar.size.y), CAUSE_COLORS[k])
			x += w)
	chart.draw.connect(bar.queue_redraw)
	v.add_child(bar)
	var total: int = deaths.reduce(func(a: int, b: int) -> int: return a + b, 0)
	var parts := []
	for k in deaths.size():
		if total > 0:
			parts.append("%s %d%%" % [CAUSE_NAMES[k], roundi(100.0 * deaths[k] / total)])
	v.add_child(Ui.label("死亡 %d　%s" % [total, "　".join(parts)] if total > 0 else "尚无死亡", 11, Ui.INK_FAINT, Ui.sans()))
	return v


func _facts() -> Array:
	var out := []
	var per: Array = stats.species
	for i in per.size():
		var st: Dictionary = per[i]
		var pk := _peak(i)
		var deaths := [int(st.starved), int(st.eaten), int(st.aged), int(st.get("temp", 0)), int(st.get("acid", 0))]
		var total: int = deaths.reduce(func(a: int, b: int) -> int: return a + b, 0)
		if pk[0] > 0 and st.alive < pk[0] * 0.5:
			out.append("%s 从峰值 %d（%s）降到现在的 %d。" % [host.labels[i], pk[0], _clock(pk[1]), st.alive])
		if total >= 20:
			var k := deaths.find(deaths.max())
			out.append("%s 最主要的死因是%s，占 %d%%。" % [host.labels[i], CAUSE_NAMES[k], roundi(100.0 * deaths[k] / total)])
		# Where its energy went: the water's share, when it is large.
		var burn: float = maxf(float(st.get("burn_total", 0.0)), 1e-6)
		var heat_share: float = float(st.get("burn_temp", 0.0)) / burn
		var acid_share: float = float(st.get("burn_acid", 0.0)) / burn
		if heat_share > 0.15:
			out.append("%s 有 %d%% 的能量耗在不合适的水温上。" % [host.labels[i], roundi(heat_share * 100.0)])
		if acid_share > 0.15:
			out.append("%s 有 %d%% 的能量被酸蚀掉。" % [host.labels[i], roundi(acid_share * 100.0)])
		if st.alive == 0 and pk[0] > 0:
			out.append("%s 已经灭绝。" % host.labels[i])
	if out.is_empty():
		out.append("各物种目前都保持在峰值的一半以上，生态平稳。")
	return out.slice(0, 5)


func _clock(t: float) -> String:
	return "%02d:%02d" % [int(t) / 60, int(t) % 60]


func _draw_chart() -> void:
	var s := chart.size
	var pad_l := 44.0
	var pad_b := 26.0
	var area := Rect2(pad_l, 6, s.x - pad_l - 8, s.y - pad_b - 6)
	var n := history.size()
	var top := 10
	for h in history:
		for c in h[1]:
			top = maxi(top, c)
	top = int(ceil(top / 100.0) * 100.0) if top > 100 else int(ceil(top / 10.0) * 10.0)
	var mono := Ui.mono()
	# Grid and axes.
	for k in 5:
		var y := area.end.y - area.size.y * k / 4.0
		chart.draw_line(Vector2(area.position.x, y), Vector2(area.end.x, y), Color(Ui.LINE, 0.35 if k > 0 else 0.8), 1.0)
		chart.draw_string(mono, Vector2(0, y + 4), str(top * k / 4), HORIZONTAL_ALIGNMENT_RIGHT, pad_l - 8, 10, Ui.INK_FAINT)
	if n < 2:
		chart.draw_string(Ui.sans(), area.get_center() - Vector2(60, 0), "数据记录中……", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Ui.INK_FAINT)
		return
	var t0: float = history[0][0]
	var t1: float = maxf(history[n - 1][0], t0 + 1.0)
	for k in 6:
		var tt := lerpf(t0, t1, k / 5.0)
		var x := area.position.x + area.size.x * k / 5.0
		chart.draw_line(Vector2(x, area.end.y), Vector2(x, area.end.y + 4), Ui.LINE_STRONG, 1.0)
		chart.draw_string(mono, Vector2(x - 16, s.y - 6), _clock(tt), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Ui.INK_FAINT)
	# One line per species, drawn in left to right by `reveal`.
	var shown := maxi(2, int(n * reveal))
	for i in host.labels.size():
		var col: Color = host.species_color(i)
		var pts := PackedVector2Array()
		for k in shown:
			var h: Array = history[k]
			if i >= h[1].size():
				continue
			var x: float = area.position.x + area.size.x * (h[0] - t0) / (t1 - t0)
			var y: float = area.end.y - area.size.y * clampf(float(h[1][i]) / top, 0.0, 1.0)
			pts.append(Vector2(x, y))
		if pts.size() < 2:
			continue
		var fill := pts.duplicate()
		fill.append(Vector2(pts[pts.size() - 1].x, area.end.y))
		fill.append(Vector2(pts[0].x, area.end.y))
		chart.draw_colored_polygon(fill, Color(col, 0.08))
		chart.draw_polyline(pts, col, 2.0, true)
		chart.draw_circle(pts[pts.size() - 1], 3.5, col)
	# Hover: a cursor line with every species' value at that moment.
	if hover_x >= area.position.x and hover_x <= area.end.x and reveal >= 1.0:
		var tt := lerpf(t0, t1, (hover_x - area.position.x) / area.size.x)
		var best := 0
		for k in n:
			if absf(history[k][0] - tt) < absf(history[best][0] - tt):
				best = k
		var h: Array = history[best]
		chart.draw_line(Vector2(hover_x, area.position.y), Vector2(hover_x, area.end.y), Color(Ui.ACCENT, 0.7), 1.0)
		var bx := hover_x + 12.0 if hover_x < area.end.x - 170 else hover_x - 170.0
		var by := area.position.y + 8.0
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(1, 1, 1, 0.92)
		sb.border_color = Ui.LINE_STRONG
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(6)
		var rows: int = h[1].size()
		chart.draw_style_box(sb, Rect2(bx, by, 158, 26 + rows * 18))
		chart.draw_string(mono, Vector2(bx + 10, by + 18), "T+" + _clock(h[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Ui.INK_SOFT)
		for i in rows:
			var y := by + 36 + i * 18
			chart.draw_circle(Vector2(bx + 14, y - 4), 4, host.species_color(i))
			chart.draw_string(Ui.sans(500), Vector2(bx + 24, y), host.labels[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Ui.INK)
			chart.draw_string(mono, Vector2(bx + 100, y), str(h[1][i]), HORIZONTAL_ALIGNMENT_RIGHT, 48, 12, Ui.INK)


func close() -> void:
	var t := Ui.tween(self)
	t.tween_property(self, "modulate:a", 0.0, Ui.T_MID)
	t.tween_callback(func() -> void:
		closed.emit()
		queue_free())


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).keycode
		if k == KEY_ESCAPE or k == KEY_R:
			close()
			get_viewport().set_input_as_handled()
