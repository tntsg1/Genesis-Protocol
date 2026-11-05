extends SceneTree
# Pre-evolution of the native species (GDD 5.2). Each zone's natives evolve
# at home, before the sample is taken: a small dish filled with that zone's
# water (temperature, acid, radiation, light, vent chemistry), only its own
# community, run until they are about 50 generations in. Each native then
# keeps its typical genome (median genes over the last 15 minutes) and its
# designed deck; the result goes to data/natives_<code>.json, which the game
# loads.
# Run: godot --headless --path . -s tools/evolve_natives.gd [-- --generations=50]

const TICK := 1.0 / 15.0
const KEYS := ["speed", "vision", "armor", "attack", "fertility", "efficiency", "neural", "temp_tol"]


func _initialize() -> void:
	_run.call_deferred()


func _median(v: Array) -> float:
	v.sort()
	return v[v.size() / 2] if not v.is_empty() else 0.0


# A dish of one zone's water with that zone's natives.
func _home_dish(z: Dictionary, natives: Array, seed: int) -> SimCore:
	var sim := SimCore.new()
	sim.setup(Vector2(1400, 1400), seed)
	sim.set_dish(Vector2(700, 700), 640.0)
	sim.set_base_environment({temp = z.temp, acid = z.acid, radiation = z.radiation})
	sim.add_light(Vector2(520, 620), 360.0, 0.5 * z.light)
	sim.add_light(Vector2(880, 780), 360.0, 0.5 * z.light)
	if z.get("chem", 0.0) > 0.0 or z.get("vent", 0.0) > 0.0:
		sim.add_zone({center = Vector2(700, 700), radius = 900.0, temp = z.temp, acid = z.acid,
			radiation = z.radiation, light = 1.0, vent = z.get("vent", 0.0), chem = z.get("chem", 0.0)})
	sim.set_algae_cap(700)
	sim.seed_algae(400, 22.0)
	for p: Dictionary in natives:
		var params := p.duplicate()
		for k in ["name", "zone", "home", "niche", "count"]:
			params.erase(k)
		var s := sim.add_species(params)
		sim.spawn(s, Vector2(700, 700), p.count, 300.0)
	return sim


func _run() -> void:
	var target := 50
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--generations="):
			target = int(arg.get_slice("=", 1))
	var layout: Dictionary = Ecology.EUROPA_SAMPLE
	var path := "res://data/natives_%s.json" % String(layout.code).to_lower()
	var all := Natives.generate(layout, 7)
	var out := []
	var t0 := Time.get_ticks_msec()
	for z: Dictionary in layout.zones:
		var natives := all.filter(func(p: Dictionary) -> bool: return p.zone == z.key)
		var sim := _home_dish(z, natives, 4242)
		var samples := []
		var minutes := 0
		while true:
			for t in int(60.0 / TICK):
				sim.step(TICK)
			minutes += 1
			var gens := []
			var minute := []
			for k in natives.size():
				var live := []
				for pos in sim.get_positions(k):
					var info: Dictionary = sim.get_agent(sim.find_agent(pos, 2.0))
					if not info.is_empty():
						gens.append(info.generation)
						live.append(info)
				minute.append(live)
			samples.append(minute)
			if _median(gens) >= target or minutes >= 90:
				print("%s: %d minutes, median generation %.0f" % [z.name, minutes, _median(gens)])
				break
		for k in natives.size():
			var p: Dictionary = natives[k].duplicate(true)
			var genes := []
			for g in KEYS.size():
				genes.append([])
			var n := 0
			for minute in samples.slice(maxi(0, samples.size() - 15)):
				for info: Dictionary in minute[k]:
					n += 1
					for g in KEYS.size():
						genes[g].append(info.genes[g])
			if n == 0:
				print("  %s died out at home: keeping its generated genome" % p.name)
			else:
				for g in KEYS.size():
					p[KEYS[g]] = snappedf(_median(genes[g]), 0.01)
				print("  %s: %d samples; %s" % [p.name, n, ", ".join(KEYS.map(func(key: String) -> String: return "%s %.2f" % [key, p[key]]))])
			out.append(Natives.to_json(p))
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "\t"))
	f.close()
	print("wrote %s (%.1f s)" % [path, (Time.get_ticks_msec() - t0) / 1000.0])
	quit()
