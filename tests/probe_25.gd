extends SceneTree
# Probe for level 2-5: the devourer over time (count, energy) against a few
# player plans.
func _initialize() -> void:
	var l: Dictionary = Levels.by_id("2-5")
	var R := Rules
	var far := Rules.default_deck(0)
	far[0] = R.card(R.C_PREDATOR_NEAR, 100.0, R.C_NONE, 0.0, R.A_FLEE)
	var genes := [2.0, 2.0, 1.0, 1.0, 3.0, 3.0, 5.0, 3.0]
	var fast := [4.0, 2.0, 1.0, 1.0, 2.0, 3.0, 5.0, 3.0]
	for dk: Array in [["原样", Rules.default_deck(0), genes], ["远逃", far, genes], ["远逃速4", far, fast]]:
		var d := LevelEval.design_from_genes(dk[2], dk[1], Color(0.4, 0.8, 0.9), 12.0, true, [], "2-5")
		var r := LevelEval.prepare(l, d, 1000, 1)
		var line := "%s:" % dk[0]
		var next := 0.0
		var shown := false
		while r.t < 360.0 and not r.eval.extinct:
			LevelEval.advance(r, 1.0 / 15.0)
			if r.t >= next:
				var st: Dictionary = r.sim.get_stats()
				if not shown:
					shown = true
					print(st.species[0].keys())
				var be := 0.0
				for p: Vector2 in r.sim.get_positions(0):
					be += float(r.sim.get_agent(r.sim.find_agent(p, 1.0)).get("energy", 0.0))
				line += "  t%d 噬%d(%d) 你%d 吃%d" % [int(next), st.species[0].alive, int(be), st.species[1].alive, int(st.species[1].eaten)]
				next += 30.0
		r.eval.finish()
		print(line, "  星", r.eval.stars(), " boss_dead ", r.eval.boss_dead)
	quit()
