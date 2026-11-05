extends SceneTree
# Organs in the designer (2026-10-29): the DNA's organ sites (empty, an
# organ pressing in, installed, one lifted out) and the specimen growing the
# organ. Level 2-2 (two slots). Saves proofs/organ_*.png.
# Run: tools/run_test.sh tests/organ_site_shots.gd

var scene: Node2D


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


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://proofs/organ_%s.png" % name))


func _wait(s: float) -> void:
	await create_timer(s).timeout


func _run() -> void:
	DevMode.active = true
	DevMode.no_tutorial = true
	scene.start_level(Levels.by_id("2-2"))
	await _until(func() -> bool: return scene.designer != null and not scene.designer.busy, 30.0)
	var d: Control = scene.designer
	await _wait(0.6)
	d.focus_organ(0)
	await _wait(1.6)
	await _shot("empty")
	d.organ_bay.chips.spines.pressed.emit()
	await _wait(0.45)
	await _shot("pressing")
	await _wait(1.4)
	await _shot("installed")
	d.organ_bay.chips.silica.pressed.emit() # same pair: replaces the spines
	await _wait(0.3)
	await _shot("swap")
	await _wait(1.5)
	d.organ_bay.chips.cnido.pressed.emit() # granules open at 2-5 now
	await _wait(1.8)
	await _shot("two")
	print("organs %s  sites %d  view %.0f" % [d.organs, d._sites(), d.view_x])
	quit()
