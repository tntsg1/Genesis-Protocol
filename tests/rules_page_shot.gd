extends SceneTree
# The designer's rules page, as the player opens it: cards full width, the
# threshold sliders inside them. Saves proofs/rules_page.png.
# Run: tools/run_test.sh tests/rules_page_shot.gd

var scene: Node2D
var fails := 0


func check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func _initialize() -> void:
	root.add_child(preload("res://tests/test_window.gd").new())
	scene = load("res://scenes/showcase.tscn").instantiate()
	scene.seed = 1000
	root.add_child(scene)
	current_scene = scene
	_run.call_deferred()


func _until(cond: Callable, limit := 30.0) -> bool:
	var end := Time.get_ticks_msec() + int(limit * 1000.0)
	while not cond.call() and Time.get_ticks_msec() < end:
		await process_frame
	return cond.call()


func _wait(s: float) -> void:
	var end := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < end:
		await process_frame


func _run() -> void:
	await _wait(1.0)
	scene.open_designer()
	# The page switch the moment the designer can take input (key 2), the
	# quickest way to reach the rules page.
	await _until(func() -> bool: return scene.designer != null and not scene.designer.busy)
	scene.designer.show_page("rules")
	await _wait(1.5)
	var ed: Control = scene.designer.deck_editor
	for v in ed.views:
		print("card %d size %s editor %s" % [v.index, str(v.size), str(ed.size)])
	check(ed.size.x > 300.0, "the deck editor has its width (%.0f)" % ed.size.x)
	check(ed.views.all(func(v: Control) -> bool: return absf(v.size.x - ed.size.x) < 1.0), "every card is as wide as the editor")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://proofs/rules_page.png"))
	print("RESULT: ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit()
