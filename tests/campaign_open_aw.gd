extends SceneTree
# Opening the campaign page straight onto a later chapter's map (a save that
# has reached chapter 3), then leaving and opening it again: the map must
# come up whole both times. Saves proofs/open_*.png.
# Run: tools/run_test.sh tests/campaign_open_aw.gd -- --menu

var scene: Node2D
var fails := 0


func _initialize() -> void:
	CampaignSave.reset_for_tests()
	for l: Dictionary in Levels.ALL:
		if int(String(l.id).get_slice("-", 0)) <= 2 or l.id in ["3-1", "3-2"]:
			CampaignSave.record(l.id, [true, false, false], false)
	root.add_child(preload("res://tests/test_window.gd").new())
	scene = load("res://scenes/showcase.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	_run.call_deferred()


func check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://proofs/open_%s.png" % name))


func _state(what: String) -> void:
	var m: Control = scene.campaign.section
	var c: int = m.chapter
	var mf: float = m.ch_mats[c][0].get_shader_parameter("form") if not m.ch_mats[c].is_empty() else -1.0
	var nf: Array = []
	for k in range(1, 11):
		if m.nodes[k].visible:
			nf.append(k)
	print("%s: chapter %d, form %.2f, material form %s, shown nodes %s, level %s" % [what, c, float(m.form[c]), str(mf), str(nf), Levels.ALL[scene.campaign.selected].id])


func _run() -> void:
	var end := Time.get_ticks_msec() + 20000
	while not (scene.in_menu and scene.menu.shown) and Time.get_ticks_msec() < end:
		await process_frame
	await create_timer(1.0).timeout
	scene.open_campaign()
	await create_timer(0.8).timeout
	_state("0.8 s")
	await _shot("a")
	await create_timer(1.5).timeout
	_state("2.3 s")
	await _shot("b")
	await create_timer(3.0).timeout
	_state("5.3 s")
	await _shot("c")
	var m: Control = scene.campaign.section
	var mat: ShaderMaterial = m.ch_mats[m.chapter][0]
	check(is_equal_approx(float(m.form[m.chapter]), 1.0) and is_equal_approx(float(mat.get_shader_parameter("form")), 1.0), "first open: the map is whole")
	# Look at another chapter's map, leave, come back straight onto this one.
	scene.campaign._select(0)
	await create_timer(2.5).timeout
	# Away and back.
	scene.campaign.close()
	await create_timer(2.0).timeout
	scene.open_campaign()
	await create_timer(4.0).timeout
	_state("again")
	await _shot("d")
	check(is_equal_approx(float(m.form[m.chapter]), 1.0) and is_equal_approx(float(mat.get_shader_parameter("form")), 1.0), "second open: the map is whole")
	print("DONE fails=%d" % fails)
	quit()
