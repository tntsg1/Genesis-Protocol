extends Control
# Experiment report for a campaign level (DECISIONS M4 Q6/Q9, revised after
# the first playtest). Opens full screen for a moment - the stars light up
# one by one - then settles into the report: the population over time and
# the plain facts on the left; on the right the control experiment set-up:
# pick one gene and a direction, and the same dish is run twice side by side
# (your design and the changed one) so the difference can be watched.

signal action(what: String, arg: Variant) # retry {design} / next / exit / compare {gene, delta}

const CHECK_TIME := 2.4
const GENE_NAMES := ["速度", "感知", "外壳", "攻击", "繁殖", "代谢", "神经", "耐温"]

var runner: Node
var level: Dictionary
var eval: LevelEval
var got: Array
var earned := 0
var t := 0.0
var settled := false
var head: Control
var panel: GlassPanel
var pick_gene := -1
var pick_delta := 1.0
var gene_pills := {}
var dir_pills := {}
var compare_b: Widgets.Pill
var compare_hint: Label
var dismissed := false
var ctrl_box: VBoxContainer # the control experiment, folded until asked for


func setup(r: Node, got_stars: Array, research: int) -> void:
	runner = r
	level = r.level
	eval = r.eval
	got = got_stars
	earned = research


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var wash := ColorRect.new()
	wash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wash.color = Color(0.965, 0.982, 0.993, 0.96) # the dish HUD must not show through
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(wash)
	_build_head()
	_build_body()
	if got[0]:
		Audio.sting("result")
	else:
		Audio.sfx("fail")
	modulate.a = 0.0
	Ui.tween(self).tween_property(self, "modulate:a", 1.0, Ui.T_MID)


func _build_head() -> void:
	head = VBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(head)
	head.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	head.offset_top = 300.0
	var ok: bool = got[0]
	var tl := Ui.label("实验成功" if ok else "实验失败", 44, Ui.INK if ok else Ui.ALERT, Ui.sans(700))
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_child(tl)
	# One line: a goal written on several (5-5: "完成以下任意一项：\n…\n…")
	# pushed the stars down and 研究点 under the divider.
	var goal_line: String = (level.goal.text as String).replace("：\n", "：").replace("\n", "　")
	var sub := Ui.label("%s  %s  ·  %s" % [level.id, level.name, goal_line if ok else _fail_reason()], 15, Ui.INK_SOFT, Ui.sans(500))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_child(sub)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 46)
	head.add_child(row)
	var names := ["完成目标", "附加挑战", "小身体" if level.has("star_blocks") else ("省着用" if level.has("star_shots") else "低预算")]
	# Each missed star says why, in a few words.
	var notes := ["没达成" if not got[0] else "", "", ""]
	if not got[1]:
		notes[1] = "目标没达成，不计" if not got[0] else "这次没做到"
	if not got[2]:
		notes[2] = "目标没达成，不计" if not got[0] else "用了 %d 点，线是 %d" % [int(eval.budget_used), int(level.star_budget)]
		if got[0] and level.has("star_blocks"):
			notes[2] = "身体 %d 块，要 %d 块以内" % [eval.blocks_used, int(level.star_blocks)]
	for k in 3:
		var s := BigStar.new()
		s.label = names[k]
		s.note = notes[k]
		s.earned = got[k]
		s.delay = 0.35 + k * 0.45
		row.add_child(s)
	var rl := Ui.label("研究点 +%d" % earned if earned > 0 else " ", 13, Ui.ACCENT, Ui.mono("Medium"))
	rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_child(rl)


func _fail_reason() -> String:
	if eval.extinct and eval.sp2 >= 0:
		return "%s灭绝了" % (level.species[0].label if eval.alive == 0 else level.species[1].label)
	if not eval.extinct and level.goal.kind == "alive_phage" and eval.lysed > int(level.goal.lysed):
		return "被撑破的超过了上限"
	if not eval.extinct and level.goal.kind == "giant_limit":
		return "巨毒囊太多了" if eval.giants > int(level.goal.giant_max) else "细胞不够多"
	return "种群灭绝了" if eval.extinct else "时间到，目标没有达成"


func _build_body() -> void:
	panel = GlassPanel.new(Vector4(28, 22, 28, 22))
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -820
	panel.offset_right = 820
	panel.offset_top = 260
	panel.offset_bottom = -40
	panel.modulate.a = 0.0
	add_child(panel)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 40)
	# The columns fill the panel and the chart takes what is left (3-1 review:
	# the failure page's lower half stood empty).
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.body.add_child(cols)
	# Left: what happened.
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 10)
	cols.add_child(left)
	left.add_child(Ui.caption("种群变化", "POPULATION"))
	var chart := Chart.new()
	chart.eval = eval
	chart.level = level
	chart.custom_minimum_size = Vector2(760, 330)
	chart.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(chart)
	left.add_child(Ui.caption("事实", "FACTS"))
	for f: String in _facts():
		var l := Ui.label("·  " + f, 14, Ui.INK, Ui.sans())
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 760
		left.add_child(l)
	# Right: the control experiment set-up.
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 12)
	right.custom_minimum_size.x = 700
	cols.add_child(right)
	if got[0] and (level.has("giant") or level.has("slug") or level.has("colony")):
		right.add_child(Ui.caption("这一局为什么赢", "WHY IT WORKED"))
		for t: String in (_giant_win() if level.has("giant") else (_slug_win() if level.has("slug") else _colony_win())):
			var wl := Ui.label("·  " + t, 16, Ui.INK, Ui.sans(600))
			wl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			wl.custom_minimum_size.x = 700
			right.add_child(wl)
	# Not passed: what passes it, said plainly (playtest: "不然我怎么知道").
	# The first miss gives a direction; from the second on, the how.
	if not got[0] and level.has("tips"):
		var tries := int(CampaignSave.level(level.id).get("attempts", 1))
		var first := tries <= 1 and level.has("hints")
		# (Level 21: every body fails differently, so the diagnosis comes first each time.)
		var lines_now: Array = _hints() if first else (_hints() + level.tips if level.has("colony") else level.tips)
		right.add_child(Ui.caption(str(level.get("hints_title", "实验失败 · 调整建议")) if first else str(level.get("tips_title", "实验失败 · 通关要点")), "HINTS" if first else "HOW TO PASS"))
		for t: String in lines_now:
			var tl := Ui.label("·  " + t, 16, Ui.INK, Ui.sans(600))
			tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			tl.custom_minimum_size.x = 700
			right.add_child(tl)
		if first:
			# Or now: the how, on request (the player decides how much help).
			var how := Widgets.Pill.new("查看具体做法  ▸", 0, Ui.sans(600))
			how.custom_minimum_size = Vector2(190, 34)
			how.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			right.add_child(how)
			var tips_box := VBoxContainer.new()
			tips_box.add_theme_constant_override("separation", 8)
			tips_box.visible = false
			right.add_child(tips_box)
			tips_box.add_child(Ui.caption(str(level.get("tips_title", "实验失败 · 通关要点")), "HOW TO PASS"))
			for t: String in level.tips:
				var tt := Ui.label("·  " + t, 16, Ui.INK, Ui.sans(600))
				tt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				tt.custom_minimum_size.x = 700
				tips_box.add_child(tt)
			how.pressed.connect(func() -> void:
				how.visible = false
				tips_box.visible = true)
		var gap := Control.new()
		gap.custom_minimum_size.y = 8
		right.add_child(gap)
	var ctrl_cap := Ui.caption("对照实验", "CONTROL EXPERIMENT")
	right.add_child(ctrl_cap)
	# Folded to one line until asked for (review round 2: half the screen of
	# an optional tool read as homework on a first failure).
	var unfold := Widgets.Pill.new("想验证某个基因到底有没有用？做个对照实验  ▸", 0, Ui.sans(600))
	unfold.custom_minimum_size = Vector2(420, 40)
	unfold.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	right.add_child(unfold)
	# Nothing to vary where no gene is open (level 18 designs a virus).
	ctrl_cap.visible = _has_control()
	unfold.visible = ctrl_cap.visible
	var outer := right
	right = VBoxContainer.new()
	right.add_theme_constant_override("separation", 12)
	right.visible = false
	outer.add_child(right)
	unfold.pressed.connect(func() -> void:
		unfold.visible = false
		right.visible = true)
	ctrl_box = right
	var intro := Ui.label("想知道某个基因到底有没有用？挑一个基因和方向，游戏会用同一个培养皿并排跑两盘：左边照你这次的方案，右边只改这一处。只是做实验，不会改动你的方案。", 14, Ui.INK, Ui.sans(500))
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.custom_minimum_size.x = 690
	right.add_child(intro)
	right.add_child(Ui.label("1　改哪个基因", 13, Ui.INK_SOFT, Ui.sans(600)))
	var gr := HBoxContainer.new()
	gr.add_theme_constant_override("separation", 8)
	right.add_child(gr)
	for g: int in level.genes_open:
		var b := Widgets.Pill.new("%s  Lv %d" % [GENE_NAMES[g], int(runner.design.genes[g])], 0, Ui.sans(600))
		b.custom_minimum_size = Vector2(130, 38)
		var gi := g
		b.pressed.connect(func() -> void: _pick(gi, pick_delta))
		gr.add_child(b)
		gene_pills[g] = b
	# Natural mutation on / off as a control (level 4 teaches selection).
	if level.has("events") or level.id == "1-4":
		var on := bool(runner.design.design.get("mutates", true))
		var mb := Widgets.Pill.new("自然变异  %s" % ("开" if on else "关"), 0, Ui.sans(600))
		mb.custom_minimum_size = Vector2(150, 38)
		mb.pressed.connect(func() -> void: _pick(-1, 0.0))
		gr.add_child(mb)
		gene_pills[-1] = mb
	right.add_child(Ui.label("2　往哪边改", 13, Ui.INK_SOFT, Ui.sans(600)))
	var dr := HBoxContainer.new()
	dr.add_theme_constant_override("separation", 8)
	right.add_child(dr)
	for spec in [[-1.0, "降一级  −1"], [1.0, "升一级  +1"]]:
		var b := Widgets.Pill.new(spec[1], 0, Ui.sans(600))
		b.custom_minimum_size = Vector2(130, 38)
		var dv: float = spec[0]
		b.pressed.connect(func() -> void: _pick(pick_gene, dv))
		dr.add_child(b)
		dir_pills[dv] = b
	compare_hint = Ui.label("", 14, Ui.INK, Ui.sans(500))
	compare_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	compare_hint.custom_minimum_size.x = 690
	right.add_child(compare_hint)
	compare_b = Widgets.Pill.new("开始并排对照  C", 0, Ui.sans(600))
	compare_b.custom_minimum_size = Vector2(220, 44)
	compare_b.pressed.connect(_compare)
	right.add_child(compare_b)
	right = outer
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(sp)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 12)
	right.add_child(foot)
	var back := Widgets.Pill.new("返回关卡页", 0, Ui.sans(500))
	back.custom_minimum_size = Vector2(130, 40)
	back.pressed.connect(func() -> void: action.emit("exit", null))
	foot.add_child(back)
	var retry := Widgets.Pill.new("改方案再试  R", 0, Ui.sans(600))
	retry.custom_minimum_size = Vector2(160, 40)
	retry.pressed.connect(func() -> void: action.emit("retry", {}))
	foot.add_child(retry)
	if _has_next():
		var nx := Widgets.Pill.new("下一关  Enter", 0, Ui.sans(600))
		nx.custom_minimum_size = Vector2(150, 40)
		nx.active = true
		nx.pressed.connect(func() -> void: action.emit("next", null))
		foot.add_child(nx)
	elif _to_ending():
		# The last level won: the way on is the end of Europa (it plays as
		# the level is left, LevelRunner.exit_level), not a dead end.
		var en := Widgets.Pill.new("继续 · 观看结局  Enter", 0, Ui.sans(600))
		en.custom_minimum_size = Vector2(220, 40)
		en.active = true
		en.pressed.connect(func() -> void: action.emit("exit", null))
		foot.add_child(en)
	else:
		retry.active = true
	# A chapter's last level, won: the chapter closes, with its stars and
	# what comes next (open, or still coming) (DECISIONS 第十九轮 Q49).
	var ch := int((level.id as String).get_slice("-", 0))
	var last := not Levels.ALL.any(func(l: Dictionary) -> bool: return int((l.id as String).get_slice("-", 0)) == ch and int((l.id as String).get_slice("-", 1)) > int((level.id as String).get_slice("-", 1)))
	if runner.eval.goal_met and last and ch >= 1 and ch <= Levels.CHAPTERS.size() and not Levels.UNFINISHED.has(ch):
		var got := 0
		var of := 0
		for l: Dictionary in Levels.ALL:
			if int((l.id as String).get_slice("-", 0)) == ch:
				got += (CampaignSave.stars(l.id) as Array).count(true)
				of += 3
		var next_ch: String = Levels.CHAPTERS[ch][0] if ch < Levels.CHAPTERS.size() else ""
		var tail := ("　·　%s 已开放" % next_ch if _has_next() else "　·　%s 即将开放" % next_ch) if next_ch != "" else ""
		var end := Ui.label("%s 完成　本章 %d / %d 星%s" % [Levels.CHAPTERS[ch - 1][0], got, of, tail], 18, Ui.ACCENT, Ui.sans(700))
		# Its own line above the buttons: in the button row it pushed 下一关
		# off the screen.
		end.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		end.custom_minimum_size.x = 700
		right.add_child(end)
		right.move_child(end, foot.get_index())
	if not level.genes_open.is_empty():
		_pick(level.genes_open[0], 1.0)


