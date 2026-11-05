class_name DishPointer
extends Node2D
# The microscope pointer (after the third playtest: the dish should answer
# the hand). Over the dish the OS arrow gives way to a thin reticle:
#   free     a small ring with four gaps, slowly turning
#   hover    it is drawn to the cell under it, the ring opens into four
#            brackets locked round the body, the cell lights up (organism
#            shader) and a tag names it: species, lineage, what it is doing
#   pressed  the ring tightens; a click sends a ripple through the water
#   panning  four small arrows
# Moving leaves faint ripples.
# Sixth round ("鼠标更明显"): a scan field rides with the pointer (the
# projected grid lights up inside a ring with a turning scale and the
# coordinates, nearby cells float small data tags), and moving it stirs the
# water: the grid glows along its path (dish shader) and motes swirl up.
# Nothing is pushed: cells under the pointer must stay easy to lock onto. Ripples are drawn only (dish and organism
# shaders): the simulation never feels them, so experiments stay
# reproducible. Over interface panels the OS arrow comes back.
# Lives on its own CanvasLayer (screen space), between the dish and the UI.

const MAX_RIPPLES := 10
const HOVER_IN := 0.16 # seconds for the reticle to lock onto a cell
const TRAIL_STEP := 85.0 # screen pixels of movement per trail ripple
const ACTIONS := ["四处游荡", "游向藻团", "正在进食", "追捕猎物", "正在捕食", "紧急逃离", "寻找空壳", "吃饱休息", "刚刚分裂", "跟随同伴", "释放信号", "游向舒适水温", "聚合体的一员"]

var host: Node2D # the showcase
var pos := Vector2(-9999, -9999) # mouse, screen
var inside_window := true
var shown := false
var hover_id := -1
var hover_info := {}
var hover_t := 0.0 # 0 free .. 1 locked on the hovered cell
var tag_t := 0.0
var lock_t := 0.0 # seconds locked on the current cell
var press := 0.0
var find_timer := 0.0
var trail_acc := 0.0
var spin := 0.0
var ripples: Array[Dictionary] = [] # {p: world, age, life, amp, size}
var bursts: Array[Dictionary] = [] # screen-space click flashes {p, age}
var os_hidden := false
var testing := false
const SCAN_R := 130.0 # screen pixels
const WAKE_MAX := 12
const WAKE_STEP := 22.0 # screen pixels of travel per wake point
var scan_amt := 0.0
var wake: Array[Dictionary] = [] # {p: world, v: world / s, age, life}
var wake_acc := 0.0
var last_pos := Vector2(-9999, -9999)
var vel := Vector2.ZERO # pointer, world units / s (smoothed)
var motes: Array[Dictionary] = [] # {p: world, v: world / s, age, life, spin, r}
var tag_ids: Array[int] = [] # cells near the pointer that wear a data tag
var tags: Array[Dictionary] = [] # their latest info
var tag_timer := 0.0


func _ready() -> void:
	var args := OS.get_cmdline_args()
	testing = "-s" in args or "--script" in args


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_MOUSE_EXIT:
		inside_window = false
	elif what == NOTIFICATION_WM_MOUSE_ENTER:
		inside_window = true
	elif what == NOTIFICATION_PREDELETE and os_hidden:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		pos = (event as InputEventMouse).position
		inside_window = true


# Is the pointer over the dish itself (not a panel, a page or the designer)?
func _over_dish() -> bool:
	if host == null or host.designer != null or not inside_window:
		return false
	if host.in_menu:
		# The menu's live dish answers the pointer right of the menu column.
		return host.menu != null and host.menu.dish_hand(pos) and not host.cine
	var hc := get_viewport().gui_get_hovered_control()
	if hc != null and hc.mouse_filter == Control.MOUSE_FILTER_STOP:
		return false
	return not (host.hud_root and host.hud_root.covers(pos))


func _panning() -> bool:
	return host.dragging or (host.left_down and host.left_dragged) or (host.right_down and host.right_dragged)


