extends SceneTree
# Probe: level 2-4 runs side by side on the worker pool, as the bot runs them.
func _initialize() -> void:
	var l: Dictionary = Levels.by_id("2-4")
	var designs := []
	for k in 8:
		designs.append(LevelEval.design_from_genes([3.0, 2.0, 1.0, 1.0, 3.0, 3.0, 4.0, 3.0], Rules.default_deck(0), Color(0.4, 0.8, 0.9), 12.0, true, [], "2-4"))
	var results := []
	results.resize(designs.size())
	var job := func(k: int) -> void:
		results[k] = LevelEval.simulate(l, designs[k], 1000 + k * 7919)
	var task := WorkerThreadPool.add_group_task(job, results.size(), -1, true)
	WorkerThreadPool.wait_for_group_task_completion(task)
	for k in results.size():
		print("run %d: alive %d eaten %d" % [k, results[k].alive, results[k].eaten])
	# And one more alone, after.
	var ev := LevelEval.simulate(l, designs[0], 1000)
	print("alone: alive %d eaten %d" % [ev.alive, ev.eaten])
	quit()
