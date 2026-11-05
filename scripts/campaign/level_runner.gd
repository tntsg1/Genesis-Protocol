extends Node
# Runs one campaign level inside the showcase (DECISIONS M4): loads the
# level's dish in place, opens the designer under the level's rules, asks for
# releases the design at the level's spot, runs
# the clock and the announced events (nutrient pulses), keeps the objective
# panel current, and ends with the experiment report (stars,
# facts and hypotheses, control experiment).

const LevelReport := preload("res://scripts/ui/level_report.gd")

signal exited

var host: Node2D
var level: Dictionary
var phase := "" # design, predict, release, run, done
var design := {} # {params, genes, used, deck, name}
var eval: LevelEval
var t0 := 0.0
var next_obs := 0.0
var next_pulse := -1.0
var last_t := 0.0
var fired := {} # one-off event announcements made
var sp_index := -1
var exit_armed := 0.0
var report: Control
var tutorial: Node
var boss_seen := 0 # level 10: how many devourers were last counted
var tagged_id := -1 # the cell last tagged on the dish
var boss_down := false # level 10: its starving was announced
var release_speed := 1.0 # the speed to go back to once the capsule has opened
var rival_peak := 0 # level 17: the rival at its most
var boss_low := false # level 10: "almost starved" was said
var echo_passed := false # chapter 3 boss: the moment you first outnumbered it was said
var boss_trend: Array = [] # level 10: [t, energy] over the last 15 s, for "starves in about N s"


# Coming in from the campaign page through the lens opened at `entry_at`
# (screen), the camera starts further out with the release spot under the
# lens and comes down to it, centring it, while the lens racks focus.
const ENTRY_ZOOM := Vector2(0.4, 0.62)
const ENTRY_SECONDS := 2.0


func start(l: Dictionary, last_design := {}, entry_at := Vector2.INF) -> void:
	var entry := entry_at.is_finite()
	level = l
	phase = "design"
	release_speed = host.speed
	host.set_speed(1.0) # (the dish runs a moment before the designer opens: see _release)
	host.load_world(l.world, randi() % 100000)
	host.release_count = int(l.release.count)
	host.hud_root.set_level(l)
	if not host.hud_root.revealed and not entry:
		host.hud_root.reveal()
	# Over the release spot, a moment to look at the dish, then the designer.
	var spot: Vector2 = l.release.at.lerp(host.DISH_CENTER, 0.35)
	if entry:
		var view: Vector2 = host.get_viewport().get_visible_rect().size
		host.focus(spot - (entry_at - view * 0.5) / ENTRY_ZOOM.x, ENTRY_ZOOM.x)
		host.fly_to(spot, ENTRY_ZOOM.y, ENTRY_SECONDS)
	else:
		host.focus(spot, 0.62)
	# The guide comes back on every try until the level is passed (playtest:
	# a retry without it left the player guessing); after that, on request.
	if l.get("tutorial", false) and not CampaignSave.stars(l.id)[0] and not DevMode.on(DevMode.no_tutorial):
		tutorial = preload("res://scripts/campaign/tutorial.gd").new()
		tutorial.host = host
		tutorial.runner = self
		# Not over the lens coming in: once the image has locked.
		if entry:
			host.get_tree().create_timer(ENTRY_SECONDS).timeout.connect(func() -> void:
				if is_instance_valid(tutorial) and tutorial.get_parent() == null:
					add_child(tutorial))
		else:
			add_child(tutorial)
	host.get_tree().create_timer(ENTRY_SECONDS + 0.5 if entry else 0.9).timeout.connect(func() -> void: open_designer(last_design))


# The designer's 重看引导: the level's guide from the start.
func replay_tutorial() -> void:
	if not level.get("tutorial", false):
		return
	if is_instance_valid(tutorial):
		tutorial.queue_free()
	CampaignSave.clear_guide_at(level.id)
	tutorial = preload("res://scripts/campaign/tutorial.gd").new()
	tutorial.host = host
	tutorial.runner = self
	add_child(tutorial)


func open_designer(last_design := {}) -> void:
	if host.designer or phase != "design":
		return
	var rules := {budget = level.budget, star_budget = level.star_budget, genes_open = level.genes_open,
		fixed = level.fixed, pages_open = level.pages_open}
	if level.has("virus"):
		rules.virus = last_design.get("virus", design.get("virus", level.virus))
		rules.virophage = level.get("phage", {}).get("virophage", false)
	if level.has("star_shots"):
		rules.star_shots = level.star_shots
	if level.has("colony"):
		rules.colony = level.colony
		rules.star_blocks = level.star_blocks
		if level.goal.has("zone"):
			rules.trip = (level.goal.zone.center as Vector2).distance_to(level.release.at) - float(level.goal.zone.radius)
	if level.has("temp_fixed"):
		rules.temp_fixed = level.temp_fixed
	rules.id = level.id
	rules.rules_readonly = level.get("rules_readonly", false)
	rules.organ_slots = level.get("organ_slots", 0)
	rules.resp = level.get("resp", 0)
	rules.resp_open = level.get("resp_open", false)
	rules.require_organs = level.get("require_organs", [])
	rules.forbid_organs = level.get("forbid_organs", [])
	if level.has("species"):
		rules.species = level.species
	if level.has("deck"):
		rules.deck = level.deck
	if not last_design.is_empty():
		rules.design = last_design
	elif not design.is_empty():
		rules.design = design.design
	elif level.has("start_design"):
		# A level may open on a ready plan (level 14: last level's alarm calls).
		rules.design = (level.start_design as Dictionary).duplicate(true)
	host.Designer.level_rules = rules
	host.open_designer()


