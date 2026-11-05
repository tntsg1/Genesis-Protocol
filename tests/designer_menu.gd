extends SceneTree
# Designer from the main menu: the dive takes a cell from the menu's live
# dish; closing pulls back out to the menu; releasing pulls out over the
# landing spot and starts the experiment with the new species.
# Run: tools/run_test.sh tests/designer_menu.gd -- --menu

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


func _run() -> void:
	await create_timer(2.0).timeout
	check(scene.in_menu, "starts in the menu")
	scene.open_designer()
	var d: Control = scene.designer
	check(d.ref_button != null, "dives into a cell of the menu dish")
	while d.busy:
		await process_frame
	d.close()
	while scene.designer != null:
		await process_frame
	await create_timer(0.8).timeout
	check(scene.in_menu and scene.cam.zoom.x < 0.8, "closing returns to the menu view (zoom %.2f)" % scene.cam.zoom.x)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://proofs/designer_menu_back.png"))
	var n: int = scene.labels.size()
	scene.open_designer()
	d = scene.designer
	while d.busy:
		await process_frame
	d.release()
	while scene.designer != null:
		await process_frame
	await create_timer(scene.CAPSULE_OPEN + 0.4).timeout
	check(not scene.in_menu and scene.labels.size() == n + 1, "releasing from the menu starts the experiment with it")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://proofs/designer_menu_release.png"))
	print("RESULT: ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails else 0)
