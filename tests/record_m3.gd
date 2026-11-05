extends SceneTree
# Scripted M3 demo for a recording (movie writer, fixed 60 fps): the Europa
# sample from above with its zones, a flight through the vent, the cold water
# and the acid pool, the analysis maps (temperature, acidity), a cell's life
# scan in the wrong water, and the designer's thermal gene and forecast.
# Run: tools/run_test.sh tests/record_m3.gd --write-movie <out.avi> --fixed-fps 60

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


func _fly(pos: Vector2, zoom: float, s: float) -> void:
	await scene.fly_to(pos, zoom, s).finished


func _run() -> void:
	scene.advance(60.0)
	scene.focus(scene.DISH_CENTER, 0.47)
	scene.hud_root.reveal()
	await _wait(2.4)
	var zones: Array = scene.layout.zones
	for z: Dictionary in zones:
		await _fly(z.center, 1.5, 1.8)
		await _wait(1.3)
	await _fly(scene.DISH_CENTER, 0.47, 1.8)
	scene.set_env_layer(1)
	await _wait(2.2)
	scene.set_env_layer(2)
	await _wait(2.0)
	scene.set_env_layer(0)
	scene.set_analysis(false)
	await _wait(0.6)
	# A grazer from the open water that has strayed into the vent's heat.
	var vent: Vector2 = zones[0].center
	var id: int = -1
	for p in scene.sim.get_positions(0):
		if p.distance_to(vent) < 380.0:
			id = scene.sim.find_agent(p, 2.0)
			break
	if id < 0:
		id = scene.sim.find_agent(vent, 500.0)
	var info: Dictionary = scene.sim.get_agent(id)
	await _fly(info.position, 3.2, 1.6)
	scene.selected = id
	scene.following = true
	await _wait(3.0)
	scene.open_designer()
	var d: Control = scene.designer
	while d.busy:
		await process_frame
	d.select_gene(7)
	await _wait(1.8)
	for t in [16.0, 22.0, 28.0, 34.0]:
		d.temp_slider.value = t
		d.temp_slider.queue_redraw()
		d.temp_slider.changed.emit(t)
		await _wait(0.5)
	await _wait(1.5)
	quit()