func _has_next() -> bool:
	return got[0] and level.index < Levels.ALL.size() and Levels.playable(Levels.ALL[level.index])


func _to_ending() -> bool:
	return got[0] and level.get("ending", false) and not runner.ending_played


# Choose the change; impossible ones (Lv 1 down, Lv 5 up) say so.
func _pick(gene: int, delta: float) -> void:
	pick_gene = gene
	pick_delta = delta
	for g in gene_pills:
		gene_pills[g].active = g == gene
	for d in dir_pills:
		dir_pills[d].active = d == delta
	if gene < 0:
		for d in dir_pills:
			dir_pills[d].modulate.a = 0.35
		var on := bool(runner.design.design.get("mutates", true))
		compare_hint.text = "现在选的是：左边自然变异%s（你这次的方案），右边假设自然变异%s，基因完全相同。" % ["开" if on else "关", "关" if on else "开"]
		compare_b.modulate.a = 1.0
		compare_b.queue_redraw()
		return
	for d in dir_pills:
		dir_pills[d].modulate.a = 1.0
	var now := float(runner.design.genes[gene])
	var to := now + delta
	if to < 1.0 or to > 5.0:
		compare_hint.text = "%s 已经是 Lv %d，不能再%s了。" % [GENE_NAMES[gene], int(now), "降" if delta < 0 else "升"]
		compare_b.modulate.a = 0.45
	else:
		compare_hint.text = "现在选的是：左边%s Lv %d（你这次的方案），右边假设%s Lv %d，其余完全相同。" % [GENE_NAMES[gene], int(now), GENE_NAMES[gene], int(to)]
		compare_b.modulate.a = 1.0
	compare_b.queue_redraw()


# (Level 19: the player's drops can't be replayed, so a second run would not
# be a fair comparison.)
func _has_control() -> bool:
	return not level.genes_open.is_empty() and not level.has("giant")


func _compare() -> void:
	if not _has_control():
		return
	if pick_gene < 0:
		action.emit("compare", {gene = -1, delta = 0.0})
		return
	var to := float(runner.design.genes[pick_gene]) + pick_delta
	if to < 1.0 or to > 5.0:
		return
	action.emit("compare", {gene = pick_gene, delta = pick_delta})


func _process(delta: float) -> void:
	t += delta
	if not settled and t >= CHECK_TIME:
		settled = true
		head.pivot_offset = Vector2(head.size.x * 0.5, 0.0)
		var tw := Ui.tween(head)
		tw.tween_property(head, "offset_top", 24.0, Ui.T_SLOW)
		tw.parallel().tween_property(head, "scale", Vector2(0.84, 0.84), Ui.T_SLOW)
		var tp := Ui.tween(panel)
		tp.tween_interval(0.2)
		tp.tween_property(panel, "modulate:a", 1.0, Ui.T_SLOW)
		panel.appear(0.2)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and settled and not dismissed:
		match (event as InputEventKey).keycode:
			KEY_R:
				action.emit("retry", {})
			KEY_C:
				_compare()
			KEY_ENTER, KEY_KP_ENTER:
				if _has_next():
					action.emit("next", null)
				elif _to_ending():
					action.emit("exit", null)
			KEY_ESCAPE:
				action.emit("exit", null)
			_:
				return
		get_viewport().set_input_as_handled()


# Leaves at once (fades, stops taking input).
func dismiss() -> void:
	dismissed = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process_unhandled_input(false)
	var tw := Ui.tween(self)
	tw.tween_property(self, "modulate:a", 0.0, Ui.T_MID)
	tw.tween_callback(queue_free)


# The first failure's hints: the level's own, or (level 9) ones read off the
# design that failed, so a player who already used alert hears what else to
# change (review: "提示说试试警戒，可我已经用了").
func _hints() -> Array:
	if level.id == "2-5":
		return _boss_hints()
	if level.id == "3-1":
		return _alarm_hints()
	if level.id == "3-2":
		return _sync_hints()
	if level.id == "3-3":
		return _quorum_hints()
	if level.id == "3-4":
		return _echo_hints()
	if level.id == "4-1":
		return _phage_hints()
	if level.id == "4-2":
		return _memory_hints()
	if level.id == "4-3":
		return _latent_hints()
	if level.id == "4-4":
		return _virus_hints()
	if level.id == "4-5":
		return _giant_hints()
	if level.id == "5-1":
		return _slug_hints()
	if level.id == "5-2":
		return _colony_hints()
	if level.id == "5-3":
		return _armour_hints()
	if level.id == "5-4":
		return _regrow_hints()
	if level.id == "5-5":
		return _guardian_hints()
	if level.id != "2-4":
		return level.hints
	var p: Dictionary = runner.design.get("params", {})
	var deck: Array = p.get("deck", [])
	var way_in: Array = deck.filter(func(c: Dictionary) -> bool: return c.act == Rules.A_TO_ALERT)
	if way_in.is_empty():
		return ["细胞还没进入警戒就被抓了。打开「行为规则」，让它们发现伏刺时直接进入警戒。", level.hints[1]]
	var out := []
	if float(way_in[0].t1) < 75.0:
		out.append("警戒距离只有 %d µm，伏刺在 110 µm 外就会冲过来。距离可以再调远一点。" % int(way_in[0].t1))
	for c: Dictionary in deck:
		if int(c.get("st", 0)) == Rules.S_ALERT and c.act == Rules.A_TO_FORAGE and c.c1 == Rules.C_STATE_TIME and float(c.t1) > 14.0:
			out.append("细胞在警戒状态待了 %d 秒才恢复觅食。可以把时间缩短，少浪费点能量。" % int(c.t1))
	if float(p.get("speed", 3.0)) < 4.0:
		out.append("速度只有 %d 级，伏刺一加速就追上来了。试试提高速度。" % int(p.get("speed", 3.0)))
	# (The sim's sight: 30 + 24 µm a level.)
	var sight := 30.0 + 24.0 * float(p.get("vision", 2.0))
	if float(way_in[0].t1) > sight + 5.0:
		out.append("你把警戒距离设成了 %d µm，但细胞最多只能看到 %d µm。超过视野的部分不会生效。" % [int(way_in[0].t1), int(sight)])
	if out.is_empty():
		out.append("可以试试装「鞭毛」，让细胞逃跑时更快。")
	return out


