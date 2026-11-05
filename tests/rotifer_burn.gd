extends SceneTree
# How fast 5-4's guardian runs down on its own (no prey within reach) and what
# it does with prey about: its energy share and swallows every 30 s.
# Env R_BURN, R_FULL. Run headless: godot --headless -s tests/rotifer_burn.gd


func _initialize() -> void:
	var l: Dictionary = Levels.by_id("5-5").duplicate(true)
	var rp: Dictionary = l.world.species[0].params
	rp.burn = float(OS.get_environment("R_BURN")) if OS.get_environment("R_BURN") != "" else rp.burn
	rp.rot_full = float(OS.get_environment("R_FULL")) if OS.get_environment("R_FULL") != "" else rp.rot_full
	var d0: Dictionary = l.start_design
	var d := LevelEval.design_from_genes(d0.genes, (d0.deck as Array).duplicate(true), d0.color, 12.0, false, [], "5-5")
	d.params.blocks = d0.blocks
	var run := LevelEval.prepare(l, d, 5, 2)
	var next := 0.0
	while float(run.t) < 360.0:
		LevelEval.advance(run, 1.0 / 15.0)
		if float(run.t) >= next:
			next += 30.0
			var r: PackedFloat32Array = (run.sim as SimCore).get_rotifers(1.0)
			print("t %3d  守卫能量 %s  吞 %s 吐 %s  群体 %d" % [int(run.t), ("%.2f" % r[5]) if r.size() > 5 else "死", run.eval.colony_stats.get("swallowed", 0), run.eval.colony_stats.get("spat", 0), run.eval.alive])
	quit()
