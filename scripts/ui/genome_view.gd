class_name GenomeView
extends Node2D
# The nucleus and its seven chromosomes in the designer's hologram style,
# retained: each piece is drawn once (GenomeArt) and then only moved, turned,
# scaled and faded, so the genome
# animates every frame without rebuilding any geometry. A chromosome redraws
# only when its length or banding changes. Built at radius BASE_R; scale the
# node to resize the whole nucleus.

const BASE_R := 86.0
const N := 8 # chromosomes, one per gene
# Graphite and steel; the selected gene's chromosome takes the accent.
const GREY := Color(0.42, 0.48, 0.53)

var nucleus: Nucleus
var ganglia: Ganglia
var halos: Array[Halo] = []
var chromos: Array[Chromo] = []


func _init() -> void:
	nucleus = Nucleus.new()
	add_child(nucleus)
	ganglia = Ganglia.new()
	add_child(ganglia)
	for k in N:
		var h := Halo.new(Ui.ACCENT)
		add_child(h)
		halos.append(h)
	for k in N:
		var c := Chromo.new(GREY)
		add_child(c)
		chromos.append(c)


# levels: shown gene levels; glow: highlight per gene; shell: nucleus fade.
func update(levels: Array, glow: Array, t: float, shell := 1.0, sel := -1) -> void:
	nucleus.modulate.a = shell
	nucleus.visible = shell > 0.0
	nucleus.rotation = t * 0.03
	nucleus.scale = Vector2.ONE * (1.0 + 0.012 * sin(t * 1.3))
	ganglia.modulate.a = shell
	ganglia.visible = shell > 0.0
	ganglia.rotation = t * 0.1
	ganglia.set_count(2 + int(round((float(levels[6]) - 1.0) * 1.5)))
	for k in N:
		var lay := GenomeArt.layout(k, BASE_R, t)
		var lv: float = levels[k]
		var len := GenomeArt.chromosome_length(BASE_R, lv)
		var g: float = glow[k]
		var c := chromos[k]
		c.set_color(Ui.ACCENT if k == sel else GREY)
		c.set_shape(len, lv)
		c.position = lay[0]
		c.rotation = lay[1]
		c.scale = Vector2.ONE * (1.0 + 0.14 * g)
		var h := halos[k]
		h.visible = g > 0.01
		h.position = lay[0]
		h.scale = Vector2.ONE * (len * 0.5 * (1.0 + 0.14 * g) * 1.25 / Halo.R)
		h.modulate.a = g


# Centromere and a telomere of chromosome k, in this node's parent space.
func marks(k: int) -> Array:
	var c := chromos[k]
	var local := GenomeArt.chromosome_marks(c.position, c.rotation, c.length, (c.scale.x - 1.0) / 0.14)
	return [transform * local[0], transform * local[1]]


class Nucleus extends Node2D:
	func _draw() -> void:
		GenomeArt.nucleus(self, Vector2.ZERO, BASE_R, 0.0, 1.0, true)


class Ganglia extends Node2D:
	var count := -1

	func set_count(n: int) -> void:
		if n != count:
			count = n
			queue_redraw()

	func _draw() -> void:
		for k in count:
			var a := TAU * k / count
			draw_circle(Vector2.from_angle(a) * BASE_R * 1.16, BASE_R * 0.05, Color(GREY, 0.7))


class Halo extends Node2D:
	const R := 50.0
	var color: Color

	func _init(c: Color) -> void:
		color = c
		visible = false

	func _draw() -> void:
		draw_circle(Vector2.ZERO, R, Color(color, 0.08))
		draw_arc(Vector2.ZERO, R, 0.0, TAU, 48, Color(color, 0.25), 6.0, true)
		draw_arc(Vector2.ZERO, R, 0.0, TAU, 48, Color(color, 0.7), 1.6, true)


class Chromo extends Node2D:
	var color: Color
	var length := 0.0
	var level := 0.0
	var _key := Vector2i(-1, -1)

	func _init(c: Color) -> void:
		color = c

	func set_color(c: Color) -> void:
		if c != color:
			color = c
			queue_redraw()

	func set_shape(len: float, lv: float) -> void:
		length = len
		level = lv
		var key := Vector2i(roundi(len * 4.0), roundi(lv * 2.0))
		if key != _key:
			_key = key
			queue_redraw()

	func _draw() -> void:
		GenomeArt.chromosome(self, Vector2.ZERO, 0.0, length, color, level, 0.0, 1.0, true)