func _to_screen(world: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * world


func _to_world(screen: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * screen


# --- called by the showcase -------------------------------------------------

func moved(relative: Vector2, delta: float) -> void:
	if not shown or _panning() or host.mode != "":
		trail_acc = 0.0
		return
	trail_acc += relative.length()
	if trail_acc >= TRAIL_STEP:
		trail_acc = 0.0
		var speed := relative.length() / maxf(delta, 1.0 / 240.0)
		ripple(_to_world(pos), clampf(speed * 0.0009, 0.5, 1.4), 1.3, 0.55)


func pressed() -> void:
	press = 1.0


# A click on the water (or a cell): a ripple ring, a second smaller one just
# behind it, and a brief flash at the point.
func click(screen: Vector2) -> void:
	var w := _to_world(screen)
	ripple(w, 4.2, 2.2, 1.0)
	get_tree().create_timer(0.14).timeout.connect(func() -> void: ripple(w, 2.0, 1.8, 0.75))
	bursts.append({p = screen, age = 0.0})


func ripple(world: Vector2, amp: float, life: float, size: float) -> void:
	if ripples.size() >= MAX_RIPPLES:
		ripples.pop_front()
	ripples.append({p = world, age = 0.0, life = life, amp = amp, size = size})


# --- per frame --------------------------------------------------------------

func _process(delta: float) -> void:
	if host == null:
		return
	shown = _over_dish() and get_viewport().get_visible_rect().has_point(pos)
	# The OS arrow hides only over the dish (never in tests: a test window
	# must not change the player's cursor).
	var hide_os := shown and not testing
	if hide_os != os_hidden:
		os_hidden = hide_os
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN if hide_os else Input.MOUSE_MODE_VISIBLE
	spin += delta * 0.7
	press = move_toward(press, 0.0, delta / 0.22) if not host.left_down else maxf(press, 0.6)
	_update_hover(delta)
	_update_ripples(delta)
	_update_field(delta)
	_upload()
	queue_redraw()


# The scan field, the wake and its motes, the tags on nearby cells.
func _update_field(delta: float) -> void:
	var zoom: float = host.cam.zoom.x
	var live: bool = shown and not _panning() and host.mode == "" and not host.cine
	scan_amt = move_toward(scan_amt, 1.0 if live else 0.0, delta / (0.25 if live else 0.15))
	var w := _to_world(pos)
	# Pointer velocity in the world (the camera's own motion left out).
	if last_pos.x > -9000.0 and delta > 0.0:
		var step := (pos - last_pos) / zoom
		vel = vel.lerp(step / delta, 1.0 - exp(-delta * 18.0))
		if live:
			wake_acc += (pos - last_pos).length()
			if wake_acc >= WAKE_STEP and vel.length() * zoom > 120.0:
				wake_acc = 0.0
				if wake.size() >= WAKE_MAX:
					wake.pop_front()
				wake.append({p = w, v = vel, age = 0.0, life = 1.2})
			# Motes stirred up, more the faster the hand goes.
			var n := int(clampf(vel.length() * zoom / 450.0, 0.0, 4.0))
			for i in n:
				if motes.size() >= 160:
					motes.pop_front()
				var off := Vector2(randf_range(-14, 14), randf_range(-14, 14)) / zoom
				motes.append({p = w + off, v = vel * randf_range(0.15, 0.35) + Vector2(randf_range(-30, 30), randf_range(-30, 30)) / zoom,
					age = 0.0, life = randf_range(0.9, 1.8), spin = randf_range(-2.6, 2.6), r = randf_range(1.1, 2.6)})
	last_pos = pos
	for e in wake:
		e.age += delta
	wake = wake.filter(func(e: Dictionary) -> bool: return e.age < e.life)
	for m in motes:
		m.age += delta
		var v: Vector2 = m.v
		m.v = v.rotated(m.spin * delta) * exp(-delta * 1.6)
		m.p += m.v * delta
	motes = motes.filter(func(m: Dictionary) -> bool: return m.age < m.life)
	# Tags: pick the nearest few cells in the field now and then, follow
	# them every frame.
	tag_timer -= delta
	if scan_amt > 0.3 and tag_timer <= 0.0:
		tag_timer = 0.15
		var r_world := SCAN_R / zoom
		var near: Array = []
		for i in host.labels.size():
			for q: Vector2 in host.sim.get_positions(i):
				var d := q.distance_squared_to(w)
				if d < r_world * r_world:
					near.append([d, q])
		near.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
		var ids: Array[int] = []
		for e in near:
			if ids.size() >= 5:
				break
			var id: int = host.sim.find_agent(e[1], 3.0 / zoom)
			if id >= 0 and id != hover_id and not ids.has(id):
				ids.append(id)
		tag_ids = ids
	elif scan_amt <= 0.3:
		tag_ids.clear()
	tags.clear()
	for id in tag_ids:
		var info: Dictionary = host.sim.get_agent(id)
		if not info.is_empty() and id != hover_id:
			tags.append(info)


func _update_hover(delta: float) -> void:
	var can: bool = shown and not host.cine and not _panning() and host.mode == ""
	find_timer -= delta
	if can and find_timer <= 0.0:
		find_timer = 0.06
		var id: int = host.sim.find_agent(_to_world(pos), 14.0 / host.cam.zoom.x)
		# Sticky: a locked cell stays locked while the cursor is inside its
		# brackets, so a swimming cell is easy to keep hold of.
		if id != hover_id and not hover_info.is_empty():
			var c := _to_screen(host.drawn_pos(hover_info))
			if pos.distance_to(c) < float(hover_info.radius) * host.cam.zoom.x * 1.45 + 13.0:
				id = hover_id
		if id != hover_id:
			hover_id = id
			lock_t = 0.0
			tag_t = 0.0
			hover_t = minf(hover_t, 0.35) # re-aim from near the cursor
	elif not can:
		hover_id = -1
	hover_info = host.sim.get_agent(hover_id) if hover_id >= 0 else {}
	if hover_info.is_empty():
		hover_id = -1
	hover_t = move_toward(hover_t, 1.0 if hover_id >= 0 else 0.0, delta / HOVER_IN)
	if hover_id >= 0 and hover_t >= 1.0:
		lock_t += delta
	tag_t = move_toward(tag_t, 1.0 if lock_t > 0.08 else 0.0, delta / 0.2)


func _update_ripples(delta: float) -> void:
	for r in ripples:
		r.age += delta
	ripples = ripples.filter(func(r: Dictionary) -> bool: return r.age < r.life)
	for b in bursts:
		b.age += delta
	bursts = bursts.filter(func(b: Dictionary) -> bool: return b.age < 0.5)


func _upload() -> void:
	var data := PackedVector4Array()
	for r in ripples:
		var a: float = r.age
		var k: float = a / r.life
		var radius: float = (10.0 + 420.0 * (1.0 - exp(-a * 1.9))) * r.size
		var amp: float = r.amp * pow(1.0 - k, 2.0) * smoothstep(0.0, 0.06, a)
		data.append(Vector4(r.p.x, r.p.y, radius, amp))
	var count := data.size()
	data.resize(MAX_RIPPLES)
	var dish := host.medium.material as ShaderMaterial
	var cm := host.cells.material as ShaderMaterial
	dish.set_shader_parameter("ripples", data)
	dish.set_shader_parameter("ripple_count", count)
	cm.set_shader_parameter("ripples", data)
	cm.set_shader_parameter("ripple_count", count)
	cm.set_shader_parameter("ripple_px", 1.0 / host.cam.zoom.x)
	# The scan field and the wake.
	var wp := _to_world(pos)
	var sp: float = host.prev_scan
	if sp > 0.001 and sp > scan_amt:
		# The menu's sandbox preview: a field opening across the whole dish.
		var c: Vector2 = host.DISH_CENTER
		dish.set_shader_parameter("scan", Vector4(c.x, c.y, 80.0 + 1000.0 * _ease(sp), _ease(sp) * 0.8))
	else:
		dish.set_shader_parameter("scan", Vector4(wp.x, wp.y, SCAN_R / host.cam.zoom.x, _ease(scan_amt)))
	var wd := PackedVector4Array()
	var wk := PackedFloat32Array()
	for e in wake:
		var k: float = 1.0 - e.age / e.life
		wd.append(Vector4(e.p.x, e.p.y, e.v.x, e.v.y))
		wk.append(k * k * smoothstep(0.0, 0.08, e.age))
	var wn := wd.size()
	wd.resize(WAKE_MAX)
	wk.resize(WAKE_MAX)
	dish.set_shader_parameter("wake", wd)
	dish.set_shader_parameter("wake_k", wk)
	dish.set_shader_parameter("wake_count", wn)
	var e := _ease(hover_t)
	if hover_id >= 0:
		var hp: Vector2 = host.drawn_pos(hover_info)
		cm.set_shader_parameter("hover", Vector4(hp.x, hp.y, float(hover_info.radius) * 0.7 + 2.0, e))
	else:
		cm.set_shader_parameter("hover", Vector4(-1e6, -1e6, 0.0, 0.0))
	var sel: int = host.selected
	if sel >= 0 and host.gone_timer <= 0.0:
		var lp: Vector2 = host.last_pos
		cm.set_shader_parameter("picked", Vector4(lp.x, lp.y, 9.0, 1.0))
	else:
		cm.set_shader_parameter("picked", Vector4(-1e6, -1e6, 0.0, 0.0))


static func _ease(t: float) -> float:
	return 1.0 - pow(1.0 - clampf(t, 0.0, 1.0), 3.0)


# --- drawing ----------------------------------------------------------------

func _draw() -> void:
	if host == null:
		return
	_draw_selected()
	for b in bursts:
		var k: float = b.age / 0.5
		var e := _ease(k)
		draw_arc(b.p, 8.0 + 46.0 * e, 0.0, TAU, 48, Color(1, 1, 1, 0.75 * (1.0 - k)), 2.0 * (1.0 - k) + 0.5, true)
		for i in 6:
			var a := TAU * i / 6.0 + 0.4
			var d := 10.0 + 34.0 * e
			draw_circle(b.p + Vector2(cos(a), sin(a)) * d, 1.6 * (1.0 - k), Color(Ui.ACCENT, 1.0 - k))
	_draw_motes()
	if not shown:
		return
	if scan_amt > 0.01 and host.mode == "":
		_draw_field()
	if host.mode != "":
		# Placing an intervention: the overlay draws the preview; a fine
		# crosshair marks the exact point.
		_cross(pos, 6.0, Ui.INK)
		return
	var e := _ease(hover_t)
	var ink := Ui.INK
	var cell_c := pos
	var cell_r := 9.0
	if hover_id >= 0:
		cell_c = _to_screen(host.drawn_pos(hover_info))
		cell_r = maxf(float(hover_info.radius) * host.cam.zoom.x * 1.45 + 7.0, 14.0)
		ink = Ui.INK.lerp(host.species_color(int(hover_info.species)).darkened(0.25), e)
		# Under the magnifier the cell is seen closer: lock onto where the
		# glass shows it.
		if host.magnifier and host.magnifier.is_open():
			var pw: float = host.magnifier.power()
			cell_c = pos + (cell_c - pos) * pw
			cell_r = minf(cell_r * pw, host.magnifier.RADIUS * host.magnifier.open_k - 10.0)
	var c := pos.lerp(cell_c, e)
	var r := lerpf(9.0, cell_r, e) * (1.0 - 0.2 * press)
	if _panning():
		_draw_pan(c)
		return
	# Ring: four arcs whose gaps widen into brackets as it locks on, turning
	# while free and settling square when locked.
	var rot := spin * (1.0 - e) + PI * 0.25 * e
	var arc_len := lerpf(TAU / 4.0 * 0.62, TAU / 4.0 * 0.28, e)
	for k in 4:
		var mid_a := rot + TAU * k / 4.0
		draw_arc(c, r, mid_a - arc_len * 0.5, mid_a + arc_len * 0.5, 12, Color(1, 1, 1, 0.6), 3.4, true)
		draw_arc(c, r, mid_a - arc_len * 0.5, mid_a + arc_len * 0.5, 12, ink, 1.3, true)
	if e > 0.02:
		# Inward ticks at the four compass points, sliding in as it locks.
		for k in 4:
			var a := TAU * k / 4.0
			var dir := Vector2(cos(a), sin(a))
			var from := c + dir * (r + 7.0 * (1.0 - e) + 3.0)
			draw_line(from, from + dir * 5.0, Color(ink, e), 1.3, true)
	else:
		draw_circle(c, 1.6, ink)
	if tag_t > 0.0 and hover_id >= 0:
		_draw_tag(c, r, ink)


func _cross(c: Vector2, s: float, col: Color) -> void:
	for d in [Vector2(1, 0), Vector2(0, 1)]:
		draw_line(c - d * s, c + d * s, Color(1, 1, 1, 0.7), 3.0, true)
		draw_line(c - d * s, c + d * s, col, 1.2, true)


func _draw_pan(c: Vector2) -> void:
	for k in 4:
		var a := TAU * k / 4.0
		var dir := Vector2(cos(a), sin(a))
		var side := dir.orthogonal()
		var tip := c + dir * 12.0
		for col_w in [[Color(1, 1, 1, 0.6), 3.0], [Ui.INK, 1.3]]:
			draw_polyline([tip - dir * 4.0 + side * 4.0, tip, tip - dir * 4.0 - side * 4.0], col_w[0], col_w[1], true)
	draw_circle(c, 1.6, Ui.INK)


# The name tag beside a locked cell: species chip and name, lineage, then
# what it is doing and its energy as a thin bar.
func _draw_tag(c: Vector2, r: float, ink: Color) -> void:
	var info := hover_info
	var sp: int = info.species
	var name: String = host.labels[sp] if sp < host.labels.size() else "未知物种"
	var doing: String
	if float(info.get("dividing", -1.0)) >= 0.0:
		doing = "正在分裂"
	else:
		doing = ACTIONS[clampi(int(info.action), 0, ACTIONS.size() - 1)]
	var ratio := clampf(float(info.energy) / maxf(float(info.divide_at), 1.0), 0.0, 1.0)
	if ratio < 0.25:
		doing += " · 饥饿"
	var f1 := Ui.sans(600)
	var f2 := Ui.sans(400)
	var line2 := "%s　#%d" % [doing, int(info.lineage)]
	var w := maxf(f1.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 18.0, f2.get_string_size(line2, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x) + 22.0
	var h := 44.0
	var k := _ease(tag_t)
	var view := get_viewport().get_visible_rect().size
	var right := c.x + r + 14.0 + w < view.x - 8.0
	var x := c.x + r + 14.0 if right else c.x - r - 14.0 - w
	x += (1.0 - k) * (-10.0 if right else 10.0)
	var y := clampf(c.y - h * 0.5, 8.0, view.y - h - 8.0)
	var box := Rect2(x, y, w, h)
	draw_rect(Rect2(box.position + Vector2(0, 3), box.size), Color(0.1, 0.2, 0.26, 0.08 * k))
	draw_rect(box, Color(1, 1, 1, 0.86 * k))
	draw_rect(Rect2(box.position, Vector2(2.0, h)), Color(ink, k))
	# A hairline from the bracket to the tag.
	var from := c + Vector2(r + 3.0 if right else -r - 3.0, 0.0)
	draw_line(from, Vector2(x if right else x + w, clampf(c.y, y + 6.0, y + h - 6.0)), Color(ink, 0.5 * k), 1.0, true)
	var col: Color = host.species_color(sp)
	draw_circle(Vector2(x + 14.0, y + 15.0), 4.0, Color(col, k))
	draw_string(f1, Vector2(x + 24.0, y + 20.0), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(Ui.INK, k))
	draw_string(f2, Vector2(x + 10.0, y + 35.0), line2, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(Ui.INK_SOFT, k))
	draw_rect(Rect2(x + 10.0, y + h - 5.0, (w - 20.0), 2.0), Color(Ui.INK_FAINT, 0.3 * k))
	draw_rect(Rect2(x + 10.0, y + h - 5.0, (w - 20.0) * ratio, 2.0), Color(col.darkened(0.15), k))


# The selected cell: four slow-turning corner brackets in its colour.
func _draw_selected() -> void:
	if host.quiet_callouts:
		return # (a close-up: the picture is the inside of the cell)
	var sel: int = host.selected
	if sel < 0 or host.gone_timer > 0.0 or host.designer != null or host.in_menu:
		return
	var info: Dictionary = host.sim.get_agent(sel)
	if info.is_empty():
		return
	var c := _to_screen(host.last_pos) # where the cell is drawn (interpolated)
	var r := maxf(float(info.radius) * host.cam.zoom.x * 1.7 + 10.0, 18.0)
	var view := get_viewport().get_visible_rect().size
	if r > view.y * 0.42 or not Rect2(Vector2.ZERO, view).grow(r).has_point(c):
		return
	var col: Color = host.species_color(int(info.species)).darkened(0.2)
	var t := Time.get_ticks_msec() / 1000.0
	var rot := t * 0.35
	var breathe := 1.0 + 0.04 * sin(t * 2.6)
	for k in 4:
		var mid_a := rot + TAU * k / 4.0
		draw_arc(c, r * breathe, mid_a - 0.32, mid_a + 0.32, 12, Color(1, 1, 1, 0.55), 3.6, true)
		draw_arc(c, r * breathe, mid_a - 0.32, mid_a + 0.32, 12, col, 1.5, true)


# --- the scan field ---------------------------------------------------------

const HOLO_INK := Color(0.05, 0.42, 0.5)


func _draw_field() -> void:
	var a := _ease(scan_amt)
	var c := pos
	var r := SCAN_R * (0.85 + 0.15 * a)
	if host.magnifier and host.magnifier.is_open():
		r = maxf(r, host.magnifier.RADIUS + 34.0)
	var col := Color(HOLO_INK, 0.55 * a)
	draw_arc(c, r, 0.0, TAU, 96, Color(1, 1, 1, 0.35 * a), 3.0, true)
	draw_arc(c, r, 0.0, TAU, 96, col, 1.0, true)
	# A turning scale outside the ring: every 5°, long every 45°; brighter on
	# the side the hand is heading.
	var head := vel.angle() if vel.length() > 5.0 else -PI * 0.5
	var mv := clampf(vel.length() * host.cam.zoom.x / 900.0, 0.0, 1.0)
	var rot := spin * 0.25
	for i in 72:
		var ang := rot + TAU * i / 72.0
		var d := Vector2(cos(ang), sin(ang))
		var long := i % 9 == 0
		var lead := pow(maxf(cos(ang - head), 0.0), 6.0) * mv
		var len := (9.0 if long else 4.5) + 6.0 * lead
		draw_line(c + d * (r + 3.0), c + d * (r + 3.0 + len), Color(HOLO_INK, (0.55 if long else 0.3) * a + 0.4 * lead * a), 1.0, true)
	# Cardinal hairs reaching in toward the reticle.
	for k in 4:
		var d := Vector2.from_angle(k * PI * 0.5)
		draw_line(c + d * (r - 16.0), c + d * (r - 4.0), Color(HOLO_INK, 0.7 * a), 1.2, true)
	# Coordinates from the dish centre, µm, and the field's span.
	var w: Vector2 = _to_world(pos) - host.DISH_CENTER
	var f := Ui.mono("Medium")
	var txt := "X %+05d  Y %+05d µm" % [roundi(w.x), roundi(-w.y)]
	var tp := c + Vector2(r * 0.72 + 8.0, r * 0.72 + 18.0)
	draw_string_outline(f, tp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, 4, Color(1, 1, 1, 0.75 * a))
	draw_string(f, tp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(HOLO_INK, a))
	var span := "SCAN Ø %d µm" % roundi(2.0 * SCAN_R / host.cam.zoom.x)
	draw_string_outline(f, tp + Vector2(0, 14), span, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, 4, Color(1, 1, 1, 0.6 * a))
	draw_string(f, tp + Vector2(0, 14), span, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(Ui.INK_SOFT, 0.85 * a))
	# Data tags on the nearby cells: a dot, a short leader, id and doing.
	if host.magnifier and host.magnifier.is_open():
		return
	var ft := Ui.mono()
	var fs := Ui.sans(500)
	var used: Array[Rect2] = []
	for i in tags.size():
		var info: Dictionary = tags[i]
		var p := _to_screen(host.drawn_pos(info))
		if p.distance_to(c) > r:
			continue
		var sp: int = info.species
		var cc: Color = host.species_color(sp).darkened(0.3)
		var out := (p - c).normalized() if p.distance_to(c) > 1.0 else Vector2.RIGHT
		var rr: float = float(info.radius) * host.cam.zoom.x + 3.0
		var a0 := p + out * rr
		var a1 := a0 + out * 14.0 + Vector2(0, -6)
		var right := out.x >= 0.0
		var a2 := a1 + Vector2(10.0 if right else -10.0, 0)
		var t1 := "#%d" % int(info.id)
		var doing: String = ACTIONS[clampi(int(info.action), 0, ACTIONS.size() - 1)]
		var w1 := ft.get_string_size(t1, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		var w2 := fs.get_string_size(doing, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		var tx := a2.x + 3.0 if right else a2.x - 3.0 - maxf(w1, w2)
		# One tag per spot: skip one that would sit on another.
		var box := Rect2(tx - 2.0, a2.y - 12.0, maxf(w1, w2) + 4.0, 27.0)
		var clash := false
		for u in used:
			if u.intersects(box):
				clash = true
				break
		if clash:
			continue
		used.append(box)
		draw_circle(p, 1.8, Color(cc, a))
		draw_polyline(PackedVector2Array([a0, a1, a2]), Color(cc, 0.75 * a), 1.0, true)
		draw_string_outline(ft, Vector2(tx, a2.y - 1), t1, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, 4, Color(1, 1, 1, 0.75 * a))
		draw_string(ft, Vector2(tx, a2.y - 1), t1, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(cc, a))
		draw_string_outline(fs, Vector2(tx, a2.y + 11), doing, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, 4, Color(1, 1, 1, 0.7 * a))
		draw_string(fs, Vector2(tx, a2.y + 11), doing, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(Ui.INK_SOFT, a))


# Motes stirred up by the hand, swirling and settling.
func _draw_motes() -> void:
	if motes.is_empty():
		return
	for m in motes:
		var k: float = m.age / m.life
		var fade := sin(k * PI)
		var p := _to_screen(m.p)
		var v: Vector2 = m.v * host.cam.zoom.x
		var tail := v * 0.03
		if tail.length() > 1.5:
			draw_line(p - tail, p, Color(1, 1, 1, 0.5 * fade), m.r, true)
		draw_circle(p, m.r, Color(0.95, 1.0, 1.0, 0.75 * fade))
		draw_circle(p, m.r * 0.5, Color(HOLO_INK, 0.6 * fade))
