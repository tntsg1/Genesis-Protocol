extends SceneTree
# Probe for level 2-4: the guided deck (alert at 90 µm, calm 10 s, flagellum)
# over a few gene sets, many seeds: which gene step should the guide teach?
func _initialize() -> void:
	var l: Dictionary = Levels.by_id("2-4")
	var R := Rules
	var cards := Rules.default_deck(0)
	cards[0] = R.card(R.C_PREDATOR_NEAR, 80.0, R.C_NONE, 0.0, R.A_TO_ALERT)
	var run := R.card(R.C_PREDATOR_NEAR, float(OS.get_environment("RUN_D")), R.C_NONE, 0.0, R.A_FLEE)
	run.st = R.S_ALERT
	var back := R.card(R.C_STATE_TIME, 10.0, R.C_NONE, 0.0, R.A_TO_FORAGE)
	back.st = R.S_ALERT
	cards += [run, back]
	# [speed, vision, armor, attack, fertility, efficiency, neural, temp_tol]
	var sets := [["设计器默认 速2感2壳1繁3代3", [2, 2, 1, 1, 3, 3, 4, 3]],
		["按引导 速4感2壳1繁2代3", [4, 2, 1, 1, 2, 3, 4, 3]],
		["只加速 速4感2壳1繁3代3（超低预算）", [4, 2, 1, 1, 3, 3, 4, 3]]]
	var seeds := 12
	for s: Array in sets:
		var g: Array = (s[1] as Array).map(func(v: int) -> float: return float(v))
		var d := LevelEval.design_from_genes(g, cards.duplicate(true), Color(0.4, 0.8, 0.9), 12.0, true, ["flagellum"], "2-4")
		var results := []
		results.resize(seeds)
		var job := func(k: int) -> void:
			results[k] = LevelEval.simulate(l, d, 1000 + k * 7919)
		for k in seeds:
			job.call(k)
		var w := 0
		var ex := 0
		var lo := 0
		var al := 0
		var ea := 0
		for ev: LevelEval in results:
			var st: Array = ev.stars()
			w += 1 if st[0] else 0
			ex += 1 if st[1] else 0
			lo += 1 if st[2] else 0
			al += ev.alive
			ea += ev.eaten
		print("%s  used %d  胜 %d/%d  挑战 %d  低预算 %d  平均存活 %d 被吃 %d" % [s[0], int(d.used), w, seeds, ex, lo, al / seeds, ea / seeds])
	quit()
