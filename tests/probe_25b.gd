extends SceneTree
# Probe for level 2-5: a few player plans over several seeds: wins, the boss
# starved, alive at the end, eaten.
func _initialize() -> void:
	var l: Dictionary = Levels.by_id("2-5")
	var R := Rules
	var seeds := int(OS.get_environment("SEEDS")) if OS.get_environment("SEEDS") != "" else 4
	var far := Rules.default_deck(0)
	far[0] = R.card(R.C_PREDATOR_NEAR, 100.0, R.C_NONE, 0.0, R.A_FLEE)
	# Breeding: in forage, energy full -> breed; in breed, flee / divide / back after T.
	var breed := func(calm: float) -> Array:
		var f := Rules.default_deck(0)
		f[0] = R.card(R.C_PREDATOR_NEAR, 100.0, R.C_NONE, 0.0, R.A_FLEE)
		f[1] = R.card(R.C_ENERGY_ABOVE, 1.0, R.C_NONE, 0.0, R.A_TO_BREED)
		var run := R.card(R.C_PREDATOR_NEAR, 100.0, R.C_NONE, 0.0, R.A_FLEE)
		run.st = R.S_BREED
		var div := R.card(R.C_ENERGY_ABOVE, 1.0, R.C_NONE, 0.0, R.A_DIVIDE)
		div.st = R.S_BREED
		var eat := R.card(R.C_ENERGY_BELOW, 1.0, R.C_SEE_ALGAE, 0.0, R.A_SEEK_ALGAE)
		eat.st = R.S_BREED
		var back := R.card(R.C_STATE_TIME, calm, R.C_NONE, 0.0, R.A_TO_FORAGE)
		back.st = R.S_BREED
		return f + [run, div, eat, back]
	var g2 := [2.0, 2.0, 1.0, 1.0, 3.0, 3.0, 5.0, 3.0]
	var g4 := [4.0, 2.0, 1.0, 1.0, 2.0, 3.0, 5.0, 3.0]
	var plans := [["原样", Rules.default_deck(0), g2], ["远逃", far, g2], ["远逃速4", far, g4],
		["繁殖期20s", breed.call(20.0), g2], ["繁殖期40s速4", breed.call(40.0), g4], ["繁殖期40s速4繁3", breed.call(40.0), [4.0, 2.0, 1.0, 1.0, 3.0, 3.0, 5.0, 3.0]]]
	for pl: Array in plans:
		var d := LevelEval.design_from_genes(pl[2], pl[1], Color(0.4, 0.8, 0.9), 12.0, true, [], "2-5")
		var w := 0
		var dead := 0
		var al := 0
		var ea := 0
		var bmax := 0
		var at := [0, 0, 0]
		for k in seeds:
			var ev: LevelEval = LevelEval.simulate(l, d, 1000 + k * 7919)
			var st: Array = ev.stars()
			w += 1 if st[0] else 0
			dead += 1 if ev.boss_dead >= 0.0 else 0
			al += ev.alive
			ea += ev.eaten
			bmax = maxi(bmax, ev.boss_alive)
			for c: Array in ev.curve:
				for q in 3:
					if absf(float(c[0]) - [120.0, 180.0, 239.0][q]) < 0.26:
						at[q] += int(c[1])
		print("%s  used %d  胜 %d/%d  饿死 %d  平均存活 %d  被吃 %d  结束时巨噬者最多 %d  2/3/4分 %d/%d/%d" % [pl[0], int(d.used), w, seeds, dead, al / seeds, ea / seeds, bmax, at[0] / seeds, at[1] / seeds, at[2] / seeds])
	quit()
