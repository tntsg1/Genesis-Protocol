extends SceneTree
# Debug for level 3-1: algae, population and the smell at a bloom over time.
func _initialize() -> void:
	var l: Dictionary = Levels.by_id("3-1")
	var R := Rules
	var base := [R.card(R.C_ENERGY_ABOVE, 1.0, R.C_NONE, 0.0, R.A_DIVIDE), R.card(R.C_ENERGY_BELOW, 1.0, R.C_SEE_ALGAE, 0.0, R.A_SEEK_ALGAE),
		R.card(R.C_ENERGY_ABOVE, 1.0, R.C_NONE, 0.0, R.A_REST)]
	var call := R.card(R.C_SEE_ALGAE, 0.0, R.C_ENERGY_ABOVE, 1.0, R.A_EMIT_A)
	var listen := R.card(R.C_NONE, 0.0, R.C_NONE, 0.0, R.A_SEEK_SIG_A)
	var both := [base[0], call, base[1], listen, base[2]]
	var d := LevelEval.design_from_genes([2.0, 2.0, 1.0, 1.0, 3.0, 3.0, 4.0, 3.0], both, Color(0.4, 0.8, 0.9), 12.0, true, ["gland", "chemo_rec"], "3-1")
	var r := LevelEval.prepare(l, d, 1000, 1)
	var next := 0.0
	while r.t < 300.0 and not r.eval.extinct:
		LevelEval.advance(r, 1.0 / 15.0)
		if r.t >= next:
			var sim: SimCore = r.sim
			var st: Dictionary = sim.get_stats()
			var line := "t%d 你%d 藻%d 藻能%d 饿死%d 老死%d 温耗%.0f 水温%.1f" % [int(next), st.species[0].alive, sim.get_algae_count(), int(st.energy_algae), int(st.species[0].starved), int(st.species[0].aged), float(st.species[0].burn_temp), float(st.species[0].temp)]
			var ps: PackedVector2Array = sim.get_positions(0)
			if not ps.is_empty():
				var a: Dictionary = sim.get_agent(sim.find_agent(ps[0], 1.0))
				line += " 信号A@0 %.3f 能%.2f" % [float(a.get("signal_a", 0.0)), float(a.get("energy_frac", 0.0))]
			var an: PackedFloat32Array = sim.get_analysis(Rect2(0, 0, 2200, 2200), 1.0)
			var cnt := {}
			for k in range(0, an.size(), 8):
				var ac := int(an[k + 3])
				cnt[ac] = cnt.get(ac, 0) + 1
			line += " 动作%s" % str(cnt)
			var mx := 0.0
			for p2: Vector2 in ps:
				mx = maxf(mx, float(sim.get_agent(sim.find_agent(p2, 1.0)).get("signal_a", 0.0)))
			line += " 最浓%.3f" % mx
			if not r.eval.blooms.is_empty():
				var bl: Dictionary = r.eval.blooms[-1]
				line += " 藻华%d@%s 到%s" % [r.eval.blooms.size(), str(bl.at.round()), str(bl.reached)]
			print(line)
			next += 10.0
	quit()
