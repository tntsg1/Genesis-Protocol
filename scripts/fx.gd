extends MultiMeshInstance2D
# Effect particles for life events (SimCore.take_events) and interventions.
# A fixed pool of slots used as a ring: spawning writes one slot, the shader
# (shaders/fx.gdshader) animates and retires it. Events outside the view are
# skipped, and a per-frame budget keeps 8x speed smooth.

const CAPACITY := 6000
const BUDGET := 700 # particles per frame at most

enum { MOTE, RING, SPARK, BUBBLE, STAR, FLASH, HELIX, RETICLE, DUST }

var mat: ShaderMaterial
var now := 0.0
var cursor := 0
var spawned := 0
var colors: Array[Color] = []
var view := Rect2()


func _init() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = CAPACITY
	# Every slot starts expired (born long ago).
	for i in CAPACITY:
		mm.set_instance_custom_data(i, Color(-1000.0, 0, 0, 0.01))
	multimesh = mm
	mat = ShaderMaterial.new()
	mat.shader = preload("res://shaders/fx.gdshader")
	material = mat


# Advance effect time (frozen while the simulation is paused) and set the
# visible world rectangle used for culling.
func tick(delta: float, visible_world: Rect2) -> void:
	now += delta
	mat.set_shader_parameter("now", now)
	view = visible_world.grow(60.0)
	spawned = 0


func particle(pos: Vector2, vel: Vector2, size: float, col: Color, kind: int, life: float, delay := 0.0) -> void:
	if spawned >= BUDGET:
		return
	spawned += 1
	var i := cursor
	cursor = (cursor + 1) % CAPACITY
	multimesh.set_instance_transform_2d(i, Transform2D(0.0, Vector2(size, size), 0.0, pos))
	multimesh.set_instance_color(i, Color(col.r, col.g, col.b, float(kind)))
	multimesh.set_instance_custom_data(i, Color(now + delay, vel.x, vel.y, life))


func _rand_dir() -> Vector2:
	var a := randf() * TAU
	return Vector2(cos(a), sin(a))