func _stats() -> Dictionary:
	var st: Dictionary = runner.host.sim.get_stats()
	return st.species[runner.sp_index] if runner.sp_index < st.species.size() else {}


func _facts() -> Array:
	var out := []
	var s := _stats()
	var unit := "个" if level.has("colony") else "只"
	out.append("%s：%d %s　最高数量：%d %s　最终数量：%d %s" % ["开局数量" if level.goal.kind in ["clear_rival", "giant_limit"] else "初始投放", int(level.release.count), unit, eval.peak, unit, eval.alive, unit])
	if level.goal.kind == "coexist":
		out.append("%s　最高数量：%d 只　结束时：%d / %d 只" % [level.species[0].label, eval.peak, eval.alive, int(level.goal.n)])
		out.append("%s　最高数量：%d 只　结束时：%d / %d 只" % [level.species[1].label, eval.peak2, eval.alive2, int(level.goal.n2)])
	if level.goal.kind == "patches" and eval.patch_counts.size() > 0:
		# Patch by patch, as judged: the last 30 s on average, you : the rival.
		var parts := []
		for k in eval.patch_counts.size():
			var pc: Array = eval.patch_counts[k]
			var won: bool = pc[0] > pc[1] and pc[0] >= 3
			parts.append("%s 片 %d : %d（%s）" % ["ABC"[k], pc[0], pc[1], "你占优" if won else "对手占优"])
		out.append("最后 30 秒各藻场的平均数量（你 : 冰晶游丝）：%s。至少要在 %d 片占优；这次你占优 %d 片。" % ["，".join(parts), int(level.goal.n), eval.patches_won])
	# Chapter 6: the oxygen, the springs held, the food chain, the anaerobes poisoned.
	if level.goal.kind == "coexist3":
		for k in 3:
			var n_end: int = [eval.alive, eval.alive2, eval.alive3][k]
			out.append("%s　最高数量：%d 只　结束时：%d / %d 只" % [level.species[k].label, [eval.peak, eval.peak2, eval.peak3][k], n_end, int(level.goal[["n", "n2", "n3"][k]])])
	if level.world.has("oxygen"):
		out.append("结束时水里的平均氧气：%.1f%%（最高 %.1f%%）" % [eval.o2_mean * 100.0, eval.o2_peak * 100.0])
	if level.challenge.kind == "zones_held" and not eval.held.is_empty():
		out.append("三个热泉口的数量：%s（每个至少 %d 只）" % [" / ".join(eval.held.map(func(v: int) -> String: return str(v))), int(level.challenge.n)])
	if level.challenge.kind == "o2_deaths_max":
		out.append("%s　被氧气毒死：%d 只（上限 %d 只）　结束时还有 %d 只" % [level.species[1].label, eval.o2_dead, int(level.challenge.n), eval.alive2])
	if level.goal.kind == "alive_safe":
		out.append("被%s吃掉：%d 只（上限 %d 只）" % [str(level.get("eaten_by", "猎手")), eval.eaten, int(level.goal.eaten)])
	if level.goal.kind == "alive_phage":
		out.append("被裂囊针撑破 %d 只（上限 %d 只）。" % [eval.lysed, int(level.goal.lysed)])
	if level.has("slug"):
		var ss: Dictionary = eval.slug_stats
		out.append("%d 个聚合体出发；另有 %d 团同伴太少，又散开了。" % [int(ss.get("formed", 0)), int(ss.get("broke", 0))])
		out.append("热带烧掉 %d 只，%d 只牺牲成柄，%d 个孢子飞了出去。" % [int(ss.get("lost", 0)), int(ss.get("stalk", 0)), int(ss.get("spored", 0))])
	if level.goal.kind == "giant_limit":
		var gs: Dictionary = eval.giant_stats
		var over := eval.giants - int(level.goal.giant_max)
		out.append("结束时：巨毒囊 %d 颗（要压到 %d 以下%s），最多时 %d 颗。" % [maxi(eval.giants, 0), int(level.goal.giant_max), ("，只差 %d 颗" if float(over) < float(level.goal.giant_max) * 0.15 else "，超出 %d 颗") % over if over > 0 else "", eval.giant_peak])
		out.append("这次的噬毒体：爆发 %d · 复制 %d · 外壳 %d · 附着 %d%s。" % [int(runner.design.virus.burst), int(runner.design.virus.speed), int(runner.design.virus.shell), int(runner.design.virus.stick), "（先潜伏）" if runner.design.virus.get("temperate", false) else "（马上裂解）"])
		var gt := eval.shot_times.map(func(t: float) -> String: return "%d:%02d" % [int(t) / 60, int(t) % 60])
		out.append("投放病毒 %d 次%s。" % [eval.shots, "（%s）" % "、".join(gt) if not gt.is_empty() else ""])
		out.append("细胞一共吞下 %d 颗，其中 %d 座工厂被噬毒体夺走；结束时 %d 只细胞带着噬毒体。" % [int(gs.get("taken", 0)), int(gs.get("hijacked", 0)), int(gs.get("carriers", 0))])
	if level.goal.kind == "clear_rival":
		out.append("结束时：绒游丝 %d 只（要压到 %d 以下），你 %d 只。" % [maxi(eval.rival_alive, 0), int(level.goal.rival_max), eval.alive])
		var vd: Dictionary = runner.design.get("virus", {})
		if not vd.is_empty():
			out.append("这次的病毒：爆发 %d · 复制 %d · 外壳 %d · 附着 %d%s。" % [int(vd.burst), int(vd.speed), int(vd.shell), int(vd.stick), "（先潜伏）" if vd.get("temperate", false) else ""])
		var times := eval.shot_times.map(func(t: float) -> String: return "%d:%02d" % [int(t) / 60, int(t) % 60])
		out.append("投放病毒 %d 次%s，撑破 %d 只绒游丝。" % [eval.shots, "（%s）" % "、".join(times) if not times.is_empty() else "", eval.rival_lysed])
		if level.challenge.kind == "rival_under" and eval.rival_alive > int(level.challenge.n):
			out.append("附加挑战要压到 %d 只，这次差 %d 只。" % [int(level.challenge.n), eval.rival_alive - int(level.challenge.n)])
	if level.id == "4-2":
		out.append("结束时有记忆的细胞 %d 只；一共被撑破 %d 只。" % [eval.immune, eval.lysed])
		if not eval.storm0.is_empty():
			out.append("大爆发到来时你有 %d 只，其中 %d 只有记忆；之后被撑破 %d 只。" % [int(eval.storm0.alive), int(eval.storm0.immune), eval.lysed - int(eval.storm0.lysed)])
	if level.goal.kind == "outnumber":
		var rl: String = level.world.species[int(level.goal.rival)].label
		if eval.rival_dead >= 0.0:
			out.append("胜因：你把%s挤到了灭绝（%d:%02d）。" % [rl, int(eval.rival_dead) / 60, int(eval.rival_dead) % 60])
		else:
			if level.has("phage"):
				out.append("结束时：你 %d 只，%s %d 只。" % [eval.alive, rl, maxi(eval.rival_alive, 0)])
				out.append("你牺牲了 %d 只细胞，病毒撑破了 %d 只%s。" % [eval.lysed, eval.rival_lysed, rl])
			else:
				out.append("结束时：你 %d 只，%s %d 只；你被吞掉 %d 只。" % [eval.alive, rl, maxi(eval.rival_alive, 0), eval.eaten])
	# (Level 24's guardian says its own lines below.)
	if level.goal.kind == "boss" and not level.has("colony"):
		if eval.boss_dead >= 0.0:
			out.append("胜因：你饿死了%s（%d:%02d）；它一共吞掉你 %d 只。" % [level.world.species[int(level.goal.boss)].label, int(eval.boss_dead) / 60, int(eval.boss_dead) % 60, eval.eaten])
		elif eval.goal_met:
			out.append("胜因：第 4 分钟你生到了 %d 只，比它吃得快；结束时还有 %d 只巨噬者，一共吞掉你 %d 只。" % [eval.alive, maxi(eval.boss_alive, 0), eval.eaten])
		else:
			out.append("结束时还有 %d 只巨噬者；它们一共吞掉你 %d 只。" % [maxi(eval.boss_alive, 0), eval.eaten])
	if level.challenge.kind == "first_kill":
		out.append("首次捕食用时：%s" % ("%.0f 秒" % eval.first_kill if eval.first_kill >= 0.0 else "未成功"))
	if level.has("slug"):
		out.append("对岸藻场上最多同时有 %d 只（要 %d 只）。" % [eval.zone_peak, int(level.goal.n)])
	elif level.has("colony") and level.id == "5-5":
		var gs: Dictionary = eval.colony_stats
		out.append("结束时场上有 %d 个群体（要 %d 个），最多时 %d 个。" % [eval.alive, int(level.goal.n), eval.peak])
		var fate := "在 %d:%02d 饿死了" % [int(eval.boss_dead) / 60, int(eval.boss_dead) % 60] if eval.boss_dead >= 0.0 else "结束时还剩 %d%% 的能量" % roundi(100.0 * maxf(eval.boss_energy, 0.0))
		out.append("喷口守卫吞下你 %d 个群体，嚼不动吐出来 %d 个，磨裂 %d 块甲，真吃下去 %d 个；它%s。" % [int(gs.get("swallowed", 0)), int(gs.get("spat", 0)), int(gs.get("worn", 0)), int(gs.get("eaten", 0)), fate])
		if int(gs.get("irritated", 0)) > 0:
			out.append("你刺激了它的头冠 %d 次，从它嘴里救出 %d 个群体。" % [int(gs.get("irritated", 0)), int(gs.get("rescued", 0))])
		else:
			out.append("你一次也没刺激它的头冠。")
		return out
	elif level.has("colony") and level.id == "5-4":
		var rs: Dictionary = eval.colony_stats
		out.append("结束时场上有 %d 个群体（要 %d 个），最多时 %d 个。" % [eval.alive, int(level.goal.n), eval.peak])
		if int(rs.get("splits", 0)) > 0:
			out.append("巨噬者咬了 %d 口，咬残 %d 块，靠再生长回 %d 块；身体被咬断 %d 次，%d 个半截长回了完整的身体；%d 个群体被啃光。" % [int(rs.get("bites", 0)), int(rs.get("broken", 0)), int(rs.get("healed", 0)), int(rs.get("splits", 0)), int(rs.get("whole", 0)), int(rs.get("eaten", 0))])
		else:
			out.append("巨噬者咬了 %d 口，咬残 %d 块，靠再生长回 %d 块；%d 个群体被啃光。" % [int(rs.get("bites", 0)), int(rs.get("broken", 0)), int(rs.get("healed", 0)), int(rs.get("eaten", 0))])
		return out
	elif level.has("colony") and level.id == "5-3":
		var ks: Dictionary = eval.colony_stats
		out.append("结束时场上有 %d 个群体（要 %d 个），最多时 %d 个。" % [eval.alive, int(level.goal.n), eval.peak])
		out.append("巨噬者咬了 %d 口，%d 口咬在甲上被挡下；%d 个群体被啃光，%d 个饿死。" % [int(ks.get("bites", 0)), int(ks.get("blocked", 0)), int(ks.get("eaten", 0)), int(ks.get("starved", 0))])
		return out
	elif level.has("colony"):
		var cs: Dictionary = eval.colony_stats
		out.append("上游藻场上最多同时有 %d 个群体（要 %d 个）。" % [eval.zone_peak, int(level.goal.n)])
		out.append("破壳 %d 次，生出 %d 个子体。砂砾打死 %d 个子体，%d 个群体被冲进喷口。" % [int(cs.get("hatched", 0)), int(cs.get("born", 0)), int(cs.get("lost", 0)), int(cs.get("burned", 0))])
		return out
	elif level.goal.kind == "zone_count" or level.challenge.kind == "first_in":
		out.append("第一只抵达光照区：%s。" % ("%.0f 秒" % eval.first_in if eval.first_in >= 0.0 else "没有抵达"))
		out.append("光照区里最多同时有 %d 只。" % eval.zone_peak)
	if not s.is_empty():
		var dead: int = int(s.starved) + int(s.eaten) + int(s.aged) + int(s.temp) + int(s.acid) + int(s.phage) + int(s.get("o2", 0))
		if dead > 0:
			# Every cause there was, biggest first: what to fix next.
			var causes := []
			for c: Array in [["饥饿", s.starved], ["被捕食", s.eaten], ["自然衰老", s.aged], ["水温", s.temp], ["酸蚀", s.acid], ["被撑破", s.phage], ["氧气中毒", s.get("o2", 0)]]:
				if int(c[1]) > 0:
					causes.append([c[0], int(c[1])])
			causes.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1])
			var parts := causes.map(func(c: Array) -> String: return "%s：%d%%" % [c[0], roundi(100.0 * c[1] / dead)])
			out.append("累计死亡：%d 只　%s" % [dead, "　".join(parts)])
			out.append("主要死因：%s" % causes[0][0])
		out.append("累计分裂：%d 次" % int(s.births))
	if level.challenge.kind == "floor_after" and eval.min_after < (1 << 30):
		out.append("第一次脉冲之后，种群最低降到 %d 只。" % eval.min_after)
	return out