# The designer's release: the design goes straight to the level's spot.
func on_design(params: Dictionary) -> void:
	var genes := [params.speed, params.vision, params.armor, params.attack, params.fertility,
		params.efficiency, params.neural, params.temp_tol]
	var used := 0.0
	for g in genes:
		used += float(g) - 1.0
	if level.get("resp_open", false):
		used += Resp.cost(int(params.get("resp", 0)))
	design = {params = params, genes = genes, used = used,
		design = {name = params.name, color = params.color, genes = genes, deck = params.deck, temp_opt = params.get("temp_opt", 12.0), mutates = params.get("mutates", true),
			organs = params.get("organs", []), resp = params.get("resp", 0)}}
	if params.has("virus"):
		design.virus = params.virus
		design.design.virus = params.virus # (a retry starts from these points)
	if params.has("blocks"):
		design.design.blocks = params.blocks
	# Chapter 6: the look of each species role carries to later levels (Q213).
	if level.has("role"):
		CampaignSave.set_look(level.role, params.name, params.color)
	var specs: Array = level.get("species", [])
	if specs.size() > 1:
		if specs[0].has("role"):
			CampaignSave.set_look(specs[0].role, params.name, params.color)
		for k in (params.get("extra", []) as Array).size():
			if k + 1 < specs.size() and specs[k + 1].has("role"):
				CampaignSave.set_look(specs[k + 1].role, params.extra[k].name, params.extra[k].color)
	# Level 8: the other species, released beside the first.
	if params.has("extra"):
		design.extra = params.extra
		design.design.designs = params.get("designs", [])
	_release()


func _release() -> void:
	phase = "release"
	host.release_params = LevelEval.level_params(level, design.params).duplicate()
	# The world runs while the capsule opens: at normal speed, or a fast-forward
	# left over from the last try hands the rivals a head start.
	if host.speed != 1.0:
		release_speed = host.speed
	host.set_speed(1.0)
	host.fly_to(level.release.at, 1.1, 1.0)
	host.get_tree().create_timer(0.6).timeout.connect(func() -> void: host._do_release(level.release.at))


# The capsule opened: the clock starts now.
func on_released(i: int) -> void:
	sp_index = i
	phase = "run"
	host.set_speed(release_speed)
	t0 = host.sim.get_time()
	next_obs = 0.0
	var pulses: Dictionary = level.get("pulses", {})
	next_pulse = pulses.get("every", -1.0)
	eval = LevelEval.new(level, i, design.used)
	# Level 15: phages after the player's cells, close enough to see them.
	if level.has("phage"):
		var ph: Dictionary = (level.phage as Dictionary).duplicate()
		ph.host = int(level.goal.get("rival", i))
		ph.rain_from = t0 + float(ph.get("rain_from", 0.0))
		ph.merge(LevelEval.virus_params(design.get("virus", {})), true)
		host.sim.set_phage(ph)
		host.phage_layer.set_look(design.get("virus", {}), bool(ph.get("virophage", false)))
		host.giant_layer.takeover = float(ph.burst)
		host.zoom_max = 26.0
	if level.has("giant"):
		LevelEval.start_giants(host.sim, level, i)
		_giant_intro()
	if level.has("slug"):
		LevelEval.start_slug(host.sim, level, i)
	if level.has("colony"):
		host.sim.set_colony(level.colony)
		host.zoom_max = 20.0 # close enough to watch an embryo cleave and turn
		eval.blocks_used = (design.params.get("blocks", []) as Array).size()
	# Level 8: the second species comes out beside the first, now.
	for k in (design.get("extra", []) as Array).size():
		var rb: Dictionary = level.get(["release_b", "release_c"][mini(k, 1)], level.get("release_b", level.release))
		var j: int = host.release_now(LevelEval.level_params(level, design.extra[k]), rb.at, int(rb.count))
		if k == 0:
			eval.sp2 = j
		else:
			eval.sp3 = j
		eval.uses_state = LevelEval.deck_uses(design.extra[k].get("deck", []), int(level.challenge.get("state", -1)))
	var dp: Dictionary = design.get("params", {})
	eval.founder = {topt = float(dp.get("temp_opt", 12.0)), tol = float(dp.get("temp_tol", 2.5))}
	last_t = 0.0
	fired = {}
	# A goal zone far from the release: pull back so both are in view, the
	# way there plain from the start (review round 3: "1-1 is small and empty").
	if level.goal.kind == "zone_count":
		var zone: Dictionary = level.goal.zone
		var box := Rect2(level.release.at, Vector2.ZERO).grow(160.0).merge(Rect2(zone.center, Vector2.ZERO).grow(float(zone.radius) + 60.0))
		var view: Vector2 = host.get_viewport().get_visible_rect().size
		host.fly_to(box.get_center(), minf(view.x / box.size.x, view.y / (box.size.y * 1.25)), 1.4)
	# Level 10: the devourer is shown first, then the camera comes back.
	if level.goal.kind == "boss":
		_boss_intro()
	if level.goal.kind == "outnumber":
		var rl: String = level.world.species[int(level.goal.rival)].label
		host.hud_root.banner(rl, level.get("rival_line", "它听得懂你说的话"), Color(0.3, 0.72, 0.62))
	if tutorial:
		tutorial.on_released()


