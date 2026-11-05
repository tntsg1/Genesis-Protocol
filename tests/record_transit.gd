extends SceneTree
# Recording of the eighth round (转场; a simulated cursor drawn on top, the
# real mouse is never touched): 设置 projected open and folded back, 战役
# behind the scan curtain (the drill-site point cloud assembling,
# turned by a drag), a station change (寒潮) wiping the card, then
# 进入实验: the light down the shaft, the lens into the level's dish.
# Run: tools/run_test.sh tests/record_transit.gd --write-movie <out.avi> --fixed-fps 60 -- --menu

var scene: Node2D
var cur := Vector2(960, 900)
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


func _idle(s: float) -> void:
	for i in int(s * 60.0):
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
	var n := int(s * 60.0)
	for i in n:
		var k := float(i + 1) / n
		k = k * k * (3.0 - 2.0 * k)
		_put(from.lerp(to, k))
		await process_frame


func _press(down: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.position = cur
	ev.global_position = cur
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = down
	Input.parse_input_event(ev)
	await process_frame


func _click() -> void:
	for down in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.position = cur
		ev.global_position = cur
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = down
		Input.parse_input_event(ev)
		await process_frame


func _run() -> void:
	_put(cur)
	await _idle(2.4)
	var items: Array = scene.menu.items
	# 设置: open, a look, close.
	await _glide(items[2].get_global_rect().get_center() + Vector2(-40, 0), 0.6)
	await _idle(0.4)
	await _click()
	await _idle(1.6)
	await _click()
	await _idle(0.9)
	# 战役.
	await _glide(items[0].get_global_rect().get_center() + Vector2(-40, 0), 0.5)
	await _idle(0.6)
	await _click()
	await _idle(2.6)
	var camp: Control = scene.campaign
	var sec: Control = camp.section
	# Turn the model by dragging it, and let it go.
	await _glide(sec.get_global_transform() * Vector2(200, 420), 0.6)
	await _press(true)
	await _glide(sec.get_global_transform() * Vector2(20, 470), 1.0)
	await _press(false)
	await _idle(0.6)
	# 寒潮, then back to the station to enter.
	var want := 3
	await _glide(sec.get_global_transform() * sec.station_pos(want) + Vector2(40, 8), 0.7)
	await _idle(0.2)
	await _click()
	await _idle(1.5)
	if not camp.can_start(Levels.ALL[want]):
		await _glide(sec.get_global_transform() * sec.station_pos(0) + Vector2(40, 8), 0.6)
		await _idle(0.2)
		await _click()
		await _idle(1.4)
	var foot: Control = camp.card_box.get_child(camp.card_box.get_child_count() - 1)
	var go: Control = foot.get_child(foot.get_child_count() - 1)
	await _glide(go.get_global_rect().get_center(), 0.8)
	await _idle(0.4)
	await _click()
	await _idle(4.6)
	quit()