# --- drawing helpers ---------------------------------------------------------------------

class BigStar extends Control:
	var label := ""
	var note := "" # why it was missed (empty when earned)
	var earned := false
	var delay := 0.0
	var t := 0.0

	func _init() -> void:
		custom_minimum_size = Vector2(160, 146)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		if t < delay + 1.0:
			var before := t
			t += delta
			if earned and before < delay and t >= delay:
				Audio.sfx("star", 0.0, 1.0 + 0.12 * get_index())
			queue_redraw()

	func _draw() -> void:
		var c := Vector2(size.x * 0.5, 46)
		var k := clampf((t - delay) / 0.35, 0.0, 1.0)
		var pop := 1.0 + 0.25 * sin(k * PI) if earned else 1.0
		var pts := PackedVector2Array()
		for i in 10:
			var a := -PI / 2.0 + i * PI / 5.0
			var r := (34.0 if i % 2 == 0 else 14.0) * pop
			pts.append(c + Vector2(cos(a), sin(a)) * r)
		if earned and k > 0.0:
			draw_colored_polygon(pts, Color(Ui.ACCENT, k))
			draw_arc(c, 44.0 + 18.0 * k, 0.0, TAU, 48, Color(Ui.ACCENT, 0.4 * (1.0 - k)), 1.2, true)
		pts.append(pts[0])
		draw_polyline(pts, Ui.ACCENT if earned and k > 0.0 else Color(Ui.INK_FAINT, 0.8), 1.4, true)
		var f := Ui.sans(600)
		var ts := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
		draw_string(f, Vector2((size.x - ts.x) * 0.5, 114), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Ui.INK if earned else Ui.INK_FAINT)
		if note != "":
			var nf := Ui.sans(500)
			var nw := nf.get_string_size(note, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
			draw_string(nf, Vector2((size.x - nw) * 0.5, 136), note, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Ui.WARN)


class Chart extends Control:
	var eval: LevelEval
	var level: Dictionary

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r := Rect2(Vector2(36, 8), size - Vector2(46, 30))
		draw_rect(r, Color(1, 1, 1, 0.5), true)
		var top := 10.0
		for p: Array in eval.curve:
			top = maxf(top, float(p[1]))
			if (level.goal.has("rival") and level.has("phage")) or level.has("giant"):
				top = maxf(top, float(p[2]))
		var g: Dictionary = level.goal
		top = maxf(top, float(g.get("n", 0)) * 1.2)
		if g.kind == "alive_phage":
			top = maxf(top, maxf(float(eval.lysed), float(g.lysed)) * 1.15)
		var limit: float = level.time_limit
		var to := func(tt: float, v: float) -> Vector2:
			return Vector2(r.position.x + r.size.x * tt / limit, r.end.y - r.size.y * v / top)
		for k in 5:
			var y := r.end.y - r.size.y * k / 4.0
			draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), Color(Ui.LINE, 0.4), 1.0)
			draw_string(Ui.mono(), Vector2(0, y + 4), "%d" % int(top * k / 4.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Ui.INK_FAINT)
		for m in int(limit / 60.0) + 1:
			var x := r.position.x + r.size.x * m * 60.0 / limit
			draw_string(Ui.mono(), Vector2(x - 8, r.end.y + 16), "%d:00" % m, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Ui.INK_FAINT)
		# A population target only (a patch count is not a population).
		if g.kind == "giant_limit":
			var gy: float = to.call(0.0, float(g.giant_max)).y
			draw_dashed_line(Vector2(r.position.x, gy), Vector2(r.end.x, gy), Ui.WARN, 1.2, 6.0)
			draw_string(Ui.sans(600), Vector2(r.position.x + 6, gy - 6), "巨毒囊上限 %d" % int(g.giant_max), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Ui.WARN)
		for e: Dictionary in level.get("events", []):
			if e.kind == "giant_wave":
				var wx: float = to.call(float(e.at), 0.0).x
				draw_dashed_line(Vector2(wx, r.position.y), Vector2(wx, r.end.y), Color(0.5, 0.3, 0.8, 0.5), 1.0, 4.0)
				draw_string(Ui.sans(500), Vector2(wx + 4, r.position.y + 30), "+%d" % int(e.n), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.5, 0.3, 0.8))
		if g.kind == "clear_rival" or g.kind == "giant_limit":
			for st: float in eval.shot_times:
				var sx: float = to.call(st, 0.0).x
				draw_line(Vector2(sx, r.end.y), Vector2(sx, r.end.y - 16.0), Ui.ACCENT, 2.0, true)
				draw_circle(Vector2(sx, r.end.y - 18.0), 3.0, Ui.ACCENT)
			if not eval.shot_times.is_empty():
				var fx: float = to.call(float(eval.shot_times[0]), 0.0).x
				draw_string(Ui.sans(600), Vector2(fx + 6, r.end.y - 12.0), "投放病毒", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Ui.ACCENT)
		if g.kind == "clear_rival":
			var ry: float = to.call(0.0, float(g.rival_max)).y
			draw_dashed_line(Vector2(r.position.x, ry), Vector2(r.end.x, ry), Ui.WARN, 1.2, 6.0)
			draw_string(Ui.sans(600), Vector2(r.position.x + 6, ry - 6), "绒游丝上限 %d" % int(g.rival_max), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Ui.WARN)
		if g.has("n") and g.kind in ["alive_end", "zone_count", "alive_safe", "alive_phage"]:
			var gy: float = to.call(0.0, float(g.n)).y
			draw_dashed_line(Vector2(r.position.x, gy), Vector2(r.end.x, gy), Ui.WARN, 1.2, 6.0)
			draw_string(Ui.sans(600), Vector2(r.end.x - 70, gy - 6), "目标 %d" % int(g.n), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Ui.WARN)
		if g.kind == "alive_phage":
			var ly: float = to.call(0.0, float(g.lysed)).y
			draw_dashed_line(Vector2(r.position.x, ly), Vector2(r.end.x, ly), Ui.ALERT, 1.2, 6.0)
			draw_string(Ui.sans(600), Vector2(r.end.x - 86, ly - 6), "撑破上限 %d" % int(g.lysed), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Ui.ALERT)
			for p: Array in eval.curve:
				if float(p[2]) > float(g.lysed):
					var at: Vector2 = to.call(float(p[0]), float(p[2]))
					draw_circle(at, 4.0, Ui.ALERT)
					draw_string(Ui.sans(600), at + Vector2(-92, -8), "%d:%02d 越过上限" % [int(p[0]) / 60, int(p[0]) % 60], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Ui.ALERT)
					break
		var all := PackedVector2Array()
		var zone := PackedVector2Array()
		for p: Array in eval.curve:
			all.append(to.call(float(p[0]), float(p[1])))
			zone.append(to.call(float(p[0]), float(p[2])))
		if all.size() > 1:
			draw_polyline(all, Ui.ACCENT, 2.0, true)
			if g.kind == "zone_count":
				draw_polyline(zone, Ui.GOOD, 2.0, true)
			elif g.kind in ["coexist", "alive_phage"]:
				draw_polyline(zone, Ui.ALERT, 2.0, true) # the second species / the cells burst so far
			elif level.has("giant"):
				draw_polyline(zone, Color(0.5, 0.3, 0.8), 2.0, true) # the giants
			elif g.has("rival") and level.has("phage"):
				draw_polyline(zone, level.world.species[int(g.rival)].params.color, 2.0, true) # the rival
			elif level.get("close_up", "") == "memory":
				draw_polyline(zone, Ui.GOOD, 2.0, true) # the cells with the memory
				var bare := PackedVector2Array()
				for p: Array in eval.curve:
					bare.append(to.call(float(p[0]), float(p[1]) - float(p[2])))
				draw_polyline(bare, Ui.ALERT, 2.0, true) # and those without
		if g.kind == "coexist":
			draw_string(Ui.sans(600), r.position + Vector2(8, 16), level.species[0].label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Ui.ACCENT)
			draw_string(Ui.sans(600), r.position + Vector2(48, 16), level.species[1].label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Ui.ALERT)
		else:
			draw_string(Ui.sans(600), r.position + Vector2(8, 16), "你的细胞" if g.kind in ["clear_rival", "giant_limit"] else "种群", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Ui.ACCENT)
		if g.kind == "zone_count":
			draw_string(Ui.sans(600), r.position + Vector2(48, 16), "对岸" if level.has("slug") else ("上游" if level.has("colony") else "光照区内"), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Ui.GOOD)
		elif g.kind == "alive_phage":
			draw_string(Ui.sans(600), r.position + Vector2(48, 16), "累计被撑破", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Ui.ALERT)
		elif level.has("giant"):
			draw_string(Ui.sans(600), r.position + Vector2(76, 16), "巨毒囊", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.5, 0.3, 0.8))
		elif g.has("rival") and level.has("phage"):
			draw_string(Ui.sans(600), r.position + Vector2(76 if g.kind == "clear_rival" else 48, 16), level.world.species[int(g.rival)].label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, level.world.species[int(g.rival)].params.color)
		elif level.get("close_up", "") == "memory":
			draw_string(Ui.sans(600), r.position + Vector2(48, 16), "有记忆", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Ui.GOOD)
			draw_string(Ui.sans(600), r.position + Vector2(100, 16), "没有记忆", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Ui.ALERT)
			for e: Dictionary in level.get("events", []):
				if e.kind == "phage_storm":
					var sx: float = to.call(float(e.at), 0.0).x
					draw_dashed_line(Vector2(sx, r.position.y), Vector2(sx, r.end.y), Ui.ALERT, 1.2, 6.0)
					draw_string(Ui.sans(600), Vector2(sx - 44, r.position.y + 32), "大爆发", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Ui.ALERT)