func tick(_delta: float) -> void:
	exit_armed = maxf(0.0, exit_armed - _delta)
	if phase != "run":
		return
	var t: float = host.sim.get_time() - t0
	for said: Dictionary in LevelEval.tick_events(level, host.sim, last_t, t, fired):
		host.hud_root.notify(said.text, Color(0.35, 0.6, 0.95), said.get("pos", Vector2.INF))
		host.hud_root.banner(said.text.get_slice("：", 0), said.text.get_slice("：", 1), Color(0.35, 0.6, 0.95))
	last_t = t
	if next_pulse > 0.0 and t >= next_pulse:
		var pulses: Dictionary = level.pulses
		host.sim.add_nutrient(pulses.at, pulses.radius, pulses.amount)
		host.fx.nutrient_splash(pulses.at)
		host.hud_root.notify("营养脉冲", Color(0.55, 0.8, 0.5), pulses.at)
		next_pulse += float(pulses.every)
	if t >= next_obs:
		eval.observe(host.sim, t)
		next_obs += 0.5
		_update_objective(t)
		if eval.extinct:
			finish()
			return
		if level.goal.kind == "boss":
			_boss_beats()
		if level.goal.kind == "outnumber" and not echo_passed and t > 20.0 and eval.alive > eval.rival_alive:
			echo_passed = true
			host.hud_root.banner("你的声音盖过了回声", "现在，水里你的同伴比它们多", Color(0.35, 0.6, 0.95))
	if level.has("phage"):
		_phage_beats() # (every frame: it eases the speed of the close-up)
	if level.id == "5-3":
		_armour_beats()
	if level.id == "5-4":
		_regrow_beats()
	if level.id == "5-4":
		# The first body bitten in two (rare: long thin bodies), shown where
		# it happened (review 2026-11-02: the brief promises it).
		var rs: Dictionary = eval.colony_stats
		if int(rs.get("splits", 0)) >= 1 and not fired.has("split_first"):
			fired["split_first"] = true
			var at: Vector2 = rs.get("split_at", Vector2.INF)
			host.hud_root.banner("一个群体被咬成了两半", "两半各自长回完整的身体，就成了两个群体", Color(0.36, 0.76, 0.56), at)
			host.hud_root.notify("一个群体被咬成了两半：两半各自长回完整的身体", Color(0.36, 0.76, 0.56), at)
	if level.id == "5-5":
		var gs: Dictionary = eval.colony_stats
		if int(gs.get("spat", 0)) >= 1 and not fired.has("spat_first"):
			fired["spat_first"] = true
			if int(gs.get("worn", 0)) >= 1:
				fired["worn_first"] = true
				host.hud_root.notify("嚼不动：外缘有 4 块好甲，它把群体吐了出来，可磨裂了一块甲：长好之前再被吞，就会被嚼碎", Color(0.62, 0.52, 0.36))
			else:
				host.hud_root.notify("嚼不动：外缘有 4 块好甲，它把群体吐了出来", Color(0.62, 0.52, 0.36))
		if int(gs.get("eaten", 0)) >= 1 and not fired.has("eaten_first"):
			fired["eaten_first"] = true
			host.hud_root.notify("喷口守卫吃下了一个群体：外缘的好甲不到 4 块", Color(0.75, 0.32, 0.3))
		# The moment the tool is for: a cracked body about to be taken back.
		if t - float(fired.get("worn_danger", -999.0)) >= 20.0:
			var rot: PackedFloat32Array = host.sim.get_rotifers(1.0)
			var worn: PackedFloat32Array = host.sim.get_worn(1.0)
			if rot.size() >= 6:
				var head := Vector2(rot[0], rot[1]) + Vector2.from_angle(rot[2]) * 88.0
				for w in range(0, worn.size(), 5):
					var at := Vector2(worn[w], worn[w + 1])
					if worn[w + 4] <= 6.0 and at.distance_to(head) < 450.0:
						fired["worn_danger"] = t
						host.hud_root.notify("裂了甲的群体快被吸回去了：按 %s 点它的头部" % Keys.name_of(Keys.code("current")), Color(0.86, 0.5, 0.2), at)
						if host.hud_root.dock_buttons.has("irritant"):
							host.hud_root.dock_buttons["irritant"].ping()
						break
		if int(gs.get("worn", 0)) >= 1 and not fired.has("worn_first"):
			fired["worn_first"] = true
			host.hud_root.notify("被吐出的群体裂了一块甲：长好之前再被吞，就会被吃掉", Color(0.62, 0.52, 0.36))
	if level.has("slug"):
		_slug_beats()
	if level.has("colony"):
		_colony_beats()
	if t >= float(level.time_limit):
		eval.observe(host.sim, t)
		finish()


