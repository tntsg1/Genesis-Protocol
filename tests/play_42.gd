extends SceneTree
# Plays 4-2 for real, through the game itself: mutation on, each plan a couple
# of times at 8x speed to the end.
# Run: tools/run_test.sh tests/play_42.gd

var scene: Node2D
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
	# [name, organ?, card: 0 as it starts, 1 only those without memory, 2 no away card]
	var plans := [["开局方案不动", false, 0], ["只装器官", true, 0], ["引导方案", true, 1], ["装器官不散开", true, 2]]
	for pl: Array in plans:
		for r in runs:
			scene.start_level(Levels.by_id("4-2"))
			await _until(func() -> bool: return scene.designer != null and not scene.designer.busy, 30.0)
			var d: Control = scene.designer
			if scene.level_runner.tutorial:
				scene.level_runner.tutorial._skip()
			d.show_page("rules")
			if d.has_method("set_rules_mode"):
				d.set_rules_mode("advanced")
			await create_timer(0.4).timeout
			if pl[1]:
				d.organ_bay.install("crispr")
			if int(pl[2]) == 1:
				d.deck_editor.set_condition(1, 2, Rules.C_IMMUNE)
				d.deck_editor.toggle_neg(1, 2)
			elif int(pl[2]) == 2:
				d.deck_editor.deck.remove_at(1)
			d.release()
			await _until(func() -> bool: return scene.level_runner.phase == "run", 15.0)
			var lr: Node = scene.level_runner
			scene.set_speed(8.0)
			await _until(func() -> bool: return is_instance_valid(lr.report), 240.0)
			var st: Array = lr.eval.stars()
			print("%s #%d: t %.0f 胜 %s 星 %s 种群 %d 有记忆 %d 撑破 %d" % [pl[0], r, lr.eval.t, st[0], st, lr.eval.alive, lr.eval.immune, lr.eval.lysed])
			lr.exit_level()
			await _until(func() -> bool: return scene.level_runner == null, 10.0)
			await create_timer(0.5).timeout
	quit()
