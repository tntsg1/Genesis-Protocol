extends SceneTree
# The ten chapters' maps on the campaign page (scripts/ui/campaign_chapters.gd):
# developer mode on (every level open, chapters without levels previewed),
# each map in turn. Saves proofs/map_01.png .. map_10.png.
# Run: tools/run_test.sh tests/chapter_maps_shots.gd -- --menu

var scene: Node2D


func _initialize() -> void:
	CampaignSave.reset_for_tests()
	root.add_child(preload("res://tests/test_window.gd").new())
	scene = load("res://scenes/showcase.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	_run.call_deferred()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://proofs/%s.png" % name))


func _run() -> void:
	var end := Time.get_ticks_msec() + 20000
	while not (scene.in_menu and scene.menu.shown) and Time.get_ticks_msec() < end:
		await process_frame
	DevMode.set_active(true)
	DevMode.unlock_all = true
	await create_timer(1.0).timeout
	scene.open_campaign()
	await create_timer(4.0).timeout
	var page: Control = scene.campaign
	for c in range(1, 11):
		if c > 1:
			page._switch_chapter(c)
		var t0 := Time.get_ticks_msec()
		await create_timer(4.0).timeout
		print("chapter %d: shown %d, form %.2f, %d ms" % [c, page.shown_chapter(), float(page.section.form[c]), Time.get_ticks_msec() - t0])
		await _shot("map_%02d" % c)
	DevMode.set_active(false)
	quit()
