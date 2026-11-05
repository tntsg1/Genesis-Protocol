extends Node2D
# Level 24's vent guardian (shaders/rotifer.gdshader), one sprite each, and the
# water its corona pulls in: fine streaks running into the mouth from the
# cone ahead of it, quicker as it starves. In its frenzy (sim rot_rage > 1) it
# flushes red, the cilia beat harder and the water runs in thicker and faster;
# when it starves its husk stays where it died, draining and going limp.

const MAX := 4
const STREAKS := 140 # (half of them drawn, all while it rages)
const DIE_TIME := 2.5 # seconds (real) for a starved guardian to drain

var host: Node2D
var sprites: Array[Sprite2D] = []
var streaks := PackedVector3Array() # (along 0..1 of the way in, side -1..1, which rotifer)
var data := PackedFloat32Array()
var reach := 260.0
var extent := 110.0
var retract := 0.0 # 0..1: the corona drawn in (irritated), eased
var beat := 0.0 # the cilia's phase: they stop while it is drawn in
var rage := 0.0 # 0..1: the frenzy, eased in
var husks: Array[Dictionary] = [] # starved: {at, rot, fury, beat, age}
var last := PackedFloat32Array() # the rotifers last frame, to see one gone


func _init() -> void:
	var white := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	white.fill(Color.WHITE)
	var tex := ImageTexture.create_from_image(white)
	for k in MAX:
		var s := Sprite2D.new()
		s.texture = tex
		var m := ShaderMaterial.new()
		m.shader = preload("res://shaders/rotifer.gdshader")
		m.set_shader_parameter("seed", k * 0.37)
		s.material = m
		s.visible = false
		add_child(s)
		sprites.append(s)
	for k in STREAKS:
		streaks.append(Vector3(randf(), randf_range(-1.0, 1.0), 0.0))
	visible = false


func tick(dt: float, alpha: float) -> void:
	var lr: Node = host.level_runner
	var on: bool = lr != null and lr.phase == "run" and lr.level.has("world") and (lr.level.world.species as Array).any(func(s: Dictionary) -> bool: return (s.get("params", {}) as Dictionary).get("rotifer", false))
	visible = on
	if not on:
		husks.clear()
		last = PackedFloat32Array()
		rage = 0.0
		return
	var rp: Dictionary = lr.level.world.species[0].params
	reach = float(rp.get("rot_reach", 260.0))
	extent = float(rp.get("radius", 110.0))
	data = host.sim.get_rotifers(alpha)
	var zoom: float = host.cam.zoom.x
	var n := data.size() / 6
	# Irritated it snaps the corona in; it unfurls again more slowly.
	var rr: PackedFloat32Array = host.sim.get_rotifer_retract()
	var want := 1.0 if rr.size() > 0 and rr[0] > 0.0 else 0.0
	retract = move_toward(retract, want, dt * (4.0 if want > retract else 1.6))
	var e := retract * retract * (3.0 - 2.0 * retract)
	rage = move_toward(rage, 1.0 if host.sim.get_rot_rage() > 1.0 and n > 0 else 0.0, dt * 0.8)
	beat += dt * (7.0 + 9.0 * (data[3] if n > 0 else 0.0)) * (1.0 + 1.3 * rage) * (1.0 - e)
	# One gone since last frame starved: its husk stays where it was (the one
	# of last frame's farthest from any still here).
	var gone := last.size() / 6 - n
	while gone > 0 and husks.size() < MAX:
		gone -= 1
		var pick := -1
		var far := -1.0
		for j in last.size() / 6:
			var at := Vector2(last[j * 6], last[j * 6 + 1])
			var near := INF
			for k in n:
				near = minf(near, Vector2(data[k * 6], data[k * 6 + 1]).distance_to(at))
			for h in husks:
				near = minf(near, (h.at as Vector2).distance_to(at))
			if near > far:
				far = near
				pick = j
		husks.append({at = Vector2(last[pick * 6], last[pick * 6 + 1]), rot = last[pick * 6 + 2], fury = last[pick * 6 + 3], beat = beat, age = 0.0})
	last = data
	# (Real time: the death reads the same at any speed, and holds when paused.)
	var real := get_process_delta_time() if dt > 0.0 else 0.0
	for h in husks:
		h.age += real
	for k in MAX:
		var s := sprites[k]
		var hk := k - n
		s.visible = k < n or hk < husks.size()
		if not s.visible:
			continue
		var m: ShaderMaterial = s.material
		# (The texture is 2 px: scale it to the body's span, local 1 = extent.)
		s.scale = Vector2.ONE * extent * 1.3
		m.set_shader_parameter("px", 1.0 / (zoom * extent * 1.3))
		if k >= n:
			var h: Dictionary = husks[hk]
			var dd := clampf(float(h.age) / DIE_TIME, 0.0, 1.0)
			s.position = h.at
			s.rotation = h.rot
			m.set_shader_parameter("fury", float(h.fury) * (1.0 - dd))
			m.set_shader_parameter("chew", 0.0)
			# Its corona sags half in as it goes; the cilia stop.
			m.set_shader_parameter("retract", 0.45 * dd * dd * (3.0 - 2.0 * dd))
			m.set_shader_parameter("beat", h.beat)
			m.set_shader_parameter("rage", 0.0)
			m.set_shader_parameter("dead", dd * dd * (3.0 - 2.0 * dd))
			continue
		var o := k * 6
		s.position = Vector2(data[o], data[o + 1])
		s.rotation = data[o + 2]
		m.set_shader_parameter("fury", data[o + 3])
		m.set_shader_parameter("chew", data[o + 4])
		m.set_shader_parameter("retract", e)
		m.set_shader_parameter("beat", beat)
		m.set_shader_parameter("rage", rage)
		m.set_shader_parameter("dead", 0.0)
	for k in streaks.size():
		var st := streaks[k]
		var fury := data[3] if n > 0 else 0.0
		st.x += dt * (0.5 + 0.9 * fury) * (1.0 + 1.2 * rage)
		if st.x >= 1.0:
			st = Vector3(0.0, randf_range(-1.0, 1.0), float(randi() % maxi(n, 1)))
		streaks[k] = st
	queue_redraw()


