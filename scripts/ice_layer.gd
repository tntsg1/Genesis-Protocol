class_name IceLayer
extends Node2D
# Chapter 7 in the dish: the ice (SimCore walls: nothing crosses or sees
# through) as thick translucent bands of sea ice with a bright core and a
# frosted edge; and the boss of 7-5, a heliozoan (太阳虫): a round body of
# foamy cytoplasm with dozens of fine straight axopods all round, granules
# running out along them; drawn in while it rolls to its next spot, a line to
# each cell it holds. Redrawn every frame (one boss, a few dozen walls).

const ICE := Color(0.84, 0.94, 0.99, 0.82)
const ICE_EDGE := Color(0.6, 0.82, 0.94, 0.9)
const HELIO := Color(0.98, 0.86, 0.6)
const HELIO_EDGE := Color(0.82, 0.6, 0.36)
const AXOPODS := 56

var host: Node2D
var walls := PackedVector2Array()
var reach_k := 1.0 # the axopods out (1) or drawn in (0)


func reset() -> void:
	walls = host.sim.get_walls()
	visible = not walls.is_empty() or bool(host.sim.get_helio().get("on", false))
	reach_k = 1.0
	queue_redraw()


func _process(delta: float) -> void:
	if not visible or host == null:
		return
	var h: Dictionary = host.sim.get_helio()
	if bool(h.get("on", false)):
		var want := 0.0 if bool(h.get("moving", false)) or bool(h.get("dead", false)) else 1.0
		reach_k = move_toward(reach_k, want, delta / 1.2)
	queue_redraw()


func _draw() -> void:
	if host == null:
		return
	var zoom: float = host.cam.zoom.x
	var px := 1.0 / zoom
	# The ice.
	for k in range(0, walls.size(), 2):
		var a := walls[k]
		var b := walls[k + 1]
		draw_line(a, b, Color(ICE_EDGE, 0.35), 30.0, true)
		draw_line(a, b, ICE, 22.0, true)
		draw_line(a, b, Color(1, 1, 1, 0.75), 5.0, true)
		for p in [a, b]:
			draw_circle(p, 11.0, ICE)
		# Frost along the edges: short ticks at a fixed spacing.
		var d := b - a
		var n := d.orthogonal().normalized()
		var steps := int(d.length() / 26.0)
		for s in steps:
			var q := a.lerp(b, (s + 0.5) / maxf(steps, 1))
			var side := 1.0 if s % 2 == 0 else -1.0
			draw_line(q + n * side * 10.0, q + n * side * (14.0 + 4.0 * fposmod(s * 0.37, 1.0)), Color(ICE_EDGE, 0.7), 1.4 * px, true)
	# The heliozoan.
	var h: Dictionary = host.sim.get_helio()
	if not bool(h.get("on", false)):
		return
	var c: Vector2 = h.pos
	var body: float = h.body
	var reach: float = float(h.reach) * reach_k
	var t := Time.get_ticks_msec() / 1000.0
	var dead := bool(h.get("dead", false))
	var fade := 0.35 if dead else 1.0
	if reach > 1.0:
		draw_circle(c, reach, Color(HELIO, 0.04 * fade))
		for k in AXOPODS:
			var ang := TAU * k / AXOPODS + 0.03 * sin(k * 2.7)
			var dir := Vector2.from_angle(ang)
			var len := reach * (0.82 + 0.18 * fposmod(k * 0.618, 1.0))
			var from := c + dir * body * 0.9
			var to := c + dir * len
			draw_line(from, to, Color(HELIO_EDGE, 0.75 * fade), 1.3 * px, true)
			# Granules running out along the axopod.
			for g in 3:
				var u := fposmod(t * 0.18 + g / 3.0 + k * 0.071, 1.0)
				draw_circle(from.lerp(to, u), 1.6 * px * 1.5, Color(HELIO, 0.9 * fade * (1.0 - u * 0.6)))
	# The body: a pale foamy sphere with a darker rim and vacuoles.
	draw_circle(c, body + 3.0, Color(HELIO_EDGE, 0.5 * fade))
	draw_circle(c, body, Color(HELIO, 0.92 * fade))
	for k in 14:
		var a := k * 2.39996
		var r := body * 0.75 * sqrt(fposmod(k * 0.618 + 0.2, 1.0))
		draw_circle(c + Vector2.from_angle(a + t * 0.05) * r, body * (0.08 + 0.06 * fposmod(k * 0.37, 1.0)), Color(1, 1, 1, 0.55 * fade))
	draw_circle(c, body * 0.32, Color(HELIO_EDGE, 0.55 * fade))
	if not dead:
		var e := float(h.get("energy_frac", 0.0))
		draw_arc(c, body + 9.0, -PI * 0.5, -PI * 0.5 + TAU * clampf(e, 0.0, 1.0), 48, Color(HELIO_EDGE, 0.9), 3.0 * px, true)
