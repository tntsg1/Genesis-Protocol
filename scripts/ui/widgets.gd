class_name Widgets
extends RefCounted
# Small HUD widgets drawn in code so they stay crisp at any scale:
# Readout (rolling number), Sparkline (live history), Meter (thin bar),
# Pill (capsule button with hover and active states), Chip (colour dot).


# A caption over a rolling monospaced value. Numbers glide to new values
# instead of jumping, so changes are readable; a notable rise or fall also
# tints the number for a moment and shows a small arrow (green up, red down;
# accent for readouts where neither way is good or bad: `judged` false).
class Readout extends VBoxContainer:
	var value_label: Label
	var arrow: Label
	var shown := 0.0
	var target := 0.0
	var fmt := "%d"
	var suffix := ""
	var judged := true
	var flashes := true # false: a live readout that drifts all the time
	var _flash := 0.0
	var _dir := 0.0
	var _decode := 0.0 # 1 -> 0: digits still scrambling

	func _init(caption: String, size := Ui.SIZE_READOUT, format := "%d", unit := "") -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_theme_constant_override("separation", 0)
		if caption != "":
			add_child(Ui.label(caption, Ui.SIZE_CAPTION, Ui.INK_FAINT, Ui.sans(500)))
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 3)
		row.alignment = BoxContainer.ALIGNMENT_END if caption == "" else BoxContainer.ALIGNMENT_BEGIN
		add_child(row)
		arrow = Ui.label("▲", maxi(size - 8, 9), Ui.GOOD, Ui.sans(700))
		arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		arrow.modulate.a = 0.0
		value_label = Ui.label("0", size, Ui.INK, Ui.mono("Medium"))
		if caption == "":
			row.add_child(arrow)
			row.add_child(value_label)
		else:
			row.add_child(value_label)
			row.add_child(arrow)
		fmt = format
		suffix = unit

	func set_value(v: float, snap := false) -> void:
		var d := v - target
		var step := maxf(2.0 if fmt == "%d" or fmt == "k" else 0.05, absf(target) * 0.04)
		if flashes and not snap and (target != 0.0 or shown != 0.0) and absf(d) >= step:
			_flash = 1.0
			_dir = signf(d)
			arrow.text = "▲" if d > 0.0 else "▼"
			if GlassPanel.holo:
				decode()
		target = v
		if snap:
			shown = v
		_render()

	# The digits scramble and settle from the left (the hologram's decode).
	func decode() -> void:
		_decode = 1.0

	func _process(delta: float) -> void:
		if absf(shown - target) > 0.001 or _decode > 0.0:
			shown = lerpf(shown, target, minf(1.0, delta * 8.0))
			if absf(shown - target) < 0.01:
				shown = target
			_decode = move_toward(_decode, 0.0, delta / 0.45)
			_render()
		if _flash > 0.0:
			_flash = move_toward(_flash, 0.0, delta / 1.1)
			var c := Ui.ACCENT if not judged else (Ui.GOOD if _dir > 0.0 else Ui.ALERT)
			var k := _flash * _flash
			value_label.add_theme_color_override("font_color", Ui.INK.lerp(c, 0.85 * k))
			arrow.add_theme_color_override("font_color", c)
			arrow.modulate.a = minf(1.0, _flash * 2.0)

	func _render() -> void:
		var t: String
		if fmt == "k":
			t = ("%.1fk" % (shown / 1000.0)) if shown >= 1000.0 else ("%d" % shown)
		else:
			t = (fmt % shown) + suffix
		value_label.text = Holo.scramble(t, 1.0 - _decode) if _decode > 0.0 else t


