class_name ShipArt
extends RefCounted
# The seed ship Genesis Protocol, drawn with the canvas API in ship lengths
# (nose at +0.535, engine bell at -0.5): shared by the end of Europa
# (ending.gd) and the landfall on planet one (arrival.gd). `burn` lights the
# engine; `t` flickers it; `glow` is a soft radial texture.

static func ship(ci: CanvasItem, at: Vector2, ang: float, s: float, burn: float, t: float, glow: Texture2D) -> void:
	ci.draw_set_transform(at, ang, Vector2(s, s))
	if burn > 0.0:
		var flick := 1.0 + 0.08 * sin(t * 37.0) + 0.05 * sin(t * 53.0)
		var l := (0.5 + 1.1 * burn) * flick
		var h := 0.16 + 0.12 * burn
		ci.draw_texture_rect(glow, Rect2(-0.5 - l, -h, l * 1.4, h * 2.0), false, Color(0.45, 0.65, 1.0, 0.55 * minf(burn, 1.0)))
		ci.draw_texture_rect(glow, Rect2(-0.5 - l * 0.45, -h * 0.4, l * 0.6, h * 0.8), false, Color(0.85, 0.95, 1.0, 0.95 * minf(burn, 1.0)))
		ci.draw_texture_rect(glow, Rect2(-0.62, -0.12, 0.24, 0.24), false, Color(1.0, 0.95, 0.85, 0.85 * minf(burn, 1.0)))
	var lit := Color(0.6, 0.72, 0.76)
	var shade := Color(0.15, 0.2, 0.23)
	var dark := Color(0.06, 0.08, 0.1)
	var rim := Color(0.6, 0.95, 1.0, 0.75)
	var w := 0.005
	# The engine bell.
	var bell := PackedVector2Array([Vector2(-0.4, -0.035), Vector2(-0.4, 0.035), Vector2(-0.5, 0.072), Vector2(-0.5, -0.072)])
	ci.draw_polygon(bell, PackedColorArray([shade, dark, dark, lit.darkened(0.25)]))
	ci.draw_line(bell[0], bell[3], rim, w)
	# Radiators: two swept wings of dark glass panels, edged in light.
	for side in [-1.0, 1.0]:
		var pts := PackedVector2Array([Vector2(-0.24, 0.024 * side), Vector2(-0.02, 0.024 * side), Vector2(-0.08, 0.2 * side), Vector2(-0.2, 0.2 * side)])
		var top: bool = side < 0
		ci.draw_polygon(pts, PackedColorArray([shade.lightened(0.1), shade, dark, dark]) if top else PackedColorArray([dark, dark, Color.BLACK, Color.BLACK]))
		for q in 6:
			var f := (q + 1) / 7.0
			ci.draw_line(Vector2(lerpf(-0.24, -0.2, f), lerpf(0.024, 0.2, f) * side), Vector2(lerpf(-0.02, -0.08, f), lerpf(0.024, 0.2, f) * side), Color(0.6, 0.95, 1.0, 0.16 if top else 0.07), 0.003)
		var edge := Color(rim, 0.7 if top else 0.25)
		ci.draw_line(pts[2], pts[3], edge, w)
		ci.draw_line(pts[1], pts[2], edge, w * 0.7)
	# The spine and its truss.
	ci.draw_rect(Rect2(-0.42, -0.018, 0.66, 0.036), shade)
	for q in 12:
		var x := -0.4 + q * 0.054
		ci.draw_line(Vector2(x, -0.018), Vector2(x + 0.027, 0.018), Color(0.6, 0.95, 1.0, 0.22), 0.003)
	ci.draw_line(Vector2(-0.42, -0.018), Vector2(0.24, -0.018), rim, w * 0.8)
	# Tanks, long, either side of the spine.
	for side in [-1.0, 1.0]:
		tube(ci, Vector2(-0.3, 0.05 * side), 0.05, 0.03, lit if side < 0 else shade, dark, Color(rim, 0.7 if side < 0 else 0.2))
	# The seed vault's pod: glass, the green medium, the five bodies in it.
	ci.draw_texture_rect(glow, Rect2(-0.1, -0.18, 0.4, 0.36), false, Color(0.4, 1.0, 0.7, 0.28))
	tube(ci, Vector2(0.1, 0), 0.085, 0.058, Color(0.3, 0.45, 0.48, 0.55), Color(0.05, 0.1, 0.1, 0.8), rim)
	tube(ci, Vector2(0.1, 0), 0.08, 0.044, Color(0.45, 0.9, 0.66, 0.85), Color(0.1, 0.36, 0.26, 0.9), Color(0, 0, 0, 0))
	for q in 5:
		var c := Vector2(0.03 + q * 0.035, 0.012 * sin(q * 2.1 + t * 0.8))
		ci.draw_rect(Rect2(c - Vector2(0.011, 0.009), Vector2(0.022, 0.018)), Color(0.16, 0.5, 0.36))
		ci.draw_rect(Rect2(c - Vector2(0.011, 0.009), Vector2(0.022, 0.018)), Color(0.8, 1.0, 0.9, 0.8), false, 0.003)
	ci.draw_line(Vector2(0.03, -0.032), Vector2(0.17, -0.032), Color(1, 1, 1, 0.5), 0.004)
	# The crew module and its nose.
	tube(ci, Vector2(0.34, 0), 0.12, 0.052, lit, dark, rim)
	var nose := PackedVector2Array([Vector2(0.45, -0.044), Vector2(0.535, -0.012), Vector2(0.535, 0.012), Vector2(0.45, 0.044)])
	ci.draw_polygon(nose, PackedColorArray([lit, lit, dark, dark]))
	ci.draw_line(nose[0], nose[1], rim, w)
	ci.draw_rect(Rect2(0.28, -0.054, 0.016, 0.108), dark)
	for q in 4:
		ci.draw_circle(Vector2(0.33 + q * 0.028, -0.022), 0.006, Color(1.0, 0.9, 0.68))
	ci.draw_set_transform(Vector2.ZERO)


# A capsule along x (centre, half length to the end caps' centres, radius),
# shaded from `lit` on its -y side to `shade` on the other, `edge` on the lit
# rim.
static func tube(ci: CanvasItem, c: Vector2, half: float, r: float, lit: Color, shade: Color, edge: Color) -> void:
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	for k in 33:
		var a := -PI * 0.5 + PI * k / 32.0
		pts.append(c + Vector2(half + cos(a) * r, sin(a) * r))
	for k in 33:
		var a := PI * 0.5 + PI * k / 32.0
		pts.append(c + Vector2(-half + cos(a) * r, sin(a) * r))
	for p in pts:
		var f := clampf(((p.y - c.y) / r + 1.0) * 0.5, 0.0, 1.0)
		cols.append(lit.lerp(shade, pow(f, 1.4)))
	ci.draw_polygon(pts, cols)
	if edge.a > 0.0:
		ci.draw_line(c + Vector2(-half, -r), c + Vector2(half, -r), edge, 0.005)
