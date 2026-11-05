extends SceneTree
# M2 / V1 view capture: the life scan explaining a deck, analysis mode at
# group and macro zoom, a click-to-locate in the event log, and keyboard
# panning. Run: tools/run_test.sh tests/m2_views.gd

var scene: Node2D
var fails := 0


func _initialize() -> void:
	root.add_child(preload("res://tests/test_window.gd").new())
	scene = load("res://scenes/showcase.tscn").instantiate()
	scene.seed = 1000
	root.add_child(scene)
	current_scene = scene
	_run.call_deferred()


# n is in 60 Hz frames; wait real time so 120 FPS does not halve it.
func _wait(n: int) -> void:
	await create_timer(n / 60.0).timeout


func check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func _key(code: Key, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = pressed
	Input.parse_input_event(e)


func _run() -> void:
	scene.set_speed(3.0)
	await _wait(300)
	scene.set_speed(1.0)
	# Life scan on a grazer that is doing something.
	var pts: PackedVector2Array = scene.sim.get_positions(1)
	var target := pts[pts.size() / 2]
	scene.focus(target, 4.0)
	scene._select_at(target)
	scene.following = true
	await _wait(90)
	var info: Dictionary = scene.sim.get_agent(scene.selected)
	check(info.has("deck") and info.deck.size() > 0, "the inspected organism reports its deck (%d cards, fired %d)" % [info.deck.size(), info.fired])
	await _shot("m2_scan")
	scene._deselect()
	# A mutant: its drifted chromosomes pulse gold in the scan; a mutation
	# releases a little rising DNA strand in the dish.
	scene.advance(150.0)
	var mutant := -1
	for p in scene.sim.get_positions(0):
		var id: int = scene.sim.find_agent(p, 2.0)
		var cand: Dictionary = scene.sim.get_agent(id)
		if cand.is_empty():
			continue
		var base: Array = scene.species_genes[0]
		for k in 7:
			if absf(cand.genes[k] - base[k]) >= 0.25:
				mutant = id
		if mutant >= 0:
			scene.focus(cand.position, 3.2)
			scene.selected = mutant
			scene.following = true
			break
	check(mutant >= 0, "found a mutant to inspect (#%d)" % mutant)
	var fxp: Vector2 = scene.cam.position + Vector2(-120, 40) / 3.2
	scene.fx.particle(fxp, Vector2(0, -70), 30.0, Color(1.0, 0.82, 0.38), scene.fx.HELIX, 1.5)
	await _wait(30)
	await _shot("m2_scan_mutant")
	scene._deselect()
	# Analysis mode at group zoom, then macro.
	scene.focus(Vector2(900, 1000), 1.3)
	scene.set_analysis(true)
	await _wait(60)
	check(scene.analysis.amount > 0.99 and scene.sim.get_analysis_count() > 50, "analysis mode draws rings for %d organisms" % scene.sim.get_analysis_count())
	await _shot("m2_analysis")
	scene.focus(scene.DISH_CENTER, 0.5)
	await _wait(40)
	await _shot("m2_analysis_macro")
	scene.set_analysis(false)
	await _wait(30)
	check(not scene.analysis.visible, "Tab off fades the diagram away")
	# Click-to-locate: log an event with a position and click its row.
	scene.focus(scene.DISH_CENTER, 1.0)
	await _wait(10)
	var spot := Vector2(700, 1500)
	scene.hud_root.notify("测试定位事件", Ui.ACCENT, spot)
	await _wait(10)
	var row: Control = scene.hud_root.events_box.get_child(0)
	row.clicked.emit()
	await create_timer(1.4).timeout
	check(scene.cam.position.distance_to(spot) < 30.0, "clicking a log entry flies the camera there (%.0f away)" % scene.cam.position.distance_to(spot))
	# Keyboard pan: hold D for half a second.
	var before: Vector2 = scene.cam.position
	_key(KEY_D, true)
	await create_timer(0.5).timeout
	_key(KEY_D, false)
	await create_timer(0.5).timeout
	check(scene.cam.position.x - before.x > 100.0, "holding D pans right (%.0f)" % (scene.cam.position.x - before.x))
	print("RESULT: ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(0 if fails == 0 else 1)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://proofs/%s.png" % name))
