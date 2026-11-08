extends Control
# Ecosystem HUD (DECISIONS: Q11 three tiers). Reads the live simulation from
# the showcase and adapts to the camera:
#   macro  (whole dish)   species, environment and a large dish map
#   group  (a region)     the standard layout
#   micro  (one organism) a life-scan panel, reticle and organ callouts;
#                         the other panels step back so the cell stays clear
# Every panel enters with the glass scan sweep; numbers roll; nothing blinks.


const TIER_MACRO := 0
const TIER_GROUP := 1
const TIER_MICRO := 2
const GENE_NAMES := ["速度", "感知", "外壳", "攻击", "繁殖", "代谢", "神经", "耐温"]
const ACTIONS := ["四处游荡", "游向藻团", "正在进食", "追捕猎物", "正在捕食", "紧急逃离", "寻找空壳", "吃饱休息", "刚刚分裂", "跟随同伴", "释放信号", "游向舒适水温", "顺着气味游", "远离同伴", "聚合体的一员", "躲避或寻找氧气", "回到记忆点", "芽孢 · 休眠中"]

var host: Node2D # the showcase scene
var tier := TIER_GROUP

var time_label: Label
var gen_label: Label
var speed_pills: Array = []
var species_rows: Array = [] # [count Readout-like label, sparkline, sub label]
var env: Dictionary = {}
var minimap: Control
var minimap_view: Control
var map_points: Array = [] # per species PackedVector2Array
var events_box: VBoxContainer
var event_log: Array = []
var scan_panel: GlassPanel
var scan := {}
var panels := {}
var sample_timer := 0.0
var last_stats := {}
var peak := []
var seen_lineages := 0
var reticle_spin := 0.0
var lineage_cooldown := 0.0
var legend: GlassPanel # population heat map key (view filter)
var legend_rows: VBoxContainer
var tier_gauge: Widgets.TierGauge
var species_box: VBoxContainer
var clear_species_focus: Button
var dock_buttons := {}
var tools: ToolTray
var dock_names := {}
const Interventions_SPECS := preload("res://scripts/interventions.gd").SPECS
var hint_panel: GlassPanel
var hint_label: Label
var observe_hint: Label
# Population history for the report: [time, [alive per species]] every 0.5 s,
# thinned by half whenever it grows past 720 samples.
var history: Array = []
var revealed := false
var _rehearse_id := -1 # a cell drawn by the prewarm (_prewarm), not the selection
var visor: Visor
var last_points := -1.0
var was_ready := {}


func setup(showcase: Node2D) -> void:
	host = showcase
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_brand()
	_build_time()
	_build_objective()
	_build_species()
	_build_environment()
	_build_scan()
	_build_events()
	_build_dock()
	_build_tools()
	_build_legend()
	_build_hint()
	_build_coach()
	_build_terrain()
	if GlassPanel.holo:
		visor = Visor.new()
		visor.host = host
		add_child(visor)
	revealed = false
	_prewarm()


# Draw every panel once, almost transparent, during the first frames: the
# glass shader pipeline compiles and the glyphs get rasterised now, not in
# the middle of the fly-in (that cost a 23 ms frame).
func _prewarm() -> void:
	visible = true
	modulate.a = 0.003
	scan_panel.visible = true
	legend.modulate.a = 1.0
	for i in 4:
		await get_tree().process_frame
	# Then the micro tier once for real, still almost transparent (behind the
	# menu): the life scan filled in for a real cell and running its appear
	# (trace, haze, motes, type-in), the side panels dimmed. The first pick
	# of a cell in play cost a 40-60 ms frame without it.
	var id: int = host.sim.find_agent(host.DISH_CENTER, 3000.0) if not revealed else -1
	if id >= 0:
		_update_scan(id)
		scan_panel.appear(0.0, true)
		_rehearse_id = id # its callouts too (_draw)
		for key in ["species", "events", "objective"]:
			panels[key].modulate.a = 0.35
		for i in 40:
			if revealed:
				break
			queue_redraw()
			await get_tree().process_frame
		_rehearse_id = -1
		queue_redraw()
		for key in ["species", "events", "objective"]:
			panels[key].modulate.a = 1.0
	if not revealed:
		visible = false
	modulate.a = 1.0
	scan_panel.visible = false
	legend.modulate.a = 0.0


# Panels sweep in one after another (game start / back from the menu).
func reveal() -> void:
	visible = true
	modulate.a = 1.0
	revealed = true
	tier = TIER_GROUP
	var brand: Control = panels["brand"]
	brand.modulate.a = 0.0
	Ui.tween(brand).tween_property(brand, "modulate:a", 1.0, Ui.T_SLOW)
	var delay := 0.0
	if visor:
		# The visor calibrates; each panel materialises as the sweep passes it.
		visor.boot()
		var h := get_viewport_rect().size.y
		for key in ["time", "species", "objective", "environment", "events", "tools", "dock"]:
			var c: Control = panels[key]
			panels[key].appear(Visor.BOOT * clampf((c.global_position.y + 10.0) / h, 0.0, 1.0))
	else:
		for key in ["time", "species", "objective", "environment", "events", "tools", "dock"]:
			panels[key].appear(delay)
			delay += 0.07
	scan_panel.visible = false
	legend.modulate.a = 0.0


func conceal() -> void:
	revealed = false
	var t := Ui.tween(self)
	t.tween_property(self, "modulate:a", 0.0, Ui.T_MID)
	t.tween_callback(func() -> void:
		visible = false
		modulate.a = 1.0)


# --- layout ------------------------------------------------------------------

func _place(p: Control, anchor: Vector2, offset: Vector2, w: float) -> void:
	p.anchor_left = anchor.x
	p.anchor_right = anchor.x
	p.anchor_top = anchor.y
	p.anchor_bottom = anchor.y
	p.custom_minimum_size.x = w
	p.grow_horizontal = Control.GROW_DIRECTION_BEGIN if anchor.x > 0.9 else (Control.GROW_DIRECTION_BOTH if anchor.x > 0.4 else Control.GROW_DIRECTION_END)
	p.grow_vertical = Control.GROW_DIRECTION_BEGIN if anchor.y > 0.9 else Control.GROW_DIRECTION_END
	p.offset_left = offset.x
	p.offset_top = offset.y
	p.offset_right = offset.x
	p.offset_bottom = offset.y


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


func _build_brand() -> void:
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 2)
	add_child(v)
	_place(v, Vector2(0, 0), Vector2(28, 22), 300)
	var t := Ui.label("GENESIS  PROTOCOL", 13, Ui.INK, Ui.mono("SemiBold"))
	v.add_child(t)
	brand_name = Ui.label("创生协议　·　木卫二冰下海洋样本", 13, Ui.INK_SOFT, Ui.sans(500))
	v.add_child(brand_name)
	brand_code = Ui.label("EUROPA STATION  /  EUR-01  /  DISH Ø 2120 µm", 10, Ui.INK_FAINT, Ui.mono())
	v.add_child(brand_code)
	panels["brand"] = v


func _build_time() -> void:
	var p := GlassPanel.new(Vector4(18, 10, 12, 10))
	add_child(p)
	_place(p, Vector2(0.5, 0), Vector2(0, 18), 0)
	var h := _hbox(p.body, 18)
	var v := _vbox(h, 0)
	time_label = Ui.label("T+00:00", 24, Ui.INK, Ui.mono("Medium"))
	v.add_child(time_label)
	gen_label = Ui.label("模拟时间　·　GEN 1", Ui.SIZE_CAPTION, Ui.INK_FAINT, Ui.sans(500))
	v.add_child(gen_label)
	var sep := ColorRect.new()
	sep.color = Ui.LINE
	sep.custom_minimum_size = Vector2(1, 36)
	sep.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(sep)
	var pills := _hbox(h, 6)
	pills.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for spec in [["II", 0.0], ["1×", 1.0], ["3×", 3.0], ["8×", 8.0]]:
		var b := Widgets.Pill.new(spec[0], 46)
		var s: float = spec[1]
		b.pressed.connect(func() -> void: host.set_speed(s))
		pills.add_child(b)
		speed_pills.append([b, s])
	var sep2 := ColorRect.new()
	sep2.color = Ui.LINE
	sep2.custom_minimum_size = Vector2(1, 36)
	sep2.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(sep2)
	tier_gauge = Widgets.TierGauge.new()
	tier_gauge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(tier_gauge)
	panels["time"] = p


func _build_objective() -> void:
	var p := GlassPanel.new()
	add_child(p)
	_place(p, Vector2(1, 0), Vector2(-24, 18), 320)
	var v := _vbox(p.body, 6)
	var cap := Ui.caption("当前实验目标", "OBJECTIVE · SAMPLE")
	v.add_child(cap)
	var title := Ui.label("让银尘与琥珀在捕食压力下共存 3 分钟", Ui.SIZE_BODY, Ui.INK, Ui.sans(500))
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.custom_minimum_size.x = 288
	v.add_child(title)
	env["objective_title"] = title
	env["objective_caption"] = cap
	var m := Widgets.Meter.new(Ui.ACCENT, 4)
	v.add_child(m)
	# (A gap the long counts can't eat into: "560剩余" ran together at level 10.)
	var row := _hbox(v, 14)
	var pct := Ui.label("0%", 12, Ui.ACCENT, Ui.mono("Medium"))
	row.add_child(pct)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var left := Ui.label("剩余 03:00", 12, Ui.INK_SOFT, Ui.mono())
	row.add_child(left)
	env["objective"] = [m, pct, left]
	panels["objective"] = p


