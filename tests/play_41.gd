extends SceneTree
# Plays 4-1 for real, through the game itself: default genes, mutation on, each
# plan a couple of times at 8x speed to the end. (The bot runs headless with
# its own setup; this is the check that the real thing matches it.)
# Run: tools/run_test.sh tests/play_41.gd

var scene: Node2D
var wins := 0
var runs := 2


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


func _run() -> void:
	# [name, place of the away card (-1 none), threshold]
	var plans := [["不散开", -1, 0.0], ["第2张 同伴≥3", 1, 3.0], ["第2张 同伴≥2", 1, 2.0], ["第1张 同伴≥3", 0, 3.0]]
	for pl: Array in plans:
		for r in runs:
			scene.start_level(Levels.by_id("4-1"))
			await _until(func() -> bool: return scene.designer != null and not scene.designer.busy, 30.0)
			var d: Control = scene.designer
			if scene.level_runner.tutorial:
				scene.level_runner.tutorial._skip()
			d.show_page("rules")
			if d.has_method("set_rules_mode"):
				d.set_rules_mode("advanced")
			await create_timer(0.4).timeout
			if int(pl[1]) >= 0:
				d.deck_editor.selected = 0
				var at: int = d.deck_editor.add_card()
				d.deck_editor.set_condition(at, 1, Rules.C_CROWD)
				d.deck_editor.set_threshold(at, 1, float(pl[2]), true)
				d.deck_editor.set_action(at, Rules.A_DISPERSE)
				if int(pl[1]) == 0:
					var c: Dictionary = d.deck_editor.deck[at]
					d.deck_editor.deck.remove_at(at)
					d.deck_editor.deck.insert(0, c)
			d.release()
			await _until(func() -> bool: return scene.level_runner.phase == "run", 15.0)
			var lr: Node = scene.level_runner
			scene.set_speed(8.0)
			await _until(func() -> bool: return is_instance_valid(lr.report), 120.0)
			var st: Array = lr.eval.stars()
			wins += 1 if st[0] else 0
			print("%s #%d: 胜 %s 星 %s 种群 %d 撑破 %d" % [pl[0], r, st[0], st, lr.eval.alive, lr.eval.lysed])
			lr.exit_level()
			await _until(func() -> bool: return scene.level_runner == null, 10.0)
			await create_timer(0.5).timeout
	print("play_41 done: %d won" % wins)
	quit()