# Live history line with a soft fill and a pulsing head. The line redraws
# when a value arrives; only the little head pulses every frame.
class Sparkline extends Control:
	var data := PackedFloat32Array()
	var color := Ui.ACCENT
	var capacity := 40
	var max_value := 1.0
	var head := Vector2(-1, -1)
	var _pulse: Control

	func _init(c := Ui.ACCENT, w := 120.0, h := 26.0) -> void:
		color = c
		custom_minimum_size = Vector2(w, h)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_pulse = Control.new()
		_pulse.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_pulse.draw.connect(_draw_head)
		add_child(_pulse)

	func push(v: float) -> void:
		if data.is_empty():
			# No history yet: start as a flat line across, not a sliver.
			for i in capacity - 1:
				data.append(v)
		data.append(v)
		if data.size() > capacity:
			data = data.slice(data.size() - capacity)
		max_value = maxf(max_value * 0.995, v)
		queue_redraw()

	func _process(_delta: float) -> void:
		if head.x >= 0.0 and is_visible_in_tree():
			_pulse.queue_redraw()

	func _draw_head() -> void:
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 260.0)
		_pulse.draw_circle(head, 2.2 + pulse * 1.6, Color(color, 0.25 * (1.0 - pulse) + 0.1))
		_pulse.draw_circle(head, 2.0, color)

	func _draw() -> void:
		var n := data.size()
		if n < 2:
			return
		var pts := PackedVector2Array()
		for i in n:
			var x := size.x * float(i) / float(capacity - 1) + size.x * float(capacity - n) / float(capacity - 1)
			var y := size.y - 2.0 - (size.y - 4.0) * clampf(data[i] / maxf(max_value, 1.0), 0.0, 1.0)
			pts.append(Vector2(x, y))
		var fill := pts.duplicate()
		fill.append(Vector2(pts[n - 1].x, size.y))
		fill.append(Vector2(pts[0].x, size.y))
		# Fill fading down from the line.
		var cols := PackedColorArray()
		for i in n:
			cols.append(Color(color, 0.16))
		cols.append(Color(color, 0.0))
		cols.append(Color(color, 0.0))
		draw_polygon(fill, cols)
		draw_polyline(pts, Color(color, 0.9), 1.4, true)
		head = pts[n - 1]


# Thin rounded bar that eases to its value.
class Meter extends Control:
	var color := Ui.ACCENT
	var ratio := 0.0
	var _shown := 0.0

	func _init(c := Ui.ACCENT, h := 4.0) -> void:
		color = c
		custom_minimum_size = Vector2(0, h)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_ratio(v: float) -> void:
		ratio = clampf(v, 0.0, 1.0)

	func _process(delta: float) -> void:
		if absf(_shown - ratio) > 0.0005:
			_shown = lerpf(_shown, ratio, minf(1.0, delta * 7.0))
			queue_redraw()

	func _draw() -> void:
		var r := size.y * 0.5
		draw_rect(Rect2(Vector2.ZERO, size), Color(Ui.LINE, 0.25), true)
		var w := maxf(size.x * _shown, 0.0)
		if w > 0.5:
			draw_rect(Rect2(Vector2.ZERO, Vector2(w, size.y)), color, true)
			draw_rect(Rect2(Vector2(w - 1.0, -1.0), Vector2(2.0, size.y + 2.0)), Color(color, 0.9), true)


