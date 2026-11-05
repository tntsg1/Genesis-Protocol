class_name DishMarks
extends Node2D
# Marks drawn over the cells for what the simulation's own look does not say
# (2-4 review: "伏刺不够显眼、被吃那一刻没标记、进入警戒头顶没标记"):
#   ambushers: a native hunter lying in wait breathes a thin crimson ring,
#     with its strike radius faintly dashed; while it lunges the ring
#     tightens and brightens.
#   eaten: where one of the player's cells is swallowed, a crimson ring
#     snaps outward under a small thin ×, gone in 1.5 s (and the HUD's
#     objective line flashes).
#   alert: a small cyan caret over each cell in the alert state; it pops in
#     with a ripple when the alert starts.
#   a boss (2-5 review; the species a level's goal names as its boss - an
#     engulfer that is not one, like 3-1's, is just a hunter): a crown -
#     counter-turning dashed rings and a ring of teeth closing in, a wake
#     of where it has been - with its name and energy over it (crimson and
#     blinking when it is close to starving); out of view an arrow at the
#     screen's edge says where it is and how far; while it is near enough to
#     see the player's cells (138 µm) the screen's edges glow red.
#   signals (3-1 review: "信号看不见"): the water's signal A / B shows as a
#     faint tinted haze under the cells (SimCore.get_signal_field, fetched a
#     few times a second); a cell calling out sends rings off itself; one of
#     the player's cells running from a smell - fleeing with no hunter near
#     it - carries a small three-arc mark.
#   shields (3-2: a herding hunter cannot pick one out of a tight group):
#     each tight group of the player's cells - as many as the hunter's herd
#     number, close together - gets a soft cyan outline hugging it,
#     brighter while a hunter is near; a hunter at one flicks dashed aim
#     lines from cell to cell (it cannot choose).
#   engulfers (any species that swallows on touch, not the level's boss): a
#     bold crimson ring with turning notches, all the time.
# Sizes are in screen pixels (divided by the zoom), so the marks read the
# same from afar and close up. Data: SimCore.get_marks (x, y, sp, state,
# action, extent per cell in view) and the eaten events.

const DANGER := Color(0.84, 0.2, 0.38)
const EATEN_T := 1.5
const POP_T := 0.45
const ACT_HUNT := 3
const ACT_BITE := 4
const ACT_REST := 7
const ACT_FLEE := 5
const ACT_SIGNAL := 10
const SIG_A := Color(0.1, 0.68, 0.6) # signal A's haze and rings
const SIG_B := Color(0.5, 0.4, 0.82)
const NOSE_R := 120.0 # a fleeing cell with no hunter this near ran from a smell

var host: Node2D
var marks := PackedFloat32Array()
var eaten: Array = [] # [pos, age]
var pops: Array = [] # [pos, age]
var _was_alert := {} # last frame's alert cells, by 14 µm grid square (to spot new ones)
var _strike := {} # species -> strike radius from its deck (µm), -1 = none
var t := 0.0
var zoom := 1.0
const SEE_R := 138.0 # how far the devourer sees (its vision gene)
var bosses: Array = [] # [position, energy 0..1 (-1 unknown), radius, name]
var _trail: Array = [] # per boss: recent spots (its wake)
var _trail_t := 0.0
var near := 0.0 # the warning's glow, 0..1
var edge: Control # screen space: the arrows and the glow
var fog: ColorRect # the signals' haze, under the cells
var fog_img: Image
var fog_tex: ImageTexture
var _fog_t := 0.0


func _ready() -> void:
	var cl := CanvasLayer.new()
	cl.layer = 4
	add_child(cl)
	edge = Control.new()
	edge.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	edge.draw.connect(_draw_edge)
	cl.add_child(edge)
	# The haze sits just under the cells.
	fog = ColorRect.new()
	fog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fog.visible = false
	var fm := ShaderMaterial.new()
	fm.shader = preload("res://shaders/signal_fog.gdshader")
	fog.material = fm
	host.add_child.call_deferred(fog)
	(func() -> void: host.move_child(fog, host.cells.get_index())).call_deferred()


