extends SceneTree
# Probe for level 2-4: hunters and prey over time for a few decks.
func _initialize() -> void:
	var l: Dictionary = Levels.by_id("2-4")
	var R := Rules
	var alert := [R.card(R.C_PREDATOR_NEAR, 90.0, R.C_NONE, 0.0, R.A_TO_ALERT),
		R.card(R.C_ENERGY_ABOVE, 1.0, R.C_NONE, 0.0, R.A_DIVIDE),
		R.card(R.C_ENERGY_BELOW, 1.0, R.C_SEE_ALGAE, 0.0, R.A_SEEK_ALGAE)]
	var run := R.card(R.C_PREDATOR_NEAR, 90.0, R.C_NONE, 0.0, R.A_FLEE)
	run.st = R.S_ALERT
	var back := R.card(R.C_STATE_TIME, 6.0, R.C_NONE, 0.0, R.A_TO_FORAGE)
	back.st = R.S_ALERT
	alert += [run, back]
	for dk: Array in [["原样", Rules.default_deck(0)], ["警戒", alert]]:
		var d := LevelEval.design_from_genes([3.0, 2.0, 1.0, 1.0, 3.0, 3.0, 4.0, 3.0], dk[1], Color(0.4, 0.8, 0.9), 12.0, true, [], "2-4")
		var r := LevelEval.prepare(l, d, 1000, 1)
		var line := "%s r=%.2f:" % [dk[0], float(d.params.get("radius", -1.0))]
		var next := 0.0
		while r.t < 300.0 and not r.eval.extinct:
			LevelEval.advance(r, 1.0 / 15.0)
			if r.t >= next:
				var st: Dictionary = r.sim.get_stats()
				line += "  t%d 伏%d 你%d 吃%d" % [int(next), st.species[0].alive, st.species[1].alive, int(st.species[1].eaten)]
				next += 30.0
		print(line)
	quit()