# Level 10: what the failed design did about the devourer: fed it (it
# split), let it near (flee distance, speed), or never bred fast.
func _boss_hints() -> Array:
	var p: Dictionary = runner.design.get("params", {})
	var deck: Array = p.get("deck", [])
	var out := []
	if runner.eval.boss_alive > 1:
		out.append("巨噬者分裂成了 %d 只：它吃得越多分裂越多，别让它靠近你的群。" % runner.eval.boss_alive)
	var flee: Array = deck.filter(func(c: Dictionary) -> bool: return int(c.get("st", 0)) == Rules.S_FORAGE and c.act == Rules.A_FLEE)
	if flee.is_empty():
		out.append("觅食里没有逃离的卡：巨噬者过来时它们只会原地等着被吞。")
	elif float(flee[0].t1) < 75.0:
		out.append("觅食里“猎手靠近 → 逃离”只有 %d µm：巨噬者 138 µm 外就看见你，拉远一些。" % int(flee[0].t1))
	if float(p.get("speed", 3.0)) < 4.0:
		out.append("速度只有 %d 级：巨噬者是 3 级，比它快才甩得掉。" % int(p.get("speed", 3.0)))
	if not deck.any(func(c: Dictionary) -> bool: return c.act == Rules.A_TO_BREED):
		out.append("没用“繁殖期”：4 分钟生到 %d 只，平常的分裂速度不够。" % int(level.goal.n))
	if out.is_empty():
		out.append("再试一次，或者把繁殖期的“在本状态超过 20 秒”调长一些。")
	return out


# Level 11: what the failed design missed of the alarm: the organs, the
# shout, the "smell -> flee" card (and its place above feeding), the speed.
func _alarm_hints() -> Array:
	var p: Dictionary = runner.design.get("params", {})
	var deck: Array = p.get("deck", []).filter(func(c: Dictionary) -> bool: return int(c.get("st", 0)) == Rules.S_FORAGE)
	var organs: Array = p.get("organs", [])
	# Directions first (review: the first layer spelt out the cards; the
	# exact fixes are behind “直接看具体做法”).
	var out := []
	if not (organs.has("gland") and organs.has("chemo_rec")):
		out.append("要喊得有会喊的器官，要听得有会闻的器官。")
	if not deck.any(func(c: Dictionary) -> bool: return c.act == Rules.A_EMIT_A):
		out.append("看见暗噬的那只只顾自己逃，没告诉同伴。")
	var sf := deck.find_custom(func(c: Dictionary) -> bool: return c.act == Rules.A_FLEE and Rules.C_SIGNAL_A in [c.c1, c.c2])
	var sa := deck.find_custom(func(c: Dictionary) -> bool: return c.act == Rules.A_SEEK_ALGAE)
	if sf < 0:
		out.append("同伴闻到了警报，却没有一张卡让它跑。")
	elif sa >= 0 and sf > sa:
		out.append("闻到警报就跑的那张卡排得太靠下：规则从上往下看，饿着的会先去吃。")
	if float(p.get("speed", 3.0)) < 4.0:
		out.append("跑得不比暗噬快，听到警报也来不及。")
	if out.is_empty():
		out.append("做得不错，再试一次。想让同伴更早逃，就把“信号 A 浓”那张卡上的滑块往左拖一点。")
	return out


# Level 12: what the failed design missed of breeding together (directions
# only; the cards are behind “直接看具体做法”).
func _sync_hints() -> Array:
	var p: Dictionary = runner.design.get("params", {})
	var deck: Array = p.get("deck", [])
	var forage: Array = deck.filter(func(c: Dictionary) -> bool: return int(c.get("st", 0)) == Rules.S_FORAGE)
	var organs: Array = p.get("organs", [])
	var out := []
	if not organs.has("recog"):
		out.append("你的生命认不出同伴在做什么：要有能认出同伴状态的器官。")
	if not deck.any(func(c: Dictionary) -> bool: return c.act == Rules.A_TO_BREED):
		out.append("一直在平常的状态里慢慢分裂：繁殖期生得快得多。")
	elif not forage.any(func(c: Dictionary) -> bool: return c.act == Rules.A_TO_BREED and Rules.C_PEER_STATE in [c.c1, c.c2]):
		out.append("大家各生各的，零零散散，急梭吃得过来：让看见同伴在生的也跟着生。")
	if float(p.get("fertility", 3.0)) < 3.0:
		out.append("繁殖调低了：这关比的就是一起生得多。")
	if out.is_empty():
		# The right plan, lost: say which way it fell short, and what to turn.
		var ev: LevelEval = runner.eval
		if ev.eaten > int(level.goal.eaten):
			out.append("差一点，可被吃了 %d 只，超了：一批生得还不够多。把繁殖调高，让它们同一刻多生些，急梭就更吃不过来了。" % ev.eaten)
		elif ev.alive < int(level.goal.n):
			out.append("种群还差 %d 只：把繁殖调高，代谢调到 3–4 级，让每一批生得更多。" % (int(level.goal.n) - ev.alive))
		else:
			out.append("路子对了，再试一次。")
	return out


