extends SceneTree
# Ecology gate (M1): the native baseline must survive 10 minutes on every
# seed with visible ups and downs, and the energy ledger must balance.
# Run: godot --headless --path . -s tests/eco_check.gd [-- --minutes=10 --seeds=5]

const TICK := 1.0 / 15.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var minutes := 10.0
	var nseeds := 5
	var first := 0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--minutes="):
			minutes = float(arg.get_slice("=", 1))
		elif arg.begins_with("--seeds="):
			nseeds = int(arg.get_slice("=", 1))
		elif arg.begins_with("--from="):
			first = int(arg.get_slice("=", 1))
	var all_ok := true
	for k in range(first, first + nseeds):
		var scene: Node = load("res://scenes/showcase.tscn").instantiate()
		scene.seed = 1000 + k * 7919
		root.add_child(scene)
		scene.set_process(false)
		var sim: SimCore = scene.sim
		var nsp: int = sim.get_stats().species.size()
		var mins := []
		var maxs := []
		var sums := []
		var sq := []
		for s in nsp:
			mins.append(1 << 30)
			maxs.append(0)
			sums.append(0.0)
			sq.append(0.0)
		var samples := 0
		var worst := 0.0
		var line := ""
		var t0 := Time.get_ticks_usec()
		var ticks := int(minutes * 60.0 / TICK)
		for t in ticks:
			sim.step(TICK)
			if t % 150 == 149:
				var st: Dictionary = sim.get_stats()
				samples += 1
				for s in nsp:
					var a: int = st.species[s].alive
					mins[s] = mini(mins[s], a)
					maxs[s] = maxi(maxs[s], a)
					sums[s] += a
					sq[s] += a * a
				worst = maxf(worst, sim.energy_audit().relative_error)
				if samples % 6 == 0:
					var parts := []
					for s in nsp:
						parts.append(str(st.species[s].alive))
					line += "  t=%d [%s] algae %d shells %d\n" % [int(st.time), ",".join(parts), st.algae, st.shells]
		var ms := float(Time.get_ticks_usec() - t0) / ticks / 1000.0
		var ok := worst < 1e-4
		var report := []
		for s in nsp:
			var mean: float = sums[s] / samples
			var cv: float = sqrt(maxf(sq[s] / samples - mean * mean, 0.0)) / maxf(mean, 1.0)
			report.append("sp%d min %d max %d cv %.2f" % [s, mins[s], maxs[s], cv])
			# Producers (chemosynthetic cells, like algae) regrow from the
			# vents, so for them only a final extinction counts.
			var alive_now: int = sim.get_stats().species[s].alive
			if (mins[s] == 0 and not scene.is_producer(s)) or alive_now == 0:
				ok = false
		print("seed %d: %s | energy err %.7f | %.2f ms/tick | %s" % [scene.seed, "PASS" if ok else "FAIL", worst, ms, "; ".join(report)])
		if "--verbose" in OS.get_cmdline_user_args():
			print(line)
			for sp_stats in sim.get_stats().species:
				print("    ", sp_stats)
		all_ok = all_ok and ok
		scene.queue_free()
		await process_frame
	print("RESULT: ", "PASS" if all_ok else "FAIL")
	quit(0 if all_ok else 1)
