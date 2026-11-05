class_name GenomeArt
extends RefCounted
# The genome drawn as flat, friendly 2D ink: a nucleus with one X-shaped
# chromosome per gene, and a DNA double helix whose base pairs grow with the
# gene's level. Used by the life designer, its dive-in transition and the
# life scan. Everything is plain draw calls on whatever CanvasItem asks.

# One colour per gene (speed, sense, shell, attack, fertility, metabolism,
# neural, thermal tolerance).
const GENE_COLORS := [
	Color("3fb6d8"), Color("ef7d6d"), Color("b98a5a"), Color("e2607f"),
	Color("5bbf7a"), Color("e8b53a"), Color("8d72e0"), Color("e07f4f"),
]
# Bases A, T, G, C: pairs are A–T and G–C.
const BASE_COLORS := [Color("f08a7e"), Color("f3c35b"), Color("5cc49a"), Color("5aa8e6")]
const BASE_LETTERS := ["A", "T", "G", "C"]
const NUCLEUS_FILL := Color(0.86, 0.85, 0.99)
const NUCLEUS_LINE := Color(0.47, 0.43, 0.78)


static func _hash(a: float, b: float) -> float:
	return fposmod(sin(a * 12.9898 + b * 78.233) * 43758.5453, 1.0)


# A pinched sausage along a gently bowed centre line: one sister chromatid.
static func _chromatid(c: Vector2, dir: Vector2, half_len: float, width: float, bow: float) -> PackedVector2Array:
	var n := Vector2(-dir.y, dir.x)
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var steps := 14
	for k in steps + 1:
		var s := -1.0 + 2.0 * k / steps
		var p := c + dir * s * half_len + n * bow * s * s * half_len
		var tan := (dir + n * bow * 2.0 * s).normalized()
		var nn := Vector2(-tan.y, tan.x)
		var w := width * 0.5 * (0.6 + 0.4 * smoothstep(0.0, 0.5, absf(s)))
		left.append(p + nn * w)
		right.append(p - nn * w)
	var poly := PackedVector2Array()
	poly.append_array(left)
	# Round cap at the far end.
	var tip := c + dir * half_len + n * bow * half_len
	var tip_dir := (dir + n * bow * 2.0).normalized()
	var a0 := tip_dir.angle() + PI * 0.5
	for k in range(1, 6):
		poly.append(tip + Vector2.from_angle(a0 - PI * k / 6.0) * width * 0.5)
	for k in range(right.size() - 1, -1, -1):
		poly.append(right[k])
	var base := c - dir * half_len + n * bow * half_len
	var base_dir := (dir - n * bow * 2.0).normalized()
	var b0 := base_dir.angle() - PI * 0.5
	for k in range(1, 6):
		poly.append(base + Vector2.from_angle(b0 - PI * k / 6.0) * width * 0.5)
	return poly


static func _point_on(c: Vector2, dir: Vector2, half_len: float, bow: float, s: float) -> Vector2:
	var n := Vector2(-dir.y, dir.x)
	return c + dir * s * half_len + n * bow * s * s * half_len


# An X-shaped (replicated) chromosome. Bands across each chromatid count the
# gene's level; glow lifts it and adds a halo.
static var _shapes := {}


# A chromosome's geometry, built once per (length, level) at the origin with
# its axis along +x; drawing then only places it with a transform.
static func _shape(length: float, level: float) -> Dictionary:
	var key := Vector2i(roundi(length * 4.0), roundi(level * 2.0))
	if _shapes.has(key):
		return _shapes[key]
	if _shapes.size() > 600:
		_shapes.clear()
	var half := length * 0.5
	var width := length * 0.3
	var bands := floori(level + 0.01)
	var shape := {polys = [], outlines = [], bands = PackedVector2Array(), faint = PackedVector2Array(),
		tips = PackedVector2Array(), width = width}
	for side: float in [-1.0, 1.0]:
		var dir := Vector2.from_angle(side * 0.36)
		var bow: float = -side * 0.14
		var poly := _chromatid(Vector2.ZERO, dir, half, width, bow)
		shape.polys.append(poly)
		var outline := poly.duplicate()
		outline.append(poly[0])
		shape.outlines.append(outline)
		# Bands count the level; the upper arm takes the odd one.
		var up := ceili(bands / 2.0)
		var down := bands - up
		var n := Vector2(-dir.y, dir.x)
		for arm in [[up, 1.0], [down, -1.0]]:
			for j in arm[0]:
				var s: float = arm[1] * (0.34 + 0.52 * (j + 0.5) / maxf(arm[0], 1.0))
				var p := _point_on(Vector2.ZERO, dir, half, bow, s)
				var tan: Vector2 = (dir + n * bow * 2.0 * s).normalized()
				var nn := Vector2(-tan.y, tan.x) * width * 0.42
				shape.bands.append(p - nn)
				shape.bands.append(p + nn)
		if level - bands > 0.25:
			var p := _point_on(Vector2.ZERO, dir, half, bow, -0.88)
			shape.faint.append(p - n * width * 0.32)
			shape.faint.append(p + n * width * 0.32)
		# Telomeres: the tips a shade paler (no dots: they read as eyes).
		for s: float in [1.0, -1.0]:
			var tp := _point_on(Vector2.ZERO, dir, half, bow, s * 0.9)
			shape.tips.append(tp - n * width * 0.36)
			shape.tips.append(tp + n * width * 0.36)
	_shapes[key] = shape
	return shape