func _build_species() -> void:
	var p := GlassPanel.new()
	add_child(p)
	_place(p, Vector2(0, 0), Vector2(24, 104), 300)
	var v := _vbox(p.body, 10)
	var heading := _hbox(v, 8)
	heading.add_child(Ui.caption("物种", "SPECIES"))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(spacer)
	clear_species_focus = Button.new()
	clear_species_focus.text = "显示全部"
	clear_species_focus.tooltip_text = "取消物种高亮，恢复所有生物的显示"
	clear_species_focus.visible = false
	clear_species_focus.pressed.connect(func() -> void: pinned_row = -1)
	heading.add_child(clear_species_focus)
	species_box = v
	for i in host.labels.size():
		_add_row(i)
	panels["species"] = p


# Dock labels show the current key of each action (rebindable in settings).
func refresh_key_labels() -> void:
	var ids := {observe = "observe", analysis = "analysis", filter = "filter", track = "track", report = "report", designer = "designer"}
	for k: String in dock_buttons:
		if not ids.has(k):
			continue
		var b: Widgets.Pill = dock_buttons[k]
		var name: String = dock_names[k] if k != "filter" else b.text.get_slice("  ", 0)
		b.text = "%s  %s" % [name, Keys.name_of(Keys.code(ids[k]))]
		b.custom_minimum_size.x = b.label_font.get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 34
		b.queue_redraw()


# Campaign level: the objective panel carries the level's goal (LevelRunner
# keeps it current through set_objective), the brand line names the level.
var level_mode := false


# In the campaign the environment readouts come in as levels start to use
# them (review round 5: six unexplained numbers from level 1 on).
const ENV_FROM := {algae = 1, nutrient = 2, lineages = 4, flow = 5, shells = 6, biomass = 6}
const DOCK_FROM := {track = 2, report = 3, observe = 3, analysis = 3, filter = 3}


func set_level(l: Dictionary) -> void:
	level_mode = not l.is_empty()
	for k: String in ENV_FROM:
		if env.has(k):
			(env[k] as Control).visible = not level_mode or int(l.index) >= int(ENV_FROM[k])
	# The dock too: follow from 1-2 (taught there), the rest from 1-3.
	for k: String in DOCK_FROM:
		if dock_buttons.has(k):
			(dock_buttons[k] as Control).visible = not level_mode or int(l.index) >= int(DOCK_FROM[k])
	if dock_buttons.has("world"):
		(dock_buttons["world"] as Control).visible = not level_mode
	if terrain and level_mode:
		terrain.close()
	var cap: HBoxContainer = env["objective_caption"]
	(cap.get_child(1) as Label).text = ("OBJECTIVE · %s" % l.id) if level_mode else "OBJECTIVE · SAMPLE"
	if level_mode:
		set_objective(l.goal.text, 0.0, "等待投放", "限时 %02d:00" % int(l.time_limit / 60.0))
	else:
		(env["objective_title"] as Label).text = "让银尘与琥珀在捕食压力下共存 3 分钟"


func set_objective(title: String, ratio: float, now: String, right: String) -> void:
	(env["objective_title"] as Label).text = title
	var obj: Array = env["objective"]
	obj[0].set_ratio(ratio)
	obj[1].text = now
	obj[2].text = right


# One of the player's cells was just eaten: the objective line blinks crimson
# (the count it shows has just gone up).
func flash_objective() -> void:
	var l: Label = env.get("objective", [null, null])[1]
	if l == null:
		return
	if not l.has_meta("ink"):
		l.set_meta("ink", l.get_theme_color("font_color"))
	var ink: Color = l.get_meta("ink")
	var tw := Ui.tween(l)
	tw.tween_method(func(c: Color) -> void: l.add_theme_color_override("font_color", c), DishMarks.DANGER, ink, 0.7)


# A different world was loaded in place (a campaign level, back to the
# sandbox): the species panel, history and records start over.
var brand_name: Label
var brand_code: Label


func rebuild_world() -> void:
	# Chapter 6: the first planet, not Europa.
	if brand_name:
		# (Chapters 7 and 8: planets two and three.)
		var lr: Node = host.get("level_runner")
		var ch := int(str(lr.level.get("id", "0")).get_slice("-", 0)) if lr and lr.get("level") else 0
		var planets := {6: ["星球一 · 热泉海床", "PLANET ONE  /  P1-00"], 7: ["星球二 · 冰封海", "PLANET TWO  /  P2-00"], 8: ["星球三 · 酸性沼泽", "PLANET THREE  /  P3-00"]}
		var pl: Array = planets.get(ch, planets[6] if host.o2_world else ["木卫二冰下海洋样本", "EUROPA STATION  /  EUR-01"])
		if lr == null:
			# The sandbox: the start it was built from (DECISIONS 地形编辑器).
			var tk: String = host.sandbox_world.map.get("template", "europa") if host.get("sandbox_world") else "europa"
			pl = ["木卫二冰下海洋样本", "EUROPA STATION  /  EUR-01"]
			for tt: Array in SandboxWorld.TEMPLATES:
				if tt[0] == tk and tk != "europa":
					pl = ["沙盒 · " + str(tt[1]), "SANDBOX  /  SBX"]
		brand_name.text = "创生协议　·　" + str(pl[0])
		brand_code.text = str(pl[1]) + "  /  DISH Ø 2120 µm"
	for c in species_box.get_children():
		if c != species_box.get_child(0): # keep the caption
			species_box.remove_child(c)
			c.queue_free()
	species_rows.clear()
	pinned_row = -1
	peak.clear()
	history.clear()
	# A new experiment starts with an empty log.
	for c in events_box.get_children():
		events_box.remove_child(c)
		c.queue_free()
	last_stats = {}
	seen_lineages = 0
	map_points.clear()
	for i in host.labels.size():
		_add_row(i)
	sample_timer = 0.0


# A newly released species joins the panel with a short highlight.
func add_species_row(i: int) -> void:
	# A released species brings its own founding lineages: recount quietly
	# instead of logging them as mutations.
	seen_lineages = 0
	var row := _add_row(i)
	row.modulate = Color(1, 1, 1, 0)
	var t := Ui.tween(row)
	t.tween_property(row, "modulate", Color(1, 1, 1, 1), Ui.T_SLOW)


func _add_row(i: int) -> VBoxContainer:
	var v := species_box
	if true:
		var col: Color = host.species_color(i)
		var row := _vbox(v, 2)
		var top := _hbox(row, 8)
		top.add_child(Widgets.Chip.new(col, 12))
		top.add_child(Ui.label(host.labels[i], Ui.SIZE_BODY, Ui.INK, Ui.sans(600)))
		var spacer := Control.new()
		spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(spacer)
		var count := Widgets.Readout.new("", 17)
		top.add_child(count)
		var bottom := _hbox(row, 10)
		var spark := Widgets.Sparkline.new(col, 150, 22)
		bottom.add_child(spark)
		var sub := Ui.label("", 11, Ui.INK_FAINT, Ui.mono())
		sub.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bottom.add_child(sub)
		# Near it, the row folds out what is behind the number (share, trend,
		# how they die) and the dish picks the species out; click flies there.
		var fold := Control.new()
		fold.clip_contents = true
		fold.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fold.custom_minimum_size.y = 0.0
		row.add_child(fold)
		var detail := VBoxContainer.new()
		detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
		detail.add_theme_constant_override("separation", 3)
		detail.position = Vector2(0, 4)
		fold.add_child(detail)
		var info := Ui.label("", 11, Ui.INK_SOFT, Ui.mono("Medium"))
		detail.add_child(info)
		var deaths := DeathBar.new()
		detail.add_child(deaths)
		var hint := Ui.label("点击高亮并定位　·　再点取消", 11, Ui.ACCENT, Ui.sans(500))
		detail.add_child(hint)
		fold.resized.connect(func() -> void: detail.size.x = fold.size.x)
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		row.gui_input.connect(func(e: InputEvent) -> void:
			var mb := e as InputEventMouseButton
			if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				# Click pins the highlight (click again to let go): picking your
				# own out of a crowded dish shouldn't need the hand kept still.
				pinned_row = -1 if pinned_row == i else i
				var c := _centroid(i)
				if c.is_finite() and pinned_row == i:
					host.look_at_point(c)
				Audio.sfx("ui_click", -8.0)
				row.accept_event())
		row.set_meta("hl", 0.0)
		row.set_meta("col", col)
		row.draw.connect(_draw_row_light.bind(row))
		species_rows.append([count, spark, sub, row, fold, info, deaths])
		peak.append(1)
		return row
	return null


