class_name Visor
extends Control
# The visor over the dish (holographic interface, fourth round): the frame
# the panels live in.
#   corners  four registration marks at the screen's corners, always there
#   boot()   the visor calibrating as the HUD comes up: the corner marks fly
#            in, a scan line sweeps the screen top to bottom with a glow,
#            a centre crosshair flashes, a status line types itself out;
#            panels materialise as the sweep passes them (EcoHud.reveal)
#   banner() a film-title line for something important: rules draw out from
#            the centre, the title decodes, and a leader line runs from the
#            title down to the place in the dish, ending in a turning
#            reticle; it holds, then dissolves

const BOOT := 0.95

var host: Node2D
var boot_t := -1.0 # seconds into the boot, -1 = not booting
var corner_in := 1.0
var banners: Array[Dictionary] = []
var status := "GENESIS VISOR  ·  SYNC"
# A leader line from a hovered piece of the HUD to its place in the dish
# (EcoHud: event rows). {from (screen), world, color}; it draws itself out.
var link := {}
var link_k := 0.0
var _link_on := false


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func boot() -> void:
	boot_t = 0.0
	corner_in = 0.0
	Audio.sfx("holo_boot", -10.0)


# Where the sweep is, 0 (top) .. 1 (bottom), as a function of boot time.
static func sweep_at(t: float) -> float:
	return clampf(t / BOOT, 0.0, 1.0)


func banner(title: String, sub: String, color: Color, world := Vector2.INF) -> void:
	banners = banners.filter(func(b: Dictionary) -> bool: return b.age < 0.4) # replace older ones
	banners.append({title = title, sub = sub, color = color, world = world, age = 0.0, life = 3.6})
	Audio.sfx("holo_banner", -9.0)


func set_link(d: Dictionary) -> void:
	if d.is_empty():
		_link_on = false
		return
	if not _link_on or (link.get("world", Vector2.INF) as Vector2) != (d.world as Vector2):
		link_k = 0.0 if not _link_on or link.is_empty() else link_k * 0.3
	link = d
	_link_on = true


func _process(delta: float) -> void:
	if boot_t >= 0.0:
		boot_t += delta
		corner_in = clampf(boot_t / 0.45, 0.0, 1.0)
		if boot_t > BOOT + 0.8:
			boot_t = -1.0
	if _link_on:
		link_k = minf(link_k + delta / 0.32, 1.0)
	else:
		link_k = maxf(link_k - delta / 0.15, 0.0)
	for b in banners:
		b.age += delta
	banners = banners.filter(func(b: Dictionary) -> bool: return b.age < b.life)
	queue_redraw()


func _ease(t: float) -> float:
	return 1.0 - pow(1.0 - clampf(t, 0.0, 1.0), 4.0)


func _draw() -> void:
	var s := size
	_draw_corners(s)
	if boot_t >= 0.0:
		_draw_boot(s)
	for b in banners:
		_draw_banner(b, s)
	if link_k > 0.0 and not link.is_empty():
		_draw_link(s)


func _draw_corners(s: Vector2) -> void:
	var e := _ease(corner_in)
	var inset := lerpf(-40.0, 14.0, e)
	var L := 22.0
	var col := Color(Ui.ACCENT, 0.55 * e)
	for cx in [0, 1]:
		for cy in [0, 1]:
			var c := Vector2(inset if cx == 0 else s.x - inset, inset if cy == 0 else s.y - inset)
			var sx := 1.0 if cx == 0 else -1.0
			var sy := 1.0 if cy == 0 else -1.0
			draw_line(c, c + Vector2(L * sx, 0), col, 1.2)
			draw_line(c, c + Vector2(0, L * sy), col, 1.2)
			draw_rect(Rect2(c + Vector2(4 * sx, 4 * sy) - Vector2(1.5, 1.5), Vector2(3, 3)), col)