func tick(delta: float, alpha: float, view: Rect2, events: PackedFloat32Array, live: bool) -> void:
	t += delta
	zoom = host.cam.zoom.x
	var mine := _mine()
	var any_eaten := false
	for k in range(0, events.size(), 6):
		if int(events[k]) == SimCore.EV_EATEN and int(events[k + 3]) in mine:
			any_eaten = true
			var p := Vector2(events[k + 1], events[k + 2])
			# A big engulfer swallows a crowd in one tick: one mark for a
			# clump, and a few dozen on screen at most.
			if view.grow(40.0).has_point(p) and eaten.size() < 24 \
					and not eaten.any(func(e: Array) -> bool: return e[1] < 0.2 and (e[0] as Vector2).distance_squared_to(p) < 400.0):
				eaten.append([p, 0.0])
	if any_eaten and host.hud_root and host.level_runner:
		host.hud_root.flash_objective()
	for e: Array in eaten:
		e[1] += delta
	eaten = eaten.filter(func(e: Array) -> bool: return e[1] < EATEN_T)
	for e: Array in pops:
		e[1] += delta
	pops = pops.filter(func(e: Array) -> bool: return e[1] < POP_T)
	marks = host.sim.get_marks(view.grow(160.0), alpha) if live else PackedFloat32Array()
	# New alerts: an alert cell with no alert cell near it last frame.
	var now_alert := {}
	for b in range(0, marks.size(), 6):
		if int(marks[b + 3]) == Rules.S_ALERT:
			var p := Vector2(marks[b], marks[b + 1])
			var g := Vector2i(p / 14.0)
			now_alert[g] = true
			if pops.size() < 60 and not _near(g):
				pops.append([p, 0.0])
	_was_alert = now_alert
	_find_bosses(delta, mine, live)
	_update_fog(delta, live)
	queue_redraw()
	edge.queue_redraw()


# The signals' concentration as a texture (R = A, G = B), a few times a
# second; hidden while the water carries none.
func _update_fog(delta: float, live: bool) -> void:
	_fog_t -= delta
	if not live:
		fog.visible = false
		return
	if _fog_t > 0.0:
		return
	_fog_t = 0.15
	var gs: Vector2i = host.sim.get_grid_size()
	var a: PackedFloat32Array = host.sim.get_signal_field(0)
	var b: PackedFloat32Array = host.sim.get_signal_field(1)
	var top := 0.0
	for v in a:
		top = maxf(top, v)
	for v in b:
		top = maxf(top, v)
	fog.visible = top > 0.004
	if not fog.visible:
		return
	var data := PackedFloat32Array()
	data.resize(gs.x * gs.y * 2)
	for i in gs.x * gs.y:
		data[i * 2] = a[i]
		data[i * 2 + 1] = b[i]
	var img := Image.create_from_data(gs.x, gs.y, false, Image.FORMAT_RGF, data.to_byte_array())
	if fog_tex == null or fog_img == null or fog_img.get_size() != img.get_size():
		fog_tex = ImageTexture.create_from_image(img)
		(fog.material as ShaderMaterial).set_shader_parameter("sig", fog_tex)
	else:
		fog_tex.update(img)
	fog_img = img
	var cell: float = host.sim.get_cell_size()
	fog.position = Vector2.ZERO
	fog.size = Vector2(gs) * cell
	(fog.material as ShaderMaterial).set_shader_parameter("texel", Vector2(1.0 / gs.x, 1.0 / gs.y))


# The level's boss: the species its goal names (a boss fight's goal).
func _boss_species() -> Array:
	var lr: Variant = host.level_runner
	if lr == null:
		return []
	var g: Dictionary = lr.level.get("goal", {})
	if g.get("kind", "") != "boss":
		return []
	return [int(g.get("boss", 0))]


func _name(sp: int) -> String:
	return host.labels[sp] if sp < host.labels.size() and host.labels[sp] != "" else "Boss"


