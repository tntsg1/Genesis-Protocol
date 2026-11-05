extends SceneTree
# 5-2 played for real, the camera on one body's germ block from the moment its
# embryo starts to the hatching: proofs/colony/e_*.png at points along the way
# (and one wider look); with CLIP=1 run under --write-movie at 1.7x instead, for
# a short film (prints the frame the embryo starts on, to cut from).
# Run: tools/run_test.sh tests/embryo_play.gd

const ZOOM := 18.0

var scene: Node2D
var dir := ""
var follow := -1
var zoom := ZOOM


func _initialize() -> void:
	CampaignSave.reset_for_tests()
	root.add_child(preload("res://tests/test_window.gd").new())
	scene = load("res://scenes/showcase.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	dir = ProjectSettings.globalize_path("res://proofs/colony")
	DirAccess.make_dir_recursive_absolute(dir)
	_run.call_deferred()


func _until(cond: Callable, limit := 10.0) -> bool:
	var end := Time.get_ticks_msec() + int(limit * 1000.0)
	while not cond.call() and Time.get_ticks_msec() < end:
		await process_frame
	return cond.call()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [dir, name])


# (id, x, y, heading, embryo share, gestating) of the body followed.
func _body() -> PackedFloat32Array:
	var b: PackedFloat32Array = scene.sim.get_colonies()
	for k in range(0, b.size(), 6):
		if (follow < 0 and b[k + 5] > 0.5) or int(b[k]) == follow:
			return b.slice(k, k + 6)
	return PackedFloat32Array()


func _process_follow() -> void:
	while true:
		await process_frame
		var b := _body()
		if b.is_empty():
			continue
		# The first germ block of the blueprint, where it is now.
		var off := Vector2.ZERO
		for c in Colony.centred(scene.level_runner.design.params.blocks):
			if int(c.z) == Colony.GERM:
				off = Vector2(c.x, c.y) * Colony.BLOCK
				break
		scene.focus(Vector2(b[1], b[2]) + off.rotated(b[3]), zoom)


func _measure(label: String) -> void:
	var ms := []
	var last := Time.get_ticks_usec()
	for k in 40:
		await process_frame
		var now := Time.get_ticks_usec()
		ms.append((now - last) / 1000.0)
		last = now
	ms.sort()
	print("%s: 95%% %.1f ms  最差 %.1f ms" % [label, ms[int(ms.size() * 0.95)], ms[-1]])


func _run() -> void:
	var clip := OS.get_environment("CLIP") == "1"
	scene.start_level(Levels.by_id("5-2"))
	await _until(func() -> bool: return scene.designer != null and not scene.designer.busy, 30.0)
	var d: Control = scene.designer
	if scene.level_runner.tutorial:
		scene.level_runner.tutorial._skip()
	await create_timer(0.5).timeout
	d.body_bench.move(Vector2i(7, 4), Vector2i(6, 4))
	d.body_bench.move(Vector2i(7, 5), Vector2i(5, 4))
	d.release()
	await _until(func() -> bool: return scene.level_runner.phase == "run", 15.0)
	var lr: Node = scene.level_runner
	if lr.tutorial:
		lr.tutorial._skip()
	scene.set_speed(3.0)
	await _until(func() -> bool: return not _body().is_empty(), 120.0)
	follow = int(_body()[0])
	scene.set_speed(1.7 if clip else 1.0)
	_process_follow()
	print("embryo from frame ", Engine.get_frames_drawn())
	if clip:
		await _until(func() -> bool: return _body().is_empty(), 60.0)
		await create_timer(2.5).timeout
		quit()
		return
	for at in [0.04, 0.12, 0.22, 0.3, 0.4, 0.5, 0.56, 0.6, 0.64, 0.68, 0.8, 0.97]:
		await _until(func() -> bool: return _body().is_empty() or _body()[4] >= at, 40.0)
		if _body().is_empty():
			break
		await _shot("e_%02d" % int(at * 100))
		if at in [0.3, 0.6, 0.8]:
			_measure("胚胎 %.1f 放大 ×18" % at)
	# The hatching: the young one fades from its pocket as it swims off a colony.
	await _until(func() -> bool: return _body().is_empty(), 20.0)
	for k in 3:
		await create_timer(0.1 if k == 0 else 0.6).timeout
		await _shot("e_hatch%d" % k)
	zoom = 6.0
	await create_timer(0.4).timeout
	await _shot("e_wide")
	quit()
