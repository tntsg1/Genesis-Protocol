extends SceneTree
# Level 24's crack marks: the guide's body released, run fast until the
# guardian has spat one out with a cracked armour block, then the camera on it
# (proofs/guardian/worn_*.png): the crack, the regrowth bar filling, and the
# objective bar's swallowed / spat / eaten counts.
# Run: tools/run_test.sh tests/worn_shot.gd

var scene: Node2D


func _initialize() -> void:
	CampaignSave.reset_for_tests()
	root.add_child(preload("res://tests/test_window.gd").new())
	scene = load("res://scenes/showcase.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	_run.call_deferred()


func _until(cond: Callable, frames := 3600) -> void:
	var n := 0
	while not cond.call() and n < frames:
		await process_frame
		n += 1


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://proofs/guardian/%s.png" % name))


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://proofs/guardian"))
	scene.start_level(Levels.by_id("5-5"))
	await _until(func() -> bool: return scene.designer != null and not scene.designer.busy)
	if scene.level_runner.tutorial:
		scene.level_runner.tutorial._skip()
	var pc: GDScript = preload("res://tests/play_ch5.gd")
	var rows: Array = pc.GUIDES["5-5"]
	var bench: Control = scene.designer.body_bench
	var kinds := {"F": Colony.FLAG, "G": Colony.GERM, "A": Colony.ARMOR, "S": Colony.STORE, "R": Colony.REGEN}
	var lo := Vector2i(100, 100)
	for c: Array in bench.cells:
		lo = Vector2i(mini(lo.x, int(c[0])), mini(lo.y, int(c[1])))
	for j in rows.size():
		for i in (rows[j] as String).length():
			if int(Colony.type_at(bench.cells, lo.x + i, lo.y + j)) != int(kinds[rows[j][i]]):
				bench.place(lo + Vector2i(i, j), kinds[rows[j][i]])
	scene.designer.release()
	await _until(func() -> bool: return scene.level_runner.phase == "run")
	if scene.level_runner.tutorial:
		scene.level_runner.tutorial._skip()
	scene.set_speed(8.0)
	await _until(func() -> bool: return scene.sim.get_worn(1.0).size() > 0, 6000)
	var w: PackedFloat32Array = scene.sim.get_worn(1.0)
	if w.is_empty():
		print("worn: none")
		await _shot("worn_none")
		quit()
		return
	scene.set_speed(1.0)
	scene.focus(Vector2(w[0], w[1]), 2.6)
	for k in 3:
		await _until(func() -> bool: return false, 150)
		var w2: PackedFloat32Array = scene.sim.get_worn(1.0)
		if not w2.is_empty():
			scene.focus(Vector2(w2[0], w2[1]), 2.6)
		await _until(func() -> bool: return false, 20)
		await _shot("worn_%d" % k)
	print("worn: shots done")
	quit()