# Level 13: secreting alone (wasted), never, or with too low a crowd (directions).
func _quorum_hints() -> Array:
	var p: Dictionary = runner.design.get("params", {})
	var forage: Array = p.get("deck", []).filter(func(c: Dictionary) -> bool: return int(c.get("st", 0)) == Rules.S_FORAGE)
	var sec: Array = forage.filter(func(c: Dictionary) -> bool: return c.act == Rules.A_SECRETE)
	var out := []
	if sec.is_empty():
		out.append("一直在自己啃硬藻：只吸收得了四成。要让酶把它化开。")
	else:
		var cr := -1.0
		for c: Dictionary in sec:
			for k in [1, 2]:
				if c["c%d" % k] == Rules.C_CROWD and not c.get("n%d" % k, false):
					cr = maxf(cr, float(c["t%d" % k]))
		if cr < 0.0:
			out.append("落单的时候也在分泌：酶全散掉了，能量白花。先数数身边的同伴。")
		elif cr < 3.0:
			out.append("同伴才 %d 个就开始分泌：酶还不够浓。把门槛提高一点。" % int(cr))
		var si := forage.find(sec[0])
		var sa := forage.find_custom(func(c: Dictionary) -> bool: return c.act == Rules.A_SEEK_ALGAE)
		if sa >= 0 and si > sa:
			out.append("分泌的那张卡排在“游向藻团”下面：饿着的先去吃，就轮不到它。")
	if out.is_empty():
		var short: int = int(level.goal.n) - int(runner.eval.alive)
		if short > 0 and not runner.eval.extinct:
			out.append("种群还差 %d 只：繁殖调到 4 级以上，速度调到 3–4 级（赶到藻场更快），外壳调到最低，省下预算。" % short)
		else:
			out.append("再试一次。繁殖调高，速度调到 3–4 级会更稳。")
	return out


# Level 15: no spreading out, a threshold too high, or a card that never gets
# its turn (directions).
func _phage_hints() -> Array:
	var p: Dictionary = runner.design.get("params", {})
	var forage: Array = p.get("deck", []).filter(func(c: Dictionary) -> bool: return int(c.get("st", 0)) == Rules.S_FORAGE)
	var ev: LevelEval = runner.eval
	var away := -1
	var seek := -1
	for k in forage.size():
		if away < 0 and forage[k].act == Rules.A_DISPERSE:
			away = k
		if seek < 0 and forage[k].act == Rules.A_SEEK_ALGAE:
			seek = k
	var follow := forage.any(func(c: Dictionary) -> bool: return c.act == Rules.A_FOLLOW)
	if away < 0:
		return ["细胞还在往一起凑：“跟随同伴”正好帮了裂囊针。换成让它们一见到同伴就游开。" if follow else "细胞挤在一起，一只爆开就传给一片。让它们一见到同伴就游开。"]
	var out := []
	if follow:
		out.append("“跟随同伴”和“远离同伴”在互相打架：删掉跟随那张。")
	var c: Dictionary = forage[away]
	if seek >= 0 and seek < away:
		out.append("“远离同伴”排在“游向藻团”下面：看见藻团就去吃，轮不到散开。把它往上挪。")
	var t := float(c.t1) if c.c1 == Rules.C_CROWD else (float(c.t2) if c.c2 == Rules.C_CROWD else 99.0)
	if t > 4.0 and t < 99.0:
		out.append("“同伴很多”的门槛是 %d：挤到这么多才散，已经传开了。往左拖。" % int(t))
	if out.is_empty():
		if ev.lysed > int(level.goal.lysed):
			out.append("方向没错，但种群超了 %d 只：把门槛往左拖，让它们早点散开。" % ev.lysed)
		elif ev.alive < int(level.goal.n):
			out.append("方向没错，但种群还差 %d 只：把繁殖调高一点，散开以后也能更快繁殖。" % (int(level.goal.n) - ev.alive))
		else:
			out.append("方向没错，再试一次。")
	return out


# Level 20, won: what the gathering cost and what it bought.
func _slug_win() -> Array:
	var ss: Dictionary = eval.slug_stats
	var out := ["单只细胞过不了热带，聚合体能过：%d 个聚合体出发，外层 %d 只替里面挡了热。" % [int(ss.get("formed", 0)), int(ss.get("lost", 0))]]
	out.append("%d 只细胞牺牲成柄，换来 %d 个孢子。盘基网柄菌也是这样：一部分细胞死去，让其余的活下去。" % [int(ss.get("stalk", 0)), int(ss.get("spored", 0))])
	if not eval.challenge_met():
		out.append("附加挑战差一点：第 4 分钟时对岸还不够多。试试把“同伴很多”的门槛调到 3：聚合体出发得更早。")
	return out


# Level 20: never gathered, gathered well fed, too small, or short (directions).
func _slug_hints() -> Array:
	var ev: LevelEval = runner.eval
	var s: Dictionary = ev.slug_stats
	var deck: Array = runner.design.get("params", {}).get("deck", [])
	var cards: Array = deck.filter(func(c: Dictionary) -> bool: return c.act == Rules.A_AGGREGATE)
	if cards.is_empty():
		return ["细胞一直各吃各的，直到饿死。第 2 张卡的动作还没换成“聚合”。"]
	if ev.extinct and not cards.any(func(c: Dictionary) -> bool: return Rules.C_ENERGY_BELOW in [c.c1, c.c2]):
		return ["细胞不饿也去聚合，藻场上没人吃东西，种群断了。给“聚合”加一个条件：饿了才去。"]
	if not deck.any(func(c: Dictionary) -> bool: return c.act == Rules.A_EMIT_A):
		return ["没有人放信号，细胞各聚各的，一个个小团都烧死在热带里。把“释放信号 A”放回来。"]
	if int(s.get("spored", 0)) == 0:
		return ["聚合体都太小，没爬过热带：烧掉了 %d 只。过热带每秒要损失一只，一个聚合体至少要三四十只。" % int(s.get("lost", 0))]
	return ["有 %d 个孢子落到了对岸，发芽的还不够。聚得更晚一点，留在藻场上的细胞多吃一会儿，聚合体会更大。" % int(s.get("spored", 0))]


# Level 21, won: what the division of labour cost and what it bought.
func _colony_win() -> Array:
	match level.id:
		"5-3": return _armour_win()
		"5-4": return _regrow_win()
		"5-5": return _guardian_win()
	var cs: Dictionary = eval.colony_stats
	var out := ["鞭毛在外缘划水，生殖块躲在里面：和团藻一样，一个身体分了工。"]
	out.append("%d 次破壳，生出 %d 个子体。每破壳一次，亲体的体细胞就死去一次：团藻里不到 1%% 的细胞能进入下一代。" % [int(cs.get("hatched", 0)), int(cs.get("born", 0))])
	if not eval.challenge_met():
		out.append("附加挑战差一点：试试只放 2 个生殖块，或者用洋流引导把群体朝上游送一程。")
	if eval.blocks_used > int(level.star_blocks):
		out.append("第三颗星要 %d 块以内：试试排成 1 格宽的细条，放 2 个生殖块。推力够，只是吃得慢。" % int(level.star_blocks))
	return out


# Level 22, won: what the armour turned away and what the store carried.
func _armour_win() -> Array:
	var cs: Dictionary = eval.colony_stats
	var bites := int(cs.get("bites", 0))
	var blocked := int(cs.get("blocked", 0))
	var s: Dictionary = Colony.stats(runner.design.get("params", {}).get("blocks", []))
	var out := []
	if blocked > 0:
		out.append("巨噬者咬了 %d 口，%d 口咬在甲上，只掉了一点点能量：外面一层角质，和水熊虫一样。" % [bites, blocked])
	else:
		out.append("身体没有甲，巨噬者咬了 %d 口，口口都是一大块；你靠数量扛了过去。" % bites)
	if int(s.store) > 0:
		out.append("荒年里藻类停长，储能块里存着的能量撑过去；饿死 %d 个，被啃光 %d 个。" % [int(cs.get("starved", 0)), int(cs.get("eaten", 0))])
	else:
		out.append("身体里没有储能块，荒年饿死了 %d 个；被啃光 %d 个。" % [int(cs.get("starved", 0)), int(cs.get("eaten", 0))])
	if not eval.challenge_met():
		var by := int(level.challenge.by)
		out.append("附加挑战差一点：荒年开始到 %d:%02d，群体最少时只有 %d 个（要 %d 个）。外缘甲挡得多、储能块存得多，低谷就浅。" % [by / 60, by % 60, eval.floor_low(float(level.challenge.from), float(level.challenge.by)), int(level.challenge.n)])
	if eval.blocks_used > int(level.star_blocks):
		out.append("第三颗星要 %d 块以内：还要再少 %d 块。" % [int(level.star_blocks), eval.blocks_used - int(level.star_blocks)])
	return out