func _update_objective(t: float) -> void:
	var g: Dictionary = level.goal
	var ratio := 0.0
	var now := ""
	if g.kind == "zone_count":
		ratio = clampf(float(eval.zone_now) / float(g.n), 0.0, 1.0)
		now = "光照区 %d / %d" % [eval.zone_now, int(g.n)]
		if level.has("slug"):
			var ss: Dictionary = eval.slug_stats
			now = "对岸 %d / %d　你 %d　聚合体里 %d　孢子 %d" % [eval.zone_now, int(g.n), eval.alive, int(ss.get("inside", 0)), int(ss.get("spores", 0))]
		elif level.has("colony"):
			now = "上游 %d / %d　共 %d 个群体　怀子 %d" % [eval.zone_now, int(g.n), eval.alive, int(eval.colony_stats.get("carrying", 0))]
	elif g.kind == "alive_end":
		ratio = clampf(float(eval.alive) / float(g.n), 0.0, 1.0)
		now = "种群：%d / %d" % [eval.alive, int(g.n)]
		if level.has("colony"):
			now = "种群：%d/%d%s" % [eval.alive, int(g.n), _colony_numbers()]
		if level.has("phage"):
			now += "　有记忆 %d　撑破 %d" % [eval.immune, eval.lysed]
	elif g.kind == "alive_safe":
		ratio = clampf(float(eval.alive) / float(g.n), 0.0, 1.0)
		now = "种群：%d / %d　被捕食：%d / %d" % [eval.alive, int(g.n), eval.eaten, int(g.eaten)]
		if eval.eaten > int(g.eaten):
			ratio = 0.0
			now += "　· 被捕食数量超标"
	elif g.kind == "alive_phage":
		ratio = clampf(float(eval.alive) / float(g.n), 0.0, 1.0)
		now = "种群 %d / %d　撑破 %d / %d" % [eval.alive, int(g.n), eval.lysed, int(g.lysed)]
		if eval.lysed > int(g.lysed):
			ratio = 0.0
			now += "　· 撑破超了"
	elif g.kind == "coexist":
		ratio = clampf(minf(float(eval.alive) / float(g.n), float(eval.alive2) / float(g.n2)), 0.0, 1.0)
		now = "%s：%d / %d　%s：%d / %d" % [level.species[0].label, eval.alive, int(g.n), level.species[1].label, eval.alive2, int(g.n2)]
	elif g.kind == "boss":
		ratio = clampf(float(eval.alive) / float(g.n), 0.0, 1.0)
		if level.id == "5-5":
			# Either way wins: the bar follows whichever is nearer.
			ratio = maxf(ratio, clampf(1.0 - eval.boss_energy, 0.0, 1.0))
		var boss_name: String = level.world.species[int(g.boss)].label
		var pct := roundi(100.0 * clampf(eval.boss_energy, 0.0, 1.0))
		if level.id == "5-5":
			# (The goal above names it; the bar keeps to numbers so it fits.)
			now = "种群：%d/%d　能量 %d%%" % [eval.alive, int(g.n), pct]
		else:
			now = "种群：%d / %d　%s：%d 只 · 能量 %d%%" % [eval.alive, int(g.n), boss_name, maxi(eval.boss_alive, 0), pct]
		# How long it has left at the rate it has been losing (review: the
		# first minute was "staring at 46%").
		boss_trend.append([t, eval.boss_energy])
		while boss_trend.size() > 1 and float(boss_trend[0][0]) < t - 15.0:
			boss_trend.pop_front()
		var span := t - float(boss_trend[0][0])
		var drop := float(boss_trend[0][1]) - eval.boss_energy
		if span > 5.0 and drop > 0.0 and eval.boss_alive > 0:
			var eta := roundi(eval.boss_energy / (drop / span))
			if level.id == "5-5":
				now += " · %d:%02d 后饿死" % [eta / 60, eta % 60]
			else:
				now += " · 预计 %d 秒后饿死" % eta
		if level.id == "5-5":
			# When it goes into its frenzy, beside how long it has left.
			for e: Dictionary in level.get("events", []):
				if e.kind == "rage" and e.has("below") and eval.boss_alive > 0:
					now += " · 暴走中" if fired.has("rage_t") else " · 能量 %d%% 时暴走" % roundi(100.0 * float(e.below))
			var gs: Dictionary = eval.colony_stats
			now += "　吐出 %d · 被吃 %d" % [int(gs.get("spat", 0)), int(gs.get("eaten", 0))]
	elif g.kind == "giant_limit":
		var gs: Dictionary = eval.giant_stats
		ratio = clampf(1.0 - float(maxi(eval.giants - int(g.giant_max), 0)) / 400.0, 0.0, 1.0)
		now = "巨毒囊 %d / %d%s　工厂 %d　你 %d / %d　投放 %d" % [maxi(eval.giants, 0), int(g.giant_max), _giant_trend(), int(gs.get("factories", 0)), eval.alive, int(g.n), eval.shots]
		for e: Dictionary in level.get("events", []):
			if float(e.at) > eval.t:
				now += "　下批 %d 秒" % ceili(float(e.at) - eval.t)
				break
		if int(gs.get("carriers", 0)) > 0:
			now += "　带噬毒体 %d%%" % roundi(100.0 * float(gs.carriers) / float(maxi(eval.alive, 1)))
	elif g.kind == "clear_rival":
		var rl: String = level.world.species[int(g.rival)].label
		ratio = clampf(1.0 - float(maxi(eval.rival_alive - int(g.rival_max), 0)) / 400.0, 0.0, 1.0)
		now = "%s %d / %d　你 %d　已投放 %d 次　水里病毒 %d" % [rl, maxi(eval.rival_alive, 0), int(g.rival_max), eval.alive, eval.shots, host.sim.get_phage_count()]
	elif g.kind == "outnumber":
		ratio = clampf(float(eval.alive) / float(maxi(eval.rival_alive, 1) * 2), 0.0, 1.0)
		now = "你 %d / %d　%s %d" % [eval.alive, int(g.get("n", 0)), level.world.species[int(g.rival)].label, maxi(eval.rival_alive, 0)]
		if level.has("phage"):
			now += "　被撑破：你 %d　%s %d" % [eval.lysed, level.world.species[int(g.rival)].label, eval.rival_lysed]
		if eval.alive > eval.rival_alive and eval.alive >= int(g.get("n", 0)):
			now += "　· 当前已达标，请保持到实验结束。"
	elif g.kind == "patches":
		ratio = clampf(float(eval.patches_won) / float(g.n), 0.0, 1.0)
		now = "占优 %d / %d 片（近 30 秒平均，比分见地图）" % [eval.patches_won, int(g.n)]
	# Goals judged at the end: enough now is not a pass yet (review round 3:
	# "62/60 at 0:22 read as done").
	if g.kind in ["alive_end", "coexist", "alive_safe", "boss"] and ratio >= 1.0 and not eval.goal_met:
		# (A famine still to come or under way: enough now says nothing yet,
		# review 2026-11-02 "第 5 秒就够了".)
		var lean_end := -1.0
		for e: Dictionary in level.get("events", []):
			if e.kind == "famine":
				lean_end = maxf(lean_end, float(e.at) + float(e.over))
		if t < lean_end:
			# (Levels 22-23 already show the famine's clock: kept short.)
			now += "　· 要撑过荒年" if level.has("colony") else "　· 荒年过后还要保持 %d 个" % int(g.get("n", 0))
		else:
			now += "　· 大爆发之后才算" if level.get("close_up", "") == "memory" and eval.storm0.is_empty() else "　· 当前已达标，请保持到实验结束。"
	if eval.goal_met:
		ratio = 1.0
		now = "✓ 已达到目标要求"
	var left := maxi(0, int(float(level.time_limit) - t))
	host.hud_root.set_objective(g.text, ratio, now, "剩余时间：%02d:%02d" % [left / 60, left % 60])


