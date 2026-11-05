class_name Holo
extends RefCounted
# Shared pieces of the holographic interface (fourth round, reference: Death
# Stranding): text that types itself in, numbers that decode through
# scrambled digits, the glyphs that drift off panels.

const GLYPHS := "01ACGT+·:/▮▯◇"
const DIGITS := "0123456789"


# Every label under `root` types itself in (layout stays put: characters
# are hidden after shaping); readouts decode their digits instead.
static func type_in(root: Node, per_char := 0.018) -> void:
	for n in _labels(root):
		if not n.is_visible_in_tree():
			continue
		if n.get_parent() and n.get_parent().get_parent() is Widgets.Readout:
			(n.get_parent().get_parent() as Widgets.Readout).decode()
			continue
		var count := n.text.length()
		if count == 0:
			continue
		n.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
		n.visible_ratio = 0.0
		var t := n.create_tween()
		t.tween_property(n, "visible_ratio", 1.0, clampf(count * per_char, 0.12, 0.5)).set_delay(randf() * 0.12)


static func _labels(root: Node) -> Array[Label]:
	var out: Array[Label] = []
	for c in root.get_children():
		if c is Label:
			out.append(c)
		out.append_array(_labels(c))
	return out


# `text` with its digits not yet settled replaced by random ones (`k` 0..1 of
# the way through, settling from the left).
static func scramble(text: String, k: float) -> String:
	var out := ""
	var settled := int(k * text.length())
	for i in text.length():
		var ch := text[i]
		if i >= settled and DIGITS.contains(ch):
			ch = DIGITS[randi() % 10]
		out += ch
	return out
