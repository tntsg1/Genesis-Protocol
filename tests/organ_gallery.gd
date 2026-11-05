extends SceneTree
# Every organ grown on a cell: the designer's specimen with each organ in
# turn (a contact sheet, proofs/organ_gallery.png), then a species released
# in the dish with spines + cilia + a chemoreceptor, seen close
# (proofs/organ_dish.png; needs the kernel's organ_mask).
# Run: tools/run_test.sh tests/organ_gallery.gd

var scene: Node2D


func _initialize() -> void:
	CampaignSave.reset_for_tests()
	root.add_child(preload("res://tests/test_window.gd").new())
	scene = load("res://scenes/showcase.tscn").instantiate()
	scene.seed = 1000
	root.add_child(scene)
	current_scene = scene
	_run.call_deferred()


func _until(cond: Callable, limit := 10.0) -> bool:
	var end := Time.get_ticks_msec() + int(limit * 1000.0)
	while not cond.call() and Time.get_ticks_msec() < end:
		await process_frame
	return cond.call()


func _wait(s: float) -> void:
	await create_timer(s).timeout


func _run() -> void:
	scene.open_designer()
	await _until(func() -> bool: return scene.designer != null and not scene.designer.busy, 20.0)
	var d: Control = scene.designer
	await _wait(0.5)
	var tiles := []
	var c: Vector2 = d._specimen_center()
	var box := Rect2(c - Vector2(150, 150), Vector2(300, 300))
	for o: Dictionary in Organs.LIST:
		d.organs = [o.id]
		await _wait(0.35)
		await RenderingServer.frame_post_draw
		var im := root.get_texture().get_image().get_region(Rect2i(box))
		im.convert(Image.FORMAT_RGBA8)
		tiles.append([im, o.name])
	var sheet := Image.create(300 * 5, 300 * 2, false, Image.FORMAT_RGBA8)
	for k in tiles.size():
		sheet.blit_rect(tiles[k][0], Rect2i(0, 0, 300, 300), Vector2i((k % 5) * 300, (k / 5) * 300))
	sheet.save_png(ProjectSettings.globalize_path("res://proofs/organ_gallery.png"))
	print("gallery: ", ", ".join(tiles.map(func(t: Array) -> String: return t[1])))
	d.organs = []
	d.close()
	await _until(func() -> bool: return scene.designer == null, 10.0)
	await _wait(1.0)
	# In the dish: a species with three organs, released and seen close.
	var p := Organs.apply({name = "器官测试", color = Color(0.35, 0.55, 0.95), radius = 5.5, speed = 2.0, vision = 3.0,
		armor = 1.0, attack = 1.0, fertility = 3.0, efficiency = 3.0, neural = 3.0, lifespan = 90.0, cohesion = 0.2}, ["spines", "cilia", "chemo_rec"])
	scene._species(p)
	scene.labels.append("器官测试")
	var at: Vector2 = scene.DISH_CENTER + Vector2(-200, 0)
	scene.sim.spawn(scene.colors.size() - 1, at, 6, 30.0)
	scene.focus(at, 7.0)
	await _wait(2.0)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://proofs/organ_dish.png"))
	quit()
