extends Control
# Effects for the main menu (seventh round: "点击按钮的无缝以及华丽酷炫特效"),
# over everything in the interface layer, drawn only while something plays.
#   lock(rect, at)  the chosen item locks on: a beam sweeps across it, two
#                   impact rings and a light streak burst from the click
#                   (bright enough to bloom), holographic shards fly out
#   dissolve(x)     while the menu dissolves along a scan front (x, screen
#                   fraction), shards and code glyphs peel off the front
#   dive(...)       the camera's plunge into the dish read like an
#                   instrument: objective and magnification rolling, a focus
#                   scale hunting, brackets snapping to FOCUS LOCK
#   fade_out()      a soft white-out before quitting
#   pins            while 战役 is hovered in the menu: the first chapter's
#                   levels pinned on the ice water, drawn out one by one
#   proj_*          设置 (eighth round): a beam shoots from the item to the
#                   panel's place, stands up into a scanner bar and sweeps
#                   the panel into being (main_menu drives proj_k)
# The burst is the only loud moment; everything after it speaks the
# instrument language (hairlines, scales, readouts).

var host: Node2D
var rings: Array[Dictionary] = [] # {p, age}
var streaks: Array[Dictionary] = [] # {y, x, age}
var beams: Array[Dictionary] = [] # {rect, age}
var shards: Array[Dictionary] = [] # {p, v, rot, spin, size, age, life, glyph}
var front := -1.0 # dissolve front (screen fraction), -1 = none
var dive_t := -1.0
var dive_len := 2.2
var dive_z := Vector2(0.5, 1.05) # from, to
var white := 0.0
var pins := 0.0 # 0..1, the campaign preview's pins
const PIN_SPOTS := [Vector2(-170, -120), Vector2(90, 40), Vector2(-60, 210)] # from the ice zone's centre
const PIN_IDS := ["1-1", "1-2", "1-3"]
const BRIGHT := Color(1.6, 2.6, 2.9) # over 1: the bloom picks it up
var proj_k := -1.0 # 0..BEAM the beam flies, BEAM..1 the bar sweeps; -1 off
var proj_a := 0.0
var proj_from := Vector2.ZERO
var proj_rect := Rect2()
const BEAM := 0.28


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)


func _go() -> void:
	set_process(true)


func lock(rect: Rect2, at: Vector2) -> void:
	rings.append({p = at, age = 0.0})
	streaks.append({y = at.y, x = at.x, age = 0.0})
	beams.append({rect = rect, age = 0.0})
	for i in 46:
		var ang := randf() * TAU
		var sp := randf_range(160.0, 760.0)
		var from := Vector2(randf_range(rect.position.x, rect.end.x), randf_range(rect.position.y, rect.end.y))
		shards.append({p = from, v = Vector2.from_angle(ang) * sp + Vector2(220.0, 0.0), rot = randf() * TAU,
			spin = randf_range(-9.0, 9.0), size = randf_range(2.0, 7.0), age = 0.0, life = randf_range(0.5, 1.0),
			glyph = Holo.GLYPHS[randi() % Holo.GLYPHS.length()] if randf() < 0.35 else ""})
	Audio.sfx("ui_confirm", -4.0)
	Audio.sfx("holo_banner", -10.0, 1.2)
	_go()


func dissolve_at(x: float) -> void:
	front = x
	_go()


func dive(z0: float, z1: float, seconds: float) -> void:
	dive_t = 0.0
	dive_len = seconds
	dive_z = Vector2(z0, z1)
	_go()


func fade_out(seconds: float) -> void:
	var t := create_tween()
	t.tween_property(self, "white", 1.0, seconds).set_trans(Tween.TRANS_SINE)
	_go()