# Level 23, won: what was broken and what the regeneration block grew back.
func _regrow_win() -> Array:
	var cs: Dictionary = eval.colony_stats
	var s: Dictionary = Colony.stats(runner.design.get("params", {}).get("blocks", []))
	var out := []
	if int(cs.get("healed", 0)) > 0:
		out.append("巨噬者咬残了 %d 块，%d 块靠再生块 15 秒就长了回来；其余的要么慢慢自己长，要么跟着被啃光的群体没了。" % [int(cs.get("broken", 0)), int(cs.get("healed", 0))])
	else:
		out.append("巨噬者咬残了 %d 块，都只能慢慢自己长：每块要三分钟，伤口一直耗能。" % int(cs.get("broken", 0)))
	if int(s.store) == 0 and int(s.germ) >= 3:
		out.append("储能块换回了生殖块：没有荒年，存粮用不上，多生一个更划算。")
	if int(cs.get("splits", 0)) > 0:
		out.append("身体被咬断 %d 次，%d 个半截长成了完整的群体，和切开的涡虫一样。" % [int(cs.get("splits", 0)), int(cs.get("whole", 0))])
	if not eval.challenge_met():
		out.append("附加挑战差一点：被咬残的 %d 块里，靠再生块长回的只有 %d%%（要 %d%%）。再生块自己别被咬残，紧挨着后排的甲角最安全。" % [int(cs.get("broken", 0)), roundi(100.0 * int(cs.get("healed", 0)) / maxf(1.0, float(cs.get("broken", 0)))), int(level.challenge.n)])
	return out


# Level 24, won: what it swallowed, what it could not chew, how it ended.
func _guardian_win() -> Array:
	var cs: Dictionary = eval.colony_stats
	var sw := int(cs.get("swallowed", 0))
	var spat := int(cs.get("spat", 0))
	var out := []
	# (When its frenzy began, as the run saw it.)
	var rage_at: float = float(runner.fired.get("rage_t", INF))
	var ate := int(cs.get("eaten", 0))
	var when := "%d:%02d" % [int(eval.boss_dead) / 60, int(eval.boss_dead) % 60]
	if sw == 0:
		out.append("喷口守卫一个群体也没吞到：你的群体都躲开了它的吸流。")
	elif ate == 0:
		out.append("喷口守卫吞下 %d 个群体，个个外缘有 4 块好甲，它嚼不动，只好全吐出来：每吐一次都白费一顿力气。" % sw)
	else:
		out.append("喷口守卫吞下 %d 个群体，吐出来 %d 个，真吃下去 %d 个：外缘好甲不到 4 块的都被嚼碎了。" % [sw, spat, ate])
	if eval.boss_dead >= 0.0:
		var fed := "它一口没吃上" if ate == 0 else "它只吃上 %d 顿" % ate
		var mad := "，饿到暴走，又扛了 %d 秒" % roundi(eval.boss_dead - rage_at) if rage_at < eval.boss_dead else ""
		out.append("%s%s，在 %s 饿死了。轮虫的咀嚼器磨得碎藻，磨不穿完好的角质。" % [fed, mad, when])
	else:
		out.append("它没饿死，可你在它嘴边繁衍到了 %d 个群体。" % eval.alive)
	if not eval.challenge_met():
		var by := float(level.challenge.get("by", INF))
		var fed := "" if ate == 0 else "它吃下的 %d 顿让它多撑了很久。" % ate
		var lever := "它每吐一次都掉一截能量，吃上一顿却能撑很久：它嚼着群体时按 %s 点它的头部，它会吐出来，还掉一截能量。" % Keys.name_of(Keys.code("current"))
		if eval.boss_dead >= by:
			out.append("附加挑战差 %d 秒：它 %d:%02d 才饿死，要在 %d:%02d 之前。%s%s" % [ceili(eval.boss_dead - by), int(eval.boss_dead) / 60, int(eval.boss_dead) % 60, int(by) / 60, int(by) % 60, fed, lever])
		else:
			out.append("附加挑战没拿到：要在 %d:%02d 之前让它饿死。%s%s" % [int(by) / 60, int(by) % 60, fed, lever])
	if eval.blocks_used > int(level.star_blocks):
		out.append("第三颗星要 %d 块以内：还要再少 %d 块。" % [int(level.star_blocks), eval.blocks_used - int(level.star_blocks)])
	return out


# Level 21: what held this body back, the biggest thing first (directions).
func _colony_hints() -> Array:
	var cells: Array = runner.design.get("params", {}).get("blocks", [])
	var s: Dictionary = Colony.stats(cells)
	var flow: float = (level.colony.stream as Vector2).length()
	var cs: Dictionary = eval.colony_stats
	if int(s.germ) == 0:
		return ["这个身体没有生殖块，一个后代也留不下。至少放 2 块。"]
	if int(s.germ) == 1:
		return ["只有 1 个生殖块：每代只生 1 个，数量涨不起来。至少放 2 块。"]
	if float(s.speed) <= flow:
		if int(s.walled) > 0:
			return ["推力 %.0f，水流 %.0f：顶不住。有 %d 块鞭毛被包在里面，把它们换到外缘。" % [s.speed, flow, s.walled]]
		return ["推力 %.0f，水流 %.0f：顶不住。少放一个生殖块换成鞭毛，或者把身体排窄一点。" % [s.speed, flow]]
	if float(s.speed) - flow < Colony.MIN_NET:
		return ["推力 %.0f，水流 %.0f：顶得住，但游得太慢，到不了上游。生殖块少放一点，或者把身体排窄一点。" % [s.speed, flow]]
	if int(cs.get("lost", 0)) >= 8 and int(s.unsafe) > 0:
		return ["砂砾打死了 %d 个子体：有 %d 个生殖块前面没有东西挡。把它们挪到别的块后面。" % [int(cs.lost), s.unsafe]]
	return ["上游藻场上最多 %d 个，差 %d 个。身体宽一点吃得更快，生殖块多一点每代生得更多，试着调调。" % [eval.zone_peak, int(level.goal.n) - eval.zone_peak]]


# Level 24, lost: was it fed, and why.
func _guardian_hints() -> Array:
	var cells: Array = runner.design.get("params", {}).get("blocks", [])
	var s: Dictionary = Colony.stats(cells)
	var cs: Dictionary = eval.colony_stats
	var rim := int(s.armor) - int(s.armor_walled)
	var why := _guardian_why(s, cs, rim)
	if eval.extinct:
		why.push_front("你的群体先灭绝了，喷口守卫还剩 %d%% 的能量。" % roundi(100.0 * clampf(eval.boss_energy, 0.0, 1.0)))
	return why


func _guardian_why(s: Dictionary, cs: Dictionary, rim: int) -> Array:
	if rim < 4:
		return ["外缘只有 %d 块甲：它吞了 %d 个，一个也没吐出来，一直吃得饱饱的。外缘放够 4 块甲，它就嚼不动了。" % [rim, int(cs.get("swallowed", 0))]]
	if int(s.germ) < 2:
		return ["生殖块少于 2 个：生得太慢。"]
	var ate := int(cs.get("eaten", 0))
	if ate > 0 and int(s.regen) == 0:
		return ["它吃下 %d 个裂了甲的群体：被吐出来时会裂一块甲，长好之前再被吞就嚼得动了。放一块再生块，裂了的甲长得快。" % ate]
	if ate > 0:
		return ["它吃下 %d 个裂了甲的群体，每吃一顿就能多撑好一阵。裂甲群体快被吸回去时刺激它的头部，那个群体能脱身；外缘多一块甲，被吐出后安全的时间也更长。" % ate]
	var left := roundi(100.0 * clampf(eval.boss_energy, 0.0, 1.0))
	if int(cs.get("starved", 0)) > 0:
		return ["它吐出来 %d 个，还剩 %d%% 的能量时你的群体先撑不住了：荒年里饿死了 %d 个。储能块、再生块都帮得上。" % [int(cs.get("spat", 0)), left, int(cs.get("starved", 0))]]
	return ["它吐出来 %d 个，还剩 %d%% 的能量时你的群体先撑不住了：它的吸流把群体拖离藻场，生得比死得慢。生殖块多一个，或外缘多一块甲让它更早放过你。" % [int(cs.get("spat", 0)), left]]


# Level 23, lost: what the bites broke, and how fast it came back.
func _regrow_hints() -> Array:
	var cells: Array = runner.design.get("params", {}).get("blocks", [])
	var s: Dictionary = Colony.stats(cells)
	var cs: Dictionary = eval.colony_stats
	if int(s.germ) < 2:
		return ["生殖块少于 2 个：每代生得太少，补不上被吃掉的。"]
	if int(s.regen) == 0:
		return ["没有再生块：咬残的 %d 块都要慢慢自己长。放一块再生块，全身的伤都长回得快 12 倍；紧挨着后排甲角最安全。" % int(cs.get("broken", 0))]
	if int(s.armor) - int(s.armor_walled) == 0:
		return ["外缘一块甲也没有：每一口都咬残一块。后排两角放上甲。"]
	return ["%d 个群体被啃光，咬残了 %d 块，靠再生长回 %d 块：再生块紧挨着后排的甲角，从后面追来的巨噬者先咬到甲；生殖块要有 3 个。" % [int(cs.get("eaten", 0)), int(cs.get("broken", 0)), int(cs.get("healed", 0))]]


# Level 22, lost: the hunters or the famine, and what in the body let them.
func _armour_hints() -> Array:
	var cells: Array = runner.design.get("params", {}).get("blocks", [])
	var s: Dictionary = Colony.stats(cells)
	var cs: Dictionary = eval.colony_stats
	if int(s.germ) < 2:
		return ["生殖块少于 2 个：每代生得太少，补不上被吃掉的。"]
	if int(s.armor) - int(s.armor_walled) == 0:
		return ["外缘一块甲也没有：巨噬者咬了 %d 口，口口都是一大块，%d 个群体被啃光。在后排两角放上甲块。" % [int(cs.get("bites", 0)), int(cs.get("eaten", 0))]]
	if int(s.armor_walled) > 0:
		return ["有 %d 块甲被包在里面，挡不到猎手：挪到外缘。" % int(s.armor_walled)]
	if int(s.store) == 0 and int(cs.get("starved", 0)) >= 3:
		return ["荒年饿死了 %d 个群体：身体里没有储能块。拿正中间的生殖块换一个储能块，藏在里面咬不到。" % int(cs.starved)]
	if int(cs.get("eaten", 0)) > int(cs.get("starved", 0)):
		var bites := int(cs.get("bites", 0))
		return ["%d 个群体被啃光：%d 口里只有 %d 口咬在甲上。甲放在最常挨咬的后排两角；甲太多鞭毛就少，游得慢，反而更难。" % [int(cs.eaten), bites, int(cs.get("blocked", 0))]]
	return ["荒年饿死了 %d 个群体：储能块可以再多一个。" % int(cs.get("starved", 0))]


