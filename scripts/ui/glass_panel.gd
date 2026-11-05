class_name GlassPanel
extends MarginContainer
# A panel of the interface. Put content in `body`.
# Two looks (static `holo`):
#   holo (the frameless hologram, fourth round: "too ordinary"): no box, a
#        feathered haze of light behind the content, a glowing header rule
#        (shaders/holo_frame.gdshader); the content draws through
#        shaders/holo_content.gdshader (flicker, chromatic split, parallax).
#        appear() materialises it: the rule traces in with a bright head,
#        the haze flickers up, the content flickers on with its channels
#        split and closing, text types itself in; glyph motes drift off.
#        The panel floats against the cursor (parallax, by `depth`).
#   glass (the earlier frosted panel, shaders/glass.gdshader).
# flash() = its content changed; glitch() = a brief chromatic jolt.

static var holo := true
# Where the pointer is, from the last mouse event (screen). Read this, not
# the viewport's query: tests drive the HUD with synthetic events.
static var pointer := Vector2(-1e5, -1e5)
static var _testing := -1


# The pointer, screen: the viewport's own reading in play; under -s (tests,
# their window parked off screen) the last synthetic event.
static func mouse(vp: Viewport) -> Vector2:
	if _testing < 0:
		var args := OS.get_cmdline_args()
		_testing = 1 if ("-s" in args or "--script" in args) else 0
	return pointer if _testing == 1 else vp.get_mouse_position()

var bg: ColorRect
var body: MarginContainer
var mat: ShaderMaterial
var content_mat: ShaderMaterial
var motes: Control
var shadow := true
var depth := 4.0 # parallax, pixels at the screen's edge
var _highlight := 0.0
var _highlight_target := 0.0
var _flash := 0.0
var _glitch := 0.0
var _appear := 1.0
# 3D lean toward the cursor (fifth round). Off: in play it switched on and
# off as the hand crossed buttons and panels ("忽有忽无，一卡一卡") and
# skewed text on wide panels. A panel may still opt in with lean > 0.
var lean := 0.0 # how far the near edge comes forward (fraction)
var _lean := Vector2.ZERO
var _motes: Array[Dictionary] = []


func _init(padding := Vector4(16, 12, 16, 14)) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg = ColorRect.new()
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mat = ShaderMaterial.new()
	mat.shader = preload("res://shaders/holo_frame.gdshader") if holo else preload("res://shaders/glass.gdshader")
	bg.material = mat
	add_child(bg)
	body = MarginContainer.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_theme_constant_override("margin_left", int(padding.x))
	body.add_theme_constant_override("margin_top", int(padding.y))
	body.add_theme_constant_override("margin_right", int(padding.z))
	body.add_theme_constant_override("margin_bottom", int(padding.w))
	add_child(body)
	resized.connect(func() -> void: mat.set_shader_parameter("size", size))
	if holo:
		shadow = false
		content_mat = ShaderMaterial.new()
		content_mat.shader = preload("res://shaders/holo_content.gdshader")
		content_mat.set_shader_parameter("seed", randf() * 100.0)
		body.material = content_mat
		# Everything put in the body draws through the content shader.
		body.child_entered_tree.connect(_adopt)
		motes = Control.new()
		motes.mouse_filter = Control.MOUSE_FILTER_IGNORE
		motes.draw.connect(_draw_motes)
		add_child(motes)
	set_process(holo)


func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		pointer = (event as InputEventMouse).position


func _adopt(n: Node) -> void:
	if n is CanvasItem and (n as CanvasItem).material == null:
		(n as CanvasItem).use_parent_material = true
	if not n.child_entered_tree.is_connected(_adopt):
		n.child_entered_tree.connect(_adopt)
	for c in n.get_children():
		_adopt(c)


# The shadow, under the glass (drawn before the children); glass look only.
func _draw() -> void:
	if not shadow:
		return
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.set_corner_radius_all(10)
	sb.shadow_color = Color(0.1, 0.24, 0.3, 0.1 + 0.05 * _highlight)
	sb.shadow_size = 14
	sb.shadow_offset = Vector2(0, 5)
	sb.anti_aliasing = true
	draw_style_box(sb, Rect2(Vector2.ZERO, size).grow(-3.0))


func set_highlight(on: bool) -> void:
	if _highlight_target == (1.0 if on else 0.0):
		return
	_highlight_target = 1.0 if on else 0.0
	if on and holo:
		_spawn_motes(5)
	set_process(true)


func flash() -> void:
	_flash = 1.0
	if holo:
		_glitch = maxf(_glitch, 0.6)
		_spawn_motes(4)
	set_process(true)


func glitch(amount := 1.0) -> void:
	_glitch = maxf(_glitch, amount)
	set_process(true)


