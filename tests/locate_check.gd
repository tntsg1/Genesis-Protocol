extends SceneTree
# "查看" in the event log opens the organism behind the event: for a
# mutation, the new lineage's cell is flown to, selected, followed and
# scanned, and its changed genes are named. A new world clears the log.
# Saves proofs/locate_mutation.png. Run: tools/run_test.sh tests/locate_check.gd

var scene: Node2D
var fails := 0


func _initialize() -> void:
	root.add_child(preload("res://tests/test_window.gd").new())
	scene = load("res://scenes/showcase.tscn").instantiate()
	scene.seed = 1000
	root.add_child(scene)
	current_scene = scene
	_run.call_deferred()


func check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func _until(cond: Callable, limit := 30.0) -> bool:
	# Real time, not frames: the frame rate is whatever the settings say.
	var end := Time.get_ticks_msec() + int(limit * 1000.0)
	while not cond.call() and Time.get_ticks_msec() < end:
		await process_frame
	return cond.call()


func _mutation_row() -> Control:
	for row in scene.hud_root.events_box.get_children():
		for l in row.find_children("*", "Label", true, false):
			if (l as Label).text.contains("突变："):
				return row
	return null


func _run() -> void:
	scene.set_speed(8.0)
	check(await _until(func() -> bool: return _mutation_row() != null, 90.0), "a mutation shows up in the log")
	scene.set_speed(1.0)
	var row: Control = _mutation_row()
	var has_view := false
	for l in row.find_children("*", "Label", true, false):
		if (l as Label).text.contains("查看"):
			has_view = true
	check(has_view, "the mutation row offers 查看")
	row.clicked.emit()
	await create_timer(1.6).timeout
	var info: Dictionary = scene.sim.get_agent(scene.selected)
	check(not info.is_empty(), "a living organism is selected (#%d)" % scene.selected)
	check(scene.cam.zoom.x >= 2.9, "the camera has closed in (zoom %.1f)" % scene.cam.zoom.x)
	check(scene.following, "the camera follows it")
	check(scene.hud_root.tier == scene.hud_root.TIER_MICRO and scene.hud_root.scan_panel.visible, "its life scan is open")
	var said := false
	for c in scene.hud_root.events_box.get_children():
		for l in c.find_children("*", "Label", true, false):
			if (l as Label).text.contains("的突变："):
				said = true
	check(said or scene.mutation_text(info) != "", "what changed is named (%s)" % scene.mutation_text(info))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://proofs/locate_mutation.png"))
	scene.load_world(Worlds.sandbox(), 7)
	await process_frame
	check(scene.hud_root.events_box.get_child_count() == 0, "a new world starts with an empty log")
	print("RESULT: ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails else 0)
