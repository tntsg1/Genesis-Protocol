extends SceneTree
# Unit check for "游向信号 A": callers sit at one spot; trackers 200 µm off
# should close in on them.
func _initialize() -> void:
	var R := Rules
	var sim := SimCore.new()
	sim.setup(Vector2(2200, 2200), 7)
	sim.set_dish(Vector2(1100, 1100), 1060.0)
	var all := {cond_mask = 0xFFFFFFFF, act_mask = 0xFFFFFFFF, logic = true}
	var caller := {color = Color.RED, radius = 5.5, speed = 1.0, vision = 2.0, armor = 1.0, attack = 1.0, fertility = 1.0, efficiency = 5.0, neural = 4.0,
		lifespan = 999.0, cohesion = 0.0, temp_opt = 12.0, temp_tol = 5.0, mutates = false, deck = [R.card(R.C_NONE, 0.0, R.C_NONE, 0.0, R.A_EMIT_A)]}
	caller.merge(all)
	var tracker := caller.duplicate()
	tracker.speed = 2.0
	tracker.deck = [R.card(R.C_NONE, 0.0, R.C_NONE, 0.0, R.A_SEEK_SIG_A)]
	sim.add_species(caller)
	sim.add_species(tracker)
	sim.spawn(0, Vector2(1100, 1100), 6, 15.0)
	sim.spawn(1, Vector2(1300, 1100), 10, 20.0)
	for s in 8:
		for k in 15 * 3:
			sim.step(1.0 / 15.0)
		var d := 0.0
		var ps: PackedVector2Array = sim.get_positions(1)
		for p: Vector2 in ps:
			d += p.distance_to(Vector2(1100, 1100))
		var an: PackedFloat32Array = sim.get_analysis(Rect2(0, 0, 2200, 2200), 1.0)
		var acts := {}
		for k in range(0, an.size(), 8):
			if int(an[k + 6]) == 1:
				acts[int(an[k + 3])] = acts.get(int(an[k + 3]), 0) + 1
		var a0: Dictionary = sim.get_agent(sim.find_agent(ps[0], 1.0))
		print("t%d 循味者平均距离 %.0f  动作%s  第一只处信号 %.4f" % [(s + 1) * 3, d / ps.size(), str(acts), float(a0.get("signal_a", 0.0))])
	quit()
