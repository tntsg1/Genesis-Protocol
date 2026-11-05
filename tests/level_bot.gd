extends SceneTree
# Level bot (DECISIONS M4 Q9): plays each open campaign level headless with a
# spread of designs inside the level's rules, several seeds each, and checks
# that the goal can be met, that every star can be earned, and that a poor
# design fails (so the level asks for thought). Prints a table per level.
# Run: godot --headless -s tests/level_bot.gd [-- --level=1-1 --seeds=3]

var fails := 0
var coarse := false # tuning: gene levels 1, 3, 5 only
# Per gene: the level (1-5) that won most in each campaign level it was open
# in (DECISIONS 第十三轮 Q29: no gene is always best maxed or always best low).
var best_lv := {}


const GENES := ["速度", "感知", "外壳", "攻击", "繁殖", "代谢", "神经", "耐温"]


func check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func _initialize() -> void:
	var only := ""
	var seeds := 3
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--level="):
			only = a.get_slice("=", 1)
		elif a == "--coarse":
			coarse = true
		elif a.begins_with("--seeds="):
			seeds = int(a.get_slice("=", 1))
	for l: Dictionary in Levels.ALL.filter(func(x: Dictionary) -> bool: return x.id != "4-4" and x.id != "4-5" and x.id != "5-1" and x.id != "5-2"): # (4-4, 4-5, 5-1, 5-2 are played by tests/play_44.gd and its like: their designs need more than genes)
		if not Levels.playable(l) or (only != "" and l.id != only):
			continue
		_play(l, seeds)
	if only == "":
		for g: int in best_lv:
			var b: Array = best_lv[g]
			if b.size() >= 2:
				check(not b.all(func(v: int) -> bool: return v == 5), "%s is not always best maxed (%s)" % [GENES[g], str(b)])
				check(not b.all(func(v: int) -> bool: return v == 1), "%s is not always best at Lv1 (%s)" % [GENES[g], str(b)])
	print("RESULT: ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails else 0)


# Every combination of the open genes at levels 1..5 within budget, crossed
# with the level's other choices: the divide card's threshold where rule
# cards are open, the preferred temperature (the level's fixed one, else the
# dish's and 12 °C), natural mutation on / off where the level teaches it.
# Big spaces are sampled (240 designs, fixed seed).
func _designs(l: Dictionary) -> Array:
	var open: Array = l.genes_open
	var base := [2.0, 2.0, 1.0, 1.0, 2.0, 3.0, 3.0, 2.5]
	for k: int in l.fixed:
		base[k] = float(l.fixed[k])
	var combos := [[]]
	for g: int in open:
		var next := []
		for c: Array in combos:
			for v in ([1.0, 3.0, 5.0] if coarse else [1.0, 2.0, 3.0, 4.0, 5.0]):
				next.append(c + [[g, v]])
		combos = next
	# Level 3: deck variants. th > 0 raises the divide (and feeding)
	# threshold; th < 0 puts "crowd >= -th -> rest" on top (no breeding
	# when packed).
	var thresholds := [1.0, 1.3, -3.0, -5.0, -8.0] if l.id == "1-3" else [1.0]
	var water := float(l.world.get("layout", Worlds.OPEN_WATER).base.temp)
	var temps := [float(l.temp_fixed)] if l.has("temp_fixed") else ([12.0] if absf(water - 12.0) < 1.0 else [12.0, water])
	var muts := [true, false] if l.id == "1-4" else [true]
	# A level with its own starting deck (1-4: rest above divide) is played
	# as given and with the fix the guide teaches (divide moved above rest).
	var decks := [["", null]]
	if l.has("deck"):
		var fixed: Array = (l.deck as Array).duplicate(true)
		var dv := fixed.find_custom(func(c: Dictionary) -> bool: return c.act == Rules.A_DIVIDE)
		var rs := fixed.find_custom(func(c: Dictionary) -> bool: return c.act == Rules.A_REST)
		if dv > rs and rs >= 0:
			fixed.insert(rs, fixed.pop_at(dv))
		decks = [[" 原样", l.deck], [" 修好", fixed]]
	# Level 6 (predation): the hunt card as the guide builds it, with and
	# without the ambush (rest whenever nothing else fires), and the two
	# sensors that pick the prey.
	var organs: Array = l.get("require_organs", [])
	if l.id == "2-1":
		var R := Rules
		var hunt := func(c2: int, t2: float, ambush: bool) -> Array:
			return [R.card(R.C_PREDATOR_NEAR, 60.0, R.C_NONE, 0.0, R.A_FLEE),
				R.card(R.C_ENERGY_ABOVE, 1.0, R.C_NONE, 0.0, R.A_DIVIDE),
				R.card(R.C_ENERGY_BELOW, 1.0, c2, t2, R.A_HUNT),
				R.card(R.C_NONE if ambush else R.C_ENERGY_ABOVE, 1.0, R.C_NONE, 0.0, R.A_REST)]
		decks = [[" 游荡", hunt.call(R.C_SEE_PREY, 0.0, false)], [" 埋伏", hunt.call(R.C_SEE_PREY, 0.0, true)],
			[" 挑小", hunt.call(R.C_PREY_SMALL, 0.7, true)], [" 近追", hunt.call(R.C_PREY_NEAR, 90.0, true)]]
	# Level 7 (the prey): the flee card as given and as the guide turns it
	# (hunter near 或 bitten), each with no armour, the shell or the spines.
	var organ_sets := [["", organs]]
	if l.id == "2-2":
		var flee_or := Rules.card(Rules.C_PREDATOR_NEAR, 60.0, Rules.C_ATTACKED, 0.0, Rules.A_FLEE)
		flee_or.any = true
		var or_deck := Rules.default_deck(0)
		or_deck[0] = flee_or
		decks = [[" 原样", null], [" 或", or_deck]]
		organ_sets = [[" 无甲", []], [" 硬壳", ["silica"]], [" 尖刺", ["spines"]]]
	# Level 9 (on alert): no alert (the plain flee card), or "hunter near ->
	# alert" with flight in alert and calm-down after T s; each with no motor
	# organ, the flagellum or the cilia.
	if l.id == "2-4":
		var R := Rules
		# (As the guide leaves it: the default deck with its flee card turned
		# to "-> alert", and alert's own flee and way back.)
		var alert := func(see: float, calm: float) -> Array:
			var cards := Rules.default_deck(0)
			cards[0] = R.card(R.C_PREDATOR_NEAR, see, R.C_NONE, 0.0, R.A_TO_ALERT)
			var run := R.card(R.C_PREDATOR_NEAR, 100.0, R.C_NONE, 0.0, R.A_FLEE)
			run.st = R.S_ALERT
			var back := R.card(R.C_STATE_TIME, calm, R.C_NONE, 0.0, R.A_TO_FORAGE)
			back.st = R.S_ALERT
			return cards + [run, back]
		var far := Rules.default_deck(0)
		far[0] = R.card(R.C_PREDATOR_NEAR, 90.0, R.C_NONE, 0.0, R.A_FLEE)
		decks = [[" 原样", null], [" 远逃", far], [" 警戒10s", alert.call(60.0, 10.0)], [" 警戒20s", alert.call(60.0, 20.0)], [" 远警戒10s", alert.call(80.0, 10.0)], [" 远警戒20s", alert.call(80.0, 20.0)]]
		organ_sets = [[" 无", []], [" 鞭毛", ["flagellum"]], [" 纤毛", ["cilia"]]]
	# Level 10 (the devourer): the plain deck, fleeing far, or a breeding
	# season (forage: full -> breed; breed: flee, divide, graze, back after T);
	# each with no organ, the flagellum or the storage granules.
	if l.id == "2-5":
		var R := Rules
		var far := Rules.default_deck(0)
		far[0] = R.card(R.C_PREDATOR_NEAR, 100.0, R.C_NONE, 0.0, R.A_FLEE)
		var breed := func(calm: float) -> Array:
			var f: Array = far.duplicate(true)
			f[1] = R.card(R.C_ENERGY_ABOVE, 1.0, R.C_NONE, 0.0, R.A_TO_BREED)
			var cards := []
			for c: Dictionary in [R.card(R.C_PREDATOR_NEAR, 100.0, R.C_NONE, 0.0, R.A_FLEE), R.card(R.C_ENERGY_ABOVE, 1.0, R.C_NONE, 0.0, R.A_DIVIDE),
					R.card(R.C_ENERGY_BELOW, 1.0, R.C_SEE_ALGAE, 0.0, R.A_SEEK_ALGAE), R.card(R.C_STATE_TIME, calm, R.C_NONE, 0.0, R.A_TO_FORAGE)]:
				c.st = R.S_BREED
				cards.append(c)
			return f + cards
		decks = [[" 原样", null], [" 远逃", far], [" 繁殖20s", breed.call(20.0)], [" 繁殖40s", breed.call(40.0)]]
		organ_sets = [[" 无", []], [" 鞭毛", ["flagellum"]], [" 颗粒", ["granules"]]]
	# Level 11 (alarm calls): the plain deck, alert alone, shouting only, and
	# shout + "smell -> flee" (above feeding, or at the bottom); with no
	# organ, the flagellum, or the two signal organs.
	if l.id == "3-1":
		var R := Rules
		var shout: Array = Rules.default_deck(0)
		shout[0] = R.card(R.C_PREDATOR_NEAR, 60.0, R.C_NONE, 0.0, R.A_EMIT_A)
		var runs: Array = shout.duplicate(true)
		runs.insert(1, R.card(R.C_SIGNAL_A, 0.1, R.C_NONE, 0.0, R.A_FLEE))
		var low: Array = shout.duplicate(true)
		low.append(R.card(R.C_SIGNAL_A, 0.1, R.C_NONE, 0.0, R.A_FLEE))
		decks = [[" 原样", null], [" 只喊", shout], [" 喊+闻逃", runs], [" 喊+闻逃(下)", low]]
		organ_sets = [[" 无", []], [" 鞭毛", ["flagellum"]], [" 信号", ["gland", "chemo_rec"]]]
	# Level 12 (breeding together): the plain deck, a breeding season of its
	# own, and "see a peer breeding -> breed" (the rest card made room); with
	# no organ, the recognition protein, or the flagellum.
	if l.id == "3-2":
		var R := Rules
		var bc := []
		for c: Dictionary in [R.card(R.C_PREDATOR_NEAR, 100.0, R.C_NONE, 0.0, R.A_FLEE), R.card(R.C_ENERGY_ABOVE, 1.0, R.C_NONE, 0.0, R.A_DIVIDE),
				R.card(R.C_ENERGY_BELOW, 1.0, R.C_SEE_ALGAE, 0.0, R.A_SEEK_ALGAE), R.card(R.C_STATE_TIME, 40.0, R.C_NONE, 0.0, R.A_TO_FORAGE)]:
			c.st = R.S_BREED
			bc.append(c)
		var solo: Array = Rules.default_deck(0)
		solo[1] = R.card(R.C_ENERGY_ABOVE, 1.0, R.C_NONE, 0.0, R.A_TO_BREED)
		solo += bc
		var sync: Array = solo.filter(func(c: Dictionary) -> bool: return not (c.act == R.A_REST and int(c.get("st", 0)) == R.S_FORAGE))
		sync.insert(1, R.card(R.C_PEER_STATE, float(R.S_BREED), R.C_NONE, 0.0, R.A_TO_BREED))
		decks = [[" 原样", null], [" 繁殖期", solo], [" 同步", sync]]
		organ_sets = [[" 无", []], [" 识别", ["recog"]], [" 鞭毛", ["flagellum"]]]
	# Level 13 (quorum): the plain deck, secreting always, or only among 3 / 4
	# peers (above feeding).
	if l.id == "3-3":
		var R := Rules
		var b33: Array = (l.get("deck", []) as Array) if l.has("deck") else [R.card(R.C_ENERGY_ABOVE, 1.0, R.C_NONE, 0.0, R.A_DIVIDE), R.card(R.C_ENERGY_BELOW, 1.0, R.C_SEE_ALGAE, 0.0, R.A_SEEK_ALGAE), R.card(R.C_ENERGY_ABOVE, 1.0, R.C_NONE, 0.0, R.A_REST)]
		var mk := func(c: Dictionary) -> Array:
			var d2: Array = b33.duplicate(true)
			d2.insert(1, c)
			return d2
		decks = [[" 原样", b33], [" 一直分泌", mk.call(R.card(R.C_NONE, 0.0, R.C_NONE, 0.0, R.A_SECRETE))], [" 同伴≥3", mk.call(R.card(R.C_CROWD, 3.0, R.C_NONE, 0.0, R.A_SECRETE))],
			[" 同伴≥4", mk.call(R.card(R.C_CROWD, 4.0, R.C_NONE, 0.0, R.A_SECRETE))]]
		organ_sets = [[" 无", []], [" 鞭毛", ["flagellum"]]]
	# Level 17 (the phage as a weapon): left asleep, or woken by the old.
	if l.id == "4-3":
		var R := Rules
		var b43: Array = [R.card(R.C_ENERGY_ABOVE, 1.0, R.C_NONE, 0.0, R.A_DIVIDE), R.card(R.C_ENERGY_BELOW, 1.0, R.C_SEE_ALGAE, 0.0, R.A_SEEK_ALGAE), R.card(R.C_ENERGY_ABOVE, 1.0, R.C_NONE, 0.0, R.A_REST)]
		var mk43 := func(age: float) -> Array:
			var d2: Array = b43.duplicate(true)
			d2.insert(1, R.card(R.C_AGE_ABOVE, age, R.C_NONE, 0.0, R.A_INDUCE))
			return d2
		decks = [[" 原样", b43], [" 年龄70%", mk43.call(0.7)], [" 年龄60%", mk43.call(0.6)], [" 年龄90%", mk43.call(0.9)]]
		organ_sets = [[" 无", []], [" 鞭毛", ["flagellum"]]]
	# Level 16 (the memory): the start plan, away only without it, no hiding.
	if l.id == "4-2":
		var R := Rules
		var all42: Array = (l.start_design.deck as Array).duplicate(true)
		var only42: Array = all42.duplicate(true)
		only42[1].c2 = R.C_IMMUNE
		only42[1].n2 = true
		var none42: Array = all42.duplicate(true)
		none42.remove_at(1)
		decks = [[" 全员散开", all42], [" 没记忆的散开", only42], [" 不散开", none42]]
		organ_sets = [[" 无", []], [" 记忆片段", ["crispr"]]]
	# Level 15 (spreading out): the plain deck, or away from peers at 2 / 3 / 5.
	if l.id == "4-1":
		var R := Rules
		var b41: Array = [R.card(R.C_ENERGY_ABOVE, 1.0, R.C_NONE, 0.0, R.A_DIVIDE), R.card(R.C_ENERGY_BELOW, 1.0, R.C_SEE_ALGAE, 0.0, R.A_SEEK_ALGAE), R.card(R.C_ENERGY_ABOVE, 1.0, R.C_NONE, 0.0, R.A_REST)]
		var mk41 := func(n: float) -> Array:
			var d2: Array = b41.duplicate(true)
			d2.insert(1, R.card(R.C_CROWD, n, R.C_NONE, 0.0, R.A_DISPERSE))
			return d2
		decks = [[" 原样", b41], [" 同伴≥2", mk41.call(2.0)], [" 同伴≥3", mk41.call(3.0)], [" 同伴≥5", mk41.call(5.0)]]
		organ_sets = [[" 无", []], [" 鞭毛", ["flagellum"]]]
	# Chapter 3 boss (the echo): the start plan (alarm on A), the alarm moved
	# to B (0.5, and 0.1 that scares itself), no alarm; with the signal organs
	# or none.
	if l.id == "3-4":
		var R := Rules
		var on_a: Array = (l.start_design.deck as Array).duplicate(true)
		var on_b: Array = on_a.duplicate(true)
		on_b[0].act = R.A_EMIT_B
		on_b[1].c1 = R.C_SIGNAL_B
		on_b[1].t1 = 0.5
		var on_b1: Array = on_b.duplicate(true)
		on_b1[1].t1 = 0.1
		var quiet: Array = on_a.duplicate(true)
		quiet[0].act = R.A_FLEE
		quiet.remove_at(1)
		decks = [[" 警报A", on_a], [" 警报B", on_b], [" 警报B低门槛", on_b1], [" 不报警", quiet]]
		organ_sets = [[" 信号", ["gland", "chemo_rec"]], [" 鞭毛", ["flagellum"]]]
	# Level 8 (two species): the bot designs the prey; the predator is one of
	# three bodies with the level's deck (ambush), a sleep cycle, or roaming.
	var partners := [["", null]]
	if l.id == "2-3":
		var R := Rules
		var hunter: Array = (l.species[1].deck as Array).duplicate(true)
		var sleepy := hunter.duplicate(true)
		var nap := R.card(R.C_SEE_PREY, 0.0, R.C_STATE_TIME, 15.0, R.A_TO_SLEEP)
		nap.n1 = true
		sleepy.insert(2, nap)
		var wake := R.card(R.C_STATE_TIME, 30.0, R.C_NONE, 0.0, R.A_TO_FORAGE)
		wake.st = R.S_SLEEP
		sleepy.append(wake)
		var roam := hunter.duplicate(true)
		roam.remove_at(2)
		partners = []
		for pg: Array in [[2.0, 2.0, 1.0, 2.0, 2.0, 3.0, 3.0, 2.5], [3.0, 2.0, 1.0, 3.0, 2.0, 3.0, 3.0, 2.5], [4.0, 2.0, 1.0, 4.0, 3.0, 2.0, 3.0, 2.5]]:
			for dk2: Array in [["埋伏", hunter], ["休眠", sleepy], ["游荡", roam]]:
				partners.append([" 猎手速%d%s" % [int(pg[0]), dk2[0]], LevelEval.design_from_genes(pg, (dk2[1] as Array).duplicate(true), Color(0.9, 0.4, 0.5), 12.0, true, ["cnido"], l.id).params])
	var out := []
	for c: Array in combos:
		var genes := base.duplicate()
		for pair: Array in c:
			genes[pair[0]] = pair[1]
		for th: float in thresholds:
			for dk: Array in decks:
				var deck: Array = (dk[1] as Array).duplicate(true) if dk[1] != null else Rules.default_deck(0)
				if th < 0.0:
					deck.insert(1, Rules.card(Rules.C_CROWD, -th, Rules.C_NONE, 0.0, Rules.A_REST))
				# Only the divide card's slider, as the level-3 guide teaches.
				for card: Dictionary in deck if th > 0.0 and th != 1.0 else []:
					if card.act == Rules.A_DIVIDE:
						card.t1 = th
				for tp: float in temps:
					for mu: bool in muts:
						for pl: Array in ([[" 暖点", _plan(l)], [" 不暖", []]] if l.id == "1-4" else [["", _plan(l)]]):
							for os: Array in organ_sets:
								for pt: Array in partners:
									var d := LevelEval.design_from_genes(genes, deck.duplicate(true), Color(0.42, 0.8, 0.88), tp, mu, os[1], l.id)
									if pt[1] != null:
										d.extra = [pt[1]]
									if d.used <= float(l.budget):
										d.genes = genes
										d.plan = (pl[1] as Array).duplicate()
										d.tag = dk[0] + pl[0] + os[0] + pt[0] + "%s%s%s" % [(" 分%d%%" % roundi(th * 100.0) if th > 0.0 else " 挤%d休" % int(-th)) if thresholds.size() > 1 else "", " %d°C" % int(tp) if temps.size() > 1 else "", (" 变异" if mu else " 无变异") if muts.size() > 1 else ""]
										out.append(d)
	if out.size() > 240:
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		for i in range(out.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var tmp: Variant = out[i]
			out[i] = out[j]
			out[j] = tmp
		out = out.slice(0, 240)
	return out


func _play(l: Dictionary, seeds: int) -> void:
	var designs := _designs(l)
	print("== %s %s: %d designs within budget %d, %d seeds" % [l.id, l.name, designs.size(), l.budget, seeds])
	var best_stars := [false, false, false]
	var any_fail := false
	var rows := []
	# Every (design, seed) run in parallel, one thread each.
	var results := []
	results.resize(designs.size() * seeds)
	# Each run gets its own copies: runs share nothing (shared dictionaries
	# touched from several threads came apart: hunters that never hunted).
	var levels := []
	var ds := []
	for k in designs.size() * seeds:
		levels.append(l.duplicate(true))
		ds.append((designs[k / seeds] as Dictionary).duplicate(true))
	var job := func(k: int) -> void:
		results[k] = LevelEval.simulate(levels[k], ds[k], 1000 + (k % seeds) * 7919)
	var task := WorkerThreadPool.add_group_task(job, results.size(), -1, true)
	WorkerThreadPool.wait_for_group_task_completion(task)
	if OS.get_environment("BOT_DEBUG") != "":
		var shown := 0
		for k in designs.size():
			if not (designs[k].tag as String).contains("原样") or shown >= 3:
				continue
			shown += 1
			var ev: LevelEval = results[k * seeds]
			print("DEBUG %s alive %d eaten %d used %.1f params %s" % [designs[k].tag, ev.alive, ev.eaten, designs[k].used, str(designs[k].params).left(600)])
	for di in designs.size():
		var d: Dictionary = designs[di]
		var wins := 0
		var st := [0, 0, 0]
		var vals := []
		for s in seeds:
			var ev: LevelEval = results[di * seeds + s]
			var got := ev.stars()
			for k in 3:
				if got[k]:
					st[k] += 1
			if got[0]:
				wins += 1
			vals.append(_value(ev))
		for k in 3:
			if st[k] == seeds:
				best_stars[k] = true
		if wins == 0:
			any_fail = true
		rows.append([wins, d.genes, d.used, st, vals, d.tag])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0] or (a[0] == b[0] and a[2] < b[2]))
	for r: Array in rows.slice(0, 8):
		print("  wins %d/%d  used %4.1f  stars %s  value %s  genes %s%s" % [r[0], seeds, r[2], str(r[3]), str(r[4]), _short(r[1], l.genes_open), r[5]])
	# Best at the extra challenge.
	var by_extra := rows.duplicate()
	by_extra.sort_custom(func(a: Array, b: Array) -> bool: return a[3][1] > b[3][1])
	for r: Array in by_extra.slice(0, 4):
		print("  extra %d/%d  wins %d  value %s  genes %s%s" % [r[3][1], seeds, r[0], str(r[4]), _short(r[1], l.genes_open), r[5]])
	print("  ... worst:")
	for r: Array in rows.slice(rows.size() - 3):
		print("  wins %d/%d  used %4.1f  stars %s  value %s  genes %s%s" % [r[0], seeds, r[2], str(r[3]), str(r[4]), _short(r[1], l.genes_open), r[5]])
	# How each open gene's level bears on winning (share of runs won).
	var mattering := 0
	for g: int in l.genes_open:
		var line := "  %s:" % GENES[g]
		var shares := {}
		for v in [1.0, 2.0, 3.0, 4.0, 5.0]:
			var w := 0
			var n := 0
			for r: Array in rows:
				if r[1][g] == v:
					w += r[0]
					n += seeds
			line += "  Lv%d %3d%%" % [int(v), roundi(100.0 * w / maxf(n, 1))]
			if n > 0:
				shares[int(v)] = 100.0 * w / n
		print(line)
		var lo: float = shares.values().min()
		var hi: float = shares.values().max()
		if hi - lo >= 15.0:
			mattering += 1
		var top := 1
		for v: int in shares:
			if shares[v] > shares[top] + 0.01:
				top = v
		# An extreme that leads the next best by under 3 points is noise, not
		# "max it" / "keep it at Lv1": count it as a middle level.
		if top == 1 or top == 5:
			for v: int in shares:
				if v != top and shares[top] - shares[v] < 3.0:
					top = 3
					break
		if not best_lv.has(g):
			best_lv[g] = []
		best_lv[g].append(top)
	# (4-2 turns on the organ and one card; the genes barely move it, by design.)
	if l.genes_open.size() >= 2 and l.id != "4-2":
		check(mattering >= 2, "%s: at least two open genes matter (%d)" % [l.id, mattering])
	# Win share by the other choices (divide threshold, temperature, mutation).
	var tags := {}
	for r: Array in rows:
		for t: String in (r[5] as String).strip_edges().split(" ", false):
			if not tags.has(t):
				tags[t] = [0, 0, 0]
			tags[t][0] += r[0]
			tags[t][1] += seeds
			tags[t][2] += r[3][1]
	if not tags.is_empty():
		var line := "  choices:"
		for t: String in tags:
			line += "  %s 胜%d%% 附加%d%%" % [t, roundi(100.0 * tags[t][0] / maxf(tags[t][1], 1)), roundi(100.0 * tags[t][2] / maxf(tags[t][1], 1))]
		print(line)
	# Level 9: average population and losses per choice (tuning n and eaten).
	if l.goal.kind in ["alive_safe", "boss"]:
		var by := {}
		for di in designs.size():
			for t: String in (designs[di].tag as String).strip_edges().split(" "):
				if not by.has(t):
					by[t] = [0, 0, 0]
				for sd in seeds:
					var ev: LevelEval = results[di * seeds + sd]
					by[t][0] += ev.alive
					by[t][1] += ev.eaten
					by[t][2] += 1
		var line := "  avg alive/eaten:"
		for t: String in by:
			line += "  %s %d/%d" % [t, by[t][0] / maxi(by[t][2], 1), by[t][1] / maxi(by[t][2], 1)]
		print(line)
		if l.goal.kind == "boss":
			var starved := 0
			for ev: LevelEval in results:
				starved += 1 if ev.boss_dead >= 0.0 else 0
			print("  the devourer starved in %d of %d runs" % [starved, results.size()])
	# The weakest seed's population per design, by deck variant (tuning n).
	if l.goal.kind == "alive_end":
		for want: String in ["", "原样", "修好"]:
			var mins := []
			for di in designs.size():
				if want == "" or (designs[di].tag as String).contains(want):
					var m := 1 << 30
					for sd in seeds:
						m = mini(m, (results[di * seeds + sd] as LevelEval).alive)
					mins.append(m)
			if mins.is_empty():
				continue
			mins.sort()
			var q := []
			for k in 11:
				q.append(mins[mini(int(k / 10.0 * mins.size()), mins.size() - 1)])
			print("  min alive %s deciles: %s" % [want if want != "" else "all", str(q)])
	var winners := rows.filter(func(r: Array) -> bool: return r[0] == seeds).size()
	print("  designs winning every seed: %d of %d" % [winners, rows.size()])
	check(best_stars[0], "%s: the goal can be met reliably" % l.id)
	check(best_stars[1], "%s: the extra challenge can be met reliably" % l.id)
	check(best_stars[2], "%s: the low-budget star can be earned reliably" % l.id)
	check(any_fail, "%s: a poor design fails (the level asks for thought)" % l.id)
	# The very first level is meant to be forgiving: up to 70% may win.
	var most := 0.7 if l.index == 1 else 0.6
	check(winners < rows.size() * most, "%s: not most designs win (%d of %d)" % [l.id, winners, rows.size()])


