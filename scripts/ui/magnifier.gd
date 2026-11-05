extends Node2D
# The loupe (fifth round: "HUD 联动 + 放大镜"). Hold Alt, or press Z to keep
# it out, and a round lens follows the pointer over the dish: the water
# under it seen closer, rendered for real by a small SubViewport sharing the
# dish's world (micro detail appears, as when zooming in), bent and fringed
# at the rim by shaders/lens_glass.gdshader. Alt + wheel sets the power.
# Around the glass: a soft shadow, a ring of ticks that turns with the
# power, the power and a scale bar in µm (one world unit is one µm).
# It irises open with a slight overshoot and closes quickly.
# Lives on its own CanvasLayer (screen space), over the lens post layer and
# under the pointer, so the reticle stays on top.

const RADIUS := 150.0
const OVERSIZE := 1.2
const MAG_MIN := 1.6
const MAG_MAX := 6.0

var host: Node2D # the showcase
var sv: SubViewport
var sv_cam: Camera2D
var glass: Node2D
var mat: ShaderMaterial
var held := false # Alt down
var sticky := false # Z
var mag := 2.6
var shown_mag := 2.6
var open_k := 0.0 # 0 closed .. 1 open (eased in _process)
var _open_lin := 0.0
var spin := 0.0
var pos := Vector2(-9999, -9999)
var _testing := false
# Watching a division: brought over a dividing cell, the lens locks onto
# it (the view follows the waist between the halves), closes in until the
# DNA shows (organism.gdshader's loupe LOD) and the dish slows to a quarter
# (showcase.observe_want); a caption names the stage. Lets go when the two
# cells part.
const WATCH_CELL_PX := 125.0 # the cell's radius in the lens while watching
var watch_id := -1
var watch_k := 0.0
var watch_split := 0.0
var _watch_aim := Vector2.ZERO


func _ready() -> void:
	var args := OS.get_cmdline_args()
	_testing = "-s" in args or "--script" in args
	sv = SubViewport.new()
	var n := int(RADIUS * 2.0 * OVERSIZE)
	sv.size = Vector2i(n, n)
	sv.disable_3d = true
	sv.use_hdr_2d = true
	sv.transparent_bg = false
	sv.world_2d = get_viewport().world_2d
	sv.render_target_update_mode = SubViewport.UPDATE_DISABLED
	sv_cam = Camera2D.new()
	sv.add_child(sv_cam)
	add_child(sv)
	glass = Node2D.new()
	mat = ShaderMaterial.new()
	mat.shader = preload("res://shaders/lens_glass.gdshader")
	mat.set_shader_parameter("radius_px", RADIUS)
	mat.set_shader_parameter("oversize", OVERSIZE)
	glass.material = mat
	glass.draw.connect(_draw_glass)
	add_child(glass)
	# Decorations over the glass.
	var deco := Node2D.new()
	deco.draw.connect(_draw_deco.bind(deco))
	add_child(deco)
	deco.set_meta("deco", true)


func is_open() -> bool:
	return open_k > 0.01


# How much closer the lens shows right now (1 while closed).
func power() -> float:
	return lerpf(1.0, shown_mag, open_k)


# Pick up (or keep) a dividing cell under the lens; let go when it is done.
func _tick_watch(delta: float, under: Vector2) -> void:
	var sim: SimCore = host.sim
	if watch_id < 0:
		var reach: float = RADIUS * 0.45 / (host.cam.zoom.x * power())
		var id := sim.find_agent(under, reach)
		if id >= 0:
			var d: float = float(sim.get_agent(id).get("dividing", -1.0))
			if d >= 0.0 and d < 0.8:
				watch_id = id
				Audio.sfx("holo_on", -12.0, 1.4)
	var info: Dictionary = sim.get_agent(watch_id) if watch_id >= 0 else {}
	var split: float = float(info.get("dividing", -1.0))
	if watch_id >= 0 and split < 0.0:
		watch_id = -1
	if watch_id >= 0:
		watch_split = split
		# The waist between parent and child (the child steps out ahead).
		var sep := smoothstep(0.08, 0.95, split)
		var r: float = info.radius
		_watch_aim = host.drawn_pos(info) + Vector2.from_angle(info.heading) * 1.04 * sep * r
	watch_k = move_toward(watch_k, 1.0 if watch_id >= 0 else 0.0, delta / 0.4)
	host.observe_want = watch_id >= 0


# The power the lens wants: the user's, or close enough to see the DNA.
func _target_mag() -> float:
	if watch_k <= 0.0 or watch_id < 0:
		return mag
	var info: Dictionary = host.sim.get_agent(watch_id)
	var r: float = info.get("radius", 6.0)
	return maxf(mag, clampf(WATCH_CELL_PX / (r * host.cam.zoom.x), MAG_MIN, 40.0))


