extends SceneTree
# Plays levels 22-24 for real, through the game itself: the guide's body put
# together on the bench block by block, released, run at 8x to the report;
# five runs each. (The probe runs headless with its own setup; this is the
# check that the real thing matches it.) Env PC_RUNS (5), PC_LEVELS (5-3,5-4,5-5).
# Run: tools/run_test.sh tests/play_ch5.gd

var scene: Node2D

# The guide's bodies, rows from the top, front at the right:
# F flagellum, G germ, A armour, S store, R regeneration.
const GUIDES := {
	"5-3": ["AFFF", "GSGF", "AFFF"],
	"5-4": ["ARFF", "GGGF", "AFFF"],
	"5-5": ["AAFF", "ARGF", "AGFF"],
}


func _initialize() -> void:
	CampaignSave.reset_for_tests()
	root.add_child(preload("res://tests/test_window.gd").new())
	scene = load("res://scenes/showcase.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	_run.call_deferred()


func _until(cond: Callable, limit := 10.0) -> bool:
	var end := Time.get_ticks_msec() + int(limit * 1000.0)
	while not cond.call() and Time.get_ticks_msec() < end:
		await process_frame
	return cond.call()


func _build(bench: Control, rows: Array) -> void:
	var kinds := {"F": Colony.FLAG, "G": Colony.GERM, "A": Colony.ARMOR, "S": Colony.STORE, "R": Colony.REGEN}
	var lo := Vector2i(100, 100)
	for c: Array in bench.cells:
		lo = Vector2i(mini(lo.x, int(c[0])), mini(lo.y, int(c[1])))
	for j in rows.size():
		var r: String = rows[j]
		for i in r.length():
			var at := lo + Vector2i(i, j)
			if int(Colony.type_at(bench.cells, at.x, at.y)) != int(kinds[r[i]]):
				bench.place(at, kinds[r[i]])


func _run() -> void:
	var runs := int(OS.get_environment("PC_RUNS")) if OS.get_environment("PC_RUNS") != "" else 5
	var ids := (OS.get_environment("PC_LEVELS") if OS.get_environment("PC_LEVELS") != "" else "5-3,5-4,5-5").split(",")
	for id in ids:
		var wins := 0
		var line := ""
		for r in runs:
			scene.start_level(Levels.by_id(id))
			await _until(func() -> bool: return scene.designer != null and not scene.designer.busy, 30.0)
			if scene.level_runner.tutorial:
				scene.level_runner.tutorial._skip()
			var bench: Control = scene.designer.body_bench
			_build(bench, GUIDES[id])
			var built: Dictionary = Colony.stats(bench.cells)
			scene.designer.release()
			await _until(func() -> bool: return scene.level_runner.phase == "run", 20.0)
			var lr: Node = scene.level_runner
			if lr.tutorial:
				lr.tutorial._skip()
			scene.set_speed(8.0)
			await _until(func() -> bool: return is_instance_valid(lr.report), 240.0)
			var ev = lr.eval
			var st: Array = ev.stars()
			wins += 1 if st[0] else 0
			var cs: Dictionary = ev.colony_stats
			line += "  [%s 终 %d 挑战 %s 长回 %d 吞 %d 吐 %d]" % ["过" if st[0] else "败", ev.alive, "有" if st[1] else "无", int(cs.get("healed", 0)), int(cs.get("swallowed", 0)), int(cs.get("spat", 0))]
			if r == 0:
				print("%s 身体：%s" % [id, str(built)])
			lr.exit_level()
			await _until(func() -> bool: return scene.level_runner == null, 20.0)
			await _until(func() -> bool: return false, 1.0)
		print("%s 真实流程 %d/%d 过关%s" % [id, wins, runs, line])
	quit()