# An X-shaped (replicated) chromosome. Bands across each chromatid count the
# gene's level; glow lifts it and adds a halo.
# holo: the designer's hologram look, outlines that glow over a faint fill.
static func chromosome(ci: CanvasItem, c: Vector2, angle: float, length: float, col: Color,
		level: float, glow := 0.0, alpha := 1.0, holo := false) -> void:
	var scale := 1.0 + 0.14 * glow
	if glow > 0.01:
		var hr := length * 0.5 * scale * 1.25
		ci.draw_circle(c, hr, Color(col, 0.13 * glow * alpha))
		ci.draw_arc(c, hr, 0.0, TAU, 40, Color(col, 0.45 * glow * alpha), 1.2, true)
	var shape := _shape(length, level)
	var width: float = shape.width
	ci.draw_set_transform(c, angle, Vector2(scale, scale))
	if holo:
		for k in 2:
			ci.draw_colored_polygon(shape.polys[k], Color(col, 0.16 * alpha))
			ci.draw_polyline(shape.outlines[k], Color(col, 0.18 * alpha), 4.0, true)
			ci.draw_polyline(shape.outlines[k], Color(col.darkened(0.12), 0.95 * alpha), 1.3, true)
		if shape.bands.size() > 0:
			ci.draw_multiline(shape.bands, Color(col, 0.8 * alpha), 1.4, true)
		if shape.faint.size() > 0:
			ci.draw_multiline(shape.faint, Color(col, 0.4 * alpha), 1.0, true)
		ci.draw_multiline(shape.tips, Color(col.lightened(0.45), 0.9 * alpha), 1.4, true)
		ci.draw_arc(Vector2.ZERO, width * 0.3, 0.0, TAU, 16, Color(col.darkened(0.2), alpha), 1.2, true)
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	var fill := Color(col.lerp(Color.WHITE, 0.28), 0.92 * alpha)
	var ink := Color(col.darkened(0.42), 0.9 * alpha)
	for k in 2:
		ci.draw_colored_polygon(shape.polys[k], fill)
		ci.draw_polyline(shape.outlines[k], ink, 1.2, true)
	if shape.bands.size() > 0:
		ci.draw_multiline(shape.bands, Color(col.darkened(0.3), 0.8 * alpha), 2.0, true)
	if shape.faint.size() > 0:
		ci.draw_multiline(shape.faint, Color(col.darkened(0.3), 0.4 * alpha), 1.4, true)
	ci.draw_multiline(shape.tips, Color(col.lightened(0.55), 0.85 * alpha), maxf(1.5, width * 0.18), true)
	# Centromere: the pinch, a darker knot.
	ci.draw_circle(Vector2.ZERO, width * 0.3, Color(col.darkened(0.3), 0.95 * alpha))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# Where the centromere and one telomere of a chromosome sit (for labels).
static func chromosome_marks(c: Vector2, angle: float, length: float, glow: float) -> Array:
	var half := length * 0.5 * (1.0 + 0.14 * glow)
	var dir := Vector2.from_angle(angle + 0.36)
	return [c, _point_on(c, dir, half, -0.14, 0.93)]