# What the dividing cell is doing, for the caption.
static func stage_of(split: float) -> String:
	if split < 0.04:
		return "分裂开始 · 细胞鼓起"
	if split < 0.27:
		return "DNA 复制 · 解旋酶打开双链，聚合酶给每条旧链配上新链"
	if split < 0.36:
		return "两份 DNA 凝缩"
	if split < 0.74:
		return "纺锤丝把两份 DNA 拉向两极"
	return "两个新细胞核形成 · 细胞一分为二"


func _want() -> bool:
	if host == null or not (held or sticky):
		return false
	return host.pointer != null and host.pointer.shown and host.mode == "" and not host.analyzing


func _notification(what: int) -> void:
	# Alt released while another window had focus (Alt+Tab) never arrives:
	# let go of it on losing focus.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		held = false


func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		pos = (event as InputEventMouse).position
	var k := event as InputEventKey
	if k and k.pressed and not k.echo and k.keycode == KEY_ESCAPE and (sticky or held) and is_open():
		sticky = false
		held = false
		Audio.sfx("holo_on", -13.0, 0.9)
		get_viewport().set_input_as_handled()
		return
	if k and k.keycode == KEY_ALT and not k.echo:
		var was := held
		held = k.pressed
		if held and not was and not sticky:
			Audio.sfx("holo_on", -13.0, 1.25)
	elif k and k.pressed and not k.echo and k.keycode == Keys.code("lens") and host and not host.in_menu \
			and host.designer == null and not (get_viewport().gui_get_focus_owner() is LineEdit):
		sticky = not sticky
		Audio.sfx("holo_on", -13.0, 1.25 if sticky else 0.9)
		if host.hud_root:
			host.hud_root.ping_action("lens")
		get_viewport().set_input_as_handled()
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and is_open() and (held or mb.alt_pressed) \
			and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var f := 1.15 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15
		mag = clampf(mag * f, MAG_MIN, MAG_MAX)
		Audio.sfx("holo_tick", -16.0, 0.8 + mag * 0.1)
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if held and not _testing and not Input.is_key_pressed(KEY_ALT):
		held = false
	var want := _want()
	_open_lin = move_toward(_open_lin, 1.0 if want else 0.0, delta / (0.3 if want else 0.16))
	# Opening overshoots a touch (back ease); closing just falls.
	if want:
		var t := _open_lin
		open_k = 1.0 + 2.2 * pow(t - 1.0, 3.0) + 1.2 * pow(t - 1.0, 2.0)
	else:
		open_k = _open_lin * _open_lin
	shown_mag = lerpf(shown_mag, _target_mag(), 1.0 - exp(-delta * (5.0 if watch_k > 0.0 else 14.0)))
	spin += delta * 0.08
	var on := open_k > 0.01
	if visible and not on:
		queue_redraw()
	visible = on
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	if not on:
		watch_id = -1
		watch_k = 0.0
		if host:
			host.observe_want = false
		return
	if host.pointer:
		pos = host.pointer.pos
	var xf := get_viewport().get_canvas_transform()
	var under := xf.affine_inverse() * pos
	_tick_watch(delta, under)
	var e := watch_k * watch_k * (3.0 - 2.0 * watch_k)
	sv_cam.position = under.lerp(_watch_aim, e)
	sv_cam.zoom = host.cam.zoom * power()
	mat.set_shader_parameter("open", clampf(open_k, 0.0, 1.0))
	queue_redraw()
	glass.queue_redraw()
	for c in get_children():
		if c.has_meta("deco"):
			(c as Node2D).queue_redraw()


func _r() -> float:
	return RADIUS * maxf(open_k, 0.0)


func _draw_glass() -> void:
	var r := _r()
	if r < 1.0:
		return
	mat.set_shader_parameter("radius_px", r)
	glass.draw_texture_rect(sv.get_texture(), Rect2(pos - Vector2(r, r), Vector2(r, r) * 2.0), false)


# Under the glass: its shadow on the water.
func _draw() -> void:
	var r := _r()
	if r < 1.0:
		return
	for i in 6:
		var k := i / 6.0
		draw_circle(pos + Vector2(0, 6), r + 3.0 + i * 4.0, Color(0.06, 0.16, 0.22, 0.05 * (1.0 - k)))


