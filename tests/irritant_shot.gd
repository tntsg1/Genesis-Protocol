extends SceneTree
# Level 24's irritant through the game: the guide's body released; once the
# guardian has cracked a body, the tool picked by the current's key slot, a
# drop far from its head (refused, nothing spent), then one on its head (the
# corona drawn in: no pull for a few seconds). Shots to proofs/guardian/irritant_*.png.
# Run: tools/run_test.sh tests/irritant_shot.gd

var scene: Node2D
var failed := 0


func _initialize() -> void:
	CampaignSave.reset_for_tests()
	root.add_child(preload("res://tests/test_window.gd").new())
	scene = load("res://scenes/showcase.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	_run.call_deferred()


func check(ok: bool, what: String) -> void:
	print(("ok    " if ok else "FAIL  ") + what)
	failed += 0 if ok else 1


func _until(cond: Callable, frames := 3600) -> void:
	var n := 0
	while not cond.call() and n < frames:
		await process_frame
		n += 1


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://proofs/guardian/%s.png" % name))


func _head() -> Vector2:
	var rot: PackedFloat32Array = scene.sim.get_rotifers(1.0)
	return Vector2(rot[0], rot[1]) + Vector2.from_angle(rot[2]) * 88.0


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
	var tray: Node = scene.hud_root.tools
	check(tray.cards.irritant.visible and not tray.cards.current.visible, "the irritant takes the current's card")
	scene.set_speed(8.0)
	await _until(func() -> bool: return scene.sim.get_worn(1.0).size() > 0, 6000)
	scene.set_speed(1.0)
	scene.iv.points = 120.0
	# The current's key picks the irritant here.
	scene.iv.select("current")
	check(scene.mode == "irritant", "key 4 picks the irritant (%s)" % scene.mode)
	var head := _head()
	scene.focus(head, 1.6)
	await _until(func() -> bool: return false, 30)
	var before: float = scene.iv.points
	scene.iv.place("irritant", head + Vector2(600, 600))
	check(is_equal_approx(scene.iv.points, before), "a drop far from its head costs nothing")
	check(scene.sim.get_rotifer_retract()[0] <= 0.0, "and does nothing")
	scene.iv.place("irritant", _head() + Vector2(20, 10))
	check(scene.sim.get_rotifer_retract()[0] > 5.0, "a drop on its head draws the corona in (%.1f s)" % scene.sim.get_rotifer_retract()[0])
	check(scene.iv.points < before, "and costs points")
	await _until(func() -> bool: return false, 20)
	await _shot("irritant_0")
	await _until(func() -> bool: return false, 60)
	await _shot("irritant_1")
	# Again within 20 s: it is getting used to it.
	scene.iv.cooldown.clear()
	await _until(func() -> bool: return scene.sim.get_rotifer_retract()[0] <= 0.0, 600)
	scene.iv.select("current")
	scene.iv.place("irritant", _head())
	check(scene.sim.get_rotifer_retract()[1] < 5.0, "again soon after: shorter (%.1f s)" % scene.sim.get_rotifer_retract()[1])
	await _until(func() -> bool: return false, 10)
	await _shot("irritant_2")
	print("irritant: %d failed" % failed)
	quit()