func _find_bosses(delta: float, mine: Array, live: bool) -> void:
	bosses.clear()
	var want := 0.0
	if live:
		for sp: int in _boss_species():
			var ps: PackedVector2Array = host.sim.get_positions(sp)
			for k in mini(ps.size(), 6):
				var p := ps[k]
				var id: int = host.sim.find_agent(p, 4.0)
				var a: Dictionary = host.sim.get_agent(id) if id >= 0 else {}
				# In view, the marks have it where it is drawn (between ticks).
				for b in range(0, marks.size(), 6):
					if int(marks[b + 2]) == sp and Vector2(marks[b], marks[b + 1]).distance_squared_to(p) < 900.0:
						p = Vector2(marks[b], marks[b + 1])
						break
				bosses.append([p, float(a.get("energy_frac", -1.0)), float(a.get("radius", 22.0)), _name(sp)])
		# Near: any of the player's cells within its sight.
		for bz: Array in bosses:
			var r: float = SEE_R + float(bz[2])
			for sp: int in mine:
				for q: Vector2 in host.sim.get_positions(sp):
					if q.distance_squared_to(bz[0]) < r * r:
						want = 1.0
						break
				if want > 0.0:
					break
	near = move_toward(near, want, delta * (3.0 if want > 0.0 else 1.2))
	# The wake: a spot every 0.12 s, the last 30.
	_trail.resize(bosses.size())
	_trail_t += delta
	var drop := _trail_t >= 0.12
	if drop:
		_trail_t = 0.0
	for k in bosses.size():
		if _trail[k] == null:
			_trail[k] = PackedVector2Array()
		if drop:
			var tr: PackedVector2Array = _trail[k]
			tr.append(bosses[k][0])
			if tr.size() > 30:
				tr.remove_at(0)
			_trail[k] = tr


func _near(g: Vector2i) -> bool:
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			if _was_alert.has(g + Vector2i(dx, dy)):
				return true
	return false


# The species the player released (the eaten marks are for those only).
func _mine() -> Array:
	var lr: Variant = host.level_runner
	if lr == null or lr.sp_index < 0:
		return []
	var out := [lr.sp_index]
	if lr.eval and int(lr.eval.sp2) >= 0:
		out.append(int(lr.eval.sp2))
	return out


# How near prey must come before this hunter strikes (its deck's 猎物在 card).
func _strike_r(sp: int) -> float:
	if not _strike.has(sp):
		var r := -1.0
		if sp < host.species_deck.size():
			for cd: Dictionary in host.species_deck[sp]:
				if cd.act == Rules.A_HUNT:
					for s in [1, 2]:
						if cd["c%d" % s] == Rules.C_PREY_NEAR:
							r = maxf(r, float(cd["t%d" % s]))
		_strike[sp] = r
	return _strike[sp]