func _build_environment() -> void:
	var p := GlassPanel.new()
	add_child(p)
	_place(p, Vector2(1, 0), Vector2(-24, 172), 320)
	var v := _vbox(p.body, 10)
	v.add_child(Ui.caption("环境", "ENVIRONMENT"))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 8)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(grid)
	var tips := {algae = "皿里还剩多少团藻：吃藻的生物的口粮", nutrient = "溶在水里的营养：藻团靠它长", shells = "死去的生物留下的空壳：食腐的生物吃它",
		flow = "水流有多急：洋流会把生物冲走", biomass = "所有生物加起来有多重", lineages = "还活着的血统（谱系）数：突变出的新品种越多，这个数越大"}
	for spec in [["algae", "藻团", "%d", ""], ["nutrient", "溶解营养", "k", ""], ["shells", "空壳", "%d", ""],
			["flow", "水流", "%.1f", "×"], ["biomass", "生物量", "k", ""], ["lineages", "谱系", "%d", ""]]:
		var r := Widgets.Readout.new(spec[1], 16, spec[2], spec[3])
		r.mouse_filter = Control.MOUSE_FILTER_PASS
		r.tooltip_text = tips[spec[0]]
		r.flashes = spec[0] == "lineages" # the others drift all the time
		r.judged = false
		grid.add_child(r)
		env[spec[0]] = r
	minimap = Control.new()
	minimap.custom_minimum_size = Vector2(288, 200)
	# Click or drag on the map to move the camera there.
	minimap.mouse_filter = Control.MOUSE_FILTER_STOP
	minimap.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	minimap.tooltip_text = "点击或拖动：镜头跳到这里"
	minimap.gui_input.connect(func(e: InputEvent) -> void:
		var held: bool = (e is InputEventMouseButton and e.pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT) 			or (e is InputEventMouseMotion and ((e as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT) != 0)
		if held:
			host.jump_to(_map_to_world(e.position))
			minimap.accept_event())
	minimap.draw.connect(_draw_minimap)
	minimap.resized.connect(minimap.queue_redraw)
	v.add_child(minimap)
	# The camera's window moves every frame; the dots only when sampled, so
	# they live on the minimap itself and the window on a layer above it.
	minimap_view = Control.new()
	minimap_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	minimap_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	minimap_view.draw.connect(_draw_minimap_view)
	minimap.add_child(minimap_view)
	panels["environment"] = p


func _build_scan() -> void:
	scan_panel = GlassPanel.new()
	add_child(scan_panel)
	_place(scan_panel, Vector2(1, 0), Vector2(-24, 172), 380)
	scan_panel.modulate.a = 0.0
	scan_panel.visible = false
	var v := _vbox(scan_panel.body, 8)
	v.add_child(Ui.caption("生命扫描", "LIFE SCAN"))
	var head := _hbox(v, 8)
	scan["chip"] = Widgets.Chip.new(Ui.ACCENT, 14)
	head.add_child(scan["chip"])
	scan["name"] = Ui.label("", Ui.SIZE_TITLE + 2, Ui.INK, Ui.sans(700))
	head.add_child(scan["name"])
	scan["id"] = Ui.label("", 12, Ui.INK_FAINT, Ui.mono())
	scan["id"].size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(scan["id"])
	scan["lineage"] = Ui.label("", 11, Ui.INK_SOFT, Ui.mono())
	v.add_child(scan["lineage"])
	scan["doing"] = Ui.label("", Ui.SIZE_BODY, Ui.ACCENT, Ui.sans(600))
	v.add_child(scan["doing"])
	for key in ["energy", "age"]:
		var row := _hbox(v, 8)
		row.add_child(Ui.label("能量" if key == "energy" else "寿命", 11, Ui.INK_SOFT, Ui.sans(500)))
		var m := Widgets.Meter.new(Ui.GOOD if key == "energy" else Color("8f9fe0"), 4)
		m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		m.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(m)
		var val := Ui.label("", 11, Ui.INK, Ui.mono())
		val.custom_minimum_size.x = 74
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(val)
		scan[key] = [m, val]
	# Its water: which zone, how warm against what it likes, how acid, and
	# how well it suits it (its own running cost against the water's drain).
	scan["water"] = Ui.label("", 11, Ui.INK_SOFT, Ui.sans(500))
	scan["water"].autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	scan["water"].custom_minimum_size.x = 340
	v.add_child(scan["water"])
	var frow := _hbox(v, 8)
	frow.add_child(Ui.label("适应", 11, Ui.INK_SOFT, Ui.sans(500)))
	var fm := Widgets.Meter.new(Ui.ACCENT, 4)
	fm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	frow.add_child(fm)
	var fv := Ui.label("", 11, Ui.INK, Ui.mono())
	fv.custom_minimum_size.x = 74
	fv.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	frow.add_child(fv)
	scan["fit"] = [fm, fv]
	var sep := ColorRect.new()
	sep.color = Ui.LINE
	sep.custom_minimum_size = Vector2(0, 1)
	v.add_child(sep)
	v.add_child(Ui.caption("基因读数", "GENOME"))
	scan["chromo"] = ChromoStrip.new()
	v.add_child(scan["chromo"])
	scan["genes"] = []
	for k in GENE_NAMES.size():
		var row := _hbox(v, 8)
		var n := Ui.label(GENE_NAMES[k], 11, Ui.INK_SOFT, Ui.sans(500))
		n.custom_minimum_size.x = 30
		row.add_child(n)
		var m := Widgets.Meter.new(GenomeArt.GENE_COLORS[k], 3)
		m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		m.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(m)
		var val := Ui.label("", 11, Ui.INK, Ui.mono())
		val.custom_minimum_size.x = 76
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(val)
		scan["genes"].append([m, val])
	# What mutated, spelled out: which chromosome and gene (or rule card),
	# the ancestor's value and this one's.
	scan["mut_head"] = Ui.label("突变（和本物种的祖先相比）", 11, Color(0.8, 0.5, 0.05), Ui.sans(600))
	v.add_child(scan["mut_head"])
	scan["mut"] = Ui.label("", 11, Ui.INK, Ui.sans(500))
	scan["mut"].autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	scan["mut"].custom_minimum_size.x = 340
	v.add_child(scan["mut"])
	var sep2 := ColorRect.new()
	sep2.color = Ui.LINE
	sep2.custom_minimum_size = Vector2(0, 1)
	v.add_child(sep2)
	v.add_child(Ui.caption("行为规则", "WHY THIS ACTION"))
	# Pause, then step one tick at a time to watch the deck decide.
	var srow := _hbox(v, 8)
	var pause_b := Widgets.Pill.new("暂停", 64, Ui.sans(600))
	pause_b.pressed.connect(func() -> void: host.paused = not host.paused)
	srow.add_child(pause_b)
	var step_b := Widgets.Pill.new("单步 ▸", 72, Ui.sans(600))
	step_b.pressed.connect(func() -> void:
		host.paused = true
		host.step_once())
	srow.add_child(step_b)
	scan["tick"] = Ui.label("", 11, Ui.INK_SOFT, Ui.mono("Medium"))
	scan["tick"].size_flags_vertical = Control.SIZE_SHRINK_CENTER
	srow.add_child(scan["tick"])
	scan["pause"] = pause_b
	scan["step"] = step_b
	scan["deck"] = DeckTrace.new()
	v.add_child(scan["deck"])
	scan["hint"] = Ui.label("F 跟随　Esc 关闭", 10, Ui.INK_FAINT, Ui.sans())
	v.add_child(scan["hint"])


const LOG_TEXT_W := 330.0 # the log's text column: longer lines wrap


func _build_events() -> void:
	var p := GlassPanel.new()
	add_child(p)
	_place(p, Vector2(0, 1), Vector2(24, -24), 500)
	var v := _vbox(p.body, 8)
	v.add_child(Ui.caption("事件", "EVENT LOG"))
	events_box = _vbox(v, 6)
	events_box.custom_minimum_size.y = 96
	panels["events"] = p


# Diagnostic teaching (DECISIONS 诊断式教学, Q271): a small card at the
# left, between the species and the log, when the run shows a typical problem: what
# is happening and what answers it. It does not pause; after a few seconds it
# folds to one line ("提示 · N"), which opens the run's hints again.
var coach_panel: GlassPanel
var coach_box: VBoxContainer
var coach_fold: Widgets.Pill
var coach_list: Array = [] # [{title, text}] this run, newest last
var coach_open_t := 0.0
const COACH_SHOW := 10.0


func _build_coach() -> void:
	coach_panel = GlassPanel.new(Vector4(16, 10, 16, 12))
	add_child(coach_panel)
	_place(coach_panel, Vector2(0, 0.5), Vector2(24, -70), 320)
	var v := _vbox(coach_panel.body, 6)
	var head := _hbox(v, 8)
	head.add_child(Ui.caption("实验诊断", "DIAGNOSIS"))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	coach_fold = Widgets.Pill.new("", 0, Ui.sans(600))
	coach_fold.custom_minimum_size = Vector2(76, 26)
	coach_fold.pressed.connect(func() -> void: _coach_toggle())
	head.add_child(coach_fold)
	coach_box = _vbox(v, 8)
	coach_panel.visible = false


# The sandbox's terrain editor (DECISIONS 地形编辑器): scripts/ui/terrain_editor.gd.
var terrain: TerrainEditor


func _build_terrain() -> void:
	terrain = TerrainEditor.new()
	add_child(terrain)
	terrain.setup(host)


func coach_clear() -> void:
	coach_list.clear()
	if coach_panel:
		coach_panel.visible = false


func coach_say(title: String, text: String) -> void:
	coach_list.append({title = title, text = text})
	coach_open_t = COACH_SHOW
	_coach_fill(true)
	if not coach_panel.visible:
		coach_panel.visible = true
		coach_panel.appear(0.0)
	else:
		coach_panel.flash()
	Audio.sfx("nutrient", -10.0, 1.6)


# Open: the newest in full (or all of them, newest first, when reopened by
# hand); folded: just the head line.
func _coach_fill(newest_only: bool, open := true) -> void:
	for c in coach_box.get_children():
		c.queue_free()
	coach_fold.text = ("收起 ▴" if open else "提示 · %d ▾" % coach_list.size())
	coach_box.visible = open
	if not open:
		return
	var shown: Array = [coach_list.back()] if newest_only else coach_list.duplicate()
	if not newest_only:
		shown.reverse()
	for h: Dictionary in shown:
		var t := Ui.label(h.title, 14, Ui.ACCENT, Ui.sans(700))
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		t.custom_minimum_size.x = 288
		coach_box.add_child(t)
		var b := Ui.label(h.text, 12, Ui.INK, Ui.sans(500))
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size.x = 288
		coach_box.add_child(b)


func _coach_toggle() -> void:
	var open := not coach_box.visible
	coach_open_t = 0.0 # (by hand: it stays as the player left it)
	_coach_fill(false, open)


func coach_tick(delta: float) -> void:
	if coach_open_t > 0.0:
		coach_open_t -= delta
		if coach_open_t <= 0.0 and coach_box.visible:
			_coach_fill(false, false)


# A mode hint under the clock ("click to place ..."), and the quiet note
# shown in observe mode.
func _build_hint() -> void:
	hint_panel = GlassPanel.new(Vector4(18, 8, 18, 8))
	add_child(hint_panel)
	_place(hint_panel, Vector2(0.5, 0), Vector2(0, 100), 0)
	hint_label = Ui.label("", 13, Ui.INK, Ui.sans(600))
	hint_panel.body.add_child(hint_label)
	hint_panel.modulate.a = 0.0
	hint_panel.visible = false
	observe_hint = Ui.label("观察模式　·　V 恢复界面", 12, Color(Ui.INK_SOFT, 0.7), Ui.sans(500))
	add_child(observe_hint)
	_place(observe_hint, Vector2(0.5, 1), Vector2(0, -28), 0)
	observe_hint.visible = false


func show_hint(text: String) -> void:
	hint_label.text = text
	hint_panel.visible = true
	hint_panel.appear()


func hide_hint() -> void:
	if hint_panel.visible:
		hint_panel.disappear()
		get_tree().create_timer(Ui.T_FAST).timeout.connect(func() -> void:
			if hint_panel.modulate.a < 0.05:
				hint_panel.visible = false)


# A rebindable action ran from the keyboard: light its button.
func ping_action(action: String) -> void:
	# (Level 24's irritant answers to the current's key.)
	if action == "current" and dock_buttons.has("irritant") and (dock_buttons["irritant"] as Control).visible:
		action = "irritant"
	# (Chapter 6's iron dust answers to the phage's key.)
	if action == "phage" and dock_buttons.has("iron") and (dock_buttons["iron"] as Control).visible:
		action = "iron"
	if action == "phage" and dock_buttons.has("stir") and (dock_buttons["stir"] as Control).visible:
		action = "stir"
	if action == "heat" and dock_buttons.has("brine") and (dock_buttons["brine"] as Control).visible:
		action = "brine"
	if dock_buttons.has(action):
		dock_buttons[action].ping()
	var speeds := {pause = 0.0}
	if speeds.has(action):
		for pair in speed_pills:
			if pair[1] == speeds[action]:
				pair[0].ping()


# Something important: a film-title line over the dish with a leader to the
# place (holographic visor), and an entry in the log.
func banner(title: String, sub: String, color: Color, pos := Vector2.INF) -> void:
	if visor:
		visor.banner(title, sub, color, pos)


func notify(text: String, color: Color, pos := Vector2.INF) -> void:
	_event(text, color, pos)


# Analysis mode legend: what the rings and line colours mean, and which
# environment map lies under them.
var analysis_legend: GlassPanel
var env_buttons: Array = []
var env_hint: Label


func set_env_layer(k: int) -> void:
	if analysis_legend == null:
		set_analysis(true)
	for j in env_buttons.size():
		env_buttons[j].active = j == k
	env_hint.text = ["", "冰蓝 = 冷　橙 = 热　每条线 5°C", "黄绿越深越酸　每条线 0.2", "品红 = 信号 A　青 = 信号 B", "紫灰 = 无氧　青 = 有氧　白线 = 8%（厌氧生命开始中毒）"][k]


func set_analysis(on: bool) -> void:
	if analysis_legend == null:
		analysis_legend = GlassPanel.new(Vector4(18, 10, 18, 12))
		add_child(analysis_legend)
		_place(analysis_legend, Vector2(0.5, 1), Vector2(0, -88), 0)
		var v := _vbox(analysis_legend.body, 6)
		var top := _hbox(v, 10)
		top.add_child(Ui.caption("分析模式", "ANALYSIS"))
		top.add_child(Ui.label("虚线圆 = 视野　实线圆 = 身体　线 = 当前目标", 12, Ui.INK_SOFT, Ui.sans(500)))
		var keys := _hbox(v, 16)
		var AL := preload("res://scripts/analysis_layer.gd")
		for k in [1, 3, 5, 6, 8, 9, 11]:
			var item := _hbox(keys, 6)
			var line := ColorRect.new()
			line.color = AL.ACTION_COLORS[k]
			line.custom_minimum_size = Vector2(18, 2)
			line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			item.add_child(line)
			item.add_child(Ui.label(AL.ACTION_NAMES[k], 12, Ui.INK, Ui.sans(500)))
		# The environment map under the diagram (T cycles it).
		var layers := _hbox(v, 8)
		layers.add_child(Ui.label("环境图层  T", 12, Ui.INK_SOFT, Ui.sans(600)))
		for spec in [[0, "无"], [1, "温度"], [2, "酸度"], [3, "信号"], [4, "氧气"]]:
			var b := Widgets.Pill.new(spec[1], 56, Ui.sans(500))
			var key: int = spec[0]
			b.pressed.connect(func() -> void: host.set_env_layer(key))
			b.active = key == 0
			layers.add_child(b)
			env_buttons.append(b)
		env_hint = Ui.label("", 11, Ui.INK_FAINT, Ui.sans())
		layers.add_child(env_hint)
		analysis_legend.visible = false
	if on:
		# (The oxygen map only where there is oxygen: chapter 6.)
		if env_buttons.size() > 4:
			env_buttons[4].visible = host.o2_world
		analysis_legend.visible = true
		analysis_legend.appear()
	else:
		analysis_legend.disappear()


# Observe mode: every panel steps out of the way; V brings them back.
func set_observe(on: bool) -> void:
	for key in panels:
		var c: Control = panels[key]
		Ui.tween(c).tween_property(c, "modulate:a", 0.0 if on else 1.0, Ui.T_MID)
	if tier == TIER_MICRO:
		Ui.tween(scan_panel).tween_property(scan_panel, "modulate:a", 0.0 if on else 1.0, Ui.T_MID)
	if host.view_mode == 2:
		Ui.tween(legend).tween_property(legend, "modulate:a", 0.0 if on else 1.0, Ui.T_MID)
	observe_hint.visible = on
	if on:
		observe_hint.modulate.a = 0.0
		var t := Ui.tween(observe_hint)
		t.tween_interval(0.4)
		t.tween_property(observe_hint, "modulate:a", 1.0, Ui.T_SLOW)


# Population heat filter: which colour is which species, how crowding reads.
func _build_legend() -> void:
	legend = GlassPanel.new()
	add_child(legend)
	_place(legend, Vector2(1, 1), Vector2(-24, -340), 300) # above the tool tray
	legend.modulate.a = 0.0
	var v := _vbox(legend.body, 8)
	v.add_child(Ui.caption("种群热力图", "POPULATION MAP"))
	legend_rows = _vbox(v, 4)
	var bar := Control.new()
	bar.custom_minimum_size = Vector2(0, 10)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.draw.connect(func() -> void:
		var n := 48
		for k in n:
			var t := float(k) / (n - 1)
			var c := Color(0.955, 0.97, 0.978).lerp(Color(0.35, 0.6, 0.7), t)
			bar.draw_rect(Rect2(bar.size.x * k / n, 0, bar.size.x / n + 1.0, bar.size.y), c)
		for k in 5:
			var x := bar.size.x * (k + 1) / 6.0
			bar.draw_line(Vector2(x, 0), Vector2(x, bar.size.y), Color(1, 1, 1, 0.8), 1.0))
	v.add_child(bar)
	var row := _hbox(v, 0)
	row.add_child(Ui.label("稀疏", 11, Ui.INK_SOFT, Ui.sans(500)))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(sp)
	row.add_child(Ui.label("拥挤", 11, Ui.INK_SOFT, Ui.sans(500)))
	v.add_child(Ui.label("颜色是占多数的物种　·　等高线是拥挤程度　·　C 切换视图", 10, Ui.INK_FAINT, Ui.sans()))


func _fill_legend() -> void:
	for c in legend_rows.get_children():
		c.queue_free()
	for i in host.labels.size():
		var r := _hbox(legend_rows, 8)
		r.add_child(Widgets.Chip.new(host.species_color(i), 10))
		r.add_child(Ui.label(host.labels[i], 12, Ui.INK, Ui.sans(500)))


# View filter: the dock button names the current view; the population view
# brings up its key.
func set_view_mode(m: int) -> void:
	if dock_buttons.has("filter"):
		var b: Widgets.Pill = dock_buttons["filter"]
		b.text = "视图：%s  %s" % [["普通", "物种", "热力"][m], Keys.name_of(Keys.code("filter"))]
		b.active = m > 0
		b.queue_redraw()
	if m == 2:
		_fill_legend()
		if revealed:
			legend.appear()
	elif legend.modulate.a > 0.0:
		legend.disappear()


const DOCK_TIPS := {
	observe = "观察模式：收起界面，只看培养皿",
	analysis = "分析模式：每只生物画出视野圈，和它此刻追向哪里的连线",
	filter = "换视图：普通 / 按物种上色 / 数量热力图",
	track = "跟随选中的生物：镜头跟住它，并弹出它的扫描卡",
	report = "生态报告：这一盘到目前为止发生了什么",
	designer = "打开生命设计器（再按一次回到培养皿）",
}


func _build_dock() -> void:
	var p := GlassPanel.new(Vector4(10, 8, 10, 8))
	add_child(p)
	_place(p, Vector2(0.5, 1), Vector2(0, -24), 0)
	var h := _hbox(p.body, 6)
	# Views only: the hands-on tools have their own tray (_build_tools).
	var specs := [["observe", "观察", "V"], ["analysis", "分析", "X"], ["filter", "视图：普通", "C"], ["|"],
		["track", "跟随", "F"], ["report", "报告", "R"], ["designer", "生命设计器", "Tab"], ["world", "地形编辑", "G"]]
	for spec: Array in specs:
		if spec[0] == "|":
			var sep := ColorRect.new()
			sep.color = Ui.LINE
			sep.custom_minimum_size = Vector2(1, 22)
			sep.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			h.add_child(sep)
			continue
		var b := Widgets.Pill.new("%s  %s" % [spec[1], spec[2]], 0, Ui.sans(500))
		b.custom_minimum_size.x = b.label_font.get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 34
		var key: String = spec[0]
		b.pressed.connect(func() -> void: host.dock_action(key))
		b.tooltip_text = DOCK_TIPS.get(key, "")
		h.add_child(b)
		dock_buttons[key] = b
		dock_names[key] = spec[1]
	refresh_key_labels()
	panels["dock"] = p


# The intervention tools at the lower right (scripts/ui/tool_tray.gd). Their
# cards answer to dock_buttons too (the guide rings them, keys ping them).
func _build_tools() -> void:
	tools = ToolTray.new()
	tools.host = host
	add_child(tools)
	_place(tools, Vector2(1, 1), Vector2(-24, -24), 346)
	panels["tools"] = tools
	for k: String in ToolTray.KINDS:
		dock_buttons[k] = tools.cards[k]


# --- live update -------------------------------------------------------------

func _process(delta: float) -> void:
	if host == null:
		return
	var st: Dictionary = host.sim.get_stats()
	var t := int(st.time)
	time_label.text = "T+%02d:%02d" % [t / 60, t % 60]
	# Paused: the clock breathes.
	time_label.modulate.a = 0.6 + 0.4 * cos(Time.get_ticks_msec() / 320.0) if host.paused else 1.0
	# Panels light their frame under the cursor.
	var mouse := GlassPanel.mouse(get_viewport())
	for key: String in panels:
		var gp := panels[key] as GlassPanel
		if gp:
			gp.set_highlight(gp.visible and gp.modulate.a > 0.5 and gp.get_global_rect().has_point(mouse))
	_link_species(delta, mouse)
	_link_events(mouse)
	for pair in speed_pills:
		pair[0].active = (host.paused and pair[1] == 0.0) or (not host.paused and is_equal_approx(host.speed, pair[1]))
	sample_timer -= delta
	if sample_timer <= 0.0:
		sample_timer = 0.5
		_sample(st)
	_update_tier()
	var z: float = host.cam.zoom.x
	tier_gauge.set_state(0 if z < 0.75 else (1 if z < 2.6 else 2), z)
	if dock_buttons.size() > 0:
		dock_buttons["observe"].active = host.observing
		dock_buttons["analysis"].active = host.analyzing
		# Spending flashes the points red (the tool tray's counter).
		var pts: float = host.iv.points
		if last_points >= 0.0 and pts < last_points - 4.0:
			var pl: Label = tools.points_label
			pl.add_theme_color_override("font_color", Ui.ALERT)
			var tw := Ui.tween(pl)
			tw.tween_interval(0.25)
			tw.tween_method(func(k: float) -> void: pl.add_theme_color_override("font_color", Ui.ALERT.lerp(Ui.GOOD, k)), 0.0, 1.0, 0.8)
		last_points = pts
		dock_buttons["track"].active = host.following
		dock_buttons["report"].active = host.report != null
		dock_buttons["designer"].active = host.designer != null
	if tier == TIER_MICRO:
		_update_scan()
	reticle_spin += delta
	queue_redraw()
	minimap_view.queue_redraw()


# Is `p` (screen) over a panel that is showing? The panels are frameless and
# let clicks through, but over one the hand belongs to the interface: the
# dish pointer steps aside and the OS arrow comes back (its reticle draws
# under the panels, where it would vanish).
func covers(p: Vector2) -> bool:
	if not visible or modulate.a < 0.3:
		return false
	var all: Array = panels.values()
	all.append_array([scan_panel, legend, hint_panel, analysis_legend])
	for c in all:
		var gp := c as Control
		if gp and gp.is_visible_in_tree() and gp.modulate.a > 0.3 and gp.get_global_rect().grow(6.0).has_point(p):
			return true
	return false


# --- linkage between the HUD and the dish (fifth round) -----------------------

var hover_row := -1
const FOLD_H := 66.0


# The species row under the cursor folds out and picks its species out in
# the dish; a cell under the pointer lights its species' row.
var pinned_row := -1 # a species row clicked: its bodies stay lit in the dish


func _link_species(delta: float, mouse: Vector2) -> void:
	var sp_panel := panels["species"] as GlassPanel
	var live: bool = sp_panel.visible and sp_panel.modulate.a > 0.5 and revealed and not host.observing
	var over := -1
	# Over the dish there is no row under the hand, whatever came before.
	if host.pointer and host.pointer.shown:
		live = false
	if live:
		for i in species_rows.size():
			var row: Control = species_rows[i][3]
			if row.get_global_rect().grow_individual(14, 4, 14, 4).has_point(mouse):
				over = i
				break
	if pinned_row >= species_rows.size():
		pinned_row = -1
	# Hover previews the row details only: cancelling must restore the dish
	# immediately even while the pointer is still over the row.
	host.focus_species = pinned_row
	clear_species_focus.visible = pinned_row >= 0
	if over != hover_row:
		hover_row = over
		if over >= 0:
			Audio.sfx("holo_tick", -15.0, 1.0 + 0.04 * over)
			_fill_detail(over)
			Holo.type_in(species_rows[over][4])
	var linked := -1
	if host.pointer and host.pointer.hover_id >= 0 and host.pointer.hover_t > 0.5:
		linked = int(host.pointer.hover_info.get("species", -1))
	for i in species_rows.size():
		var r: Array = species_rows[i]
		var row: Control = r[3]
		var fold: Control = r[4]
		var want_h := FOLD_H if i == hover_row else 0.0
		if absf(fold.custom_minimum_size.y - want_h) > 0.2:
			fold.custom_minimum_size.y = lerpf(fold.custom_minimum_size.y, want_h, 1.0 - exp(-delta * 16.0))
		elif fold.custom_minimum_size.y != want_h:
			fold.custom_minimum_size.y = want_h
		var hl: float = row.get_meta("hl")
		var want := 1.0 if i == hover_row or i == pinned_row else (0.7 if i == linked else 0.0)
		if absf(hl - want) > 0.004:
			row.set_meta("hl", lerpf(hl, want, 1.0 - exp(-delta * 12.0)))
			row.queue_redraw()


func _fill_detail(i: int) -> void:
	var r: Array = species_rows[i]
	if last_stats.is_empty() or i >= last_stats.species.size():
		(r[5] as Label).text = "等待采样…"
		return
	var per: Array = last_stats.species
	var total := 0
	for s in per:
		total += int(s.alive)
	var a: int = per[i].alive
	var trend := ""
	if history.size() > 61:
		var before: Array = history[history.size() - 61][1]
		if i < before.size() and int(before[i]) > 0:
			var d := (float(a) - float(before[i])) / float(before[i]) * 100.0
			trend = "　30s %s%d%%" % ["▲" if d >= 0.0 else "▼", absi(roundi(d))]
	(r[5] as Label).text = "占比 %d%%　峰值 %d%s" % [roundi(100.0 * a / maxf(total, 1.0)), peak[i], trend]
	(r[6] as DeathBar).set_counts(int(per[i].starved), int(per[i].eaten), int(per[i].aged))


func _draw_row_light(row: Control) -> void:
	var hl: float = row.get_meta("hl")
	if hl <= 0.004:
		return
	var col: Color = row.get_meta("col")
	var rect := Rect2(Vector2(-12, -4), row.size + Vector2(20, 8))
	# A wash of the species' colour fading to the right, and a bar at the
	# left edge that grows from the middle.
	var n := 12
	for k in n:
		var x0 := rect.position.x + rect.size.x * k / n
		row.draw_rect(Rect2(x0, rect.position.y, rect.size.x / n + 0.5, rect.size.y), Color(col, 0.13 * hl * (1.0 - float(k) / n)))
	var bh := rect.size.y * hl
	row.draw_rect(Rect2(rect.position.x, rect.position.y + (rect.size.y - bh) * 0.5, 2.5, bh), Color(col.darkened(0.15), hl))


# A log row under the cursor draws a leader line to where it happened.
func _link_events(mouse: Vector2) -> void:
	if visor == null:
		return
	var link := {}
	if (panels["events"] as GlassPanel).visible and revealed:
		for c in events_box.get_children():
			var row := c as EventRow
			if row and row.pos.is_finite() and row.get_global_rect().has_point(mouse):
				var gr := row.get_global_rect()
				link = {from = Vector2(gr.end.x + 10.0, gr.get_center().y), world = row.pos, color = row.tint}
				break
	visor.set_link(link)


func _sample(st: Dictionary) -> void:
	var per: Array = st.species
	var counts := []
	for sp_st in per:
		counts.append(sp_st.alive)
	history.append([st.time, counts])
	if history.size() > 720:
		var thin := []
		for k in range(0, history.size(), 2):
			thin.append(history[k])
		history = thin
	var max_gen := 1
	for i in per.size():
		var a: int = per[i].alive
		var row: Array = species_rows[i]
		row[0].set_value(a, last_stats.is_empty())
		row[1].push(a)
		row[2].text = "生 %d  死 %d" % [per[i].births, per[i].starved + per[i].eaten + per[i].aged + per[i].phage]
		# A species released since the last sample has no "before" yet.
		if not last_stats.is_empty() and i < last_stats.species.size():
			var before: int = last_stats.species[i].alive
			if a > peak[i] * 1.25 and a > 60 and before <= peak[i] * 1.25:
				_event("%s 种群增长至 %d" % [host.labels[i], a], Ui.GOOD, _centroid(i), false, {species = i})
			if a < peak[i] * 0.3 and before >= peak[i] * 0.3 and peak[i] > 40:
				_event("%s 种群锐减至 %d" % [host.labels[i], a], Ui.ALERT, _centroid(i), false, {species = i})
				banner("%s 种群锐减" % host.labels[i], "POPULATION CRASH  ·  %d → %d" % [before, a], Ui.ALERT, _centroid(i))
			if a == 0 and before > 0:
				_event("%s 灭绝" % host.labels[i], Ui.ALERT)
				banner("%s 灭绝" % host.labels[i], "EXTINCTION  ·  T+%02d:%02d" % [int(st.time) / 60, int(st.time) % 60], Ui.ALERT)
		peak[i] = maxi(peak[i], a)
	# Count mutations, not lineages: producers drifting in from the vents
	# are founders and get new lineages too.
	var lin: int = host.mutations
	lineage_cooldown -= 0.5
	if seen_lineages > 0 and lin - seen_lineages >= 3 and lineage_cooldown <= 0.0:
		lineage_cooldown = 12.0
		var mut: Dictionary = host.sim.get_agent(host.last_mutation_id) if host.last_mutation_id >= 0 else {}
		# Name the latest mutation itself: whose, where, from what to what.
		var n := lin - seen_lineages
		var text := "%d 次基因突变" % n
		if not mut.is_empty():
			var changes: Array[String] = host.mutation_list(mut, true)
			text = "%s #%d 突变：%s" % [host.labels[int(mut.species)], int(mut.lineage), changes[0] if not changes.is_empty() else "与祖先几乎相同"]
			if changes.size() > 1:
				text += " 等 %d 处" % changes.size()
			if n > 1:
				text += "（同期另有 %d 次突变）" % (n - 1)
		_event(text, Color(1.0, 0.72, 0.25), host.last_mutation_pos, true,
			{id = host.last_mutation_id, lineage = int(mut.get("lineage", -1)), species = int(mut.get("species", -1))})
		seen_lineages = lin
	elif seen_lineages == 0 and lin > 0:
		seen_lineages = lin
	env["algae"].set_value(st.algae)
	env["nutrient"].set_value(st.energy_nutrient)
	env["shells"].set_value(st.shells)
	env["flow"].set_value(host.sim.get_flow_scale())
	env["biomass"].set_value(st.energy_organisms)
	env["lineages"].set_value(lin)
	gen_label.text = "模拟时间　·　%d 个生命" % st.count
	if hover_row >= 0 and hover_row < species_rows.size():
		last_stats = st
		_fill_detail(hover_row)
	if level_mode:
		map_points.clear()
		for i in per.size():
			map_points.append(host.sim.get_positions(i))
		minimap.queue_redraw()
		last_stats = st
		return
	# Objective (sample): both grazers alive for 3 minutes.
	var goal := 180.0
	var prog := clampf(st.time / goal, 0.0, 1.0)
	var obj: Array = env["objective"]
	obj[0].set_ratio(prog)
	obj[1].text = "%d%%" % int(prog * 100.0)
	var left := maxi(0, int(goal - st.time))
	obj[2].text = "剩余 %02d:%02d" % [left / 60, left % 60]
	map_points.clear()
	for i in per.size():
		map_points.append(host.sim.get_positions(i))
	minimap.queue_redraw()
	last_stats = st


# Where most of a species lives right now (for "定位" in the log).
func _centroid(i: int) -> Vector2:
	var pts: PackedVector2Array = host.sim.get_positions(i)
	if pts.is_empty():
		return Vector2.INF
	var c := Vector2.ZERO
	for q in pts:
		c += q
	c /= pts.size()
	# The mean can fall between two colonies; snap to the nearest member.
	var best := pts[0]
	for q in pts:
		if q.distance_squared_to(c) < best.distance_squared_to(c):
			best = q
	return best


# `who` names the organism behind the event (id, lineage, species): "定位"
# then opens that organism (or a living relative) instead of just looking.
func _event(text: String, color: Color, pos := Vector2.INF, chromosome := false, who := {}) -> void:
	var t := int(host.sim.get_time())
	var row := EventRow.new(pos)
	events_box.add_child(row)
	var h := _hbox(row, 8)
	var stamp := Ui.label("%02d:%02d" % [t / 60, t % 60], 11, Ui.INK_FAINT, Ui.mono())
	stamp.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(stamp)
	var mark: Control = ChromoIcon.new(color) if chromosome else Widgets.Chip.new(color, 9)
	mark.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(mark)
	# A long line (the cause of what happened) wraps instead of running off
	# the glass; its height set from the wrapped lines (an autowrapped Label in
	# a container reports one line).
	var words := Ui.label(text, 12, Ui.INK, Ui.sans(500))
	words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.custom_minimum_size.x = LOG_TEXT_W
	var lh := Ui.sans(500).get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, LOG_TEXT_W, 12, -1, TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_GRAPHEME_BOUND).y
	words.custom_minimum_size.y = ceilf(lh) + 2.0
	h.add_child(words)
	if pos.is_finite():
		var go := Ui.label("查看 ›" if not who.is_empty() else "定位 ›", 11, Ui.ACCENT, Ui.sans(600))
		go.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		h.add_child(go)
		if who.is_empty():
			row.clicked.connect(func() -> void: host.look_at_point(pos))
		else:
			row.clicked.connect(func() -> void: host.inspect(int(who.get("id", -1)), int(who.get("lineage", -1)), int(who.get("species", -1)), pos))
	events_box.move_child(row, 0)
	# It slides in from the left with a bar of its colour that fades, and
	# the log's glass flashes once.
	row.modulate.a = 0.0
	row.fresh = 1.0
	row.tint = color
	var tw := Ui.tween(row)
	tw.tween_property(row, "modulate:a", 1.0, Ui.T_MID)
	tw.parallel().tween_property(h, "position:x", 4.0, 0.42).from(-22.0).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	panels["events"].flash()
	Holo.type_in(row)
	while events_box.get_child_count() > 4:
		var old := events_box.get_child(events_box.get_child_count() - 1)
		events_box.remove_child(old)
		old.queue_free()


