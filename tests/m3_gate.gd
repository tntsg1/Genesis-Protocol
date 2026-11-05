extends SceneTree
# M3 acceptance (GDD 17): the same genome does better or worse in different
# environments, and the game can say why. Each genome is released alone into
# a dish of each water of the Europa sample (open, vent, ice, acid), 3 seeds,
# 3 minutes. Checks: populations differ clearly between waters; the designer's
# fitness forecast ranks the waters the way they turn out; where a water is
# wrong for it, its energy accounts name the cause (the share burnt on heat or
# cold, or on acid). A vent-adapted
# genome must rank the waters the other way round. Headless.
# Run: godot --headless --path . -s tests/m3_gate.gd

const TICK := 1.0 / 15.0
const SEEDS := [11, 22, 33]
const MINUTES := 3.0
var fails := 0


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func _trial(water: Dictionary, genome: Dictionary, seed: int) -> Dictionary:
	var sim := SimCore.new()
	sim.setup(Vector2(1400, 1400), seed)
	sim.set_dish(Vector2(700, 700), 640.0)
	sim.set_base_environment({temp = water.temp, acid = water.acid, radiation = water.get("radiation", 0.05)})
	sim.add_light(Vector2(520, 620), 360.0, 0.5)
	sim.add_light(Vector2(880, 780), 360.0, 0.5)
	sim.set_algae_cap(700)
	sim.seed_algae(400, 22.0)
	sim.add_species(genome)
	sim.spawn(0, Vector2(700, 700), 120, 300.0)
	var sum := 0.0
	var n := 0
	for t in int(MINUTES * 60.0 / TICK):
		sim.step(TICK)
		if t % 15 == 0:
			sum += sim.get_count()
			n += 1
	var st: Dictionary = sim.get_stats().species[0]
	var burn: float = maxf(st.burn_total, 1e-6)
	return {mean = sum / n, temp = st.burn_temp / burn, acid = st.burn_acid / burn}


func _rank(v: Array) -> Array:
	var idx := range(v.size())
	idx.sort_custom(func(a: int, b: int) -> bool: return v[a] > v[b])
	return idx


func _test(label: String, genome: Dictionary) -> Array:
	var layout: Dictionary = Ecology.EUROPA_SAMPLE
	var waters := [{name = "开阔水域", temp = layout.base.temp, acid = layout.base.acid}]
	for z: Dictionary in layout.zones:
		waters.append({name = z.name, temp = z.temp, acid = z.acid, radiation = z.radiation})
	var genes := [genome.speed, genome.vision, genome.armor, genome.attack, genome.fertility, genome.efficiency, genome.neural, genome.temp_tol]
	var means := []
	var forecast := []
	print("— %s (最适 %d°C, 耐温 Lv %.1f, 外壳 %.1f)" % [label, genome.temp_opt, genome.temp_tol, genome.armor])
	for w: Dictionary in waters:
		var m := 0.0
		var tshare := 0.0
		var ashare := 0.0
		for s in SEEDS:
			var r := _trial(w, genome, s)
			m += r.mean / SEEDS.size()
			tshare += r.temp / SEEDS.size()
			ashare += r.acid / SEEDS.size()
		var f := Ecology.fitness(genes, genome.temp_opt, w)
		means.append(m)
		forecast.append(f)
		print("  %-6s population %4.0f   forecast %3d%%   energy burnt on heat/cold %2d%%  acid %2d%%" % [w.name, m, roundi(f * 100), roundi(tshare * 100), roundi(ashare * 100)])
		w["tshare"] = tshare
		w["ashare"] = ashare
	var best: float = means.max()
	var worst: float = means.min()
	check(best > worst * 2.0, "%s: populations differ clearly between waters (%.0f vs %.0f)" % [label, best, worst])
	var r_obs := _rank(means)
	var r_fc := _rank(forecast)
	check(r_obs[0] == r_fc[0] and r_obs[-1] == r_fc[-1], "%s: the forecast picks the same best and worst water (%s / %s)" % [label, waters[r_fc[0]].name, waters[r_fc[-1]].name])
	# Explanations: where it struggles, its energy went to the water's fault.
	for k in waters.size():
		var w: Dictionary = waters[k]
		if forecast[k] < 0.6:
			var named: bool = w.tshare > 0.25 or w.ashare > 0.25
			check(named, "%s in %s: its energy shows why (%d%% on heat/cold, %d%% on acid)" % [label, w.name, roundi(w.tshare * 100), roundi(w.ashare * 100)])
	return r_obs


func _run() -> void:
	var base := {color = Color.AQUA, radius = 5.5, speed = 2.0, vision = 2.5, armor = 1.4, attack = 1.0,
		fertility = 3.0, efficiency = 3.0, lifespan = 80.0, neural = 3.0, temp_opt = 12.0, temp_tol = 2.5}
	var r1 := _test("温和水域型", base)
	var vent := base.duplicate()
	vent.temp_opt = 34.0
	vent.temp_tol = 2.0
	var r2 := _test("热泉适应型", vent)
	check(r1[0] != r2[0], "a different genome ranks the waters differently (best: %d vs %d)" % [r1[0], r2[0]])
	print("RESULT: ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(0 if fails == 0 else 1)