func _draw() -> void:
	var px := 1.0 / maxf(zoom, 0.05) # one screen pixel in world units
	var mine := _mine()
	var caret_a := smoothstep(0.3, 0.65, zoom)
	# Hunters in view (for "fled from a smell": no hunter near).
	var hunters := PackedVector2Array()
	if not mine.is_empty():
		for b in range(0, marks.size(), 6):
			var hs := int(marks[b + 2])
			if not (hs in mine) and hs < host.species_diet.size() and host.species_diet[hs] == 1:
				hunters.append(Vector2(marks[b], marks[b + 1]))
	if not mine.is_empty():
		_draw_shields(px, mine)
	for b in range(0, marks.size(), 6):
		var p := Vector2(marks[b], marks[b + 1])
		var sp := int(marks[b + 2])
		var ext := marks[b + 5]
		var act := int(marks[b + 4])
		# A native hunter lying in wait (or lunging).
		# (Levels only: the sandbox's hunters are the player's own business.)
		var engulfer: bool = sp < host.species_engulf.size() and host.species_engulf[sp] and not (sp in _boss_species())
		if not mine.is_empty() and not (sp in mine) and engulfer:
			# An engulfer: a bold ring, always, notches turning on it.
			var r := maxf(ext * 1.45, 10.0 * px)
			draw_arc(p, r + 3.0 * px, 0.0, TAU, 48, Color(DANGER, 0.14), 6.0 * px, true)
			draw_arc(p, r, 0.0, TAU, 48, Color(DANGER, 0.9), 2.2 * px, true)
			for j in 4:
				var a0 := t * 1.1 + TAU * j / 4.0
				var d := Vector2.from_angle(a0)
				draw_line(p + d * (r + 2.0 * px), p + d * (r + 7.0 * px), Color(DANGER, 0.9), 2.0 * px, true)
		elif not mine.is_empty() and not (sp in mine) and sp < host.species_diet.size() and host.species_diet[sp] == 1 and not (sp in _boss_species()) and act in [ACT_REST, ACT_HUNT, ACT_BITE]:
			var phase := fmod(t * 0.9 + p.x * 0.013 + p.y * 0.007, TAU)
			if act == ACT_REST:
				var br := 0.5 + 0.5 * sin(phase)
				var r := maxf(ext * 1.6, 9.0 * px) + br * 3.0 * px
				draw_arc(p, r + 2.0 * px, 0.0, TAU, 40, Color(DANGER, 0.08 + 0.06 * br), 4.0 * px, true)
				draw_arc(p, r, 0.0, TAU, 40, Color(DANGER, 0.42 + 0.3 * br), 1.3 * px, true)
				var sr := _strike_r(sp)
				if sr > 0.0 and zoom > 0.45:
					_dashed(p, sr, Color(DANGER, 0.16), 1.0 * px)
			else:
				var r := maxf(ext * 1.25, 7.0 * px)
				draw_arc(p, r + 2.0 * px, 0.0, TAU, 40, Color(DANGER, 0.2), 4.0 * px, true)
				draw_arc(p, r, 0.0, TAU, 40, Color(DANGER, 0.95), 2.0 * px, true)
		# Calling out: rings going off it (two out of step).
		if act == ACT_SIGNAL:
			var off := fposmod(p.x * 0.013 + p.y * 0.007, 1.0)
			for k in 2:
				var u := fposmod(t * 0.9 + off + k * 0.5, 1.0)
				draw_arc(p, ext + 4.0 + u * 52.0, 0.0, TAU, 36, Color(SIG_A, 0.65 * (1.0 - u)), 1.5 * px, true)
		# One of ours running from a smell (fleeing, no hunter near): three
		# small arcs over it, like a scent rising.
		if act == ACT_FLEE and sp in mine and caret_a > 0.0:
			var hunted := false
			for q in hunters:
				if q.distance_squared_to(p) < NOSE_R * NOSE_R:
					hunted = true
					break
			if not hunted:
				var top := p - Vector2(0.0, maxf(ext, 3.0 * px) + 6.0 * px)
				for j in 3:
					var rr := (2.5 + j * 2.6) * px
					draw_arc(top + Vector2(0, 4.0 * px), rr, -PI * 0.78, -PI * 0.22, 8, Color(SIG_A, (0.95 - j * 0.22) * caret_a), 1.4 * px, true)
		# One of ours on alert: a small caret above it.
		if int(marks[b + 3]) == Rules.S_ALERT and caret_a > 0.0:
			var top := p - Vector2(0.0, maxf(ext, 3.0 * px) + 7.0 * px)
			var w := 4.0 * px
			draw_polyline(PackedVector2Array([top + Vector2(-w, w * 0.8), top, top + Vector2(w, w * 0.8)]), Color(Ui.ACCENT, 0.9 * caret_a), 1.6 * px, true)
	for k in bosses.size():
		_draw_boss(k, px)
	# Alerts just begun: the caret's ripple.
	for e: Array in pops:
		var u: float = e[1] / POP_T
		draw_arc(e[0], (6.0 + 16.0 * u) * px, 0.0, TAU, 32, Color(Ui.ACCENT, 0.7 * (1.0 - u) * caret_a), 1.4 * px, true)
	# Eaten: a ring snapping outward under a thin ×.
	for e: Array in eaten:
		var u: float = e[1] / EATEN_T
		var a := 1.0 - u * u
		var snap := 1.0 - pow(1.0 - minf(u * 3.0, 1.0), 3.0)
		draw_arc(e[0], (5.0 + 17.0 * snap) * px, 0.0, TAU, 40, Color(DANGER, 0.75 * (1.0 - snap * 0.6) * a), 1.5 * px, true)
		var s := 5.0 * px
		var c := Color(DANGER, 0.95 * a)
		draw_line(e[0] + Vector2(-s, -s), e[0] + Vector2(s, s), c, 1.6 * px, true)
		draw_line(e[0] + Vector2(-s, s), e[0] + Vector2(s, -s), c, 1.6 * px, true)