# The chromosomes (one per gene) resting loosely inside a nucleus of radius r.
# A rosette round the nucleolus, each one pointing outwards, so the seven
# never overlap however long they grow.
static func layout(k: int, r: float, t: float) -> Array:
	var a := TAU * k / 8.0 - PI * 0.5
	var p := Vector2.from_angle(a) * r * 0.56
	p += Vector2(sin(t * 0.7 + k * 1.7), cos(t * 0.6 + k * 2.3)) * r * 0.025
	var ang := a + 0.18 * sin(t * 0.4 + k)
	return [p, ang]


static func chromosome_length(r: float, level: float) -> float:
	return r * (0.26 + 0.055 * level)


# The nucleus: double membrane with pores, a nucleolus, faint chromatin.
static func nucleus(ci: CanvasItem, c: Vector2, r: float, t: float, alpha := 1.0, holo := false) -> void:
	if holo:
		_holo_nucleus(ci, c, r, t, alpha)
		return
	ci.draw_circle(c, r, Color(NUCLEUS_FILL, 0.62 * alpha))
	ci.draw_circle(c, r * 0.82, Color(1, 1, 1, 0.16 * alpha))
	# The nucleolus fills the gap the chromosomes leave in the middle.
	ci.draw_circle(c, r * 0.14, Color(NUCLEUS_LINE, 0.16 * alpha))
	ci.draw_arc(c, r * 0.14, 0.0, TAU, 24, Color(NUCLEUS_LINE, 0.3 * alpha), 1.0, true)
	var wob := 0.012 * sin(t * 1.3)
	var w := maxf(1.0, r * 0.02)
	ci.draw_arc(c, r * (1.0 + wob), 0.0, TAU, 72, Color(NUCLEUS_LINE, 0.8 * alpha), w * 1.2, true)
	ci.draw_arc(c, r * (0.95 + wob), 0.0, TAU, 72, Color(NUCLEUS_LINE, 0.4 * alpha), w * 0.8, true)
	# Nuclear pores: little bright gaps through both membranes.
	var pores := 16
	for k in pores:
		var a := TAU * (k + 0.3 * sin(k * 3.1)) / pores + t * 0.03
		var p := c + Vector2.from_angle(a) * r * (0.975 + wob)
		ci.draw_circle(p, w * 1.9, Color(1, 1, 1, 0.9 * alpha))
		ci.draw_arc(p, w * 1.9, 0.0, TAU, 12, Color(NUCLEUS_LINE, 0.55 * alpha), 0.8, true)


# The nucleus as a hologram: a faint cyan disc, two glowing membrane lines,
# pores as small rings, a dashed nucleolus.
static func _holo_nucleus(ci: CanvasItem, c: Vector2, r: float, t: float, alpha: float) -> void:
	var ink := Color(0.03, 0.5, 0.62)
	var glo := Color(0.1, 0.78, 0.9)
	ci.draw_circle(c, r, Color(glo, 0.08 * alpha))
	var w := maxf(1.0, r * 0.012)
	ci.draw_arc(c, r, 0.0, TAU, 96, Color(glo, 0.22 * alpha), w * 5.0, true)
	ci.draw_arc(c, r, 0.0, TAU, 96, Color(ink, 0.9 * alpha), w * 1.4, true)
	ci.draw_arc(c, r * 0.94, 0.0, TAU, 96, Color(ink, 0.45 * alpha), w, true)
	var pores := 18
	for k in pores:
		var a := TAU * (k + 0.3 * sin(k * 3.1)) / pores + t * 0.03
		ci.draw_arc(c + Vector2.from_angle(a) * r * 0.97, w * 2.4, 0.0, TAU, 12, Color(ink, 0.8 * alpha), w, true)
	for k in 24:
		var a0 := TAU * k / 24.0
		ci.draw_arc(c, r * 0.14, a0, a0 + TAU / 48.0, 3, Color(ink, 0.5 * alpha), w, true)


# Which base (0 A, 1 T, 2 G, 3 C) sits on strand one at pair j of gene g;
# each level of a gene has its own sequence (v = level × 2). An integer hash
# so the genome stage shader (shaders/genome_stage.gdshader) agrees exactly.
static func base_of(g: int, j: int, v := 0) -> int:
	var h := ((g * 73856093) ^ (j * 19349663) ^ (v * 83492791)) & 0xFFFFFFFF
	h = ((h ^ (h >> 16)) * 0x45d9f3b) & 0xFFFFFFFF
	h ^= h >> 16
	return h & 3
