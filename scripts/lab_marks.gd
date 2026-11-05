extends Node2D
# Text that belongs to the lab (sixth round: "整个背景更像实验室"), in world
# space so it moves and scales with the dish like the real thing; drawn once
# (fonts rasterised large and scaled down, so they stay crisp close up):
#   stage   numbers along the engraved scales (dish.gdshader draws the
#           ticks), the label on the stage, makings near the corners
#   dish    the projected grid's ring radii and axis values, faint; they
#           fade out when zoomed far out, where they would only be dots
# Under the organisms (added right after the dish).

const H := 1720.0 # half the stage, as in dish.gdshader
const RASTER := 4.0 # glyphs drawn this many times larger, scaled down

var host: Node2D
var dish_text: Node2D


func _ready() -> void:
	var stage := Node2D.new()
	stage.draw.connect(_draw_stage.bind(stage))
	add_child(stage)
	dish_text = Node2D.new()
	dish_text.draw.connect(_draw_dish.bind(dish_text))
	add_child(dish_text)


func _process(_delta: float) -> void:
	if host == null:
		return
	var z: float = host.cam.zoom.x
	dish_text.modulate.a = smoothstep(0.55, 0.95, z) * (1.0 - (host.analysis.amount if host.analysis else 0.0))


# Text at `p` (world), `size` world units tall, rotated by `rot`.
func _text(n: Node2D, p: Vector2, s: String, size: float, col: Color, font: Font, align := HORIZONTAL_ALIGNMENT_CENTER, rot := 0.0) -> void:
	var k := 1.0 / RASTER
	n.draw_set_transform(p, rot, Vector2(k, k))
	var fs := int(size * RASTER)
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var x := -w * 0.5 if align == HORIZONTAL_ALIGNMENT_CENTER else (0.0 if align == HORIZONTAL_ALIGNMENT_LEFT else -w)
	n.draw_string(font, Vector2(x, fs * 0.35), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	n.draw_set_transform(Vector2.ZERO)


func _draw_stage(n: Node2D) -> void:
	var c: Vector2 = host.DISH_CENTER
	var mono := Ui.mono("Medium")
	var engraved := Color(0.36, 0.44, 0.51, 0.75)
	# Scale numbers every 250 along each edge, inside the long ticks.
	var inset := H - 70.0 - 52.0 - 26.0
	var v := -1250.0
	while v <= 1250.0:
		var t := "%d" % int(v)
		_text(n, c + Vector2(v, inset), t, 22.0, engraved, mono)
		_text(n, c + Vector2(v, -inset), t, 22.0, engraved, mono)
		_text(n, c + Vector2(inset, v), t, 22.0, engraved, mono, HORIZONTAL_ALIGNMENT_CENTER, -PI * 0.5)
		_text(n, c + Vector2(-inset, v), t, 22.0, engraved, mono, HORIZONTAL_ALIGNMENT_CENTER, PI * 0.5)
		v += 250.0
	# Makings by the corners.
	_text(n, c + Vector2(-H + 210.0, -H + 120.0), "STAGE  X–Y  ·  0.5 µm STEP", 24.0, engraved, mono, HORIZONTAL_ALIGNMENT_LEFT)
	_text(n, c + Vector2(H - 210.0, -H + 120.0), "GP-LAB  M-07  ·  NO. 0412", 24.0, engraved, mono, HORIZONTAL_ALIGNMENT_RIGHT)
	_text(n, c + Vector2(H - 210.0, H - 120.0), "OBJ 10× / 0.30  ·  WD 5.2 mm", 24.0, engraved, mono, HORIZONTAL_ALIGNMENT_RIGHT)
	# The label on the stage (dish.gdshader draws the card and its stripe).
	var lc := c + Vector2(-1180.0, 1330.0)
	var ink := Ui.INK
	_text(n, lc + Vector2(-240.0, -48.0), "SAMPLE  EUR-01", 34.0, ink, Ui.mono("SemiBold"), HORIZONTAL_ALIGNMENT_LEFT)
	_text(n, lc + Vector2(-240.0, -2.0), "木卫二冰下海洋 · 深层水样", 30.0, Ui.INK_SOFT, Ui.sans(600), HORIZONTAL_ALIGNMENT_LEFT)
	_text(n, lc + Vector2(-240.0, 44.0), "BSL-2   Ø 2120 µm   4 °C", 24.0, Ui.INK_SOFT, mono, HORIZONTAL_ALIGNMENT_LEFT)
	# A small barcode at the label's right end.
	var bx := lc.x + 170.0
	var seed := 7
	for i in 26:
		seed = (seed * 1103515245 + 12345) & 0x7fffffff
		var w := 2.0 + float(seed % 3) * 2.0
		n.draw_rect(Rect2(bx, lc.y - 60.0, w, 96.0), Color(Ui.INK, 0.85))
		bx += w + 2.0 + float((seed >> 4) % 3) * 1.5
		if bx > lc.x + 290.0:
			break


func _draw_dish(n: Node2D) -> void:
	var c: Vector2 = host.DISH_CENTER
	var holo := Color(0.05, 0.42, 0.5, 0.42)
	var mono := Ui.mono("Medium")
	# Ring radii along the spoke at -60° (up and to the right).
	var dir := Vector2.from_angle(-PI / 3.0)
	for r in [200, 400, 600, 800]:
		_text(n, c + dir * (r + 4.0) + dir.orthogonal() * 12.0, "R %d" % r, 11.0, holo, mono, HORIZONTAL_ALIGNMENT_LEFT, -PI / 3.0 + PI * 0.5)
	# Axis values along the horizontal and vertical lines through the centre.
	for v in [-750, -500, -250, 250, 500, 750]:
		_text(n, c + Vector2(v + 6.0, -8.0), "%+d" % v, 10.0, holo, mono, HORIZONTAL_ALIGNMENT_LEFT)
		_text(n, c + Vector2(6.0, v - 8.0), "%+d" % -v, 10.0, holo, mono, HORIZONTAL_ALIGNMENT_LEFT)
	_text(n, c + Vector2(8.0, -8.0), "0,0", 10.0, holo, mono, HORIZONTAL_ALIGNMENT_LEFT)
	# The degree scale's numbers, every 30°, inside the tick band.
	for k in 12:
		var ang := k * PI / 6.0
		var d := Vector2.from_angle(ang)
		var rr: float = host.DISH_RADIUS - 126.0 - 34.0
		# Upright on the lower half too (read from outside the ring there).
		var rot := ang + PI * 0.5 if sin(ang) <= 0.01 else ang - PI * 0.5
		_text(n, c + d * rr, "%03d°" % (k * 30), 12.0, holo, mono, HORIZONTAL_ALIGNMENT_CENTER, rot)