func _draw_boss(k: int, px: float) -> void:
	var p: Vector2 = bosses[k][0]
	var e: float = bosses[k][1]
	var r: float = maxf(float(bosses[k][2]), 8.0 * px)
	# The wake.
	if k < _trail.size() and _trail[k] != null:
		var tr: PackedVector2Array = _trail[k]
		for j in tr.size():
			var u := float(j) / maxf(1.0, tr.size())
			draw_circle(tr[j], (1.0 + 2.0 * u) * px, Color(DANGER, 0.22 * u))
	# The crown: two dashed rings turning against each other, teeth closing in.
	var breath := 0.5 + 0.5 * sin(t * 2.4)
	for ring: Array in [[1.45, 14, 1.0, 0.6], [1.72, 22, -0.6, 0.32]]:
		var rr: float = r * float(ring[0])
		var n: int = ring[1]
		var rot: float = t * float(ring[2])
		for j in n:
			var a0 := rot + TAU * j / n
			draw_arc(p, rr, a0, a0 + TAU / n * 0.55, 6, Color(DANGER, float(ring[3])), 1.5 * px, true)
	for j in 12:
		var a := -t * 0.35 + TAU * j / 12.0
		var d := Vector2.from_angle(a)
		var r0 := r * (1.18 + 0.06 * breath)
		draw_line(p + d * r0, p + d * (r0 + r * 0.12), Color(DANGER, 0.75), 1.6 * px, true)
	# Name and energy over it.
	var top := p - Vector2(0.0, r * 1.72 + 18.0 * px)
	var w := 76.0 * px
	var low := e >= 0.0 and e < 0.25
	var blink := 0.55 + 0.45 * sin(t * 9.0) if low else 1.0
	var fill := DANGER if low else Color(0.62, 0.22, 0.42)
	draw_rect(Rect2(top - Vector2(w * 0.5, 0.0), Vector2(w, 5.0 * px)), Color(1, 1, 1, 0.85))
	if e >= 0.0:
		draw_rect(Rect2(top - Vector2(w * 0.5, 0.0), Vector2(w * clampf(e, 0.0, 1.0), 5.0 * px)), Color(fill, blink))
	draw_rect(Rect2(top - Vector2(w * 0.5, 0.0), Vector2(w, 5.0 * px)), Color(fill, 0.8), false, 1.0 * px)
	var label: String = String(bosses[k][3]) + ("  能量 %d%%" % int(round(e * 100.0)) if e >= 0.0 else "")
	if low:
		label += "  · 快饿死了"
	draw_set_transform(top + Vector2(-w * 0.5, -6.0 * px), 0.0, Vector2(px, px))
	draw_string_outline(Ui.sans(600), Vector2.ZERO, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 4, Color(1, 1, 1, 0.85))
	draw_string(Ui.sans(600), Vector2.ZERO, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(fill.darkened(0.15), maxf(blink, 0.75)))
	draw_set_transform(Vector2.ZERO)


