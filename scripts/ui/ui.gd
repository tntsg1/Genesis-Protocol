class_name Ui
extends RefCounted
# Design tokens and small helpers for the bright sci-fi lab UI
# (DECISIONS.md, "视觉与交互方向"): frosted light glass, hairline frames,
# cyan accent, monospaced readouts, scan/hologram motion.

# Ink (text) on light glass.
# Deep ink-blue (fifth round: the lens under the panels carries legibility,
# the ink carries contrast).
const INK := Color("13283a")
const INK_SOFT := Color("3e5868")
const INK_FAINT := Color("6f8693")
# Accent and states.
const ACCENT := Color("12a6bb")
const ACCENT_SOFT := Color(0.07, 0.65, 0.73, 0.16)
const GOOD := Color("3aa877")
const WARN := Color("df9f37")
const ALERT := Color("de6168")
# Frames.
const LINE := Color(0.24, 0.52, 0.62, 0.35)
const LINE_STRONG := Color(0.18, 0.5, 0.6, 0.7)
const GLASS := Color(0.975, 0.99, 1.0, 0.74)

# Type scale (px).
const SIZE_CAPTION := 12
const SIZE_BODY := 14
const SIZE_TITLE := 16
const SIZE_READOUT := 18
const SIZE_HERO := 30

# Motion (seconds). Everything eases out cubic unless noted.
const T_FAST := 0.14
const T_MID := 0.28
const T_SLOW := 0.6

static var _fonts := {}


static func sans(weight := 400) -> Font:
	var key := "sans%d" % weight
	if not _fonts.has(key):
		var f := FontVariation.new()
		f.base_font = load("res://assets/fonts/NotoSansSC-VF.ttf")
		# Variation axes are keyed by OpenType tag (an int), not by name.
		f.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
		_fonts[key] = f
	return _fonts[key]


static func mono(weight := "Regular") -> Font:
	var key := "mono" + weight
	if not _fonts.has(key):
		_fonts[key] = load("res://assets/fonts/JetBrainsMono-%s.ttf" % weight)
	return _fonts[key]


static func label(text: String, size := SIZE_BODY, color := INK, font: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font if font else sans())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if GlassPanel.holo:
		# No boxes behind text any more: a soft light halo keeps it legible
		# over the dish.
		l.add_theme_constant_override("outline_size", 5)
		l.add_theme_color_override("font_outline_color", Color(0.98, 0.995, 1.0, 0.42))
	l.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


# Small caps caption in the "中文 · ENGLISH" style used on every panel header.
static func caption(zh: String, en: String) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(label(zh, SIZE_CAPTION + 1, INK_SOFT, sans(600)))
	var e := label(en, SIZE_CAPTION - 1, INK_FAINT, mono("Medium"))
	e.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(e)
	return box


static func tween(node: Node) -> Tween:
	var t := node.create_tween()
	t.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	return t