func _update_tier() -> void:
	var z: float = host.cam.zoom.x
	var want := TIER_GROUP
	if host.selected >= 0 and z >= 2.0:
		want = TIER_MICRO
	elif z < 0.75:
		want = TIER_MACRO
	if want == tier or not revealed:
		return
	var was := tier
	tier = want
	# Micro: the cell takes the stage; the side panels step back.
	var dim := 0.35 if tier == TIER_MICRO else 1.0
	for key in ["species", "events", "objective"]:
		Ui.tween(panels[key]).tween_property(panels[key], "modulate:a", dim, Ui.T_MID)
	if tier == TIER_MICRO:
		panels["environment"].disappear()
		tools.disappear() # the life scan takes the right side
		scan_panel.visible = true
		scan_panel.appear()
	elif was == TIER_MICRO:
		scan_panel.disappear()
		panels["environment"].appear()
		tools.appear()
	minimap.custom_minimum_size.y = 288.0 if tier == TIER_MACRO else 200.0


func _update_scan(id := -1) -> void:
	var info: Dictionary = host.sim.get_agent(host.selected if id < 0 else id)
	if info.is_empty():
		scan["doing"].text = "生命信号消失"
		return
	var i: int = info.species
	scan["chip"].color = host.species_color(i)
	scan["chip"].queue_redraw()
	scan["name"].text = host.labels[i]
	scan["id"].text = "#%05d" % info.id
	scan["lineage"].text = "GEN %d  ·  LINEAGE %d" % [info.generation, info.lineage]
	var act: int = info.action
	scan["doing"].text = "▸ " + ACTIONS[act] + ("　→ #%d" % info.target if act in [3, 4, 5] and info.target > 0 else "")
	if bool(info.get("slug", false)):
		scan["doing"].text = "▸ 聚合体的一员：不进食，也不变老"
	elif float(info.get("spore_in", -1.0)) > 0.0:
		scan["doing"].text = "▸ 孢子　%d 秒后发芽" % ceili(float(info.spore_in))
	elif bool(info.get("factory", false)):
		scan["doing"].text = ("▸ 工厂被噬毒体闯入　%d 秒后爆开" if bool(info.get("hijacked", false)) else "▸ 体内有巨毒囊工厂　%d 秒后爆开") % ceili(float(info.get("burst_in", 0.0)))
	elif float(info.get("infected", -1.0)) >= 0.0:
		scan["doing"].text = ("▸ 潜伏针醒了　%d 秒后爆开" if bool(info.get("woken", false)) else "▸ 被病毒扎中　%d 秒后爆开") % ceili(float(info.burst_in))
	elif bool(info.get("cutting", false)):
		var ct := float(info.get("cut_t", 0.0))
		scan["doing"].text = "▸ 裂囊针落在膜上" if ct < 1.2 else ("▸ 病毒 DNA 钻进来了" if ct < 2.2 else ("▸ 正在剪碎病毒 DNA" if ct < 5.0 or bool(info.immune) else "▸ 把一小段存进基因"))
	elif bool(info.get("immune", false)):
		scan["doing"].text += "　· 有免疫记忆"
	elif bool(info.get("latent", false)):
		scan["doing"].text += "　· 基因里藏着噬毒体" if host.level_runner and host.level_runner.level.has("giant") else "　· 基因里藏着潜伏针"
	scan["energy"][0].set_ratio(info.energy / info.divide_at)
	scan["energy"][1].text = "%d / %d" % [int(info.energy), int(info.divide_at)]
	scan["age"][0].set_ratio(info.age / info.lifespan)
	scan["age"][1].text = "%d / %d s" % [int(info.age), int(info.lifespan)]
	var zone: Dictionary = Ecology.zone_at(host.layout, info.position)
	var note := ""
	if info.stress_temp > 0.05:
		note = "　过热，额外耗能" if info.temp > info.temp_opt else "　过冷，额外耗能"
		note += " %.1f/s" % info.stress_temp
	if info.stress_acid > 0.05:
		note += "　酸蚀 %.1f/s" % info.stress_acid
	scan["water"].text = "%s　%d°C（适宜 %d ± %d）%s%s" % [zone.get("name", "开阔水域"), roundi(info.temp), roundi(info.temp_opt),
		roundi(info.temp_band), "　pH %.1f" % (7.0 - 4.0 * float(info.acid)) if info.acid > 0.2 else "", note]
	var fit := Ecology.fitness(info.genes, info.temp_opt, {temp = info.temp, acid = info.acid}, info.radius)
	scan["fit"][0].set_ratio(fit)
	scan["fit"][1].text = "%d%%" % roundi(fit * 100.0)
	var base: Array = host.species_genes[info.species] if info.species < host.species_genes.size() else []
	for k in GENE_NAMES.size():
		var g: float = info.genes[k]
		scan["genes"][k][0].set_ratio((g - 1.0) / 4.0)
		# A mutated gene shows the ancestor's value next to its own, in gold.
		var was: float = base[k] if k < base.size() else g
		var drifted := absf(g - was) >= 0.02
		scan["genes"][k][1].text = ("%.2f→%.2f" % [was, g]) if drifted else "%.1f" % g
		scan["genes"][k][1].add_theme_color_override("font_color", Color(0.8, 0.5, 0.05) if drifted else Ui.INK)
	var muts: Array[String] = host.mutation_list(info)
	var mt := "\n".join(muts.map(func(m: String) -> String: return "• " + m)) if not muts.is_empty() else "没有突变：和祖先一模一样"
	if scan["mut"].text != mt:
		scan["mut"].text = mt
	scan["chromo"].show_genes(info.genes, base)
	scan["deck"].show_info(info)
	scan["pause"].text = "继续" if host.paused else "暂停"
	scan["pause"].active = host.paused
	scan["tick"].text = "第 %d 拍  ·  %s" % [roundi(host.sim.get_time() * 15.0), ("按 %s 再走一拍" % Keys.name_of(Keys.code("step"))) if host.paused else "每秒 15 拍"]
	scan["hint"].text = "F 取消跟随　Esc 关闭" if host.following else "F 跟随　Esc 关闭"


