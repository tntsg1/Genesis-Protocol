extends SceneTree
# Opens the campaign page and selects every level's card in turn, so a card
# that errors while filling (a missing name in a lookup table, say) shows up
# as a SCRIPT ERROR in the output. Prints "cards: N shown".
# CC_SHOT=4-1 also saves proofs/card_4-1.png and card_4-1_end.png (scrolled down).
# Run: tools/run_test.sh tests/campaign_cards_all.gd -- --menu

var scene: Node2D


func _initialize() -> void:
	CampaignSave.reset_for_tests()
	for l: Dictionary in Levels.ALL:
		CampaignSave.record(l.id, [true, false, false], false)
	root.add_child(preload("res://tests/test_window.gd").new())
	scene = load("res://scenes/showcase.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	_run.call_deferred()


func _run() -> void:
	var end := Time.get_ticks_msec() + 20000
	while not (scene.in_menu and scene.menu.shown) and Time.get_ticks_msec() < end:
		await process_frame
	await create_timer(0.5).timeout
	scene.open_campaign()
	await create_timer(1.0).timeout
	var n := 0
	for i in Levels.ALL.size():
		scene.campaign._select(i, true)
		await process_frame
		n += 1
	print("cards: %d shown" % n)
	var want := OS.get_environment("CC_SHOT")
	if want != "":
		for i in Levels.ALL.size():
			if Levels.ALL[i].id == want:
				scene.campaign._select(i, true)
		await create_timer(4.0).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://proofs/card_%s.png" % want))
		var sc: ScrollContainer = scene.campaign.card_scroll
		sc.scroll_vertical = 100000
		await create_timer(0.5).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://proofs/card_%s_end.png" % want))
	quit(0)
