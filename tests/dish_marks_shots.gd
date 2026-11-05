extends SceneTree
# The dish's marks (scripts/dish_marks.gd) in level 2-4: ambushers lying in
# wait ringed in crimson, the player's cells on alert with a caret, the eaten
# marked where they went. Saves proofs/marks_*.png.
# Run: tools/run_test.sh tests/dish_marks_shots.gd

var scene: Node2D
var fails := 0


func _initialize() -> void:
	CampaignSave.reset_for_tests()
	root.add_child(preload("res://tests/test_window.gd").new())
	scene = load("res://scenes/showcase.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	_run.call_deferred()


func check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func _until(cond: Callable, limit := 10.0) -> bool:
	var end := Time.get_ticks_msec() + int(limit * 1000.0)
	while not cond.call() and Time.get_ticks_msec() < end:
		await process_frame
	return cond.call()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://proofs/marks_%s.png" % name))


# [resting ambushers, cells on alert] among the marks now.
func _counts() -> Array:
	var m: PackedFloat32Array = scene.dish_marks.marks
	var mine: Array = scene.dish_marks._mine()
	var rest := 0
	var alert := 0
	for b in range(0, m.size(), 6):
		if not (int(m[b + 2]) in mine) and int(m[b + 4]) == 7:
			rest += 1
		if int(m[b + 3]) == Rules.S_ALERT:
			alert += 1
	return [rest, alert]


func _run() -> void:
	scene.start_level(Levels.by_id("2-4"))
	await _until(func() -> bool: return scene.designer != null and not scene.designer.busy, 30.0)
	var d: Control = scene.designer
	if scene.level_runner.tutorial:
		scene.level_runner.tutorial._skip()
	d.show_page("rules")
	d.set_rules_mode("advanced")
	d.deck_editor.add_state(Rules.S_ALERT)
	d.deck_editor.set_state(Rules.S_FORAGE)
	d.deck_editor.set_action(0, Rules.A_TO_ALERT)
	d.deck_editor.set_threshold(0, 1, 100.0, true)
	d.release()
	check(await _until(func() -> bool: return scene.level_runner.phase == "run", 15.0), "released")
	scene.fly_to(Vector2(1100, 1100), 0.55, 0.3)
	await create_timer(1.0).timeout
	var c := _counts()
	check(c[0] >= 5, "ambushers lying in wait are marked (%d in view)" % c[0])
	await _shot("wide")
	scene.set_speed(4.0)
	var best := [0, 0]
	var saw_eaten := false
	var end := Time.get_ticks_msec() + 25000
	while Time.get_ticks_msec() < end and not (saw_eaten and best[1] > 0):
		await process_frame
		c = _counts()
		best = [maxi(best[0], c[0]), maxi(best[1], c[1])]
		if not scene.dish_marks.eaten.is_empty() and not saw_eaten:
			saw_eaten = true
			scene.set_speed(0.25)
			await create_timer(0.15).timeout
			await _shot("eaten")
			scene.set_speed(4.0)
	scene.set_speed(1.0)
	check(saw_eaten, "an eaten cell is marked")
	check(best[1] > 0, "cells on alert carry a caret (up to %d at once)" % best[1])
	# Close up on an ambusher with our cells about.
	var m: PackedFloat32Array = scene.dish_marks.marks
	var mine: Array = scene.dish_marks._mine()
	var spot := Vector2(1100, 1100)
	var top := -1
	for b in range(0, m.size(), 6):
		if int(m[b + 2]) in mine or int(m[b + 4]) != 7:
			continue
		var p := Vector2(m[b], m[b + 1])
		var near := 0
		for q in range(0, m.size(), 6):
			if int(m[q + 2]) in mine and Vector2(m[q], m[q + 1]).distance_to(p) < 180.0:
				near += 1
		if near > top:
			top = near
			spot = p
	scene.set_speed(0.5)
	scene.fly_to(spot, 2.0, 0.4)
	await create_timer(1.2).timeout
	await _shot("close")
	print("DONE fails=%d" % fails)
	quit()
