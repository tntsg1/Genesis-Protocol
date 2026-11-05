extends SceneTree
# Debug for level 3-2: the huddle plan over time (deaths by cause, actions).
func _initialize() -> void:
	var l: Dictionary = Levels.by_id("3-2")
	var R := Rules
	var st := func(c: Dictionary, s: int) -> Dictionary:
		c.st = s
		return c
	var deck: Array = Rules.default_deck(0)
	deck[0] = R.card(R.C_PREDATOR_NEAR, 80.0, R.C_NONE, 0.0, R.A_TO_ALERT)
	deck.insert(1, R.card(R.C_PEER_STATE, float(R.S_ALERT), R.C_NONE, 0.0, R.A_FOLLOW))
	deck += [st.call(R.card(R.C_ENERGY_BELOW, 1.0, R.C_SEE_ALGAE, 0.0, R.A_SEEK_ALGAE), R.S_ALERT), st.call(R.card(R.C_NONE, 0.0, R.C_NONE, 0.0, R.A_FOLLOW), R.S_ALERT),
		st.call(R.card(R.C_STATE_TIME, 10.0, R.C_NONE, 0.0, R.A_TO_FORAGE), R.S_ALERT)]
	var d := LevelEval.design_from_genes([2.0, 2.0, 1.0, 1.0, 3.0, 3.0, 5.0, 3.0], deck, Color(0.4, 0.8, 0.9), 12.0, true, ["recog"], "3-2")
	print("masks ", d.params.get("cond_mask", -1), " ", d.params.get("act_mask", -1))
	var r := LevelEval.prepare(l, d, 1000, 1)
	var next := 0.0
	while r.t < 120.0 and not r.eval.extinct:
		LevelEval.advance(r, 1.0 / 15.0)
		if r.t >= next:
			var sim: SimCore = r.sim
			var s: Dictionary = sim.get_stats().species[1]
			var an: PackedFloat32Array = sim.get_analysis(Rect2(0, 0, 2200, 2200), 1.0)
			var acts := {}
			for k in range(0, an.size(), 8):
				if int(an[k + 6]) == 1:
					acts[int(an[k + 3])] = acts.get(int(an[k + 3]), 0) + 1
			var mk: PackedFloat32Array = sim.get_marks(Rect2(0, 0, 2200, 2200), 1.0)
			var sts := {}
			for k in range(0, mk.size(), 6):
				if int(mk[k + 2]) == 1:
					sts[int(mk[k + 3])] = sts.get(int(mk[k + 3]), 0) + 1
			print("t%d 活%d 饿死%d 被吃%d 老死%d 动作%s 状态%s" % [int(next), s.alive, int(s.starved), int(s.eaten), int(s.aged), str(acts), str(sts)])
			next += 10.0
	quit()
