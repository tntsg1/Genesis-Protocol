extends SceneTree
# Probe for 5-3 in real conditions (mutation on, fresh seeds): which bodies
# come through the hunters and the famine? Env P_SEEDS, P_N, P_BITE, P_ARMOR,
# P_STORE, P_GAP, P_PER, P_MOST, P_FADE, P_STREAM, P_HZ (steps a second), P_SET.
func _env(key: String, d: float) -> float:
	return float(OS.get_environment(key)) if OS.get_environment(key) != "" else d


# Rows of a blueprint, front at the right: F flagellum, G germ, A armour, S store, . gap.
static func _bp(rows: Array) -> Array:
	var out := []
	var kinds := {"F": Colony.FLAG, "G": Colony.GERM, "A": Colony.ARMOR, "S": Colony.STORE, "R": Colony.REGEN}
	for j in rows.size():
		var r: String = rows[j]
		for i in r.length():
			if kinds.has(r[i]):
				out.append([i, j, kinds[r[i]]])
	return out


func _initialize() -> void:
	var lid := OS.get_environment("P_LEVEL") if OS.get_environment("P_LEVEL") != "" else "5-3"
	var l: Dictionary = Levels.by_id(lid).duplicate(true)
	l.colony.bite_e = _env("P_BITE", l.colony.bite_e)
	l.colony.armor = _env("P_ARMOR", l.colony.armor)
	l.colony.store_e = _env("P_STORE", l.colony.store_e)
	l.colony.bite_gap = _env("P_GAP", l.colony.bite_gap)
	l.colony.stream = Vector2(-_env("P_STREAM", -l.colony.stream.x), 0.0)
	l.goal.n = int(_env("P_N", l.goal.n))
	if l.challenge.kind == "count_by":
		l.challenge.n = l.goal.n
	for hunt: Dictionary in l.events.filter(func(e: Dictionary) -> bool: return e.kind == "hunters"):
		hunt.per = int(_env("P_PER", hunt.per))
		hunt.most = int(_env("P_MOST", hunt.most))
	var rot: Dictionary = l.world.species[0].params
	if rot.get("rotifer", false):
		rot.rot_pull = _env("P_PULL", rot.rot_pull)
		rot.rot_full = _env("P_FULL", rot.rot_full)
		rot.rot_spit = int(_env("P_SPIT", rot.rot_spit))
		rot.burn = _env("P_RBURN", rot.burn)
		rot.speed = _env("P_RSPEED", rot.speed)
		rot.rot_gain = _env("P_GAIN", rot.get("rot_gain", 1.0))
		rot.rot_chew = _env("P_CHEW", rot.rot_chew)
		rot.rot_reach = _env("P_REACH", rot.rot_reach)
	for e: Dictionary in l.events:
		if e.kind == "hunt_waves" and OS.get_environment("P_HMUL") != "":
			# More hunters on the same timetable (each wave's total times P_HMUL).
			var waves := []
			for w: Array in e.waves:
				waves.append([w[0], roundi(int(w[1]) * _env("P_HMUL", 1.0)), w[2]])
			e.waves = waves
	for e: Dictionary in l.events:
		if e.kind == "famine":
			e.fade = _env("P_FADE", e.get("fade", 1.0))
	if l.colony.has("hurt"):
		l.colony.regrow = _env("P_REGROW", l.colony.regrow)
		l.colony.crack = _env("P_CRACK", l.colony.crack)
		l.colony.regrow_e = _env("P_REGE", l.colony.regrow_e)
		l.colony.bleed = _env("P_BLEED", l.colony.get("bleed", 0.0))
		l.colony.regen = _env("P_REGEN", l.colony.regen)
		if OS.get_environment("P_RALL") != "":
			l.colony.regen_all = true
	l.release.count = int(_env("P_REL", l.release.count))
	if OS.get_environment("P_DIG") != "":
		l.colony.dig = true
	if OS.get_environment("P_DEPTH") != "":
		l.colony.depth = int(_env("P_DEPTH", 1.0))
	if OS.get_environment("P_RAGE") != "":
		l.events.append({kind = "rage", at = _env("P_RAGEAT", 180.0), mult = _env("P_RAGE", 2.0)})
	if OS.get_environment("P_WEAR") != "":
		l.world.species[0].params.rot_wear = _env("P_WEAR", 0.5)
	if OS.get_environment("P_SPURN") != "":
		l.world.species[0].params.rot_spurn = _env("P_SPURN", 15.0)
	if OS.get_environment("P_GAIN") != "":
		l.world.species[0].params.rot_gain = _env("P_GAIN", 6.0)
	if OS.get_environment("P_JET") != "":
		l.colony.jet = _env("P_JET", 1.0)
	if OS.get_environment("P_BELOW") != "":
		for re: Dictionary in l.events.filter(func(e: Dictionary) -> bool: return e.kind == "rage"):
			re.below = _env("P_BELOW", 0.1)
			re.warn_below = re.below + 0.05
	if OS.get_environment("P_RGAIN") != "":
		l.world.species[0].params.rot_rage_gain = _env("P_RGAIN", 0.25)
		l.world.species[0].params.rot_rage_spurn = _env("P_RSPURN", 5.0)
		for re: Dictionary in l.events.filter(func(e: Dictionary) -> bool: return e.kind == "rage"):
			re.mult = _env("P_RMULT", 1.5)
	if OS.get_environment("P_W4") != "":
		# "t,n": the last hunter wave's time and size.
		var w4 := OS.get_environment("P_W4").split(",")
		for he: Dictionary in l.events.filter(func(e: Dictionary) -> bool: return e.kind == "hunt_waves"):
			var ws: Array = (he.waves as Array).duplicate(true)
			ws[-1] = [float(w4[0]), int(w4[1]), ws[-1][2]]
			he.waves = ws
	if OS.get_environment("P_FLOOR") != "":
		l.challenge = {kind = "floor", n = int(_env("P_FLOOR", 15.0)), from = 120.0, by = _env("P_FLOORBY", 270.0), text = ""}
	if OS.get_environment("P_SHARE") != "":
		l.challenge = {kind = "heal_share", n = int(_env("P_SHARE", 15.0)), min = 20, text = ""}
	if OS.get_environment("P_COST") != "":
		l.world.species[0].params.rot_cost = _env("P_COST", 0.03)
	if OS.get_environment("P_BBURN") != "":
		l.world.species[0].params.burn = _env("P_BBURN", 9.0)
	if OS.get_environment("P_BRUISE") != "":
		l.world.species[0].params.rot_bruise = int(_env("P_BRUISE", 2.0))
	l.world.algae_cap = int(_env("P_ALG", l.world.algae_cap))
	l.world.algae_seed[0] = int(_env("P_SEED", l.world.algae_seed[0]))
	var d0: Dictionary = l.start_design
	var plans := [["开局不改（无甲无储）", d0.blocks],
		["后角 2 甲", _bp(["AFFF", "GGGF", "AFFF"])],
		["后角 2 甲 + 侧储", _bp(["AFFF", "GGGF", "ASFF"])],
		["后角 2 甲 + 后储", _bp(["AFFF", "SGGF", "AFFF"])],
		["4×3 两甲两储", _bp(["AFF", "SGF", "GGF", "ASF"])],
		["侧后 4 甲", _bp(["AAFF", "GGGF", "AAFF"])],
		["1 储（无甲）", _bp(["FFFF", "GGGF", "SFFF"])],
		["2 储（无甲）", _bp(["FFFF", "GGGF", "SSFF"])],
		["满圈甲", _bp(["AAAA", "AGGA", "AAAA"])],
		["2 甲 + 内储 3 生殖", _bp(["AFFF", "GSGF", "AGFF"])],
		["引导解（两角甲 + 换一鞭毛成储）", _bp(["ASFF", "GGGF", "AFFF"])],
		["只储 1（换生殖）", _bp(["FFFF", "SGGF", "FFFF"])]]
	if OS.get_environment("P_SET") == "regrow":
		plans = [["开局不改（无再生）", d0.blocks], ["引导解（正中再生）", _bp(["AFFF", "GRGF", "AFFF"])],
			["再生在后排中间", _bp(["AFFF", "RSGF", "AFFF"])], ["无甲 + 再生", _bp(["FFFF", "GRGF", "FFFF"])],
			["细长 2×6 + 再生", _bp(["AFFRFF", "GGFFFF"])], ["一字 1×10 两生殖", _bp(["GFGFRFFFFF"])],
			["一字 1×12 三生殖", _bp(["GFGFGFRFFFFF"])]]
	if OS.get_environment("P_SET") == "regrow2":
		plans = [["开局不改（无再生）", d0.blocks], ["引导解（正中再生）", _bp(["AFFF", "GRGF", "AFFF"])], ["一字 1×12 三生殖", _bp(["GFGFGFRFFFFF"])]]
	if OS.get_environment("P_SET") == "heal":
		plans = [["引导解（正中再生）", _bp(["AFFF", "GRGF", "AFFF"])], ["后排中间再生", _bp(["AFFF", "RGGF", "AFFF"])],
			["两再生（正中 + 下排）", _bp(["AFFF", "GRGF", "ARFF"])], ["再生挨甲角", _bp(["ARFF", "GGGF", "AFFF"])],
			["两再生 后排两角旁", _bp(["ARFF", "GGGF", "ARFF"])]]
	if OS.get_environment("P_SET") == "heal2":
		plans = [["开局不改（无再生）", d0.blocks], ["三生殖 无再生无储", _bp(["AFFF", "GGGF", "AFFF"])],
			["再生挨甲角", _bp(["ARFF", "GGGF", "AFFF"])], ["引导解（正中再生）", _bp(["AFFF", "GRGF", "AFFF"])],
			["两再生（正中 + 下排）", _bp(["AFFF", "GRGF", "ARFF"])]]
	if OS.get_environment("P_SET") == "neck":
		plans = [["开局不改（无再生）", d0.blocks], ["引导解（正中再生）", _bp(["AFFF", "GRGF", "AFFF"])],
			["哑铃 中腰一格", _bp(["AF.FF", "GRFGF", "AF.F."])], ["哑铃 再生两头", _bp(["GF.FF", "RFFRF", "GF.F."])],
			["哑铃 甲尾", _bp(["AG.GF", "RFFFF", "AG.F."])], ["一字 1×12 三生殖", _bp(["GFGFGFRFFFFF"])]]
	if OS.get_environment("P_SET") == "boss":
		plans = [["开局不改（2 甲）", d0.blocks], ["3 甲（后角 + 后中）", _bp(["AFFF", "ARGF", "AGFF"])],
			["4 甲 + 储 + 再生", _bp(["AFFF", "ARGF", "ASGA"])], ["全鞭毛（逃）", _bp(["FFFF", "GRGF", "FFFF"])],
			["3 甲 + 储", _bp(["AFFF", "ASGF", "AGFF"])]]
	if OS.get_environment("P_SET") == "boss3":
		plans = [["开局不改（2 甲）", d0.blocks], ["3 甲（后角 + 后中）", _bp(["AFFF", "ARGF", "AGFF"])], ["全鞭毛（逃）", _bp(["FFFF", "GRGF", "FFFF"])]]
	if OS.get_environment("P_SET") == "boss4":
		plans = [["开局不改（2 甲）", d0.blocks], ["旧引导 3 甲", _bp(["AFFF", "ARGF", "AGFF"])],
			["4 甲 上排第二", _bp(["AAFF", "ARGF", "AGFF"])], ["4 甲 下排第二", _bp(["AFFF", "ARGF", "AAGF"])],
			["4 甲 船头", _bp(["AFFF", "ARGA", "AGFF"])], ["5 甲", _bp(["AAFF", "ARGF", "AAGF"])], ["全鞭毛（逃）", _bp(["FFFF", "GRGF", "FFFF"])]]
	if OS.get_environment("P_SET") == "boss5":
		plans = [["开局不改（2 甲）", d0.blocks], ["旧引导 3 甲", _bp(["AFFF", "ARGF", "AGFF"])],
			["4 甲 上排第二", _bp(["AAFF", "ARGF", "AGFF"])], ["4 甲 船头", _bp(["AFFF", "ARGA", "AGFF"])], ["全鞭毛（逃）", _bp(["FFFF", "GRGF", "FFFF"])]]
	if OS.get_environment("P_FAM") != "":
		for fe: Dictionary in l.events.filter(func(e: Dictionary) -> bool: return e.kind == "famine"):
			fe.over = _env("P_FAM", 60.0)
	if OS.get_environment("P_SET") == "g5":
		plans = [["4 甲 上排第二", _bp(["AAFF", "ARGF", "AGFF"])], ["5 甲", _bp(["AAFF", "ARGF", "AAGF"])]]
	if OS.get_environment("P_SET") == "g4":
		plans = [["4 甲 上排第二", _bp(["AAFF", "ARGF", "AGFF"])]]
	if OS.get_environment("P_SET") == "armour":
		plans = [plans[0], ["2 甲 + 后储", plans[3][1]], ["3 甲 + 后储", _bp(["AFFF", "SGGF", "AAFF"])],
			["4 甲 + 后储", _bp(["AAFF", "SGGF", "AAFF"])], ["3 甲 + 后储（前角）", _bp(["AFFA", "SGGF", "AFFF"])]]
	if OS.get_environment("P_SET") == "s22":
		plans = [plans[0], ["引导解（两角甲 + 内储）", _bp(["AFFF", "GSGF", "AFFF"])], plans[1], plans[6], plans[7],
			["后排 3 甲 + 内储", _bp(["AFFF", "ASGF", "AFFF"])], ["两角甲 + 两内储", _bp(["AFFF", "SSGF", "AFFF"])]]
	if OS.get_environment("P_SET") == "two":
		plans = [plans[0], ["引导解（两角甲 + 内储）", _bp(["AFFF", "GSGF", "AFFF"])]]
	if OS.get_environment("P_SET") == "three":
		plans = [plans[0], plans[1], plans[3], plans[11]]
	if OS.get_environment("P_SET") == "core":
		plans = [plans[0], plans[1], plans[2], plans[3], plans[4], plans[6]]
	var seeds := int(_env("P_SEEDS", 8.0))
	var seed0 := int(_env("P_SEED0", float(randi() % 900000)))
	var jobs := []
	for pl: Array in plans:
		var d := LevelEval.design_from_genes(d0.genes, (d0.deck as Array).duplicate(true), d0.color, 12.0, true, [], lid)
		d.params.blocks = pl[1]
		if OS.get_environment("P_FEED") != "":
			d.feed = int(OS.get_environment("P_FEED"))
		if OS.get_environment("P_BURN") != "":
			d.params.tune = {burn = _env("P_BURN", 1.0)}
		for k in seeds:
			jobs.append([l.duplicate(true), d.duplicate(true), seed0 + k * 6113])
	var res := []
	res.resize(jobs.size())
	var job := func(k: int) -> void:
		res[k] = LevelEval.simulate(jobs[k][0], jobs[k][1], jobs[k][2], 1.0 / _env("P_HZ", 15.0))
	WorkerThreadPool.wait_for_group_task_completion(WorkerThreadPool.add_group_task(job, jobs.size(), -1, true))
	var k := 0
	for pl: Array in plans:
		var s: Dictionary = Colony.stats(pl[1])
		var al := []
		var w := 0
		var ch := 0
		var ex := 0
		var born := 0
		var bites := 0
		var blocked := 0
		var eaten := 0
		var pk := 0
		var low := 0
		var starved := 0
		var splits := 0
		var spat := 0
		var swallowed := 0
		var bossdead := 0
		var early := 0
		var deaths := []
		var worn := 0
		var whole := 0
		var healed := []
		var burned := 0
		var aged := 0
		for q in seeds:
			var ev: LevelEval = res[k]
			k += 1
			al.append(ev.alive)
			var st: Array = ev.stars()
			w += 1 if st[0] else 0
			ch += 1 if st[1] else 0
			ex += 1 if ev.extinct else 0
			born += int(ev.colony_stats.get("born", 0))
			bites += int(ev.colony_stats.get("bites", 0))
			blocked += int(ev.colony_stats.get("blocked", 0))
			eaten += int(ev.colony_stats.get("eaten", 0))
			splits += int(ev.colony_stats.get("splits", 0))
			spat += int(ev.colony_stats.get("spat", 0))
			swallowed += int(ev.colony_stats.get("swallowed", 0))
			bossdead += 1 if ev.boss_dead >= 0.0 else 0
			early += 1 if ev.boss_dead >= 0.0 and ev.boss_dead < 180.0 else 0
			worn += int(ev.colony_stats.get("worn", 0))
			if ev.boss_dead >= 0.0:
				deaths.append(int(ev.boss_dead))
			whole += int(ev.colony_stats.get("whole", 0))
			healed.append(int(100.0 * int(ev.colony_stats.get("healed", 0)) / maxf(1.0, float(ev.colony_stats.get("broken", 0)))) if OS.get_environment("P_SHARE") != "" else int(ev.colony_stats.get("healed", 0)))
			starved += int(ev.colony_stats.get("starved", 0))
			burned += int(ev.colony_stats.get("burned_all", 0))
			aged += int(ev.colony_stats.get("aged", 0))
			pk += ev.peak
			# The low point after the famine began (the curve: [t, alive, ...]).
			var m := 1 << 30
			for c: Array in ev.curve:
				if float(c[0]) >= 120.0 and float(c[0]) <= 270.0:
					m = mini(m, int(c[1]))
			low += m
		al.sort()
		healed.sort()
		deaths.sort()
		if deaths.size() > 0:
			print("%-18s 守卫饿死时刻 %s" % [pl[0], str(deaths)])
		if OS.get_environment("P_HEAL") != "":
			print("%-18s 再生长回 中位 %d（%d–%d）" % [pl[0], healed[seeds / 2], healed[0], healed[-1]])
		if OS.get_environment("P_NS") != "":
			# Wins at other goals (alive at the end only): "N=190:20 ...".
			var line := ""
			for nv in OS.get_environment("P_NS").split(","):
				line += " N=%s:%d" % [nv, al.filter(func(v: int) -> bool: return v >= int(nv)).size()]
			print("%-18s%s" % [pl[0], line])
		print("%-18s 速%4.1f  胜 %d/%d 挑战 %d 灭 %d 终 %d（%d–%d）峰 %d 荒后低 %d 生 %d 咬 %d 挡 %d 吃掉 %d 饿死 %d 烫死 %d 老死 %d 断 %d 长全 %d 吞 %d 吐 %d 磨甲 %d 饿死守卫 %d（发狂前 %d）" % [pl[0], s.speed, w, seeds, ch, ex, al[seeds / 2], al[0], al[-1], pk / seeds, low / seeds, born / seeds, bites / seeds, blocked / seeds, eaten / seeds, starved / seeds, burned / seeds, aged / seeds, splits / seeds, whole / seeds, swallowed / seeds, spat / seeds, worn / seeds, bossdead, early])
	quit()
