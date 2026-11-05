extends SceneTree
# The designer's dive-in / pull-out and its genome art: frames through the
# intro, the settled designer, a gene change lighting its chromosome and DNA
# segment, the reference button, the draft surviving a close, and the outro
# handing the release back to the dish. Run: tools/run_test.sh tests/designer_dive.gd

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


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://proofs/%s.png" % name))


# Wait until the designer's own clock reaches t (intro) — real time drifts.
func _until(cond: Callable) -> void:
	for i in 2000:
		if cond.call():
			return
		await process_frame


func _run() -> void:
	await create_timer(1.0).timeout
	scene.focus(Vector2(900, 1000), 1.2)
	await create_timer(0.3).timeout
	var t_before: float = scene.sim.get_time()
	scene.open_designer()
	var d: Control = scene.designer
	check(d.busy, "the designer ignores input while diving in")
	for spec in [[0.6, "dive_1_zoom"], [1.25, "dive_2_portal"], [1.6, "dive_3_inside"], [1.95, "dive_4_dna"], [2.25, "dive_5_settle"]]:
		await _until(func() -> bool: return d.tl >= spec[0])
		await _shot(spec[1])
	await _until(func() -> bool: return not d.busy)
	check(d.tl >= d.INTRO_LEN, "the intro runs its full %.1f s" % d.INTRO_LEN)
	check(absf(scene.sim.get_time() - t_before) < 0.01, "the dish holds still while designing")
	check(scene.cam.zoom.x > 4.0, "the camera is parked inside the cell (zoom %.1f)" % scene.cam.zoom.x)
	await create_timer(0.4).timeout
	await _shot("dive_6_designer")
	# A gene change lights its chromosome (with labels) and DNA segment.
	d.gene_sliders[0].value = 4.0
	d.gene_sliders[0].changed.emit(4.0)
	await create_timer(0.5).timeout
	check(d.glow[0] > 0.5 and d.shown[0] > 3.5, "raising speed lights and grows its chromosome")
	await _shot("dive_7_gene")
	d.hover_gene = 3
	await create_timer(0.3).timeout
	await _shot("dive_8_helix_hover")
	d.hover_gene = -1
	# Reference: copy the dived cell's genome.
	check(d.ref_button != null, "the reference button names the cell: " + (d.ref_button.text if d.ref_button else ""))
	if d.ref_button:
		var before: Array = d.genes.duplicate()
		d.apply_reference()
		check(d.genes != before or d.deck_editor.deck.size() > 0, "reference copies its genes %s and deck (%d cards)" % [str(d.genes), d.deck_editor.deck.size()])
	# Close keeps a draft; reopening restores it.
	d.gene_sliders[1].value = 5.0
	d.gene_sliders[1].changed.emit(5.0)
	d.close()
	await create_timer(1.0).timeout
	await _shot("dive_9_outro")
	await _until(func() -> bool: return scene.designer == null)
	check(scene.designer == null, "closing plays the outro and lets go")
	await create_timer(1.0).timeout
	check(scene.sim.get_time() > t_before, "the dish runs again after closing")
	scene.open_designer()
	d = scene.designer
	check(d.genes[1] == 5.0, "the draft comes back on reopening (sense %.1f)" % d.genes[1])
	await _until(func() -> bool: return not d.busy)
	# Release: outro, then the dish asks where to drop the new species.
	d.release()
	await _until(func() -> bool: return scene.designer == null)
	check(scene.mode == "release", "after the pull-out the dish asks where to release (mode \"%s\")" % scene.mode)
	check(scene.Designer.draft.is_empty(), "releasing clears the draft")
	print("RESULT: ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails else 0)