func _process(delta: float) -> void:
	var want_pins: bool = host != null and host.in_menu and host.menu_preview == 0 and host.menu.shown
	pins = move_toward(pins, 1.0 if want_pins else 0.0, delta / (0.9 if want_pins else 0.25))
	for r in rings:
		r.age += delta
	rings = rings.filter(func(r: Dictionary) -> bool: return r.age < 0.75)
	for s in streaks:
		s.age += delta
	streaks = streaks.filter(func(s: Dictionary) -> bool: return s.age < 0.5)
	for b in beams:
		b.age += delta
	beams = beams.filter(func(b: Dictionary) -> bool: return b.age < 0.4)
	# Shards peel off the dissolve front.
	if front > -0.5 and front < 1.1:
		var view := size
		for i in 3:
			var y := randf() * view.y
			shards.append({p = Vector2(front * view.x, y), v = Vector2(randf_range(60.0, 260.0), randf_range(-90.0, 30.0)),
				rot = randf() * TAU, spin = randf_range(-5.0, 5.0), size = randf_range(1.5, 4.5), age = 0.0,
				life = randf_range(0.4, 0.8), glyph = Holo.GLYPHS[randi() % Holo.GLYPHS.length()] if randf() < 0.5 else ""})
	for s in shards:
		s.age += delta
		s.v *= exp(-delta * 2.4)
		s.p += s.v * delta
		s.rot += s.spin * delta
	shards = shards.filter(func(s: Dictionary) -> bool: return s.age < s.life)
	if dive_t >= 0.0:
		dive_t += delta
		if dive_t > dive_len + 0.9:
			dive_t = -1.0
	# Glyphs peel off the projector's bar while it sweeps.
	if proj_k > BEAM and proj_k < 1.0 and proj_a > 0.5:
		var x := proj_x()
		for i in 2:
			shards.append({p = Vector2(x, randf_range(proj_rect.position.y, proj_rect.end.y)), v = Vector2(randf_range(40.0, 180.0), randf_range(-60.0, 60.0)),
				rot = randf() * TAU, spin = randf_range(-5.0, 5.0), size = randf_range(1.5, 3.5), age = 0.0,
				life = randf_range(0.3, 0.6), glyph = Holo.GLYPHS[randi() % Holo.GLYPHS.length()] if randf() < 0.6 else ""})
	queue_redraw()
	if rings.is_empty() and streaks.is_empty() and beams.is_empty() and shards.is_empty() and dive_t < 0.0 \
			and front < -0.5 and white <= 0.0 and pins <= 0.0 and not want_pins and proj_a <= 0.0:
		set_process(false)


# The menu wakes this when a preview starts.
func wake() -> void:
	_go()


# The projector's bar (screen x) at proj_k.
func proj_x() -> float:
	var k := clampf((proj_k - BEAM) / (1.0 - BEAM), 0.0, 1.0)
	return lerpf(proj_rect.position.x, proj_rect.end.x, k)


func project(from: Vector2, rect: Rect2) -> void:
	proj_from = from
	proj_rect = rect
	proj_a = 1.0
	_go()


static func _ease(t: float) -> float:
	return 1.0 - pow(1.0 - clampf(t, 0.0, 1.0), 3.0)


func _draw() -> void:
	for b in beams:
		_draw_beam(b)
	for s in streaks:
		_draw_streak(s)
	for r in rings:
		_draw_ring(r)
	_draw_shards()
	if dive_t >= 0.0:
		_draw_dive()
	if pins > 0.0:
		_draw_pins()
	if proj_a > 0.0 and proj_k >= 0.0:
		_draw_projector()
	if white > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.98, 0.99, 1.0, white))