# Level 10: the camera goes to the devourer with its name, then back.
# Level 15 on: the first cell hit is tagged where it swims. The camera stays
# the player's (2026-11-01 "不用每次...突然来一个特写"); the whole infection
# plays out on the cell for anyone who zooms in.
# Level 22: the first bite on armour and the first that tears the rim, said.
# Levels 22-23 in the objective bar (reviews 2026-11-03: "局内没有任何关键
# 数字"): the hunters and the next wave, the famine's clock, the stores, the
# regrowth toward the challenge.
func _colony_numbers() -> String:
	var out := ""
	var cs: Dictionary = eval.colony_stats
	for e: Dictionary in level.get("events", []):
		if e.kind == "hunt_waves":
			out += "　巨噬者 %d" % host.sim.get_positions(int(e.species)).size()
			for wave: Array in e.waves:
				if float(wave[0]) > eval.t:
					out += " · 下批 %d 秒" % ceili(float(wave[0]) - eval.t)
					break
		elif e.kind == "famine":
			var fat := float(e.at)
			var fend := fat + float(e.over)
			if eval.t < fat:
				out += "　荒年 %d 秒后" % ceili(fat - eval.t)
			elif eval.t < fend:
				out += "　荒年剩 %d 秒" % ceili(fend - eval.t)
	var s: Dictionary = Colony.stats(design.get("params", {}).get("blocks", []))
	if int(s.store) > 0 and eval.alive > 0:
		var full := float(eval.alive) * int(s.store) * float(level.colony.get("store_e", 350.0))
		out += "　储能 %d%%" % roundi(100.0 * clampf(float(cs.get("stored", 0.0)) / full, 0.0, 1.0))
	if level.challenge.kind == "healed":
		out += "　附加 · 再生长回 %d/%d" % [int(cs.get("healed", 0)), int(level.challenge.n)]
	elif level.challenge.kind == "heal_share":
		out += "　附加 · 再生长回 %d%%/%d%%" % [roundi(100.0 * int(cs.get("healed", 0)) / maxf(1.0, float(cs.get("broken", 0)))), int(level.challenge.n)]
	elif level.challenge.kind == "floor" and eval.t < float(level.challenge.from):
		out += "　附加 · 荒年低谷要 ≥%d" % int(level.challenge.n)
	elif level.challenge.kind == "floor" and eval.t <= float(level.challenge.by):
		out += "　附加 · 低谷 %d/%d" % [eval.floor_low(float(level.challenge.from), eval.t), int(level.challenge.n)]
	return out


# Level 23: the first wound and the first one the regeneration block closes.
func _regrow_beats() -> void:
	var cs: Dictionary = eval.colony_stats
	if int(cs.get("broken", 0)) >= 1 and not fired.has("first_wound"):
		fired["first_wound"] = true
		host.hud_root.notify("巨噬者咬残了一块：伤口会慢慢长回，长好之前一直耗能", Color(0.75, 0.32, 0.3))
	if int(cs.get("healed", 0)) >= 1 and not fired.has("first_heal"):
		fired["first_heal"] = true
		host.hud_root.notify("一块伤口靠再生块长回来了：再生块管全身，自己别被咬残", Color(0.36, 0.76, 0.56))


func _armour_beats() -> void:
	var cs: Dictionary = eval.colony_stats
	if int(cs.get("blocked", 0)) >= 1 and not fired.has("armour_held"):
		fired["armour_held"] = true
		host.hud_root.notify("巨噬者咬在甲上：挡住了，只掉了一点点", Color(0.62, 0.52, 0.36))
	if int(cs.get("bites", 0)) - int(cs.get("blocked", 0)) >= 1 and not fired.has("rim_torn"):
		fired["rim_torn"] = true
		host.hud_root.notify("巨噬者从没甲的外缘咬掉了一大口", Color(0.75, 0.32, 0.3))


