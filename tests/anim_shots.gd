extends SceneTree
# Behaviour animations close up: a division from start to finish, then one
# cell feeding, hunting, biting, hurt, and a dying shell, each a crop of the
# middle of the screen. Run: tools/run_test.sh tests/anim_shots.gd

const ACT_GRAZE := 2
const ACT_HUNT := 3
const ACT_BITE := 4

var scene: Node2D


func _initialize() -> void:
	root.add_child(preload("res://tests/test_window.gd").new())
	scene = load("res://scenes/showcase.tscn").instantiate()
	scene.seed = 1000
	root.add_child(scene)
	current_scene = scene
	_run.call_deferred()


func _shot(name: String, half := Vector2i(300, 220)) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var c := img.get_size() / 2
	img = img.get_region(Rect2i(c - half, half * 2))
	img.save_png(ProjectSettings.globalize_path("res://proofs/%s.png" % name))


func _wait(s: float) -> void:
	await create_timer(s).timeout


# Every organism as (id, agent) near the view, a few hundred at most.
func _agents() -> Array:
	var out := []
	var sim: SimCore = scene.sim
	for s in 16:
		var ps := sim.get_positions(s)
		for k in mini(ps.size(), 90):
			var id := sim.find_agent(ps[k], 1.0)
			if id >= 0:
				out.append(sim.get_agent(id))
	return out


# Keep the camera on one organism without selecting it (no reticle or card).
func _watch(id: int, zoom: float, seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		var a: Dictionary = scene.sim.get_agent(id)
		if a.is_empty():
			return
		scene.focus(a.position + Vector2.from_angle(a.heading) * a.radius * 0.9 * clampf(a.dividing * 2.0, 0.0, 1.0), zoom)
		await process_frame
		t += 1.0 / 60.0


func _find(pred: Callable, tries := 300) -> Dictionary:
	for t in tries:
		for a: Dictionary in _agents():
			if pred.call(a):
				return a
		await process_frame
	return {}


func _run() -> void:
	scene.advance(60.0)
	await _wait(0.5)
	# Division: catch one right as it starts and follow it through.
	var a: Dictionary = await _find(func(a: Dictionary) -> bool: return a.get("dividing", -1.0) >= 0.0 and a.dividing < 0.08 and a.diet == 0)
	if a.is_empty():
		push_error("no division found")
	else:
		for k in 10:
			await _watch(a.id, 11.0, 0.5)
			print("div ", k, " ", scene.sim.get_agent(a.id).get("dividing"), " t=", scene.sim.get_time())
			await _shot("anim_div_%d" % k, Vector2i(260, 180))
	var shots := {
		"anim_feed": func(a: Dictionary) -> bool: return a.action == ACT_GRAZE and a.get("dividing", -1.0) < 0.0,
		"anim_hunt": func(a: Dictionary) -> bool: return a.action == ACT_HUNT,
		"anim_bite": func(a: Dictionary) -> bool: return a.action == ACT_BITE,
	}
	for name: String in shots:
		var b: Dictionary = await _find(shots[name], 120)
		if b.is_empty():
			push_warning("none for %s" % name)
			continue
		await _watch(b.id, 8.0, 0.4)
		await _shot(name, Vector2i(260, 180))
		await _watch(b.id, 8.0, 0.12)
		await _shot(name + "_b", Vector2i(260, 180))
	# The three tiers on one spot: macro, group, micro.
	for z: Array in [["anim_tier_macro", 0.6], ["anim_tier_group", 2.2], ["anim_tier_micro", 8.0]]:
		scene.focus(scene.DISH_CENTER + Vector2(-300, 120), z[1])
		await _wait(1.2)
		await _shot(z[0], Vector2i(480, 300))
	quit()