func _draw_pins() -> void:
	var xf := get_viewport().get_canvas_transform()
	var centre: Vector2 = Ecology.EUROPA_SAMPLE.zones[1].center
	var f1 := Ui.sans(700)
	var f2 := Ui.mono("Medium")
	var t := Time.get_ticks_msec() / 1000.0
	var prev := Vector2.INF
	for i in PIN_SPOTS.size():
		var k := clampf(pins * 1.6 - i * 0.3, 0.0, 1.0)
		if k <= 0.0:
			continue
		var e := _ease(k)
		var p: Vector2 = xf * (centre + PIN_SPOTS[i])
		if prev.is_finite():
			# The route between levels, drawn out.
			draw_line(prev, prev.lerp(p, e), Color(Ui.ACCENT, 0.6 * e), 1.2, true)
		prev = p
		var r := 9.0 + 2.0 * sin(t * 3.0 + i)
		draw_arc(p, r * e, 0.0, TAU, 32, Color(1, 1, 1, 0.7 * e), 4.0, true)
		draw_arc(p, r * e, 0.0, TAU, 32, Color(Ui.ACCENT, e), 1.6, true)
		draw_circle(p, 3.0 * e, Color(Ui.ACCENT, e))
		var top := p + Vector2(0, -24.0 - 14.0 * e)
		draw_line(p + Vector2(0, -r), top, Color(Ui.ACCENT, 0.7 * e), 1.0, true)
		var l: Dictionary = Levels.by_id(PIN_IDS[i])
		var name: String = "%s  %s" % [PIN_IDS[i], l.get("name", "")]
		var en: String = l.get("en", "")
		var w := f1.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		draw_string_outline(f1, top + Vector2(-w * 0.5, -6), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 6, Color(1, 1, 1, 0.8 * e))
		draw_string(f1, top + Vector2(-w * 0.5, -6), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(Ui.INK, e))
		var w2 := f2.get_string_size(en, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		draw_string_outline(f2, top + Vector2(-w2 * 0.5, 8), en, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, 4, Color(1, 1, 1, 0.7 * e))
		draw_string(f2, top + Vector2(-w2 * 0.5, 8), en, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(Ui.INK_SOFT, e))


# 设置's projector: the beam from the item to the panel's left edge, then a
# bar standing the panel's height and sweeping it in.
func _draw_projector() -> void:
	var a := proj_a
	var r := proj_rect
	var dock := Vector2(r.position.x, proj_from.y)
	var bk := _ease(proj_k / BEAM)
	var tip := proj_from.lerp(dock, bk)
	for i in 4:
		var h := 1.0 + i * 3.0
		draw_line(proj_from, tip, Color(0.55, 0.93, 1.0, 0.07 * a), h, true)
	draw_line(proj_from, tip, Color(BRIGHT, 0.9 * a), 1.4, true)
	draw_circle(proj_from, 3.0, Color(BRIGHT, a))
	if proj_k < BEAM:
		draw_circle(tip, 4.0, Color(BRIGHT, a))
		return
	# The bar: grows from the beam's point to the panel's height, then rides
	# the sweep with a soft wake behind it.
	var gk := _ease((proj_k - BEAM) / 0.12)
	var y0 := lerpf(dock.y, r.position.y - 6.0, gk)
	var y1 := lerpf(dock.y, r.end.y + 6.0, gk)
	var x := proj_x()
	for i in 6:
		var w := 3.0 + i * 9.0
		draw_rect(Rect2(x - w, y0, w, y1 - y0), Color(0.6, 0.94, 1.0, 0.03 * a))
	draw_rect(Rect2(x - 1.0, y0, 2.0, y1 - y0), Color(BRIGHT, a))
	for yy in [y0, y1]:
		draw_line(Vector2(x - 10, yy), Vector2(x + 10, yy), Color(BRIGHT, a), 1.4, true)
	var mono := Ui.mono("Medium")
	draw_string(mono, Vector2(x + 8, y0 - 6), "PROJ %03d%%" % int(clampf((x - r.position.x) / r.size.x, 0.0, 1.0) * 100.0),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(Ui.ACCENT, a))


# A bright bar sweeping across the chosen item.
func _draw_beam(b: Dictionary) -> void:
	var r: Rect2 = b.rect
	var k := _ease(b.age / 0.3)
	var x := r.position.x + r.size.x * k
	var a := 1.0 - clampf((b.age - 0.25) / 0.15, 0.0, 1.0)
	for i in 8:
		var w := 3.0 + i * 7.0
		draw_rect(Rect2(x - w, r.position.y + 4, w, r.size.y - 8), Color(0.55, 0.95, 1.0, 0.05 * a))
	draw_rect(Rect2(x - 2.0, r.position.y + 2, 2.5, r.size.y - 4), Color(BRIGHT, a))


# An anamorphic light streak across the screen at the click's height.
func _draw_streak(s: Dictionary) -> void:
	var k: float = s.age / 0.5
	var a := (1.0 - k) * (1.0 - k)
	var half := size.x * (0.2 + 0.8 * _ease(k * 1.6))
	var cx: float = s.x
	var y: float = s.y
	for i in 5:
		var h := 1.0 + i * 3.0
		draw_rect(Rect2(cx - half, y - h * 0.5, half * 2.0, h), Color(0.5, 0.92, 1.0, 0.09 * a))
	draw_rect(Rect2(cx - half, y - 0.75, half * 2.0, 1.5), Color(BRIGHT, a * 0.9))


func _draw_ring(r: Dictionary) -> void:
	var t: float = r.age
	for j in 2:
		var tt := t - j * 0.09
		if tt <= 0.0:
			continue
		var k := _ease(tt / 0.6)
		var rad := 12.0 + (240.0 - j * 90.0) * k
		var a := (1.0 - clampf(tt / 0.6, 0.0, 1.0))
		draw_arc(r.p, rad, 0.0, TAU, 96, Color(0.5, 0.92, 1.0, 0.25 * a), 9.0 * a + 1.0, true)
		draw_arc(r.p, rad, 0.0, TAU, 96, Color(BRIGHT, a), 1.6, true)
	# Four ticks pointing in at the click, snapping shut.
	var kk := _ease(t / 0.25)
	var ta := 1.0 - clampf(t / 0.6, 0.0, 1.0)
	for i in 4:
		var d := Vector2.from_angle(i * PI * 0.5 + PI * 0.25)
		var r0 := lerpf(60.0, 14.0, kk)
		draw_line(r.p + d * r0, r.p + d * (r0 + 10.0), Color(Ui.ACCENT, ta), 1.5, true)


func _draw_shards() -> void:
	var f := Ui.mono("Medium")
	for s in shards:
		var k: float = s.age / s.life
		var a := (1.0 - k) * minf(1.0, s.age * 12.0)
		var p: Vector2 = s.p
		if s.glyph != "":
			draw_string(f, p, s.glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, int(8.0 + s.size * 1.6), Color(Ui.ACCENT, 0.85 * a))
			continue
		var sz: float = s.size
		var rot: float = s.rot
		var pts := PackedVector2Array()
		for i in 3:
			pts.append(p + Vector2.from_angle(rot + i * TAU / 3.0) * sz * (1.0 if i != 1 else 0.55))
		draw_colored_polygon(pts, Color(0.75, 0.97, 1.0, 0.75 * a))
		pts.append(pts[0])
		draw_polyline(pts, Color(Ui.ACCENT, a), 1.0, true)


# The plunge, read like an instrument at the bottom centre: objective and
# magnification rolling, a focus scale whose marker hunts and settles, and
# brackets that close on the middle with FOCUS LOCK.
func _draw_dive() -> void:
	var t := dive_t
	var k := clampf(t / dive_len, 0.0, 1.0)
	var e := k * k * (3.0 - 2.0 * k)
	var a := minf(1.0, t / 0.25) * (1.0 - clampf((t - dive_len - 0.5) / 0.4, 0.0, 1.0))
	var c := Vector2(size.x * 0.5, size.y - 150.0)
	var mono := Ui.mono("Medium")
	var z := exp(lerpf(log(dive_z.x), log(dive_z.y), e))
	var obj := "4×" if z < 0.75 else ("10×" if z < 1.4 else "40×")
	var line1 := "OBJ %s   ·   ×%.2f" % [obj, z]
	var w1 := mono.get_string_size(line1, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	draw_string_outline(mono, c + Vector2(-w1 * 0.5, 0), line1, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 5, Color(1, 1, 1, 0.7 * a))
	draw_string(mono, c + Vector2(-w1 * 0.5, 0), line1, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(Ui.INK, a))
	# Focus scale: ticks, and a marker that swings past and settles at 0.
	var sw := 360.0
	var y := c.y + 18.0
	draw_line(Vector2(c.x - sw * 0.5, y), Vector2(c.x + sw * 0.5, y), Color(Ui.INK_SOFT, 0.6 * a), 1.0, true)
	for i in 25:
		var x := c.x - sw * 0.5 + sw * i / 24.0
		var long := i % 6 == 0
		draw_line(Vector2(x, y), Vector2(x, y + (8.0 if long else 4.0)), Color(Ui.INK_SOFT, (0.7 if long else 0.4) * a), 1.0, true)
	var hunt := sin(k * 11.0) * exp(-k * 3.2) * (1.0 - k)
	var mx := c.x + hunt * sw * 0.45
	var locked := t >= dive_len
	var mcol := Ui.GOOD if locked else Ui.ACCENT
	draw_colored_polygon(PackedVector2Array([Vector2(mx, y - 2), Vector2(mx - 5, y - 10), Vector2(mx + 5, y - 10)]), Color(mcol, a))
	var label := "FOCUS LOCK" if locked else "FOCUSING"
	var f2 := Ui.mono("SemiBold")
	var w2 := f2.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	draw_string(f2, Vector2(c.x - w2 * 0.5, y + 26.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(mcol.darkened(0.2), a))
	# Brackets closing on the middle; they snap and flash on lock.
	var mid := size * 0.5
	var lk := clampf((t - dive_len) / 0.25, 0.0, 1.0)
	var gap := lerpf(260.0, 120.0, e) - 20.0 * _ease(lk)
	var ba := a * (0.45 + 0.55 * (1.0 - lk) * float(locked))
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var p := mid + Vector2(sx * gap * 1.6, sy * gap)
			draw_line(p, p - Vector2(sx * 24.0, 0), Color(Ui.ACCENT, ba), 1.4, true)
			draw_line(p, p - Vector2(0, sy * 24.0), Color(Ui.ACCENT, ba), 1.4, true)