func _phage_beats() -> void:
	if level.get("close_up", "") == "memory":
		_memory_beats()
		return
	var latent: bool = level.get("close_up", "") == "latent"
	var made: bool = level.get("close_up", "") == "made"
	var giant: bool = level.has("giant")
	if giant:
		_giant_notes()
	if latent:
		rival_peak = maxi(rival_peak, eval.rival_alive)
		if float(eval.rival_alive) < 0.85 * float(rival_peak) and not fired.has("rival_falling"):
			fired["rival_falling"] = true
			host.hud_root.notify("%s开始减少了：病毒在起作用" % level.world.species[int(level.goal.rival)].label, Color(0.5, 0.3, 0.82))
	if latent and eval.rival_lysed >= 1 and not fired.has("rival_burst"):
		fired["rival_burst"] = true
		host.hud_root.notify("病毒撑破了第一只%s" % level.world.species[int(level.goal.rival)].label, Color(0.5, 0.3, 0.82))
	if eval.lysed >= 1 and not fired.has("phage_burst") and not latent:
		fired["phage_burst"] = true
		if giant:
			host.hud_root.notify("第一座工厂撑破了细胞，新的巨毒囊漂了出来", Color(0.5, 0.3, 0.8))
		else:
			host.hud_root.notify("第一只细胞爆开了，放出 %d 个裂囊针" % int(level.phage.get("yield", 30)), Color(0.85, 0.3, 0.45))
	if level.goal.kind == "alive_phage" and eval.lysed > int(level.goal.lysed) and not fired.has("phage_over"):
		fired["phage_over"] = true
		host.hud_root.notify("被撑破的超过 %d 只了：这一局已经过不了关" % int(level.goal.lysed), Color(0.85, 0.3, 0.45))
	if not fired.has("phage_seen"):
		var c: PackedFloat32Array = host.sim.get_infected(Rect2(Vector2.ZERO, host.WORLD), 0.0)
		if c.is_empty():
			return
		var k0 := 0
		if latent or giant:
			# (One of the player's, woken; not the rival, infected. Level 19: a
			# real factory, not a cell cutting the giant up.)
			k0 = -1
			for k in range(0, c.size(), 12):
				if c[k + 10] == (4.0 if giant else 3.0):
					k0 = k
					break
			if k0 < 0:
				return
		var id: int = host.sim.find_agent(Vector2(c[k0], c[k0 + 1]), 12.0)
		if id < 0:
			return # (next frame)
		fired["phage_seen"] = true
		var by_rule: bool = latent and c[k0 + 6] > 0.5
		var at := Vector2(c[k0], c[k0 + 1])
		var col := Color(0.5, 0.3, 0.8) if giant else (Color(0.5, 0.3, 0.82) if latent or made else Color(0.85, 0.3, 0.45))
		host.hud_root.notify("一只细胞把巨毒囊当成食物吞了下去" if giant else "你的病毒扎中了第一只绒游丝" if made else ("你的规则叫醒了第一只细胞的潜伏针" if by_rule else ("一只细胞基因里的潜伏针醒了" if latent else "一只细胞被裂囊针扎中了")), col, at)
		_tag(id, "吞下了巨毒囊" if giant else "被你的病毒扎中" if made else ("潜伏针醒了" if latent else "被裂囊针扎中"), col)
		return
	if giant:
		_stolen_tag()


func _tag(id: int, text: String, col: Color) -> void:
	tagged_id = id
	host.phage_layer.tag_cell(id, text, col)


# Level 20: the steps of the gathering, said as they happen, once each.
func _slug_beats() -> void:
	var s: Dictionary = eval.slug_stats
	if s.is_empty():
		return
	var col := Color(0.08, 0.56, 0.54)
	for g: Dictionary in host.sim.get_slugs():
		match int(g.stage):
			0:
				if not fired.has("slug_call"):
					fired["slug_call"] = true
					host.hud_root.notify("细胞开始聚合：中心在召集同伴", col, g.pos)
					var id: int = host.sim.find_agent(g.pos, 40.0)
					if id >= 0:
						_tag(id, "聚合中心", col)
			1:
				if not fired.has("slug_go"):
					fired["slug_go"] = true
					host.hud_root.notify("聚合体 %d 只：开始朝光爬" % int(g.n), col, g.pos)
			2:
				if not fired.has("slug_rise"):
					fired["slug_rise"] = true
					host.hud_root.notify("聚合体到了：开始长子实体", col, g.pos)
			3:
				if not fired.has("slug_fruit"):
					fired["slug_fruit"] = true
					host.hud_root.banner("子实体", "和盘基网柄菌一样：两成细胞牺牲成柄，其余变成孢子飞出去", col, g.pos)
	if int(s.lost) >= 1 and not fired.has("slug_hot"):
		fired["slug_hot"] = true
		host.hud_root.notify("喷口热带在烧聚合体的外层", Color(0.85, 0.42, 0.2))
	if int(s.broke) >= 3 and not fired.has("slug_small"):
		fired["slug_small"] = true
		host.hud_root.notify("聚到的同伴太少，又散开了", Color(0.85, 0.42, 0.2))
	if eval.zone_now >= 1 and not fired.has("slug_sprout"):
		fired["slug_sprout"] = true
		host.hud_root.notify("第一个孢子在对岸发芽了", col)