# Screen space: an arrow at the edge toward each devourer out of view, and
# the edges glowing red while one is near.
func _draw_edge() -> void:
	var vs := edge.size
	var to_screen := get_viewport().get_canvas_transform() * get_global_transform()
	if near > 0.01:
		var a := near * (0.16 + 0.08 * sin(t * 5.0))
		var bw := 110.0
		var c0 := Color(DANGER, a)
		var c1 := Color(DANGER, 0.0)
		edge.draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(vs.x, 0), Vector2(vs.x, bw), Vector2(0, bw)]), PackedColorArray([c0, c0, c1, c1]))
		edge.draw_polygon(PackedVector2Array([Vector2(0, vs.y - bw), Vector2(vs.x, vs.y - bw), Vector2(vs.x, vs.y), Vector2(0, vs.y)]), PackedColorArray([c1, c1, c0, c0]))
		edge.draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(bw, 0), Vector2(bw, vs.y), Vector2(0, vs.y)]), PackedColorArray([c0, c1, c1, c0]))
		edge.draw_polygon(PackedVector2Array([Vector2(vs.x - bw, 0), Vector2(vs.x, 0), Vector2(vs.x, vs.y), Vector2(vs.x - bw, vs.y)]), PackedColorArray([c1, c0, c0, c1]))
		var msg := "%s看见你的生命了" % String(bosses[0][3]) if not bosses.is_empty() else "Boss 看见你的生命了"
		var f := Ui.sans(700)
		var sw := f.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		edge.draw_string_outline(f, Vector2((vs.x - sw) * 0.5, 128), msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 5, Color(1, 1, 1, 0.9 * near))
		edge.draw_string(f, Vector2((vs.x - sw) * 0.5, 128), msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(DANGER, near))
	# Inside the HUD's frame: clear of the top bar, the bottom toolbar and
	# the side panels.
	var box := Rect2(Vector2(90.0, 130.0), vs - Vector2(180.0, 290.0))
	var mid := box.get_center()
	var view_c: Vector2 = host.cam.get_screen_center_position()
	for bz: Array in bosses:
		var sp: Vector2 = to_screen * (bz[0] as Vector2)
		if Rect2(Vector2.ZERO, vs).grow(-20.0).has_point(sp):
			continue
		var d := (sp - mid)
		if d.length() < 1.0:
			continue
		var s := INF
		if d.x != 0.0:
			s = minf(s, (box.size.x * 0.5) / absf(d.x))
		if d.y != 0.0:
			s = minf(s, (box.size.y * 0.5) / absf(d.y))
		var at := mid + d * s
		var dir := d.normalized()
		var nrm := Vector2(-dir.y, dir.x)
		var pulse := 0.75 + 0.25 * sin(t * 4.0)
		edge.draw_circle(at, 22.0, Color(1, 1, 1, 0.75))
		edge.draw_arc(at, 22.0, 0.0, TAU, 40, Color(DANGER, 0.7), 1.5, true)
		# (A dart is concave: two triangles, not one polygon.)
		var tip := at + dir * 16.0
		var notch := at - dir * 2.0
		edge.draw_colored_polygon(PackedVector2Array([tip, at - dir * 7.0 + nrm * 9.0, notch]), Color(DANGER, pulse))
		edge.draw_colored_polygon(PackedVector2Array([tip, notch, at - dir * 7.0 - nrm * 9.0]), Color(DANGER, pulse))
		var dist := (bz[0] as Vector2).distance_to(view_c)
		var txt := "%s  %d µm" % [String(bz[3]), int(dist)]
		var e: float = bz[1]
		if e >= 0.0:
			txt += "  ·  能量 %d%%" % int(round(e * 100.0))
		var f := Ui.sans(600)
		var tw := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		var tp := at - dir * 44.0 - Vector2(tw * 0.5, -5.0)
		tp.x = clampf(tp.x, 12.0, vs.x - tw - 12.0)
		edge.draw_string_outline(f, tp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 5, Color(1, 1, 1, 0.9))
		edge.draw_string(f, tp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, DANGER.darkened(0.1))


