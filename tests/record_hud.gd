extends SceneTree
# Recording of the HUD motion pass (a simulated cursor; the real mouse is never
# touched): the HUD's entrance, panels lighting under the cursor, button
# hover / press / hotkey pings, spending points, events sliding in.
# Over panels the game shows the OS arrow, which a recording does not
# capture, so this test draws a stand-in arrow there.
# Run: tools/run_test.sh tests/record_hud.gd --write-movie <out.avi> --fixed-fps 60

var scene: Node2D
var cur := Vector2(960, 600)
var arrow: Node2D


func _initialize() -> void:
	root.add_child(preload("res://tests/test_window.gd").new())
	scene = load("res://scenes/showcase.tscn").instantiate()
	scene.seed = 1000
	root.add_child(scene)
	current_scene = scene
	var layer := CanvasLayer.new()
	layer.layer = 100
	arrow = Node2D.new()
	arrow.draw.connect(_draw_arrow)
	layer.add_child(arrow)
	root.add_child(layer)
	_run.call_deferred()


func _process(_delta: float) -> bool:
	if arrow:
		arrow.queue_redraw()
	return false


func _draw_arrow() -> void:
	if scene == null or scene.pointer.shown:
		return
	var p := cur
	var pts := PackedVector2Array([p, p + Vector2(0, 17), p + Vector2(4.5, 13), p + Vector2(8, 20), p + Vector2(10.5, 19), p + Vector2(7, 12), p + Vector2(12.5, 12)])
	arrow.draw_colored_polygon(pts, Color.WHITE)
	pts.append(p)
	arrow.draw_polyline(pts, Color(0.1, 0.15, 0.2), 1.2, true)


func _frames(s: float) -> int:
	return int(s * 60.0)


func _idle(s: float) -> void:
	for i in _frames(s):
		await process_frame


func _put(p: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = p
	ev.global_position = p
	ev.relative = p - cur
	cur = p
	Input.parse_input_event(ev)


func _glide(to: Vector2, s: float) -> void:
	var from := cur
	var n := _frames(s)
	for i in n:
		var k := float(i + 1) / n
		k = k * k * (3.0 - 2.0 * k)
		_put(from.lerp(to, k))
		await process_frame


func _click() -> void:
	for down in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.position = cur
		ev.global_position = cur
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = down
		Input.parse_input_event(ev)
		for i in 5:
			await process_frame


func _key(k: Key) -> void:
	for down in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = k
		ev.physical_keycode = k
		ev.pressed = down
		Input.parse_input_event(ev)
		await process_frame


func _centre_of(c: Control) -> Vector2:
	return c.get_global_rect().get_center()


func _run() -> void:
	scene.advance(60.0)
	scene.focus(scene.DISH_CENTER + Vector2(-200, 120), 1.3)
	var hud: Control = scene.hud_root
	hud.conceal()
	await _idle(0.9)
	# The visor boots; panels materialise as the sweep passes.
	hud.reveal()
	await _idle(2.3)
	# Panels light under the cursor (glyphs drift off), parallax as it moves.
	await _glide(_centre_of(hud.panels["species"]) + Vector2(40, -60), 1.0)
	await _idle(0.5)
	await _glide(_centre_of(hud.panels["environment"]), 1.1)
	await _idle(0.4)
	# Buttons: sweep across the dock, use one.
	var dock: Dictionary = hud.dock_buttons
	await _glide(_centre_of(dock["observe"]), 0.9)
	for k: String in ["analysis", "filter", "nutrient", "membrane", "heat"]:
		await _glide(_centre_of(dock[k]), 0.24)
		await _idle(0.08)
	await _glide(_centre_of(dock["analysis"]), 0.45)
	await _click()
	await _idle(1.1)
	await _click()
	await _idle(0.4)
	await _glide(Vector2(1180, 640), 0.5)
	await _key(KEY_3)
	await _idle(0.7)
	await _key(KEY_1)
	await _idle(0.3)
	# Something important: the banner, its leader line down to the place.
	var near: Vector2 = scene.cam.position + Vector2(160, 120)
	var id: int = scene.sim.find_agent(near, 200.0)
	var p: Vector2 = scene.sim.get_agent(id).position if id >= 0 else near
	hud.banner("新谱系出现　冰晶游丝 β", "NEW LINEAGE  ·  #812  ·  感知 +0.21  游速 −0.08", Color(1.0, 0.68, 0.2), p)
	hud.notify("新谱系 #812：冰晶游丝 β（感知突变）", Color(1.0, 0.72, 0.25), p)
	await _idle(3.6)
	quit()