func _process(delta: float) -> void:
	_highlight = move_toward(_highlight, _highlight_target, delta / Ui.T_MID)
	_flash = move_toward(_flash, 0.0, delta / 0.7)
	_glitch = move_toward(_glitch, 0.0, delta / 0.25)
	mat.set_shader_parameter("highlight", _highlight)
	mat.set_shader_parameter("flash", _flash * _flash)
	if not holo:
		queue_redraw()
		if _highlight == _highlight_target and _flash <= 0.0:
			set_process(false)
		return
	content_mat.set_shader_parameter("glitch", _glitch)
	# Parallax: the visor floats against the cursor, more toward the edges.
	if is_visible_in_tree():
		var view := get_viewport_rect().size
		var mp := GlassPanel.mouse(get_viewport())
		var m := (mp / view - Vector2(0.5, 0.5)) * 2.0 if mp.x > -1e4 else Vector2.ZERO
		var c := (get_global_rect().get_center() / view - Vector2(0.5, 0.5)) * 2.0
		var s := -m * depth * (0.6 + 0.4 * c.length())
		mat.set_shader_parameter("shift", s)
		content_mat.set_shader_parameter("shift", s)
		motes.position = s
		# Lean: within reach the panel turns its near side toward the hand.
		var r := get_global_rect()
		var mouse := mp
		var hs := r.size * 0.5
		var want := Vector2.ZERO
		if lean > 0.0 and r.grow(90.0).has_point(mouse) and hs.x > 1.0 and hs.y > 1.0:
			var rel := (mouse - r.get_center()) / hs
			want = Vector2(clampf(rel.x, -1.0, 1.0), clampf(rel.y, -1.0, 1.0))
		_lean = _lean.lerp(want, 1.0 - exp(-delta * 7.0))
		if _lean.length_squared() > 1e-6:
			var t := Vector2(_lean.x * lean / maxf(hs.x, 1.0), _lean.y * lean * 0.6 / maxf(hs.y, 1.0))
			var pv := r.get_center() + s
			mat.set_shader_parameter("tilt", t)
			mat.set_shader_parameter("pivot", pv)
			content_mat.set_shader_parameter("tilt", t)
			content_mat.set_shader_parameter("pivot", pv)
		else:
			mat.set_shader_parameter("tilt", Vector2.ZERO)
			content_mat.set_shader_parameter("tilt", Vector2.ZERO)
	_tick_motes(delta)


func _set_param(v: float, name: String) -> void:
	mat.set_shader_parameter(name, v)


func _set_appear(v: float) -> void:
	_appear = v
	content_mat.set_shader_parameter("appear", v)


# The scan wipe (holo_frame / holo_content): visible where
# dot(screen fraction, dir) < front; front >= 8 turns it off.
func set_wipe(dir: Vector2, front: float) -> void:
	var w := Vector3(dir.x, dir.y, front)
	mat.set_shader_parameter("wipe", w)
	if content_mat:
		content_mat.set_shader_parameter("wipe", w)


# quiet: no sound (a rehearsal while the HUD is hidden, see EcoHud._prewarm).
func appear(delay := 0.0, quiet := false) -> void:
	if not holo:
		_appear_glass(delay)
		return
	modulate.a = 1.0
	mat.set_shader_parameter("trace", 0.0)
	mat.set_shader_parameter("haze_in", 0.0)
	_set_appear(0.0)
	var t := Ui.tween(self)
	t.tween_interval(delay)
	t.tween_callback(func() -> void:
		if not quiet:
			Audio.sfx("holo_on", -14.0, randf_range(0.95, 1.08))
		_spawn_motes(8))
	t.tween_method(_set_param.bind("trace"), 0.0, 1.0, 0.42).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	t.parallel().tween_method(_set_param.bind("haze_in"), 0.0, 1.0, 0.5).set_delay(0.08)
	t.parallel().tween_method(_set_appear, 0.0, 1.0, 0.55).set_delay(0.12).set_trans(Tween.TRANS_SINE)
	var rise := Ui.tween(body)
	rise.tween_interval(delay)
	rise.tween_property(body, "position:x", body.position.x, 0.55).from(body.position.x - 14.0).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	get_tree().create_timer(delay + 0.12).timeout.connect(func() -> void: Holo.type_in(body))


func _appear_glass(delay: float) -> void:
	modulate.a = 0.0
	for k in ["scan", "trace", "bracket_in"]:
		mat.set_shader_parameter(k, 0.0)
	var t := Ui.tween(self)
	t.tween_interval(delay)
	t.tween_property(self, "modulate:a", 1.0, Ui.T_FAST)
	t.parallel().tween_method(_set_param.bind("trace"), 0.0, 1.0, 0.5)
	t.parallel().tween_method(_set_param.bind("bracket_in"), 0.0, 1.0, 0.45).set_trans(Tween.TRANS_BACK).set_delay(0.12)
	t.parallel().tween_method(_set_param.bind("scan"), 0.0, 1.0, Ui.T_SLOW).set_trans(Tween.TRANS_SINE).set_delay(0.06)
	var rise := Ui.tween(body)
	rise.tween_interval(delay)
	rise.tween_property(body, "position:y", body.position.y, Ui.T_SLOW).from(body.position.y + 10.0)


func disappear() -> void:
	var t := Ui.tween(self)
	if holo:
		t.tween_method(_set_appear, 1.0, 0.3, 0.12)
		t.parallel().tween_property(self, "modulate:a", 0.0, 0.18).set_delay(0.04)
		t.tween_callback(_set_appear.bind(1.0))
	else:
		t.tween_property(self, "modulate:a", 0.0, Ui.T_FAST)


# --- glyph motes: tiny code characters drifting up off the rule ---------------

func _spawn_motes(n: int) -> void:
	if size.x <= 0.0:
		return
	for i in n:
		_motes.append({p = Vector2(randf() * size.x, randf_range(-2.0, 6.0)), v = Vector2(randf_range(-6, 6), randf_range(-26, -10)),
			age = 0.0, life = randf_range(0.6, 1.3), ch = Holo.GLYPHS[randi() % Holo.GLYPHS.length()]})


func _tick_motes(delta: float) -> void:
	if _motes.is_empty():
		return
	for m in _motes:
		m.age += delta
		m.p += m.v * delta
	_motes = _motes.filter(func(m: Dictionary) -> bool: return m.age < m.life)
	motes.queue_redraw()


func _draw_motes() -> void:
	var f := Ui.mono()
	for m in _motes:
		var k: float = m.age / m.life
		var a := (1.0 - k) * minf(1.0, m.age * 8.0)
		motes.draw_string(f, m.p, m.ch, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(Ui.ACCENT, 0.75 * a))
