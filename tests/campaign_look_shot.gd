extends SceneTree
# A look at the campaign page with some progress (proofs/campaign_look_*.png).
# Run: tools/run_test.sh tests/campaign_look_shot.gd

var scene: Node2D


func _initialize() -> void:
	CampaignSave.reset_for_tests()
	for id in ["1-1", "1-2", "1-3", "1-4"]:
		CampaignSave.record(id, [true, id != "1-3", id == "1-1"], false)
	root.add_child(preload("res://tests/test_window.gd").new())
	scene = load("res://scenes/showcase.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	_run.call_deferred()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://proofs/campaign_look_%s.png" % name))


func _run() -> void:
	var end := Time.get_ticks_msec() + 20000
	while not (scene.in_menu and scene.menu.shown) and Time.get_ticks_msec() < end:
		await process_frame
	await create_timer(1.5).timeout
	scene.open_campaign()
	await create_timer(4.0).timeout
	await _shot("current")
	# Chapter 2 is not open yet: the arrow says so, the map stays.
	scene.campaign._switch_chapter(2)
	await create_timer(0.4).timeout
	print("locked note: %s, still chapter %d" % [scene.campaign.ch_note.text, scene.campaign.chapter_of(scene.campaign.selected)])
	await _shot("locked")
	# 1-5 passed: on to chapter 2's map.
	CampaignSave.record("1-5", [true, false, false], false)
	scene.campaign._select(4, true)
	await create_timer(0.5).timeout
	scene.campaign._switch_chapter(2)
	await create_timer(0.55).timeout
	await _shot("morph")
	await create_timer(2.5).timeout
	print("now chapter %d, selected %s" % [scene.campaign.chapter_of(scene.campaign.selected), Levels.ALL[scene.campaign.selected].id])
	await _shot("ch2")
	quit()
