extends SceneTree
# Recording of the seventh round (主页; a simulated cursor drawn on top, the
# real mouse is never touched): the menu, hovering each item and its preview
# in the dish, the pointer on the dish, then 沙盒: lock-on burst, dissolve,
# the dive racking focus, the HUD coming up.
# Run: tools/run_test.sh tests/record_menu.gd --write-movie <out.avi> --fixed-fps 60 -- --menu

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
	await _idle(2.6)
	var items: Array = scene.menu.items
	for i in [0, 1, 2, 3]:
		await _glide(items[i].get_global_rect().get_center() + Vector2(-40, 0), 0.4)
		await _idle(1.7)
	# The dish answers the hand; a click ripples.
	await _glide(Vector2(1300, 560), 0.8)
	await _glide(Vector2(1460, 420), 1.0)
	await _click()
	await _idle(0.8)
	# 沙盒.
	await _glide(items[1].get_global_rect().get_center() + Vector2(-60, 0), 0.7)
	await _idle(0.5)
	await _click()
	await _idle(4.2)
	quit()