# Capsule button. Hover sweeps a tint in from the left and lifts a soft glow;
# a press (or ping(), e.g. its hotkey) sends a ring out from the capsule and
# flashes it; becoming active fills it with the accent.
class Pill extends Button:
	var active := false:
		set(v):
			if v != active:
				active = v
				if v:
					_pulse = 1.0
				queue_redraw()
	var _hover := 0.0
	var _press := 0.0
	var _act := 0.0
	var _pulse := 0.0
	var label_font: Font

	func _init(t: String, w := 52.0, font: Font = null) -> void:
		text = t
		pressed.connect(func() -> void:
			Audio.sfx("ui_click", -4.0, randf_range(0.97, 1.04))
			_pulse = 1.0)
		flat = true
		focus_mode = Control.FOCUS_NONE
		custom_minimum_size = Vector2(w, 28)
		label_font = font if font else Ui.mono("Medium")
		add_theme_font_override("font", label_font)
		add_theme_font_size_override("font_size", 13)
		for s in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
			add_theme_color_override(s, Color(0, 0, 0, 0))
		for s in ["normal", "hover", "pressed", "focus", "hover_pressed"]:
			add_theme_stylebox_override(s, StyleBoxEmpty.new())
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	# Light it as if pressed (its action ran from the keyboard).
	func ping() -> void:
		_pulse = 1.0
		queue_redraw()

	func _process(delta: float) -> void:
		var k := minf(1.0, delta / Ui.T_FAST)
		var h := 1.0 if is_hovered() and not disabled else 0.0
		if h > 0.5 and _hover < 0.05 and GlassPanel.holo:
			Audio.sfx("holo_tick", -20.0, randf_range(0.95, 1.12))
		var p := 1.0 if button_pressed or (is_hovered() and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)) else 0.0
		var a := 1.0 if active else 0.0
		if absf(_hover - h) + absf(_press - p) + absf(_act - a) > 0.001 or _pulse > 0.0:
			_hover = lerpf(_hover, h, k)
			_press = lerpf(_press, p, k * 1.5)
			_act = lerpf(_act, a, k)
			_pulse = move_toward(_pulse, 0.0, delta / 0.45)
			queue_redraw()

	func _capsule(r: Rect2, fill: Color, border: Color, glow := 0.0) -> void:
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(int(minf(r.size.y, r.size.x) * 0.5))
		sb.bg_color = fill
		sb.border_color = border
		sb.set_border_width_all(1 if border.a > 0.0 else 0)
		if glow > 0.0:
			sb.shadow_color = Color(Ui.ACCENT, 0.22 * glow)
			sb.shadow_size = int(2.0 + 7.0 * glow)
		sb.anti_aliasing = true
		draw_style_box(sb, r)

	func _draw() -> void:
		if GlassPanel.holo:
			_draw_holo()
			return
		var r := Rect2(Vector2.ZERO, size).grow(-1.0 - 1.2 * _press)
		var e := 1.0 - pow(1.0 - _hover, 3.0)
		# Frame (with the hover glow), then the tint sweeping in from the left.
		_capsule(r, Color(1, 1, 1, 0.35 * e), Color(Ui.ACCENT, 0.35 + 0.5 * maxf(_hover, _act)), maxf(e, _act * 0.6))
		if e > 0.01 and _act < 0.99:
			var w := maxf(r.size.x * e, r.size.y)
			_capsule(Rect2(r.position, Vector2(w, r.size.y)), Color(Ui.ACCENT, 0.13 * e), Color(0, 0, 0, 0))
		if _act > 0.01:
			_capsule(r, Color(Ui.ACCENT, 0.9 * _act), Color(0, 0, 0, 0))
		if _pulse > 0.0:
			# The ring going out, and the flash.
			var ring := r.grow(1.0 + 9.0 * (1.0 - pow(_pulse, 2.0)))
			var sb := StyleBoxFlat.new()
			sb.set_corner_radius_all(int(ring.size.y * 0.5))
			sb.draw_center = false
			sb.border_color = Color(Ui.ACCENT, 0.7 * _pulse)
			sb.set_border_width_all(1)
			sb.anti_aliasing = true
			draw_style_box(sb, ring)
			_capsule(r, Color(1, 1, 1, 0.45 * _pulse * _pulse) if _act > 0.5 else Color(Ui.ACCENT, 0.28 * _pulse * _pulse), Color(0, 0, 0, 0))
		var col := Ui.INK.lerp(Color.WHITE, _act)
		var fs := 13
		var ts := label_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		draw_string(label_font, Vector2((size.x - ts.x) * 0.5, (size.y + fs * 0.72) * 0.5 - e * 0.8), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


	# Holographic button: no capsule. A hairline underline that, on hover,
	# grows bright from the centre with a glow; corner brackets slide in; a
	# light haze rises behind. Active: a solid underline, a diamond, accent
	# text. A press snaps the brackets out and splits the text's colours.
	func _draw_holo() -> void:
		var e := 1.0 - pow(1.0 - _hover, 3.0)
		var on := maxf(e, _act)
		var r := Rect2(Vector2.ZERO, size)
		var y := size.y - 2.0
		if on > 0.01:
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(1, 1, 1, 0.5 * e).lerp(Color(Ui.ACCENT, 0.12), _act * (1.0 - e * 0.5))
			sb.set_corner_radius_all(3)
			sb.shadow_color = Color(1, 1, 1, 0.45 * on)
			sb.shadow_size = 6
			draw_style_box(sb, r.grow(-1.0))
		draw_line(Vector2(2, y), Vector2(size.x - 2, y), Color(Ui.ACCENT, 0.28), 1.0)
		var w := (size.x - 4.0) * maxf(0.25 + 0.75 * e, _act)
		var cx := size.x * 0.5
		if on > 0.01:
			draw_line(Vector2(cx - w * 0.5, y), Vector2(cx + w * 0.5, y), Color(Ui.ACCENT, 0.18 * on), 5.0)
			draw_line(Vector2(cx - w * 0.5, y), Vector2(cx + w * 0.5, y), Color(Ui.ACCENT, on), 1.0 + _act)
		if _pulse > 0.0:
			draw_line(Vector2(2, y), Vector2(size.x - 2, y), Color(1, 1, 1, _pulse), 2.0)
		# Corner brackets.
		var ba := maxf(e, _pulse)
		if ba > 0.01:
			var out := 6.0 * (1.0 - e) + 7.0 * _pulse * _pulse
			var L := 5.0
			var col := Color(Ui.ACCENT, ba)
			for cx2 in [0, 1]:
				for cy2 in [0, 1]:
					var c := Vector2(-out if cx2 == 0 else size.x + out, -out * 0.4 if cy2 == 0 else size.y + out * 0.4)
					var sx := 1.0 if cx2 == 0 else -1.0
					var sy := 1.0 if cy2 == 0 else -1.0
					draw_line(c, c + Vector2(L * sx, 0), col, 1.2)
					draw_line(c, c + Vector2(0, L * sy), col, 1.2)
		var fs := 13
		var ts := label_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var tp := Vector2((size.x - ts.x) * 0.5 + 4.0 * _act, (size.y + fs * 0.72) * 0.5 - 1.0 - e)
		if _act > 0.01:
			# Diamond marker.
			var d := Vector2(tp.x - 9.0, size.y * 0.5 - 1.0)
			var k := 3.0 * _act
			draw_colored_polygon([d + Vector2(0, -k), d + Vector2(k, 0), d + Vector2(0, k), d + Vector2(-k, 0)], Ui.ACCENT)
		var col := Ui.INK.lerp(Ui.ACCENT.darkened(0.3), _act)
		draw_string_outline(label_font, tp, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0.97, 0.99, 1.0, 0.6))
		if _pulse > 0.05:
			var sp := 2.5 * _pulse
			draw_string(label_font, tp + Vector2(-sp, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 0.25, 0.45, 0.6 * _pulse))
			draw_string(label_font, tp + Vector2(sp, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.1, 0.85, 1.0, 0.6 * _pulse))
		draw_string(label_font, tp, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


# Coloured dot used as a species / status marker.
class Chip extends Control:
	var color := Ui.ACCENT

	func _init(c: Color, d := 10.0) -> void:
		color = c
		custom_minimum_size = Vector2(d, d)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		draw_circle(c, size.x * 0.5, Color(color, 0.25))
		draw_circle(c, size.x * 0.32, color)


# Microscope tier gauge: 宏观 · 群体 · 显微 with a marker that glides to the
# tier the zoom is in, and the magnification under it.
class TierGauge extends Control:
	const NAMES := ["宏观", "群体", "显微"]
	var tier := 1
	var mag := 1.0
	var _x := 1.0
	var font: Font

	func _init() -> void:
		custom_minimum_size = Vector2(150, 36)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		font = Ui.sans(600)

	func set_state(t: int, m: float) -> void:
		if t != tier or absf(m - mag) > 0.05:
			tier = t
			mag = m
			queue_redraw()

	func _process(delta: float) -> void:
		if absf(_x - tier) > 0.002:
			_x = lerpf(_x, tier, minf(1.0, delta / Ui.T_FAST))
			queue_redraw()

	func _draw() -> void:
		var w := size.x / 3.0
		for i in 3:
			var on := clampf(1.0 - absf(_x - i), 0.0, 1.0)
			var col := Ui.INK_FAINT.lerp(Ui.ACCENT, on)
			var ts := font.get_string_size(NAMES[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
			draw_string(font, Vector2(w * i + (w - ts.x) * 0.5, 14), NAMES[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)
		draw_line(Vector2(4, 20), Vector2(size.x - 4, 20), Color(Ui.LINE, 0.6), 1.0)
		var cx := w * (_x + 0.5)
		draw_line(Vector2(cx - 12, 20), Vector2(cx + 12, 20), Ui.ACCENT, 2.0)
		var mf := Ui.mono()
		var txt := "×%.1f" % mag
		var ms := mf.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10)
		draw_string(mf, Vector2((size.x - ms.x) * 0.5, 33), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Ui.INK_FAINT)