# Turn the simulation's event stream into effects.
func consume(events: PackedFloat32Array, zoom: float) -> void:
	var n := events.size() / 6
	# Fine detail only when close enough to see it.
	var close := zoom > 1.4
	for k in n:
		var b := k * 6
		var pos := Vector2(events[b + 1], events[b + 2])
		if not view.has_point(pos):
			continue
		var type := int(events[b])
		var s := int(events[b + 3])
		var col: Color = colors[s] if s < colors.size() else Ui.ACCENT
		var other := Vector2(events[b + 4], events[b + 5])
		# A restrained, instrument-like language: hairline rings, a focusing
		# reticle, fine dust. Division and feeding are drawn by the organism
		# shader itself (pinching, engulfing, food vacuoles), so they get
		# little or nothing here.
		match type:
			SimCore.EV_BIRTH:
				# The division scene says it all; close up, one faint ripple.
				if close:
					particle((pos + other) * 0.5, Vector2.ZERO, 30.0, col.lerp(Color.WHITE, 0.5), RING, 0.7)
			SimCore.EV_MUTATION:
				# A new lineage: a reticle in its colour closes in on it, and a
				# short grey strand of DNA rises off it (close enough to read).
				particle(pos, Vector2.ZERO, 34.0, col.lerp(Ui.INK, 0.25), RETICLE, 1.3)
				if zoom > 0.75:
					particle(pos, Vector2(0.0, -38.0), 20.0, Color(0.55, 0.6, 0.64), HELIX, 1.6, 0.15)
			SimCore.EV_EATEN:
				# Swallowed whole (the shader shows it inside the predator).
				if close:
					particle(pos, Vector2.ZERO, events[b + 4] * 2.6, col.lerp(Color.WHITE, 0.5), RING, 0.5)
			SimCore.EV_DIED:
				# Starved or old: a faint ring and a couple of small bubbles
				# (nothing from afar, where deaths would only add noise).
				if zoom > 0.75:
					particle(pos, Vector2.ZERO, 26.0, col.lerp(Color.WHITE, 0.5), RING, 1.2)
				if close:
					for j in 2:
						particle(pos + _rand_dir() * 4.0, Vector2.ZERO, randf_range(3.5, 5.5), Color(0.8, 0.9, 0.96), BUBBLE, 2.2, j * 0.3)
			SimCore.EV_HATCH:
				# A young colony breaks out through the jelly.
				particle(pos, Vector2.ZERO, 46.0, col.lerp(Color.WHITE, 0.45), RING, 0.9)
				if zoom > 0.75:
					for j in 7:
						particle(pos + _rand_dir() * 7.0, _rand_dir() * randf_range(10, 34), randf_range(2.0, 3.4), col.lerp(Color.WHITE, 0.3), DUST, randf_range(0.8, 1.5), j * 0.03)
			SimCore.EV_CBITE:
				# A hunter's bite off a colony's rim: armour throws it off with
				# a few flakes of cuticle; anything else spills green.
				if events[b + 4] > 0.5:
					particle(pos, Vector2.ZERO, 22.0, Color(0.9, 0.8, 0.6), RING, 0.45)
					if close:
						for j in 4:
							particle(pos + _rand_dir() * 3.0, Vector2.from_angle(events[b + 5] + randf_range(-0.8, 0.8)) * randf_range(10, 24), randf_range(1.6, 2.4), Color(0.86, 0.74, 0.54), DUST, randf_range(0.5, 0.8), j * 0.02)
				else:
					particle(pos, Vector2.ZERO, 30.0, Color(0.92, 0.42, 0.26), RING, 0.6)
					for j in 7:
						particle(pos + _rand_dir() * 4.0, _rand_dir() * randf_range(8, 28), randf_range(2.0, 3.2), Color(0.5, 0.74, 0.4), DUST, randf_range(0.7, 1.3), j * 0.03)
			SimCore.EV_GRIT:
				# A killed embryo spills; a grain that only glanced off does less.
				if events[b + 4] > 0.5:
					particle(pos, Vector2.ZERO, 24.0, Color(0.92, 0.42, 0.26), RING, 0.6)
					for j in 6:
						particle(pos + _rand_dir() * 3.0, _rand_dir() * randf_range(8, 26), randf_range(1.8, 3.0), Color(0.5, 0.74, 0.4), DUST, randf_range(0.7, 1.2), j * 0.02)
				elif close:
					particle(pos, _rand_dir() * 12.0, 2.4, Color(0.6, 0.54, 0.46), DUST, 0.5)


# A nutrient drop by the player: like a pinch of powder in water, one
# hairline ripple and fine pale grains drifting out and settling (the dish's
# nutrient field spreads underneath).
func nutrient_splash(pos: Vector2) -> void:
	particle(pos, Vector2.ZERO, 140.0, Color(0.6, 0.78, 0.62), RING, 1.4)
	for j in 16:
		var tone := Color(0.7, 0.86, 0.66).lerp(Color(0.94, 0.96, 0.88), randf())
		particle(pos + _rand_dir() * randf_range(0, 10), _rand_dir() * randf_range(12, 48), randf_range(2.2, 3.6), tone, DUST, randf_range(2.0, 3.2), randf() * 0.25)


# A designed species is seeded: a soft pulse and two hairline rings racing out.
func release_burst(pos: Vector2, col: Color, radius: float) -> void:
	particle(pos, Vector2.ZERO, radius * 1.6, Color.WHITE, FLASH, 0.5)
	particle(pos, Vector2.ZERO, radius * 3.4, col, RING, 1.4)
	particle(pos, Vector2.ZERO, radius * 2.2, Ui.ACCENT, RING, 1.0, 0.18)