# Level 19, won: what the virophage did, and how far the extra star was.
func _giant_win() -> Array:
	var gs: Dictionary = eval.giant_stats
	var out := ["噬毒体闯进了 %d 座工厂，巨毒囊因此少造了约 %d 颗。" % [int(gs.get("hijacked", 0)), int(gs.get("saved", 0))]]
	if int(gs.get("carriers", 0)) > 0:
		out.append("结束时 %d 只细胞的基因里带着噬毒体：巨毒囊一被吞下，它们的工厂一开始就是噬毒体的。" % int(gs.carriers))
	if not eval.challenge_met():
		out.append("附加挑战还差一步：结束时还剩 %d 颗。工厂之外，水里的巨毒囊也能用投放追着清。" % maxi(eval.giants, 0))
	if eval.shots > int(level.star_shots):
		out.append("这次投放了 %d 次：第三颗星最多 %d 次。" % [eval.shots, int(level.star_shots)])
	return out


# Level 19: never dropped, close, or a form that can't keep up (directions).
func _giant_hints() -> Array:
	var ev: LevelEval = runner.eval
	var v: Dictionary = runner.design.get("virus", {})
	if ev.shots == 0:
		return ["你设计了噬毒体，却一次也没有投放：运行时点右下角“投放病毒”，再点培养皿。"]
	var over := ev.giants - int(level.goal.giant_max)
	var slow := int(v.speed) <= 3
	var take := int(LevelEval.virus_params(v).burst)
	if over > 0 and float(over) < float(level.goal.giant_max) * 0.15:
		return ["只差 %d 颗，方向是对的。%s" % [over, "噬毒体要 %d 秒才能夺走工厂：复制速度再高一点，巨毒囊就造得更少。" % take if slow else "把爆发量调高一点，每座被夺走的工厂会放出更多噬毒体。"]]
	if bool(v.get("temperate", false)):
		if slow:
			return ["噬毒体醒来后要 %d 秒才能夺走工厂，巨毒囊已经造出一大半了。看看设计页的“复制速度”。" % take]
		if ev.shot_times[0] > 25.0:
			return ["第 %d 秒才投放：先潜伏要赶在第一批工厂前面，趁细胞还少、还挤在一起。" % int(ev.shot_times[0])]
		if ev.shots == 1:
			return ["这次只投了 1 团，结束时 %d 只细胞里只有 %d 只带着噬毒体，没带的细胞还在替巨毒囊开工厂。第三颗星允许投 3 次：趁早再补一团。" % [ev.alive, int(ev.giant_stats.get("carriers", 0))]]
		return ["结束时只有 %d 只细胞带着噬毒体：投在你的细胞最密的地方，每一只接种的细胞都会把它传给后代。" % int(ev.giant_stats.get("carriers", 0))]
	if slow:
		return ["噬毒体要 %d 秒才能夺走工厂，来不及了。看看设计页的“复制速度”。" % take]
	return ["工厂长在你的细胞身体里，投放只能一团一团地追。有没有办法让噬毒体提前等在那里？"]


# Level 18: never dropped, spent too thin, or a virus with no staying power
# let go too early (directions).
func _virus_hints() -> Array:
	var ev: LevelEval = runner.eval
	var v: Dictionary = runner.design.get("virus", {})
	if ev.shots == 0:
		return ["你设计了病毒，却一次也没有投放：运行时点右下角“投放病毒”，再点培养皿。"]
	if bool(v.get("temperate", false)):
		return ["先潜伏不杀细胞：绒游丝吃得饱，它就一直睡着。这一关要的是马上裂解。"]
	var first: float = ev.shot_times[0] if not ev.shot_times.is_empty() else 0.0
	var life: float = LevelEval.virus_params(v).get("life", 16.0)
	if life <= 8.0 and first < 90.0:
		return ["这种病毒在水里只活 %d 秒，第 %d 秒投放时绒游丝还很稀：它碰不到几只就散了。要么让它活得久，要么晚点放。" % [int(life), int(first)]]
	if first > 170.0:
		return ["第 %d 秒才投放，绒游丝已经长满了，病毒传开也来不及压下去。早点放。" % int(first)]
	if ev.rival_lysed < 200:
		return ["病毒只撑破了 %d 只：放在绒游丝最密的地方，它们挤在一起才传得开。" % ev.rival_lysed]
	return ["对手还剩 %d 只，已经快压住它们了。试试把外壳再做结实一点，或者换个投放时机。" % maxi(ev.rival_alive, 0)]


# Level 17: nobody woken on purpose, too late, too soon (directions).
func _latent_hints() -> Array:
	var p: Dictionary = runner.design.get("params", {})
	var forage: Array = p.get("deck", []).filter(func(c: Dictionary) -> bool: return int(c.get("st", 0)) == Rules.S_FORAGE)
	var wake: Array = forage.filter(func(c: Dictionary) -> bool: return c.act == Rules.A_INDUCE)
	if wake.is_empty():
		return ["潜伏针一直在睡：你的细胞老死了也没用上它。让快老死的细胞把它叫醒。"]
	var c: Dictionary = wake[0]
	var age := float(c.t1) if c.c1 == Rules.C_AGE_ABOVE else (float(c.t2) if c.c2 == Rules.C_AGE_ABOVE else -1.0)
	if age < 0.0:
		return ["唤醒的细胞太多，你自己也在一批批爆开：只让快老死的细胞动手，用“年龄超过”。"]
	if age >= 0.85:
		return ["年龄门槛是 %d%%：细胞等到这时候才醒，病毒还没造完，它就老死了。往左拖。" % roundi(age * 100.0)]
	if age < 0.5:
		return ["年龄门槛是 %d%%：细胞还年轻就爆了，生得不够多。往右拖。" % roundi(age * 100.0)]
	return ["再试一次，把繁殖调高一点，生得比绒游丝快。"]


# Level 16: no memory organ, everyone still hiding, or nobody hiding (directions).
func _memory_hints() -> Array:
	var p: Dictionary = runner.design.get("params", {})
	var forage: Array = p.get("deck", []).filter(func(c: Dictionary) -> bool: return int(c.get("st", 0)) == Rules.S_FORAGE)
	var ev: LevelEval = runner.eval
	if not (p.get("organs", []) as Array).has("crispr"):
		return ["没有记忆片段，一只都记不住：大爆发来的时候，人人都是第一次见它。"]
	var away: Array = forage.filter(func(c: Dictionary) -> bool: return c.act == Rules.A_DISPERSE)
	if not away.is_empty():
		var c: Dictionary = away[0]
		var only: bool = (c.c1 == Rules.C_IMMUNE and c.get("n1", false)) or (c.c2 == Rules.C_IMMUNE and c.get("n2", false))
		if not only:
			return ["有记忆的细胞也在躲：它们本来不用怕，却一直散开，吃得少、生得慢。给“远离同伴”加个条件，让它只管还没有记忆的细胞。"]
	if ev.alive >= int(level.goal.n) and ev.lysed > int(level.challenge.n):
		return ["过了，但撑破了 %d 只：没记忆的细胞没有躲，是拿命换来的免疫。让它们先散开。" % ev.lysed]
	return ["再试一次，把繁殖调高一点，让有记忆的后代铺得更快。"]


# Chapter 3 boss: still trusting signal A (the echo's fake alarm), a B alarm
# that scares itself, or no alarm at all (directions).
func _echo_hints() -> Array:
	var p: Dictionary = runner.design.get("params", {})
	var forage: Array = p.get("deck", []).filter(func(c: Dictionary) -> bool: return int(c.get("st", 0)) == Rules.S_FORAGE)
	var out := []
	if forage.any(func(c: Dictionary) -> bool: return c.act == Rules.A_FLEE and Rules.C_SIGNAL_A in [c.c1, c.c2]):
		out.append("你的生命一闻到信号 A 就逃——可放 A 的大多是回声菌群：假警报。换一种它说不出口的信号。")
	var b: Array = forage.filter(func(c: Dictionary) -> bool: return c.act == Rules.A_FLEE and Rules.C_SIGNAL_B in [c.c1, c.c2])
	if not b.is_empty():
		var t := float(b[0].t1) if b[0].c1 == Rules.C_SIGNAL_B else float(b[0].t2)
		if t < 0.3:
			out.append("“信号 B 浓”的门槛只有 %.2f：喊完的那只会被自己的气味吓跑。往右拖一点。" % t)
	elif not forage.any(func(c: Dictionary) -> bool: return c.act in [Rules.A_EMIT_A, Rules.A_EMIT_B]):
		out.append("暗噬一来，一只看见了也救不了别的：没人报警，同伴全被吞了。")
	if out.is_empty():
		if float(p.get("speed", 3.0)) < 4.0:
			out.append("速度只有 %d 级：跑不过暗噬，抢藻也慢。" % int(p.get("speed", 3.0)))
		else:
			out.append("再试一次，把繁殖调高点，生得比它快。")
	return out