func _draw() -> void:
	var n := data.size() / 6
	if n == 0:
		return
	var zoom: float = host.cam.zoom.x
	# While it chews: a ring round the mouth filling up; far off, a ring round it.
	for k in n:
		var o := k * 6
		var at := Vector2(data[o], data[o + 1])
		var mouth := at + Vector2.from_angle(data[o + 2]) * extent * 0.85
		if data[o + 4] > 0.0:
			draw_arc(mouth, 70.0, -PI * 0.5, -PI * 0.5 + TAU * data[o + 4], 48, Color(0.75, 0.3, 0.25, 0.85), 3.0 / zoom, true)
		if zoom < 1.2:
			var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.004)
			draw_arc(at, extent * 1.6 + 20.0 * pulse, 0, TAU, 64, Color(0.75, 0.3, 0.25, 0.35 + 0.3 * pulse), 2.5 / zoom, true)
	# Raging: twice the streaks, longer, quicker (tick), tinged with its red.
	var shown := STREAKS if rage > 0.3 else STREAKS / 2
	var tint := Color(0.42, 0.56, 0.62).lerp(Color(0.72, 0.36, 0.42), rage * 0.6)
	for si in shown:
		var st := streaks[si]
		var o := int(st.z) * 6
		if o + 5 >= data.size() or data[o + 4] > 0.0 or retract > 0.2:
			continue # (chewing or drawn in: the corona rests)
		var at := Vector2(data[o], data[o + 1])
		var h := data[o + 2]
		var mouth := at + Vector2.from_angle(h) * extent * 0.85
		# From the edge of its reach, curving in to the mouth.
		var r := reach * (1.0 - st.x)
		var a := h + st.y * 0.85 * (1.0 - st.x * 0.7)
		var p := mouth + Vector2.from_angle(a) * r
		var q := mouth + Vector2.from_angle(a) * maxf(r - (12.0 + 22.0 * st.x) * (1.0 + 0.9 * rage), 0.0)
		var fade := sin(PI * st.x)
		draw_line(p, q, Color(tint, (0.22 + 0.18 * rage) * fade), (1.2 + 0.4 * rage) / zoom)
