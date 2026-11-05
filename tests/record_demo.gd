extends SceneTree
# Scripted demo for a screen recording (Godot movie writer, fixed 60 fps):
# the dish, the dive into a cell, the genome lab driven by a pushed mouse
# (hover lens and probe, click ripple and run, drag-throw-snap, wheel,
# karyotype jump, level changes), release, the incubation capsule.
# Run: tools/run_test.sh tests/record_demo.gd --write-movie <out.avi> --fixed-fps 60

var scene: Node2D


func _initialize() -> void:
	root.add_child(preload("res://tests/test_window.gd").new())
	scene = load("res://scenes/showcase.tscn").instantiate()
	scene.seed = 1000
	root.add_child(scene)
	current_scene = scene
	_run.call_deferred()


func _wait(s: float) -> void:
	await create_timer(s).timeout


func _bump(d: Control, k: int, to: float) -> void:
	d.gene_sliders[k].value = to
	d.gene_sliders[k].changed.emit(to)


var _last := Vector2.ZERO


func _move(at: Vector2, mask := 0) -> void:
	var e := InputEventMouseMotion.new()
	e.relative = at - _last
	_last = at
	e.position = at
	e.global_position = at
	e.button_mask = mask
	root.push_input(e)


func _btn(at: Vector2, idx: MouseButton, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = idx
	e.pressed = pressed
	e.position = at
	e.global_position = at
	e.button_mask = (1 << (idx - 1)) if pressed else 0
	root.push_input(e)


# Glide the mouse from a to b over s seconds (ease in-out), one event a frame.
func _glide(a: Vector2, b: Vector2, s: float, mask := 0) -> void:
	var n := maxi(2, int(s * 60.0))
	for i in range(1, n + 1):
		var u := float(i) / n
		_move(a.lerp(b, u * u * (3.0 - 2.0 * u)), mask)
		await process_frame


func _click(at: Vector2) -> void:
	_btn(at, MOUSE_BUTTON_LEFT, true)
	await process_frame
	_btn(at, MOUSE_BUTTON_LEFT, false)


func _run() -> void:
	scene.advance(30.0)
	scene.focus(Vector2(900, 980), 1.3)
	scene.hud_root.reveal()
	await _wait(1.4)
	var id: int = scene.sim.find_agent(Vector2(900, 980), 400.0)
	scene.selected = id
	await _wait(0.5)
	scene.open_designer()
	var d: Control = scene.designer
	while d.busy:
		await process_frame
	var c: Vector2 = d.STAGE_CENTER
	await _wait(0.4)
	# The mouse comes onto the strand and reads it.
	_last = c + Vector2(560, 300)
	await _glide(_last, c + Vector2(-240, 30), 1.2)
	await _glide(_last, c + Vector2(120, -10), 1.3)
	await _wait(0.3)
	# Level up: base pairs pour in.
	_bump(d, 0, 4.0)
	await _wait(1.1)
	# Click a neighbour: ripple, and the run to it.
	await _click(c + Vector2(330, -30))
	await _wait(1.3)
	_bump(d, 1, 1.5)
	await _wait(1.0)
	# Grab the strand and throw it: it coasts and snaps to a gene far away.
	var g0 := c + Vector2(260, 0)
	await _glide(_last, g0, 0.4)
	_btn(g0, MOUSE_BUTTON_LEFT, true)
	await process_frame
	await _glide(g0, g0 + Vector2(-520, 0), 0.25, 1)
	_btn(_last, MOUSE_BUTTON_LEFT, false)
	await _wait(2.4)
	# Wheel back a couple of genes.
	for i in 2:
		_btn(_last, MOUSE_BUTTON_WHEEL_UP, true)
		_btn(_last, MOUSE_BUTTON_WHEEL_UP, false)
		await _wait(1.0)
	await _glide(_last, c + Vector2(-60, 40), 0.8)
	_bump(d, d.sel_gene, 3.5)
	await _wait(1.2)
	# Karyotype: jump straight to the first gene.
	var ky: float = d._specimen_center().y + d.TANK_BOTTOM + 92.0
	var kx: float = d.chamber.position.x + 18.0 + (d.chamber.size.x - 36.0) / 7.0 * 0.5
	await _glide(_last, Vector2(kx, ky), 0.7)
	await _click(Vector2(kx, ky))
	await _wait(2.0)
	# Release: pull out, the capsule incubates and opens.
	d.release()
	while scene.designer != null:
		await process_frame
	await _wait(0.4)
	scene._do_release(scene.cam.position + Vector2(40, 10))
	await _wait(4.0)
	quit()
