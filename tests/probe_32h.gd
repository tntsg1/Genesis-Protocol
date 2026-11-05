extends SceneTree
# Debug for level 3-2: how long the hunters last (plain prey deck).
func _initialize() -> void:
	var l: Dictionary = Levels.by_id("3-2").duplicate(true)
	if OS.get_environment("EFF") != "":
		l.world.species[0].params.efficiency = float(OS.get_environment("EFF"))
	var d := LevelEval.design_from_genes([2.0, 2.0, 1.0, 1.0, 3.0, 3.0, 5.0, 3.0], Rules.default_deck(0), Color(0.4, 0.8, 0.9), 12.0, true, [], "3-2")
	var r := LevelEval.prepare(l, d, 1000, 1)
	var next := 0.0
	var line := ""
	while r.t < 300.0 and not r.eval.extinct:
		LevelEval.advance(r, 1.0 / 15.0)
		if r.t >= next:
			var s: Array = r.sim.get_stats().species
			line += " t%d 梭%d(饿%d) 你%d 吃%d" % [int(next), s[0].alive, int(s[0].starved), s[1].alive, int(s[1].eaten)]
			next += 30.0
	print(line)
	quit()
