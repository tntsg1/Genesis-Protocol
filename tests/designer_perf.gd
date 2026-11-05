extends SceneTree
# Designer smoothness under the mouse (playtest: "划过去会一卡一卡"): vsync
# off, frame times while the pointer sweeps back and forth over the strand
# (hover lens), while dragging and throwing it, and while sweeping over the
# side panels. Prints average / p99 / max and every frame over 12 ms with
# what was happening.
# Run: tools/run_test.sh tests/designer_perf.gd

var scene: Node2D
var _last := Vector2.ZERO
var times := PackedFloat32Array()
var phase := ""
var spikes: Array = []


func _initialize() -> void:
	root.add_child(preload("res://tests/test_window.gd").new())
	scene = load("res://scenes/showcase.tscn").instantiate()
	scene.seed = 1000
	root.add_child(scene)
	current_scene = scene
	_run.call_deferred()


func _move(at: Vector2, mask: int) -> void:
	var e := InputEventMouseMotion.new()
	e.relative = at - _last
	_last = at
	e.position = at
	e.global_position = at
	e.button_mask = mask
	root.push_input(e)


func _btn(at: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = at
	e.global_position = at
	e.button_mask = 1 if pressed else 0
	root.push_input(e)


func _report(label: String, t: PackedFloat32Array) -> void:
	var s := t.duplicate()
	s.sort()
	var avg := 0.0
	for x in t:
		avg += x
	avg /= maxf(t.size(), 1)
	print("%-12s avg %.2f ms  p99 %.2f  max %.2f  (%d frames)" % [label, avg, s[int(s.size() * 0.99)], s[-1], t.size()])


func _frames(n: int, label: String, step: Callable) -> void:
	var t := PackedFloat32Array()
	var last := Time.get_ticks_usec()
	for i in n:
		step.call(i)
		await process_frame
		var now := Time.get_ticks_usec()
		var ms := (now - last) / 1000.0
		last = now
		t.append(ms)
		if ms > 12.0:
			spikes.append("%s frame %d: %.1f ms" % [label, i, ms])
	_report(label, t)


func _run() -> void:
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	await create_timer(1.0).timeout
	scene.open_designer()
	var d: Control = scene.designer
	while d.busy:
		await process_frame
	await create_timer(0.5).timeout
	var c: Vector2 = d.STAGE_CENTER
	await _frames(120, "idle", func(_i: int) -> void: pass)
	if "--occlusion" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		var a := root.get_texture().get_image()
		scene.medium.visible = false
		scene.cells.visible = false
		for i in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		var b := root.get_texture().get_image()
		var diff := 0
		for y in range(0, a.get_height(), 8):
			for x in range(0, a.get_width(), 8):
				var ca := a.get_pixel(x, y)
				var cb := b.get_pixel(x, y)
				if absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b) > 0.03:
					diff += 1
		print("pixels that change when the world is hidden: ", diff, " of ", (a.get_width() / 8) * (a.get_height() / 8))
		b.save_png(ProjectSettings.globalize_path("res://proofs/designer_noworld.png"))
		quit()
		return
	if "--layers" in OS.get_cmdline_user_args():
		scene.vignette.visible = false
		await _frames(120, "no lens", func(_i: int) -> void: pass)
		scene.medium.visible = false
		await _frames(120, "+no dish", func(_i: int) -> void: pass)
		scene.cells.visible = false
		await _frames(120, "+no cells", func(_i: int) -> void: pass)
		scene.water_fx.render_target_update_mode = SubViewport.UPDATE_DISABLED
		await _frames(120, "+no waterfx", func(_i: int) -> void: pass)
		scene.world_env.glow_enabled = false
		await _frames(120, "+no glow", func(_i: int) -> void: pass)
		quit()
		return
	await _frames(240, "hover sweep", func(i: int) -> void:
		var k := sin(i / 240.0 * TAU * 2.0)
		_move(c + Vector2(k * 420.0, 30.0 * sin(i * 0.3)), 0))
	var from := c + Vector2(300, 0)
	_move(from, 0)
	_btn(from, true)
	await _frames(120, "drag", func(i: int) -> void:
		_move(from + Vector2(-8.0 * i, 0), 1))
	_btn(from + Vector2(-960, 0), false)
	await _frames(180, "coast", func(_i: int) -> void: pass)
	await _frames(240, "panels", func(i: int) -> void:
		var k := float(i) / 240.0
		_move(Vector2(lerpf(1560.0, 1880.0, k), lerpf(150.0, 700.0, fmod(k * 3.0, 1.0))), 0))
	for s in spikes.slice(0, 30):
		print("  spike ", s)
	quit()
