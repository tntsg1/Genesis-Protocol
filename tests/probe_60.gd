extends SceneTree
# Chapter 6 kernel probe (no window): the light from above, the vents, the
# oxygen field. A chemosynthetic anaerobe at the vents, a producer in the
# light, optionally aerobic grazers. Env: P_MIN (minutes), P_PHOTO (producers
# at start), P_GRAZE (aerobic grazers), P_RESP (grazers' respiration),
# P_EMIT, P_DECAY, P_SULF, P_TOX, P_HARM, P_IRON (1: iron dust at minute 2).
func _env(key: String, d: float) -> float:
	return float(OS.get_environment(key)) if OS.get_environment(key) != "" else d


const VENTS := [Vector2(700, 1780), Vector2(1100, 1950), Vector2(1500, 1780)]


func _initialize() -> void:
	var sim := SimCore.new()
	sim.setup(Vector2(2200, 2200), int(_env("P_SEED", 7)))
	sim.set_dish(Vector2(1100, 1100), 1060.0)
	sim.set_algae_cap(0)
	sim.add_light_band(350.0, 1000.0, float(_env("P_LIGHT", 0.6)))
	for v: Vector2 in VENTS:
		sim.add_zone({center = v, radius = 230.0, temp = 26.0, chem = 1.0})
	sim.set_oxygen({emit = _env("P_EMIT", 0.05), decay = _env("P_DECAY", 0.003), sulfide = _env("P_SULF", 0.6),
		tox = _env("P_TOX", 0.08), harm = _env("P_HARM", 1.2)})
	# 0: anaerobic chemotroph (硫泉游丝), 1: producer (晨光丝), 2: grazer
	sim.add_species({color = Color(0.9, 0.6, 0.3), diet = 2, radius = 5.5, resp = 1, reseed = false, temp_opt = 26.0, temp_tol = 3.0, lifespan = 120.0})
	sim.add_species({color = Color(0.4, 0.85, 0.5), diet = 3, radius = 5.0, resp = 0, speed_mult = 0.6, lifespan = 120.0, temp_tol = 4.0})
	sim.add_species({color = Color(0.4, 0.6, 0.95), diet = 0, radius = 6.5, resp = int(_env("P_RESP", 2)), lifespan = 110.0, temp_tol = 4.0})
	for v: Vector2 in VENTS:
		sim.spawn(0, v, 20, 80.0)
	sim.spawn(1, Vector2(1100, 450), int(_env("P_PHOTO", 60)), 300.0)
	if _env("P_GRAZE", 0) > 0:
		sim.spawn(2, Vector2(1100, 600), int(_env("P_GRAZE", 0)), 250.0)
	var mins := _env("P_MIN", 6.0)
	var dt := 1.0 / 15.0
	var steps := int(mins * 60.0 / dt)
	var t0 := Time.get_ticks_msec()
	for k in steps:
		sim.step(dt)
		if _env("P_IRON", 0) > 0 and k == int(120.0 / dt):
			sim.add_iron(Vector2(1100, 1500), 300.0, 40.0)
		if k % int(30.0 / dt) == 0 or k == steps - 1:
			var st: Dictionary = sim.get_stats()
			var sp: Array = st.species
			var pe := 0.0
			var pn := 0
			var ys := 0.0
			for a in 400:
				var ag: Dictionary = sim.get_agent(a)
				if not ag.is_empty() and int(ag.get("species", -1)) == 1:
					pe += float(ag.energy)
					ys += float(ag.position.y) if ag.has("position") else 0.0
					pn += 1
			if pn > 0:
				print("   晨光 平均能量 %.1f 平均 y %.0f 出生 %d 光(450) %.3f" % [pe / pn, ys / pn, sp[1].births, sim.get_light_field()[int(450 / 16) * 138 + 68] * 255.0 / 400.0])
			print("t=%3ds  硫泉 %3d (氧死 %3d 饿 %3d 老 %3d)  晨光 %3d (被吃 %3d)  采集 %3d  平均氧 %.3f  上 %.3f 中 %.3f 泉 %.3f  >8%%水域 %.2f" % [
				int(k * dt), sp[0].alive, sp[0].o2, sp[0].starved, sp[0].aged, sp[1].alive, sp[1].eaten, sp[2].alive,
				sim.get_o2_mean(), sim.get_o2_at(Vector2(1100, 450)), sim.get_o2_at(Vector2(1100, 1100)), sim.get_o2_at(VENTS[1]),
				sim.get_o2_share(0.08)])
	var au: Dictionary = sim.energy_audit()
	print("能量账误差 %.4f  用时 %d ms" % [au.relative_error, Time.get_ticks_msec() - t0])
	quit()