# Level 21: the first of everything, said as it happens, once each.
func _colony_beats() -> void:
	var s: Dictionary = eval.colony_stats
	if s.is_empty():
		return
	var col := Color(0.2, 0.6, 0.42)
	if int(s.carrying) >= 1 and not fired.has("col_embryo"):
		fired["col_embryo"] = true
		var b: PackedFloat32Array = host.sim.get_colonies()
		for k in range(0, b.size(), 6):
			if b[k + 5] > 0.5:
				_tag(int(b[k]), "开始怀子", col)
				host.hud_root.notify("第一个群体开始怀子：生殖块里的细胞在分裂", col, Vector2(b[k + 1], b[k + 2]))
				break
	if int(s.born) >= 1 and not fired.has("col_hatch"):
		fired["col_hatch"] = true
		host.hud_root.banner("破壳", "子体从亲体里出来了。亲体的体细胞不会进入下一代：它们留下空壳死去", col)
		host.hud_root.notify("第一批子体破壳，亲体留下空壳死去", col)
	if int(s.lost) >= 1 and not fired.has("col_grit"):
		fired["col_grit"] = true
		host.hud_root.notify("砂砾打死了一个子体：挡在前面的块能护住生殖块", Color(0.85, 0.42, 0.2))
	if int(s.burned) >= 1 and not fired.has("col_burn"):
		fired["col_burn"] = true
		host.hud_root.notify("一个群体被冲进了喷口热带：推力不够", Color(0.85, 0.42, 0.2))
	if eval.zone_now >= 1 and not fired.has("col_arrive"):
		fired["col_arrive"] = true
		host.hud_root.notify("第一个群体到了上游藻场", col)


# Level 19: which way the giants are heading, over the last 15 seconds.
func _giant_trend() -> String:
	var k := eval.curve.size() - 1
	while k > 0 and float(eval.curve[k][0]) > eval.t - 15.0:
		k -= 1
	if k < 0 or eval.t < 15.0:
		return ""
	var then := int(eval.curve[k][2])
	if eval.giants > then * 1.08 + 2:
		return " ▲"
	return " ▼" if eval.giants < then * 0.92 - 2 else ""


# Level 19: they are shown first, then the camera comes back.
func _giant_intro() -> void:
	var at: PackedVector2Array = host.sim.get_giant_positions()
	if at.is_empty():
		return
	host.fly_to(at[0], 2.4, 1.2)
	host.hud_root.banner("巨毒囊", "比细胞还大　·　细胞会把它当成食物", Color(0.5, 0.3, 0.8), at[0])
	host.get_tree().create_timer(3.2).timeout.connect(func() -> void:
		if phase == "run" and not host.following:
			host.fly_to(level.release.at, 1.0, 1.2))


# Level 19: the moments worth saying.
func _giant_notes() -> void:
	var gs: Dictionary = eval.giant_stats
	if gs.is_empty():
		return
	if int(gs.hijacked) >= 1 and not fired.has("first_stolen"):
		fired["first_stolen"] = true
		host.hud_root.notify("噬毒体闯进了一座工厂", Color(0.08, 0.6, 0.56))
	if int(gs.carriers) >= 1 and not fired.has("first_carrier"):
		fired["first_carrier"] = true
		host.hud_root.notify("噬毒体接进了细胞的基因，它的后代都会带着", Color(0.08, 0.6, 0.56))
	if eval.giant_peak > int(level.goal.giant_max) and eval.giants <= int(level.goal.giant_max) and not fired.has("giants_under"):
		fired["giants_under"] = true
		host.hud_root.banner("巨毒囊退下来了", "总数回到 %d 颗以内" % int(level.goal.giant_max), Color(0.08, 0.6, 0.56))
	if eval.giants_zero >= 0.0 and not fired.has("giants_gone"):
		fired["giants_gone"] = true
		host.hud_root.banner("巨毒囊清零", "水里和细胞里，一颗也不剩", Color(0.08, 0.6, 0.56))


# Level 19: the first factory a virophage takes.
func _stolen_tag() -> void:
	if fired.has("stolen_seen") or int(eval.giant_stats.get("stolen", 0)) < 1:
		return
	var c: PackedFloat32Array = host.sim.get_infected(Rect2(Vector2.ZERO, host.WORLD), 0.0)
	for k in range(0, c.size(), 12):
		if c[k + 10] == 4.0 and c[k + 11] >= 0.0:
			var id: int = host.sim.find_agent(Vector2(c[k], c[k + 1]), 12.0)
			if id < 0:
				return
			fired["stolen_seen"] = true
			_tag(id, "工厂被噬毒体闯入", Color(0.08, 0.6, 0.56))
			return


# Level 16: the first cell that beats the phage is tagged.
func _memory_beats() -> void:
	if eval.immune >= 1 and not fired.has("memory_first"):
		fired["memory_first"] = true
		host.hud_root.notify("第一只细胞记住了裂囊针：它的后代生下来就记得", Color(0.12, 0.62, 0.56))
	# The storm: back off to see the whole dish; once it has done its work, say so.
	if not eval.storm0.is_empty():
		if not fired.has("storm_view"):
			fired["storm_view"] = true
			host.following = false
			host.fly_to(host.DISH_CENTER, 0.62, 1.6)
		elif eval.t >= float(level.events[0].at) + 32.0 and not fired.has("storm_told"):
			fired["storm_told"] = true
			var hit := eval.lysed - int(eval.storm0.lysed)
			host.hud_root.banner("大爆发过去了", "撑破 %d 只没有记忆的细胞　·　有记忆的 %d 只毫发无伤" % [hit, eval.immune], Color(0.12, 0.62, 0.56))
	if not fired.has("memory_seen"):
		var c: PackedFloat32Array = host.sim.get_infected(Rect2(Vector2.ZERO, host.WORLD), 0.0)
		for k in range(0, c.size(), 12):
			if c[k + 10] == 1.0 and c[k + 5] < 1.0:
				var id: int = host.sim.find_agent(Vector2(c[k], c[k + 1]), 8.0)
				if id < 0:
					continue
				fired["memory_seen"] = true
				_tag(id, "正在记住病毒", Color(0.12, 0.62, 0.56))
				break