# --- drawing: reticle, callouts, minimap ------------------------------------------

func _draw() -> void:
	if (tier != TIER_MICRO and _rehearse_id < 0) or host == null:
		return
	var info: Dictionary = host.sim.get_agent(host.selected if _rehearse_id < 0 else _rehearse_id)
	if info.is_empty():
		return
	var xf := get_viewport().get_canvas_transform()
	var c: Vector2 = xf * (host.last_pos if _rehearse_id < 0 else info.position) # interpolated like the drawn cell
	var zoom: float = host.cam.zoom.x
	var r: float = info.radius * zoom * 1.9 + 14.0
	var col := Color(Ui.ACCENT, 0.85)
	if host.quiet_callouts:
		return # (a close-up of what is inside the cell: no ring, no labels)
	# Segmented ring rotating slowly, four ticks, and a sweeping arc.
	var segs := 12
	for k in segs:
		var a0 := reticle_spin * 0.4 + TAU * k / segs
		draw_arc(c, r, a0, a0 + TAU / segs * 0.55, 6, col, 1.2, true)
	for k in 4:
		var a := TAU * k / 4.0 + PI * 0.25
		var d := Vector2(cos(a), sin(a))
		draw_line(c + d * (r + 4.0), c + d * (r + 12.0), col, 1.4, true)
	var sweep := fmod(reticle_spin * 1.6, TAU)
	draw_arc(c, r + 6.0, sweep, sweep + 0.7, 16, Color(Ui.ACCENT, 0.35), 3.0, true)
	# Organ callouts: leader lines from the parts to labels outside the ring.
	var h: float = info.heading
	var fwd := Vector2(cos(h), sin(h))
	var side := Vector2(-fwd.y, fwd.x)
	var rr: float = info.radius * zoom
	var genes: PackedFloat32Array = info.genes
	var parts := [
		["细胞核", c - fwd * rr * 0.12, Vector2(-1, -1)],
		["储能颗粒", c + side * rr * 0.35 + fwd * rr * 0.1, Vector2(1, -1)],
		["细胞膜", c - side * rr, Vector2(-1, 1)],
	]
	if genes[0] > 1.5:
		parts.append(["纤毛", c + side * rr * 1.05 - fwd * rr * 0.2, Vector2(1, 1)])
	if genes[1] > 2.2:
		parts.append(["眼点", c + fwd * rr * 0.62, Vector2(1, -0.2)])
	var font := Ui.sans(500)
	var mono := Ui.mono()
	if host.quiet_callouts:
		parts = [] # (a close-up of something else: the labels only get in the way)
	for p in parts:
		var anchor: Vector2 = p[1]
		var dir: Vector2 = p[2]
		var elbow := c + Vector2(dir.x * (r + 34.0), dir.y * (r * 0.75 + 18.0))
		var end := elbow + Vector2(dir.x * 46.0, 0)
		draw_circle(anchor, 2.5, col)
		draw_line(anchor, elbow, Color(col, 0.6), 1.0, true)
		draw_line(elbow, end, Color(col, 0.6), 1.0, true)
		var text: String = p[0]
		var ts := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
		var tx := end.x + (6.0 if dir.x > 0 else -ts.x - 6.0)
		draw_string(font, Vector2(tx, end.y + 4.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Ui.INK)
	var tag := "#%05d  %.0f µm/s" % [info.id, info.speed]
	draw_string(mono, c + Vector2(-r, r + 22.0), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Ui.INK_SOFT)


func _map_to_world(p: Vector2) -> Vector2:
	var s := minimap.size
	var rad := minf(s.x, s.y) * 0.5 - 4.0
	return host.DISH_CENTER + (p - s * 0.5) / rad * host.DISH_RADIUS


func _draw_minimap() -> void:
	var s := minimap.size
	var center := s * 0.5
	var rad := minf(s.x, s.y) * 0.5 - 4.0
	var dish_r: float = host.DISH_RADIUS
	var dish_c: Vector2 = host.DISH_CENTER
	minimap.draw_circle(center, rad, Color(0.85, 0.94, 0.97, 0.6))
	minimap.draw_arc(center, rad, 0, TAU, 64, Ui.LINE_STRONG, 1.0, true)
	if GlassPanel.holo:
		# A scope: inner rings, ticks round the rim, a heavier mark every 90°.
		for f in [0.33, 0.66]:
			minimap.draw_arc(center, rad * f, 0, TAU, 48, Color(Ui.ACCENT, 0.18), 1.0, true)
		for k in 72:
			var a := TAU * k / 72.0
			var l := 8.0 if k % 18 == 0 else (4.0 if k % 6 == 0 else 2.0)
			var d := Vector2.from_angle(a)
			minimap.draw_line(center + d * (rad + 2.0), center + d * (rad + 2.0 + l), Color(Ui.ACCENT, 0.6 if k % 18 == 0 else 0.3), 1.0)
	for i in map_points.size():
		var col: Color = host.species_color(i)
		var pts: PackedVector2Array = map_points[i]
		var step := maxi(1, pts.size() / 400)
		for k in range(0, pts.size(), step):
			var m := center + (pts[k] - dish_c) / dish_r * rad
			minimap.draw_rect(Rect2(m - Vector2(1, 1), Vector2(2.2, 2.2)), Color(col, 0.85))


# The camera's view on the minimap.
func _draw_minimap_view() -> void:
	var s := minimap.size
	var center := s * 0.5
	var rad := minf(s.x, s.y) * 0.5 - 4.0
	var dish_r: float = host.DISH_RADIUS
	var dish_c: Vector2 = host.DISH_CENTER
	var view: Vector2 = get_viewport().get_visible_rect().size / host.cam.zoom
	var tl: Vector2 = center + (host.cam.position - view * 0.5 - dish_c) / dish_r * rad
	var br: Vector2 = center + (host.cam.position + view * 0.5 - dish_c) / dish_r * rad
	var rect := Rect2(tl, br - tl).intersection(Rect2(Vector2.ZERO, s))
	# A slow radar sweep (the only thing that moves on its own).
	var a := Time.get_ticks_msec() / 1000.0 * TAU / 7.0
	for k in 10:
		var a0 := a - k * 0.06
		var pts := PackedVector2Array([center, center + Vector2.from_angle(a0) * rad, center + Vector2.from_angle(a0 - 0.06) * rad])
		minimap_view.draw_colored_polygon(pts, Color(Ui.ACCENT, 0.1 * (1.0 - k / 10.0)))
	minimap_view.draw_line(center, center + Vector2.from_angle(a) * rad, Color(Ui.ACCENT, 0.35), 1.0, true)
	minimap_view.draw_rect(rect, Color(Ui.ACCENT, 0.9), false, 1.2)


# One line of the event log. With a position it is clickable: hover lights
# it, a click flies the camera there.
# The inspected cell's seven chromosomes, banded by level. Loci that have
# drifted from the species' founding genome (mutations) pulse gold, with an
# arrow for which way they went.
class ChromoStrip extends Control:
	var genes: Array = []
	var base: Array = []
	var t := 0.0

	func _init() -> void:
		custom_minimum_size = Vector2(0, 50)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	var _pulse: Control
	var _drifted := []

	func _ready() -> void:
		# Only the gold pulse animates; the chromosomes redraw on change.
		_pulse = Control.new()
		_pulse.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_pulse.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_pulse.draw.connect(_draw_pulse)
		add_child(_pulse)

	func show_genes(g: Array, b: Array) -> void:
		var ng := Array(g)
		if ng == genes and b == base:
			return
		genes = ng
		base = b
		_drifted.clear()
		for k in mini(GENE_NAMES.size(), genes.size()):
			var drift: float = float(genes[k]) - float(base[k]) if k < base.size() else 0.0
			if absf(drift) >= 0.25:
				_drifted.append([k, drift > 0.0])
		queue_redraw()

	func _process(delta: float) -> void:
		if not _drifted.is_empty() and is_visible_in_tree():
			t += delta
			_pulse.queue_redraw()

	func _draw() -> void:
		var n := GENE_NAMES.size()
		if genes.size() < n:
			return
		var w := size.x / n
		var gold := Color(1.0, 0.72, 0.25)
		var marked := {}
		for d in _drifted:
			marked[d[0]] = true
		for k in n:
			var lv: float = genes[k]
			GenomeArt.chromosome(self, Vector2(w * (k + 0.5), 19.0), -PI * 0.5, 16.0 + 3.0 * lv, GenomeArt.GENE_COLORS[k], lv)
			draw_string(Ui.sans(500), Vector2(w * k, 48.0), GENE_NAMES[k], HORIZONTAL_ALIGNMENT_CENTER, w, 9,
				gold.darkened(0.25) if marked.has(k) else Ui.INK_FAINT)

	func _draw_pulse() -> void:
		var w := size.x / GENE_NAMES.size()
		var gold := Color(1.0, 0.72, 0.25)
		for d in _drifted:
			var k: int = d[0]
			var c := Vector2(w * (k + 0.5), 19.0)
			var pulse := 0.55 + 0.45 * sin(t * 4.0 + k)
			_pulse.draw_circle(c, 17.0, Color(gold, 0.12 * pulse))
			_pulse.draw_arc(c, 17.0, 0.0, TAU, 32, Color(gold, 0.75 * pulse), 1.4, true)
			var up: bool = d[1]
			var ay := 4.0 if up else 34.0
			var tip := Vector2(c.x + 15.0, ay + (-3.0 if up else 3.0))
			_pulse.draw_colored_polygon(PackedVector2Array([tip, Vector2(c.x + 11.5, ay + (2.0 if up else -2.0)), Vector2(c.x + 18.5, ay + (2.0 if up else -2.0))]), gold)


# A tiny chromosome in place of the colour dot on mutation log entries.
class ChromoIcon extends Control:
	var color := Color.WHITE

	func _init(c: Color) -> void:
		color = c
		custom_minimum_size = Vector2(12, 14)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		GenomeArt.chromosome(self, size * 0.5, -PI * 0.5, 13.0, color, 2.0)


class EventRow extends MarginContainer:
	signal clicked
	var pos := Vector2.INF
	var fresh := 0.0 # 1 when it arrives, fading
	var tint := Ui.ACCENT
	var _hover := 0.0

	func _init(p: Vector2) -> void:
		pos = p
		add_theme_constant_override("margin_left", 4)
		add_theme_constant_override("margin_right", 4)
		mouse_filter = Control.MOUSE_FILTER_STOP if p.is_finite() else Control.MOUSE_FILTER_IGNORE
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if p.is_finite() else Control.CURSOR_ARROW

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			clicked.emit()
			accept_event()

	func _process(delta: float) -> void:
		var h := 1.0 if pos.is_finite() and get_global_rect().has_point(GlassPanel.mouse(get_viewport())) else 0.0
		if absf(_hover - h) > 0.001 or fresh > 0.0:
			_hover = lerpf(_hover, h, minf(1.0, delta / Ui.T_FAST))
			fresh = move_toward(fresh, 0.0, delta / 1.6)
			queue_redraw()

	func _draw() -> void:
		if fresh > 0.0:
			var k := fresh * fresh
			draw_rect(Rect2(Vector2(-4, -2), size + Vector2(8, 4)), Color(tint, 0.14 * k))
			draw_rect(Rect2(Vector2(-4, -2), Vector2(3, size.y + 4)), Color(tint, k))
		if _hover > 0.01:
			draw_rect(Rect2(Vector2(-4, -2), size + Vector2(8, 4)), Color(Ui.ACCENT, 0.1 * _hover))
			draw_rect(Rect2(Vector2(-4, -2), Vector2(2, size.y + 4)), Color(Ui.ACCENT, _hover))


# Life scan, "why this action": the organism's deck, top to bottom. The card
# that fired is lit; every card above it says why it was passed over; the
# ones below were not checked this tick.
class DeckTrace extends Control:
	var info := {}
	var _fired := -2
	var _flash := 0.0

	func _init() -> void:
		custom_minimum_size = Vector2(348, 40)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func show_info(i: Dictionary) -> void:
		info = i
		var f: int = i.fired
		if f != _fired:
			_fired = f
			_flash = 1.0
		var n: int = i.deck.size()
		custom_minimum_size.y = 26.0 * n + (22.0 if f < 0 else 0.0) + 4.0
		queue_redraw()

	func _process(delta: float) -> void:
		if _flash > 0.0:
			_flash = maxf(0.0, _flash - delta * 2.0)
			queue_redraw()

	func _why_not(c: int) -> String:
		return "已有记忆，这张不管它" if c == Rules.C_IMMUNE else "“不”不成立"


	func _why_cond(c: int, t: float) -> String:
		match c:
			Rules.C_ENERGY_BELOW, Rules.C_ENERGY_ABOVE:
				return "能量 %d%%" % roundi(info.energy_frac * 100.0)
			Rules.C_SEE_ALGAE: return "看不见藻团"
			Rules.C_PREDATOR_NEAR:
				return "没有猎手" if info.threat_distance < 0.0 else "猎手在 %d µm" % roundi(info.threat_distance)
			Rules.C_SEE_PREY: return "看不见猎物"
			Rules.C_CROWD: return "同伴 %d" % info.crowd
			Rules.C_ATTACKED: return "没被攻击"
			Rules.C_AGE_ABOVE: return "年龄 %d%%" % roundi(info.age / info.lifespan * 100.0)
			Rules.C_SEE_SHELL: return "看不见空壳"
			Rules.C_TEMP_BAD: return "水温合适"
		return ""

	func _why_act(a: int) -> String:
		match a:
			Rules.A_SEEK_ALGAE: return "做不到：看不见藻团"
			Rules.A_FLEE: return "做不到：没有猎手"
			Rules.A_HUNT: return "做不到：没猎物或在消化"
			Rules.A_FOLLOW: return "做不到：身边没同伴"
			Rules.A_DIVIDE: return "做不到：能量不够或冷却中"
			Rules.A_SCAVENGE: return "做不到：看不见空壳"
			Rules.A_SEEK_COMFORT: return "做不到：四周没有更合适的水"
			Rules.A_INDUCE: return "已经叫醒了"
		return "做不到"

	func _draw() -> void:
		if info.is_empty():
			return
		var f: int = info.fired
		var deck: Array = info.deck
		var sans := Ui.sans(500)
		var bold := Ui.sans(700)
		var mono := Ui.mono("Medium")
		for k in deck.size():
			var cd: Dictionary = deck[k]
			var y := 26.0 * k
			var r := Rect2(0, y, size.x, 24)
			var state := "skip" if f < 0 or k < f else ("fire" if k == f else "idle")
			if state == "fire":
				draw_rect(r, Color(Ui.ACCENT, 0.14 + 0.25 * _flash))
				draw_rect(Rect2(r.position, Vector2(3, r.size.y)), Ui.ACCENT)
			var ink := Ui.INK if state == "fire" else (Ui.INK_SOFT if state == "skip" else Ui.INK_FAINT)
			draw_string(mono, Vector2(8, y + 16), str(k + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Ui.ACCENT if state == "fire" else ink)
			var text := Rules.card_text(cd)
			var tag_w := 112.0
			draw_string(bold if state == "fire" else sans, Vector2(24, y + 16), text, HORIZONTAL_ALIGNMENT_LEFT, size.x - 24.0 - tag_w, 11, ink)
			var tag := ""
			var tag_col := Ui.INK_FAINT
			match state:
				"fire":
					tag = "▶ 生效"
					tag_col = Ui.ACCENT
				"idle":
					tag = "未检查"
				_:
					# (A negated condition fails when the plain one holds; an 或
					# card holds when either does.)
					if cd.get("any", false) and cd.c2 != Rules.C_NONE and (cd.ok1 or cd.ok2):
						tag = _why_act(cd.act)
					elif not cd.ok1:
						tag = _why_not(cd.c1) if cd.get("n1", false) else _why_cond(cd.c1, cd.t1)
					elif not cd.ok2:
						tag = _why_not(cd.c2) if cd.get("n2", false) else _why_cond(cd.c2, cd.t2)
					elif not cd.possible:
						tag = _why_act(cd.act)
					tag_col = Ui.WARN
			var tw := sans.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
			draw_string(sans, Vector2(size.x - tw - 4, y + 16), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, tag_col)
		if f < 0:
			draw_string(Ui.sans(600), Vector2(8, 26.0 * deck.size() + 15), "一张都不生效 → 漫游", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Ui.ACCENT)


# How a species dies, as one thin bar: starved / eaten / old age.
class DeathBar extends Control:
	var parts := [0, 0, 0]
	const COLS := [Color("df9f37"), Color("de6168"), Color("8f9fe0")]
	const NAMES := ["饿死", "被吃", "老死"]

	func _init() -> void:
		custom_minimum_size = Vector2(0, 20)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_counts(starved: int, eaten: int, aged: int) -> void:
		parts = [starved, eaten, aged]
		queue_redraw()

	func _draw() -> void:
		var total := maxi(parts[0] + parts[1] + parts[2], 1)
		var w := size.x
		var x := 0.0
		draw_rect(Rect2(0, 1, w, 3), Color(Ui.INK_FAINT, 0.25))
		for k in 3:
			var seg: float = w * parts[k] / total
			draw_rect(Rect2(x, 1, maxf(seg - 1.0, 0.0), 3), COLS[k])
			x += seg
		var f := Ui.sans(500)
		var tx := 0.0
		for k in 3:
			var t := "%s %d" % [NAMES[k], parts[k]]
			draw_circle(Vector2(tx + 3, 13.5), 2.5, COLS[k])
			draw_string(f, Vector2(tx + 9, 17.5), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Ui.INK_SOFT)
			tx += f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x + 22.0