# Interventions the bot plays where the level is about them: level 5 sends
# two currents from the release toward the two nearest patches at once
# (the starting 60 points) and a third toward the last at 50 s.
func _plan(l: Dictionary) -> Array:
	# Level 4: one warm spot on the cells when the cold arrives (as guided).
	if l.id == "1-4":
		return [{at = 126.0, kind = "heat"}]
	if l.goal.kind != "patches":
		return []
	var from: Vector2 = l.release.at
	var ps: Array = l.goal.patches.duplicate()
	ps.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return from.distance_to(a.center) < from.distance_to(b.center))
	var out := []
	for k in 3:
		var dir: Vector2 = (ps[k].center - from).normalized()
		# Two at once with the starting points, the third once income allows.
		out.append({at = 3.0 + k if k < 2 else 50.0, kind = "current", pos = from + dir * 120.0, velocity = dir * 70.0})
	return out


# The number that says how close a run came (per goal kind).
func _value(ev: LevelEval) -> String:
	match ev.level.goal.kind:
		"patches":
			return "%d片%s" % [ev.patches_won, str(ev.patch_counts)]
		"zone_count":
			return str(ev.zone_now)
		"coexist":
			return "%d/%d" % [ev.alive, ev.alive2]
	var extra := ""
	match ev.level.challenge.kind:
		"algae_left":
			extra = "/藻%d%%" % roundi(100.0 * ev.algae_now / maxf(ev.algae0, 1))
		"cold_lineage":
			extra = "/冷%d%%" % roundi(100.0 * ev.cold_share)
	return "%d%s" % [ev.alive, extra]


func _short(genes: Array, open: Array) -> String:
	var names := ["速", "感", "壳", "攻", "繁", "代", "神", "温"]
	var parts := []
	for g: int in open:
		parts.append("%s%d" % [names[g], int(genes[g])])
	return " ".join(parts)