func _draw_deco(n: Node2D) -> void:
	var r := _r()
	if r < 8.0:
		return
	var a := clampf(open_k, 0.0, 1.0)
	var ink := Color(Ui.INK, 0.8 * a)
	var acc := Color(Ui.ACCENT, 0.9 * a)
	# Bezel: a crisp outer ring and a faint second one.
	n.draw_arc(pos, r + 0.5, 0.0, TAU, 96, Color(1, 1, 1, 0.75 * a), 2.0, true)
	n.draw_arc(pos, r + 2.0, 0.0, TAU, 96, Color(Ui.INK, 0.45 * a), 1.0, true)
	# Ticks every 6°, long every 30°, turning with the power.
	var rot := spin + shown_mag * 0.35
	for i in 60:
		var ang := rot + TAU * i / 60.0
		var d := Vector2(cos(ang), sin(ang))
		var long := i % 5 == 0
		var l0 := r + 5.0
		var l1 := r + (11.0 if long else 7.5)
		n.draw_line(pos + d * l0, pos + d * l1, Color(Ui.INK, (0.55 if long else 0.28) * a), 1.0 if not long else 1.3, true)
	# The power, on a tab at the lower right of the rim.
	var tab_a := PI * 0.25
	var tp := pos + Vector2(cos(tab_a), sin(tab_a)) * (r + 22.0)
	var f := Ui.mono("SemiBold")
	var txt := "×%.1f" % shown_mag
	n.draw_string_outline(f, tp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color(1, 1, 1, 0.7 * a))
	n.draw_string(f, tp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, ink)
	var f2 := Ui.mono("Medium")
	n.draw_string(f2, tp + Vector2(0, 13), "LENS  ALT+WHEEL", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(Ui.INK_SOFT, 0.75 * a))
	# How to put it away, said on the glass itself.
	var how := "%s / Esc 关闭" % Keys.name_of(Keys.code("lens")) if sticky else "松开 Alt 关闭"
	var fz := Ui.sans(500)
	n.draw_string_outline(fz, tp + Vector2(0, 29), how, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, 4, Color(1, 1, 1, 0.7 * a))
	n.draw_string(fz, tp + Vector2(0, 29), how, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(Ui.INK, 0.85 * a))
	# Scale bar inside the glass, bottom: a round number of µm.
	var px_per_um: float = host.cam.zoom.x * power() if host else 1.0
	var um := 1.0
	for cand in [1.0, 2.0, 5.0, 10.0, 20.0, 50.0, 100.0, 200.0, 500.0]:
		if cand * px_per_um <= r * 0.5:
			um = cand
	var bw := um * px_per_um
	var by := pos.y + r * 0.72
	var bx := pos.x - bw * 0.5
	n.draw_line(Vector2(bx, by), Vector2(bx + bw, by), Color(1, 1, 1, 0.8 * a), 3.0)
	n.draw_line(Vector2(bx, by), Vector2(bx + bw, by), ink, 1.2)
	for x in [bx, bx + bw]:
		n.draw_line(Vector2(x, by - 3), Vector2(x, by + 3), ink, 1.2)
	var lbl := "%d µm" % int(um)
	var lw := f2.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	n.draw_string_outline(f2, Vector2(pos.x - lw * 0.5, by - 6), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, 4, Color(1, 1, 1, 0.7 * a))
	n.draw_string(f2, Vector2(pos.x - lw * 0.5, by - 6), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, ink)
	# Watching a division: the stage over the top of the lens, the slow-down
	# and a progress arc on the rim.
	if watch_k > 0.01:
		var wa := a * watch_k
		var cap := stage_of(watch_split)
		var fc := Ui.sans(600)
		var cw := fc.get_string_size(cap, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		var cp := Vector2(pos.x - cw * 0.5, pos.y - r - 30.0)
		n.draw_rect(Rect2(cp + Vector2(-10, -17), Vector2(cw + 20, 24)), Color(1, 1, 1, 0.82 * wa))
		n.draw_rect(Rect2(cp + Vector2(-10, -17), Vector2(cw + 20, 24)), Color(Ui.ACCENT, 0.7 * wa), false, 1.0)
		n.draw_string(fc, cp, cap, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(Ui.INK, wa))
		var slow := "细胞分裂观察 · 慢放 ×%.2f" % host.OBSERVE_SPEED
		var sw := f2.get_string_size(slow, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		n.draw_string_outline(f2, Vector2(pos.x - sw * 0.5, cp.y - 24.0), slow, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, 4, Color(1, 1, 1, 0.7 * wa))
		n.draw_string(f2, Vector2(pos.x - sw * 0.5, cp.y - 24.0), slow, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(Ui.ACCENT, wa))
		var a0 := -PI * 0.5
		n.draw_arc(pos, r + 15.0, a0, a0 + TAU * clampf(watch_split, 0.0, 1.0), 64, Color(Ui.ACCENT, 0.9 * wa), 2.0, true)
	# Fine centre cross.
	for d in [Vector2(1, 0), Vector2(0, 1)]:
		n.draw_line(pos - d * 7.0, pos - d * 3.0, Color(acc, 0.6 * a), 1.0, true)
		n.draw_line(pos + d * 3.0, pos + d * 7.0, Color(acc, 0.6 * a), 1.0, true)
