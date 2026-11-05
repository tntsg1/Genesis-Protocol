extends SceneTree
# M1 acceptance gate (design/DECISIONS.md, M1 round 2, Q13). Headless.
#   --only=energy  30 sim-minutes, ledger error < 1e-4
#   --only=perf    3000 organisms + 800 algae, <= 3 ms per tick
#   --only=soak    2 sim-hours with render-buffer building; process memory
#                  after warm-up must not keep growing (< 5% drift)
# The 5-seed ecology gate is tests/eco_check.gd.
# Run: godot --headless --path . -s tests/m1_gate.gd -- --only=energy

const TICK := 1.0 / 15.0


func _initialize() -> void:
	_run.call_deferred()


func _make(seed: int) -> Node:
	var scene: Node = load("res://scenes/showcase.tscn").instantiate()
	scene.seed = seed
	root.add_child(scene)
	scene.set_process(false)
	return scene


func _rss_mb() -> float:
	var out := []
	OS.execute("powershell", ["-NoProfile", "-Command", "(Get-Process -Id %d).WorkingSet64" % OS.get_process_id()], out)
	return float(str(out[0]).strip_edges()) / 1048576.0 if out.size() > 0 else -1.0


func _run() -> void:
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = arg.get_slice("=", 1)
	var ok := true
	if only in ["", "energy"]:
		var sim: SimCore = _make(1000).sim
		var worst := 0.0
		for t in int(30 * 60 / TICK):
			sim.step(TICK)
			if t % 900 == 0:
				worst = maxf(worst, sim.energy_audit().relative_error)
		worst = maxf(worst, sim.energy_audit().relative_error)
		var pass_e := worst < 1e-4
		print("ENERGY 30 min: worst relative error %.7f -> %s" % [worst, "PASS" if pass_e else "FAIL"])
		ok = ok and pass_e
	if only in ["", "perf"]:
		var sim: SimCore = _make(2000).sim
		sim.set_algae_cap(1300)
		for i in 30:
			sim.step(TICK)
		var need := 3000 - sim.get_count()
		sim.spawn(0, Vector2(1100, 1100), need / 2, 900.0)
		sim.spawn(1, Vector2(1100, 1100), need - need / 2, 900.0)
		sim.seed_algae(1300 - sim.get_algae_count(), 25.0)
		sim.get_profile()
		var t0 := Time.get_ticks_usec()
		var n := 300
		var orgs := 0
		var alg := 0
		for i in n:
			sim.step(TICK)
			orgs += sim.get_count()
			alg += sim.get_algae_count()
		var ms := float(Time.get_ticks_usec() - t0) / n / 1000.0
		print("  phases (us/tick): ", sim.get_profile())
		var pass_p: bool = ms <= 3.0 and orgs / n >= 2800 and alg / n >= 800
		print("PERF: %.2f ms/tick with avg %d organisms, %d algae -> %s" % [ms, orgs / n, alg / n, "PASS" if pass_p else "FAIL"])
		ok = ok and pass_p
	if only in ["", "soak"]:
		var sim: SimCore = _make(3000).sim
		var ticks := int(2 * 3600 / TICK)
		var warm := int(5 * 60 / TICK)
		var base := 0.0
		var peak := 0.0
		var t0 := Time.get_ticks_msec()
		for t in ticks:
			sim.step(TICK)
			if t % 15 == 0:
				sim.build_render_buffer(0.5, t * TICK, 12000)
				sim.get_nutrient_field()
			if t == warm:
				base = _rss_mb()
			if t > warm and t % int(15 * 60 / TICK) == 0:
				var m := _rss_mb()
				peak = maxf(peak, m)
				print("  soak t=%d min rss %.1f MB organisms %d algae %d shells %d" % [int(t * TICK / 60), m, sim.get_count(), sim.get_algae_count(), sim.get_shell_count()])
		var end := _rss_mb()
		var drift := (end - base) / maxf(base, 1.0)
		var pass_s := drift < 0.05
		print("SOAK 2 h (sim time, %.0f s wall): rss %.1f -> %.1f MB (peak %.1f), drift %.1f%% -> %s" % [
			(Time.get_ticks_msec() - t0) / 1000.0, base, end, peak, drift * 100.0, "PASS" if pass_s else "FAIL"])
		ok = ok and pass_s
	print("RESULT: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