const LINK := 34.0 # cells this close are one group


func _draw_shields(px: float, mine: Array) -> void:
	# Only a hunter that herds (a species with a herd number) is beaten by
	# a tight group; no level uses one at present (3-2 became 一起生).
	var need := 0.0
	var herders: Array = [] # positions
	for b in range(0, marks.size(), 6):
		var sp := int(marks[b + 2])
		if sp in mine or sp >= host.species_herd.size() or host.species_herd[sp] <= 0.0:
			continue
		var h: float = host.species_herd[sp]
		need = h if need == 0.0 else minf(need, h)
		herders.append(Vector2(marks[b], marks[b + 1]))
	if need <= 0.0:
		return
	var pts := PackedVector2Array()
	var exts := PackedFloat32Array()
	for b in range(0, marks.size(), 6):
		if int(marks[b + 2]) in mine:
			pts.append(Vector2(marks[b], marks[b + 1]))
			exts.append(marks[b + 5])
	var n := pts.size()
	if n < int(ceilf(need)):
		return
	# Groups: cells within LINK of each other, joined (grid + union-find).
	var parent := PackedInt32Array()
	parent.resize(n)
	for i in n:
		parent[i] = i
	var grid := {}
	for i in n:
		var g := Vector2i(pts[i] / LINK)
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				var key: Vector2i = g + Vector2i(dx, dy)
				if grid.has(key):
					for j: int in grid[key]:
						if pts[i].distance_squared_to(pts[j]) < LINK * LINK:
							var a := _root(parent, i)
							var bb := _root(parent, j)
							if a != bb:
								parent[a] = bb
		if not grid.has(g):
			grid[g] = []
		grid[g].append(i)
	var groups := {}
	for i in n:
		var r := _root(parent, i)
		if not groups.has(r):
			groups[r] = []
		groups[r].append(i)
	for key in groups:
		var idx: Array = groups[key]
		if idx.size() < int(ceilf(need)):
			continue
		var ring := PackedVector2Array()
		var c := Vector2.ZERO
		for i: int in idx:
			c += pts[i]
			var rr: float = exts[i] + 9.0
			for k in 10:
				ring.append(pts[i] + Vector2.from_angle(TAU * k / 10.0) * rr)
		c /= idx.size()
		var hull := Geometry2D.convex_hull(ring)
		if hull.size() > 1 and hull[0] == hull[hull.size() - 1]:
			hull.remove_at(hull.size() - 1)
		if hull.size() < 3:
			continue
		var radius := 0.0
		for i: int in idx:
			radius = maxf(radius, pts[i].distance_to(c))
		var threat := PackedVector2Array()
		for hp: Vector2 in herders:
			if hp.distance_to(c) < radius + 90.0:
				threat.append(hp)
		var hot := 0.0 if threat.is_empty() else 0.75 + 0.25 * sin(t * 6.0)
		draw_colored_polygon(hull, Color(Ui.ACCENT, 0.05 + 0.07 * hot))
		var line := hull.duplicate()
		line.append(hull[0])
		draw_polyline(line, Color(Ui.ACCENT, 0.4 + 0.5 * hot), (1.3 + 0.7 * hot) * px, true)
		# A hunter at the group: its aim flicks between cells.
		for hp: Vector2 in threat:
			var tick := int(t / 0.18)
			for k in 3:
				var j: int = idx[absi(tick * 7 + k * 13 + int(hp.x)) % idx.size()]
				draw_dashed_line(hp, pts[j], Color(DANGER, 0.7), 1.2 * px, 5.0 * px, true, true)


static func _root(parent: PackedInt32Array, i: int) -> int:
	while parent[i] != i:
		parent[i] = parent[parent[i]]
		i = parent[i]
	return i


func _dashed(c: Vector2, r: float, col: Color, w: float) -> void:
	var n := 36
	for k in n:
		if k % 2 == 0:
			draw_arc(c, r, TAU * k / n, TAU * (k + 1) / n, 4, col, w, true)