func _boss_intro() -> void:
	var at: PackedVector2Array = host.sim.get_positions(int(level.goal.boss))
	if at.is_empty():
		return
	boss_seen = at.size()
	host.fly_to(at[0], 0.9, 1.2)
	host.hud_root.banner(level.world.species[int(level.goal.boss)].label, "碰到就吞，但它也会饿死。", Color(0.85, 0.3, 0.45), at[0])
	host.get_tree().create_timer(3.2).timeout.connect(func() -> void:
		if phase == "run":
			host.fly_to(level.release.at, 1.0, 1.2))


# Level 10: say when the devourer splits (it was fed) and when it starves;
# a starved devourer ends the run a few seconds later.
func _boss_beats() -> void:
	var n := eval.boss_alive
	var who: String = level.world.species[int(level.goal.boss)].label
	if n > boss_seen and boss_seen > 0:
		host.hud_root.notify("%s分裂了 · 当前 %d 只" % [who, n], Color(0.85, 0.3, 0.45))
	boss_seen = n
	if eval.boss_energy >= 0.0 and eval.boss_energy < 0.15 and n > 0 and not boss_low:
		boss_low = true
		host.hud_root.notify("%s能量低于 15%% · 别让它再吃到东西" % who, Color(0.35, 0.6, 0.95))
	elif eval.boss_energy > 0.3:
		boss_low = false
	if eval.boss_dead >= 0.0 and not boss_down:
		boss_down = true
		host.hud_root.banner("%s已饿死" % who, "能量耗尽 · 威胁解除", Color(0.35, 0.6, 0.95))
		host.get_tree().create_timer(4.0).timeout.connect(func() -> void:
			if phase == "run":
				finish())


func finish() -> void:
	if phase == "done":
		return
	phase = "done"
	eval.finish()
	host.paused = true
	host.hud_root.conceal()
	if tutorial:
		# Seen; it still comes back on retries until the level is passed.
		CampaignSave.mark_tutorial(level.id)
		tutorial.queue_free()
		tutorial = null
	var got := DevMode.take_stars(eval.stars())
	var earned := CampaignSave.record(level.id, got, false)
	var rec := CampaignSave.level(level.id)
	rec.last_design = design.design
	CampaignSave.data.levels[level.id] = rec
	CampaignSave.save()
	report = LevelReport.new()
	report.setup(self, got, earned)
	report.action.connect(_on_report_action)
	host.ui_layer.add_child(report)


func _on_report_action(what: String, arg: Variant) -> void:
	if what == "compare":
		_open_bench(arg)
		return
	_close_report()
	match what:
		"retry":
			# Same level, a fresh dish, the design on the bench (maybe changed).
			report = null
			host.paused = false
			var d: Dictionary = arg if arg is Dictionary and not arg.is_empty() else design.design
			start(level, d)
		"next":
			report = null
			host.paused = false
			var nl: Dictionary = Levels.ALL[level.index] if level.index < Levels.ALL.size() else {}
			if not nl.is_empty() and Levels.playable(nl):
				design = {}
				start(nl)
			else:
				exit_level()
		"exit":
			report = null
			exit_level()


# The side-by-side control experiment over the report (which waits hidden).
var bench: Control


var last_pick := {}


func _open_bench(pick: Dictionary) -> void:
	if bench:
		return
	last_pick = pick
	report.visible = false
	bench = preload("res://scripts/ui/compare_bench.gd").new()
	bench.setup(level, design, int(pick.gene), float(pick.delta), randi() % 100000)
	bench.finished.connect(_on_bench)
	host.ui_layer.add_child(bench)


func _on_bench(choice: String, variant: Dictionary) -> void:
	bench = null
	if choice == "rerun":
		_open_bench(last_pick)
	elif choice == "retry_variant":
		_close_report()
		host.paused = false
		start(level, variant)
	elif report:
		report.visible = true


# The report leaves with whatever the player chose (retry, next, back).
func _close_report() -> void:
	if report and is_instance_valid(report):
		report.dismiss()
	report = null


# Esc in a level: press twice (within 2 s) to go back to the campaign page.
func request_exit() -> bool:
	if phase == "done" or host.designer:
		return false
	if exit_armed > 0.0:
		exit_level()
	else:
		exit_armed = 2.0
		host.hud_root.show_hint("再按一次 Esc 放弃本次实验，返回关卡页")
		host.get_tree().create_timer(2.0).timeout.connect(func() -> void:
			if is_instance_valid(host) and exit_armed <= 0.0:
				host.hud_root.hide_hint())
	return true


var ending_played := false


func exit_level() -> void:
	# Level 24 won: the end of Europa plays first (scripts/ui/ending.gd).
	if level.get("ending", false) and eval != null and eval.goal_met and not ending_played:
		ending_played = true
		_close_report()
		var e: CanvasLayer = preload("res://scripts/ui/ending.gd").new()
		host.add_child(e)
		e.finished.connect(exit_level)
		return
	_close_report()
	phase = "done"
	host.Designer.level_rules = {}
	host.paused = false
	exited.emit()