func _draw_boot(s: Vector2) -> void:
	var t := boot_t
	var k := sweep_at(t)
	var fade := 1.0 - clampf((t - BOOT) / 0.6, 0.0, 1.0)
	if k < 1.0:
		var y := s.y * k
		# The sweep: a bright line with a tall soft glow above it.
		for i in 12:
			var gy := y - i * 6.0
			draw_line(Vector2(0, gy), Vector2(s.x, gy), Color(Ui.ACCENT, 0.05 * (1.0 - i / 12.0)), 6.0)
		draw_line(Vector2(0, y), Vector2(s.x, y), Color(0.75, 0.97, 1.0, 0.9), 1.5)
		# Tick marks riding the line.
		for i in 40:
			var x := s.x * (i + 0.5) / 40.0
			draw_line(Vector2(x, y - 4.0), Vector2(x, y + 4.0), Color(Ui.ACCENT, 0.5), 1.0)
	# Centre crosshair flash.
	var cf := clampf(1.0 - absf(t - 0.35) / 0.3, 0.0, 1.0) * fade
	if cf > 0.0:
		var c := s * 0.5
		var r := 30.0 + 40.0 * _ease(t / 0.6)
		draw_arc(c, r, 0.0, TAU, 64, Color(Ui.ACCENT, 0.5 * cf), 1.2, true)
		for i in 4:
			var d := Vector2.from_angle(i * PI * 0.5)
			draw_line(c + d * (r - 8.0), c + d * (r + 10.0), Color(Ui.ACCENT, 0.8 * cf), 1.5)
	# Status line, bottom-left, typing out and counting up.
	var f := Ui.mono("Medium")
	var pct := int(100.0 * clampf(t / BOOT, 0.0, 1.0))
	var txt := "%s %3d%%" % [status, pct]
	var shown := txt.substr(0, int(clampf(t / 0.4, 0.0, 1.0) * txt.length()))
	draw_string_outline(f, Vector2(40, s.y - 40), shown, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 4, Color(1, 1, 1, 0.6 * fade))
	draw_string(f, Vector2(40, s.y - 40), shown, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(Ui.ACCENT.darkened(0.3), fade))


func _draw_banner(b: Dictionary, s: Vector2) -> void:
	var t: float = b.age
	var out := clampf((t - (b.life - 0.5)) / 0.5, 0.0, 1.0)
	var a := 1.0 - out
	var col: Color = b.color
	var f1 := Ui.sans(700)
	var f2 := Ui.mono("Medium")
	var cy := 150.0
	var cx := s.x * 0.5
	# Rules drawing out from the centre.
	var w := 260.0 * _ease(t / 0.4)
	draw_line(Vector2(cx - w, cy - 26), Vector2(cx + w, cy - 26), Color(col, 0.7 * a), 1.0)
	draw_line(Vector2(cx - w * 0.6, cy + 22), Vector2(cx + w * 0.6, cy + 22), Color(col, 0.4 * a), 1.0)
	for sx in [-1.0, 1.0]:
		var e := Vector2(cx + w * sx, cy - 26)
		draw_colored_polygon([e + Vector2(0, -3), e + Vector2(3, 0), e + Vector2(0, 3), e + Vector2(-3, 0)], Color(col, a))
	# The title decodes (characters appear left to right with a block cursor).
	var title: String = b.title
	var k := clampf((t - 0.15) / 0.45, 0.0, 1.0)
	var n := int(k * title.length())
	var shown := title.substr(0, n)
	var fs := 30
	var full := f1.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var x0 := cx - full * 0.5
	var glitch := maxf(0.0, 1.0 - t / 0.5) * 3.0
	if glitch > 0.1:
		draw_string(f1, Vector2(x0 - glitch, cy + 10), shown, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 0.25, 0.45, 0.5 * a))
		draw_string(f1, Vector2(x0 + glitch, cy + 10), shown, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.1, 0.85, 1.0, 0.5 * a))
	draw_string_outline(f1, Vector2(x0, cy + 10), shown, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 8, Color(0.97, 0.99, 1.0, 0.7 * a))
	draw_string(f1, Vector2(x0, cy + 10), shown, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(Ui.INK, a))
	if k < 1.0:
		var cw := f1.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_rect(Rect2(x0 + cw + 2.0, cy - 14, 12, 28), Color(col, 0.8 * a))
	var sub: String = b.sub
	var sk := clampf((t - 0.45) / 0.4, 0.0, 1.0)
	var subw := f2.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	draw_string(f2, Vector2(cx - subw * 0.5, cy + 40), sub.substr(0, int(sk * sub.length())), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(Ui.INK_SOFT, a))
	# Leader line to the place in the dish, ending in a turning reticle.
	var world: Vector2 = b.world
	if world.is_finite() and host:
		var p: Vector2 = get_viewport().get_canvas_transform() * world
		var lk := _ease((t - 0.35) / 0.5)
		if lk > 0.0 and Rect2(Vector2.ZERO, s).grow(-20.0).has_point(p):
			var start := Vector2(cx, cy + 50)
			var elbow := Vector2(p.x, start.y + 30.0)
			var pts := [start, Vector2(start.x, elbow.y), elbow, p]
			# Draw the polyline out to lk of its length.
			var total := 0.0
			for i in 3:
				total += (pts[i + 1] - pts[i]).length()
			var left := total * lk
			for i in 3:
				var seg: float = (pts[i + 1] - pts[i]).length()
				var e: Vector2 = pts[i + 1] if left >= seg else pts[i].lerp(pts[i + 1], left / maxf(seg, 0.001))
				draw_line(pts[i], e, Color(col, 0.75 * a), 1.2, true)
				left -= seg
				if left <= 0.0:
					break
			if lk >= 1.0:
				var rr := 16.0 + 4.0 * sin(t * 6.0)
				var spin := t * 1.5
				for i in 4:
					var a0 := spin + i * PI * 0.5
					draw_arc(p, rr, a0, a0 + 0.9, 10, Color(col, a), 1.6, true)
				draw_circle(p, 2.5, Color(col, a))


func _draw_link(s: Vector2) -> void:
	var col: Color = link.color
	var a := clampf(link_k * 2.0, 0.0, 1.0) if _link_on else link_k
	var from: Vector2 = link.from
	var p: Vector2 = get_viewport().get_canvas_transform() * (link.world as Vector2)
	var inside := Rect2(Vector2.ZERO, s).grow(-30.0).has_point(p)
	if not inside:
		# Off screen: point to the edge, toward it.
		var c := s * 0.5
		var d := p - c
		var t := minf((s.x * 0.5 - 40.0) / maxf(absf(d.x), 1e-3), (s.y * 0.5 - 40.0) / maxf(absf(d.y), 1e-3))
		p = c + d * minf(t, 1.0)
	var elbow := Vector2(from.x + 40.0, from.y)
	var pts := [from, elbow, p]
	var e := _ease(link_k)
	var total := (elbow - from).length() + (p - elbow).length()
	var left := total * e
	for i in 2:
		var seg: float = (pts[i + 1] - pts[i]).length()
		var q: Vector2 = pts[i + 1] if left >= seg else pts[i].lerp(pts[i + 1], left / maxf(seg, 0.001))
		draw_line(pts[i], q, Color(1, 1, 1, 0.6 * a), 3.0, true)
		draw_line(pts[i], q, Color(col.darkened(0.2), 0.9 * a), 1.2, true)
		left -= seg
		if left <= 0.0:
			break
	draw_circle(from, 2.5, Color(col.darkened(0.2), a))
	if e >= 0.98:
		var t := Time.get_ticks_msec() / 1000.0
		# Signal pulses running down the line to the place.
		for j in 2:
			var u := fmod(t * 0.9 + j * 0.5, 1.0)
			var along := total * u
			var q := from.lerp(elbow, along / maxf((elbow - from).length(), 0.001)) if along < (elbow - from).length() 					else elbow.lerp(p, (along - (elbow - from).length()) / maxf((p - elbow).length(), 0.001))
			var fade := sin(u * PI)
			draw_circle(q, 4.0, Color(1, 1, 1, 0.5 * a * fade))
			draw_circle(q, 2.2, Color(col, a * fade))
		var rr := 18.0 + 3.0 * sin(t * 5.0)
		for i in 4:
			var a0 := t * 1.2 + i * PI * 0.5
			draw_arc(p, rr, a0, a0 + 0.9, 10, Color(1, 1, 1, 0.6 * a), 3.4, true)
			draw_arc(p, rr, a0, a0 + 0.9, 10, Color(col.darkened(0.2), a), 1.5, true)
		draw_circle(p, 2.5, Color(col.darkened(0.2), a))
		if not inside:
			var f := Ui.sans(600)
			draw_string_outline(f, p + Vector2(24, 5), "画面外", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, 4, Color(1, 1, 1, 0.7 * a))
			draw_string(f, p + Vector2(24, 5), "画面外", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(Ui.INK, a))
