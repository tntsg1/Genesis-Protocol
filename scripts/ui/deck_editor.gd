extends Control
# Behaviour deck editor (M2). The deck is a list of cards {c1, t1, c2, t2, act}
# (scripts/rules.gd). Cards are laid out by hand so every change animates:
# new cards grow in, deleted ones fold away, reordered ones glide.
# Interactions (mouse and keyboard):
#   drag a library piece onto a card     set a condition / the action
#   click a library piece                same, on the selected card (or a new one)
#   pick a card up by its handle (⋮⋮)    reorder: the card follows, the
#                                        others make room (see lift)
#   drag a threshold knob                change X
#   click × on a condition / on a card   remove it
#   Ctrl+Z                               undo

signal changed

const CARD_W := 0.0 # width follows the editor
const GAP := 10.0
const CARD_H := 60.0 # one card: a single row

var deck: Array = []
var readonly := false # shown, not edited (level 1-2): select a card, nothing else
var logic := false # 不 / 或 are open (level 7 on, the sandbox): their toggles show
# States (DECISIONS 第十一轮): every card belongs to one; the editor shows the
# cards of `cur_state` only (the StateBar above switches it).
var cur_state := 0
signal state_changed
var slots := 5
var diet := 0
var selected := -1
var history: Array = []
var views: Array = [] # CardView per card, same order as deck
var _warn: Array = []


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	clip_contents = false
	# The cards take the editor's width in _process, which stops once they
	# settle: lay them out again whenever the editor is resized (it is 0 wide
	# while the rules page is still hidden).
	resized.connect(func() -> void: set_process(true))


func set_deck(d: Array, record := false) -> void:
	if record:
		_push_history()
	deck = d.duplicate(true)
	selected = clampi(selected, -1, deck.size() - 1)
	_sync_views()
	changed.emit()


func _push_history() -> void:
	history.append(deck.duplicate(true))
	if history.size() > 64:
		history.pop_front()


func undo() -> void:
	if history.is_empty():
		return
	deck = history.pop_back()
	selected = clampi(selected, -1, deck.size() - 1)
	_sync_views()
	changed.emit()


func edit(fn: Callable) -> void:
	# Every change goes through here: snapshot for undo, apply, relayout.
	_push_history()
	fn.call()
	_sync_views()
	changed.emit()


# --- operations ---------------------------------------------------------------------

func add_card(c := Rules.C_NONE, act := Rules.A_WANDER) -> int:
	if deck.size() >= slots:
		return -1
	var t: float = Rules.CONDS[c][4]
	var at := deck.size() if selected < 0 else selected + 1
	_insert_view(at)
	edit(func() -> void:
		var cd := Rules.card(c, t, Rules.C_NONE, 0.0, act)
		cd.st = cur_state
		deck.insert(at, cd)
		selected = at)
	return at


# Card k's place among the cards of its own state (the badge number).
func rank_in_state(k: int) -> int:
	var st := int(deck[k].get("st", 0)) if k < deck.size() else 0
	var n := 0
	for j in mini(k, deck.size()):
		if int(deck[j].get("st", 0)) == st:
			n += 1
	return n


func shown(k: int) -> bool:
	return k < deck.size() and int(deck[k].get("st", 0)) == cur_state


# Show another state's cards.
func set_state(st: int) -> void:
	if st == cur_state:
		return
	cur_state = st
	selected = -1
	for v: Control in views:
		v.modulate.a = 0.0
	_sync_views()
	state_changed.emit()


# The states with cards (forage always).
func states_used() -> Array:
	var out := [Rules.S_FORAGE]
	for cd: Dictionary in deck:
		var st := int(cd.get("st", 0))
		if not out.has(st):
			out.append(st)
	out.sort()
	return out


# A new state: it starts with one card (so it is in use) that leads back.
func add_state(st: int) -> void:
	if states_used().has(st):
		set_state(st)
		return
	edit(func() -> void:
		# (Breeding stays longer: the bot found 40 s beat 20 s at level 10.)
		var back := Rules.card(Rules.C_STATE_TIME, 40.0 if st == Rules.S_BREED else 20.0, Rules.C_NONE, 0.0, Rules.A_TO_FORAGE)
		back.st = st
		deck.append(back)
		# Sleep also gets a way in, so the new state works from the first try:
		# "no prey in sight for 15 s -> sleep", just above foraging's last card.
		# (Review round 3: two separate steps to wire up one state lost players.)
		if st == Rules.S_SLEEP and deck.size() < slots and not deck.any(func(cd: Dictionary) -> bool: return cd.act == Rules.A_TO_SLEEP):
			var nap := Rules.card(Rules.C_SEE_PREY, 0.0, Rules.C_STATE_TIME, 15.0, Rules.A_TO_SLEEP)
			nap.n1 = true
			var at := deck.size() - 1
			for k in deck.size():
				if int(deck[k].get("st", 0)) == Rules.S_FORAGE:
					at = k
			deck.insert(at, nap)
		# Alert comes with what alert is for: "hunter near -> flee" above
		# its way back (level 9 teaches wiring the way in and the calm-down).
		# (At 100 µm: alert sees 30% further, and a flee nearer than the way in
		# left them tense but standing; the bot lost a third of its wins.)
		if st == Rules.S_ALERT and deck.size() < slots:
			var run := Rules.card(Rules.C_PREDATOR_NEAR, 100.0, Rules.C_NONE, 0.0, Rules.A_FLEE)
			run.st = st
			deck.insert(deck.size() - 1, run)
		# Breeding comes ready to breed: flee, split, graze, then its way back
		# (level 10 teaches the way in: "full -> breed" in foraging).
		if st == Rules.S_BREED:
			for cd: Dictionary in [Rules.card(Rules.C_PREDATOR_NEAR, 100.0, Rules.C_NONE, 0.0, Rules.A_FLEE),
					Rules.card(Rules.C_ENERGY_ABOVE, 1.0, Rules.C_NONE, 0.0, Rules.A_DIVIDE),
					Rules.card(Rules.C_ENERGY_BELOW, 1.0, Rules.C_SEE_ALGAE, 0.0, Rules.A_SEEK_ALGAE)]:
				if deck.size() >= slots:
					break
				cd.st = st
				deck.insert(deck.size() - 1, cd))
	set_state(st)


# Remove a state with its cards (Ctrl+Z brings them back).
func remove_state(st: int) -> void:
	if st == Rules.S_FORAGE:
		return
	edit(func() -> void:
		deck = deck.filter(func(cd: Dictionary) -> bool: return int(cd.get("st", 0)) != st)
		selected = -1)
	set_state(Rules.S_FORAGE)


func remove_card(k: int) -> void:
	if k < 0 or k >= deck.size():
		return
	# The card folds away where it is; the ones below glide up.
	var v: CardView = views[k]
	views.remove_at(k)
	v.dying = true
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tw := Ui.tween(v)
	tw.tween_property(v, "modulate:a", 0.0, Ui.T_FAST)
	tw.parallel().tween_property(v, "scale", Vector2(0.96, 0.96), Ui.T_FAST)
	tw.tween_callback(v.queue_free)
	edit(func() -> void:
		deck.remove_at(k)
		if selected >= deck.size():
			selected = deck.size() - 1)


func move_card(from: int, to: int) -> void:
	if from == to or from < 0 or from >= deck.size():
		return
	to = clampi(to, 0, deck.size() - 1)
	var v: CardView = views[from]
	views.remove_at(from)
	views.insert(to, v)
	edit(func() -> void:
		var c: Dictionary = deck[from]
		deck.remove_at(from)
		deck.insert(to, c)
		selected = to)


func set_condition(k: int, slot: int, c: int) -> void:
	edit(func() -> void:
		var cd: Dictionary = deck[k]
		# Fill the first slot first; a second condition goes in slot 2.
		if slot == 2 and cd.c1 == Rules.C_NONE:
			slot = 1
		cd["c%d" % slot] = c
		cd["t%d" % slot] = Rules.CONDS[c][4]
		selected = k)


func clear_condition(k: int, slot: int) -> void:
	edit(func() -> void:
		var cd: Dictionary = deck[k]
		if slot == 1:
			cd.c1 = cd.c2
			cd.t1 = cd.t2
			cd.n1 = cd.get("n2", false)
		cd.c2 = Rules.C_NONE
		cd.t2 = 0.0
		cd.n2 = false
		cd.any = false)


# 不 on condition `slot`, or 且 <-> 或 between the two.
func toggle_neg(k: int, slot: int) -> void:
	edit(func() -> void:
		var key := "n%d" % slot
		deck[k][key] = not deck[k].get(key, false)
		selected = k)


func toggle_any(k: int) -> void:
	edit(func() -> void:
		deck[k].any = not deck[k].get("any", false)
		selected = k)


func set_action(k: int, a: int) -> void:
	edit(func() -> void:
		deck[k].act = a
		selected = k)


func set_threshold(k: int, slot: int, t: float, record: bool) -> void:
	if record:
		_push_history()
	deck[k]["t%d" % slot] = t
	views[k].queue_redraw()
	changed.emit()


# A library piece was clicked: put it on the selected card, or start a new one.
func apply_piece(kind: String, id: int) -> void:
	var k := selected
	if k < 0 or k >= deck.size():
		k = add_card(id if kind == "cond" else Rules.C_NONE, id if kind == "act" else Rules.A_WANDER)
		return
	if kind == "act":
		set_action(k, id)
	else:
		var cd: Dictionary = deck[k]
		set_condition(k, 1 if cd.c1 == Rules.C_NONE else 2, id)


# --- layout ---------------------------------------------------------------------------

func _insert_view(at: int) -> void:
	var v := CardView.new(self)
	v.position.y = _target_y(at) + 14.0
	v.modulate.a = 0.0
	add_child(v)
	views.insert(at, v)


func _sync_views() -> void:
	_warn = Rules.warnings(deck, diet)
	# Views follow their cards (see add/remove/move); fix any count mismatch
	# (a whole new deck, undo) at the end.
	while views.size() < deck.size():
		_insert_view(views.size())
	while views.size() > deck.size():
		var v: CardView = views.pop_back()
		var t := Ui.tween(v)
		t.tween_property(v, "modulate:a", 0.0, Ui.T_FAST)
		t.tween_callback(v.queue_free)
	for k in views.size():
		var v: CardView = views[k]
		v.index = k
		v.queue_redraw()
	set_process(true)


func card_height(k: int) -> float:
	if not shown(k):
		return 0.0
	# One row reads as one sentence: 如果 … 且 … → 那么 …; a warning adds a line.
	return CARD_H + (22.0 if warning(k) != "" else 0.0)


func _target_y(k: int) -> float:
	var y := 0.0
	for j in mini(k, deck.size()):
		if shown(j):
			y += card_height(j) + GAP
	return y


func content_height() -> float:
	return _target_y(deck.size())


# On-screen rect of card k (the guide rings it); empty while not laid out.
func card_rect(k: int) -> Rect2:
	for v: Control in views:
		if v.index == k and v.size.x > 0.0:
			return v.get_global_rect()
	return Rect2()


# On-screen rect of the first threshold slider on a card with this action
# (the guide rings it); empty while not laid out.
func slider_rect(act: int) -> Rect2:
	for v: Control in views:
		if v.index < deck.size() and deck[v.index].act == act and v.hits.has("track1"):
			var r: Rect2 = v.hits.track1
			return Rect2(v.get_global_transform() * r.position, r.size).grow_individual(10, 12, 70, 12)
	return Rect2()


func warning(k: int) -> String:
	if k >= slots:
		return "超出卡槽：投放前删掉它，或提高神经容量"
	return _warn[k] if k < _warn.size() else ""


func _process(delta: float) -> void:
	# Room below the cards for the "new rule" slot a dragged piece can fill.
	custom_minimum_size.y = content_height() + (CARD_H + GAP if not readonly else 0.0)
	var moving := lift >= 0
	_edge_scroll(delta)
	var y := 0.0
	var k_ease := 1.0 - exp(-delta * 16.0)
	# The order on show: while a card is carried, the others close up round
	# the gap it would drop into.
	var order := range(views.size())
	if lift >= 0:
		order.erase(lift)
		var shown_others := order.filter(func(j: int) -> bool: return shown(j))
		var at := order.size() if lift_pos >= shown_others.size() else order.find(shown_others[lift_pos])
		order.insert(at, lift)
	for k: int in order:
		var v: CardView = views[k]
		v.visible = shown(k)
		if not v.visible:
			continue
		var h := card_height(k)
		v.size = Vector2(size.x, h)
		v.pivot_offset = v.size * 0.5
		var carried := k == lift
		var target := lift_y if carried else y
		var ny := target if carried else lerpf(v.position.y, y, k_ease)
		if absf(ny - target) < 0.3:
			ny = target
		moving = moving or ny != v.position.y or v.modulate.a < 1.0
		v.position = Vector2(0, ny)
		var sc := 1.02 if carried else 1.0
		v.scale = v.scale.lerp(Vector2.ONE * sc, k_ease)
		v.z_index = 5 if carried else 0
		moving = moving or absf(v.scale.x - sc) > 0.001
		v.modulate.a = minf(1.0, v.modulate.a + delta / Ui.T_MID)
		y += h + GAP
	if not moving:
		set_process(false)


# While a card is carried near the top or bottom of the scrolling list, the
# list scrolls (the top card may be out of sight), and the card keeps under
# the pointer.
func _edge_scroll(delta: float) -> void:
	if lift < 0 or not _lift_ptr.is_finite():
		return
	var sc := get_parent() as ScrollContainer
	if sc == null:
		return
	var r := sc.get_global_rect()
	var edge := 56.0
	var v := 0.0
	if _lift_ptr.y < r.position.y + edge:
		v = -clampf((r.position.y + edge - _lift_ptr.y) / edge, 0.0, 1.5)
	elif _lift_ptr.y > r.end.y - edge:
		v = clampf((_lift_ptr.y - (r.end.y - edge)) / edge, 0.0, 1.5)
	if v == 0.0:
		return
	var before := sc.scroll_vertical
	sc.scroll_vertical = int(before + v * 700.0 * delta)
	if sc.scroll_vertical != before:
		_drag_to((get_global_transform().affine_inverse() * _lift_ptr).y)


# --- reordering: the card itself is picked up -------------------------------------
# 2026-10-30 ("整个卡片能够拖动，而不是往上拖了覆盖然后直接交换"): pressing ⋮⋮
# lifts the whole card; it follows the pointer up and down, the others slide
# aside to show the gap it would go into, and letting go sets it there.

var lift := -1 # the deck index being carried
var lift_y := 0.0 # its top, following the pointer
var lift_pos := 0 # the gap among the other shown cards it would drop into
var _lift_grab := 0.0
var _lift_ptr := Vector2.INF # the pointer while carrying, global (to scroll the list at its edges)


func begin_lift(k: int, local_y: float) -> void:
	if readonly or k < 0 or k >= views.size():
		return
	lift = k
	lift_y = views[k].position.y
	_lift_grab = local_y - lift_y
	lift_pos = _gap_for(local_y)
	selected = k
	Audio.sfx("ui_click", -8.0, 0.9)
	set_process(true)
	for v in views:
		v.queue_redraw()


# The gap the pointer at `cy` points into among the others on show (by the
# pointer, not the carried card's middle: a tall card, one with a warning
# line, could never reach the top that way; above the list is the top).
func _gap_for(cy: float) -> int:
	var y := 0.0
	var p := 0
	for j in deck.size():
		if j == lift or not shown(j):
			continue
		var h := card_height(j)
		if cy > y + h * 0.5:
			p += 1
		y += h + GAP
	return p


func _input(event: InputEvent) -> void:
	if lift < 0:
		return
	if event is InputEventMouseMotion:
		_lift_ptr = (event as InputEventMouseMotion).global_position
		_drag_to(make_input_local(event).position.y)
	elif event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		end_lift()
		get_viewport().set_input_as_handled()


# The carried card follows the pointer (local y) and the gap updates.
func _drag_to(my: float) -> void:
	if lift < 0:
		return
	lift_y = clampf(my - _lift_grab, 0.0, maxf(0.0, content_height() - card_height(lift) - GAP))
	var p := _gap_for(my)
	if p != lift_pos:
		lift_pos = p
		Audio.sfx("holo_tick", -16.0, 1.2)
	set_process(true)


# Set the carried card down in its gap (a move only when the gap is another).
func end_lift() -> void:
	if lift < 0:
		return
	var from := lift
	var others := range(deck.size()).filter(func(j: int) -> bool: return j != from and shown(j))
	var to := from
	if not others.is_empty():
		if lift_pos < others.size():
			var x: int = others[lift_pos]
			to = x - (1 if from < x else 0)
		else:
			var last: int = others.back()
			to = last - (1 if from < last else 0) + 1
	lift = -1
	_lift_ptr = Vector2.INF
	move_card(from, to)
	selected = to
	set_process(true)
	for v in views:
		v.queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		selected = -1
		for v in views:
			v.queue_redraw()


# --- drop feedback ----------------------------------------------------------------
# Nothing lights up until a drag is under way, and then only the one place it
# would land (2026-10-29: "只有在鼠标按下并碰到下一个方块时，才会在下一个方块上
# 显示一个框"): a slot on a card, the gap a card would move into, or the empty
# "new rule" slot under the deck.

var insert_at := -1 # a dragged card would land before this card (deck index)
var ghost := false # a dragged piece would start a new card


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END or what == NOTIFICATION_MOUSE_EXIT:
		_clear_drop()


func _clear_drop() -> void:
	if insert_at >= 0 or ghost:
		insert_at = -1
		ghost = false
		queue_redraw()


func set_insert(k: int) -> void:
	if k != insert_at or ghost:
		insert_at = k
		ghost = false
		queue_redraw()


func _ghost_rect() -> Rect2:
	return Rect2(0, content_height(), size.x, CARD_H)


func _can_drop_data(at: Vector2, data: Variant) -> bool:
	if readonly or not data is Dictionary:
		return false
	if data.has("card"):
		# Below the last card: move it to the end.
		set_insert(deck.size())
		return true
	var ok: bool = data.has("piece") and deck.size() < slots and _ghost_rect().has_point(at)
	if ok != ghost or insert_at >= 0:
		ghost = ok
		insert_at = -1
		queue_redraw()
	return ok


func _drop_data(_at: Vector2, data: Variant) -> void:
	_clear_drop()
	if data.has("card"):
		move_card(data.card, deck.size() - 1)
		return
	selected = -1
	apply_piece(data.piece, data.id)


func _draw() -> void:
	if ghost:
		var r := _ghost_rect()
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(10)
		sb.anti_aliasing = true
		sb.bg_color = Color(Ui.ACCENT, 0.07)
		sb.border_color = Ui.ACCENT
		sb.set_border_width_all(2)
		draw_style_box(sb, r.grow(-1.0))
		draw_string(Ui.sans(600), Vector2(24, r.position.y + r.size.y * 0.5 + 5), "放开：新建一张规则", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Ui.ACCENT)
	if insert_at >= 0:
		# The gap the card would move into: a bright bar with end caps.
		var y := _target_y(insert_at) - GAP * 0.5
		draw_line(Vector2(8, y), Vector2(size.x - 8, y), Ui.ACCENT, 2.0, true)
		draw_circle(Vector2(8, y), 4.0, Ui.ACCENT)
		draw_circle(Vector2(size.x - 8, y), 4.0, Ui.ACCENT)


# One card. Draws itself and keeps hit rectangles for its parts.
class CardView extends Control:
	var ed: Control
	var index := 0
	var dying := false
	var dragging := false
	var _hover := 0.0
	var zone := "" # the slot a drag over this card would fill: g1 / g2 / act
	var hits := {} # name -> Rect2
	var _slider := 0 # condition slot whose knob is being dragged
	var _drag_from := Vector2.ZERO

	func _init(editor: Control) -> void:
		ed = editor
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _cd() -> Dictionary:
		return ed.deck[index] if index < ed.deck.size() else {}

	func _process(delta: float) -> void:
		var h := 1.0 if get_global_rect().has_point(get_global_mouse_position()) else 0.0
		if absf(_hover - h) > 0.001:
			_hover = lerpf(_hover, h, minf(1.0, delta / Ui.T_FAST))
			if absf(_hover - h) < 0.01:
				_hover = h
			queue_redraw()

	func _notification(what: int) -> void:
		if (what == NOTIFICATION_DRAG_END or what == NOTIFICATION_MOUSE_EXIT) and zone != "":
			zone = ""
			queue_redraw()

	# -- input --
	func _gui_input(event: InputEvent) -> void:
		var cd := _cd()
		if cd.is_empty():
			return
		if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			var at: Vector2 = event.position
			if event.pressed and ed.readonly:
				ed.selected = index
				for v in ed.views:
					v.queue_redraw()
				accept_event()
				return
			if event.pressed:
				if hits.has("handle") and hits.handle.grow(6).has_point(at):
					ed.begin_lift(index, position.y + at.y)
					accept_event()
					return
				for s in [1, 2]:
					var key := "track%d" % s
					if hits.has(key) and hits[key].grow(8).has_point(at):
						_slider = s
						ed._push_history()
						_set_threshold_from(at.x)
						accept_event()
						return
				if hits.has("neg1") and hits.neg1.has_point(at):
					ed.toggle_neg(index, 1)
				elif hits.has("neg2") and hits.neg2.has_point(at):
					ed.toggle_neg(index, 2)
				elif hits.has("join") and hits.join.has_point(at):
					ed.toggle_any(index)
				elif hits.has("delete") and hits.delete.has_point(at):
					ed.remove_card(index)
				elif hits.has("x1") and hits.x1.has_point(at):
					ed.clear_condition(index, 1)
				elif hits.has("x2") and hits.x2.has_point(at):
					ed.clear_condition(index, 2)
				else:
					ed.selected = index
					for v in ed.views:
						v.queue_redraw()
				accept_event()
			else:
				_slider = 0
		elif event is InputEventMouseMotion and _slider > 0:
			_set_threshold_from(event.position.x)
			accept_event()

	func _set_threshold_from(px: float) -> void:
		var cd := _cd()
		var c: int = cd["c%d" % _slider]
		var spec: Array = Rules.CONDS[c]
		var r: Rect2 = hits["track%d" % _slider]
		var t := clampf((px - r.position.x) / r.size.x, 0.0, 1.0)
		var v: float = lerpf(spec[2], spec[3], t)
		v = snappedf(v, spec[5])
		ed.set_threshold(index, _slider, v, false)

	# -- drag and drop --
	# Only the ⋮⋮ handle picks a card up; the rest of the card is for its parts.
	# (A card is picked up by its handle in _gui_input: see the editor's lift.)
	func _get_drag_data(_at: Vector2) -> Variant:
		return null

	# The slot under the cursor for a dragged piece ("" = none here).
	func _zone_at(at: Vector2, data: Dictionary) -> String:
		var cd := _cd()
		if data.piece == "act":
			return "act" if hits.has("z_act") and hits.z_act.has_point(at) else ""
		if hits.has("z_g2") and hits.z_g2.has_point(at) and cd.c1 != Rules.C_NONE:
			return "g2"
		if hits.has("z_g1") and hits.z_g1.has_point(at):
			return "g1"
		return ""

	func _can_drop_data(at: Vector2, data: Variant) -> bool:
		if ed.readonly or not data is Dictionary:
			return false
		var z := ""
		var ok := false
		if data.has("card"):
			ok = true
			# Upper half: in front of this card; lower half: behind it.
			ed.set_insert(index + (1 if at.y > size.y * 0.5 else 0))
		elif data.has("piece"):
			z = _zone_at(at, data)
			ok = z != ""
			ed._clear_drop()
		if z != zone:
			zone = z
			queue_redraw()
		return ok

	func _drop_data(at: Vector2, data: Variant) -> void:
		var z := zone
		zone = ""
		if data.has("card"):
			var to: int = ed.insert_at
			ed._clear_drop()
			var from: int = data.card
			if to > from:
				to -= 1
			ed.move_card(from, to)
			return
		if data.piece == "act":
			ed.set_action(index, data.id)
		else:
			ed.set_condition(index, 2 if z == "g2" else 1, data.id)

	# -- drawing --
	func _chip(x: float, y: float, text: String, col: Color, filled: bool, key: String, closable: bool) -> float:
		var f := Ui.sans(600)
		var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + (36.0 if closable else 22.0)
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(12)
		sb.bg_color = col if filled else Color(col, 0.1)
		sb.border_color = Color(col, 0.7)
		sb.set_border_width_all(1)
		sb.anti_aliasing = true
		var r := Rect2(x, y, w, 24)
		closable = closable and not ed.readonly
		draw_style_box(sb, r)
		draw_string(f, Vector2(x + 11, y + 17), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE if filled else Ui.INK)
		hits[key] = r
		if closable:
			var xr := Rect2(x + w - 22, y + 4, 16, 16)
			hits["x" + key.substr(4)] = xr
			var a := 0.35 + 0.65 * _hover
			var c := xr.get_center()
			draw_line(c - Vector2(3.5, 3.5), c + Vector2(3.5, 3.5), Color(Ui.INK_SOFT, a), 1.4, true)
			draw_line(c + Vector2(-3.5, 3.5), c + Vector2(3.5, -3.5), Color(Ui.INK_SOFT, a), 1.4, true)
		return x + w + 8.0

	# An empty slot: a dashed outline with a quiet label.
	func _empty_slot(r: Rect2, text: String) -> void:
		var col := Color(Ui.INK_FAINT, 0.6)
		var pts := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), r.position]
		for i in 4:
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			var n := int(a.distance_to(b) / 7.0)
			for j in n:
				if j % 2 == 0:
					draw_line(a.lerp(b, float(j) / n), a.lerp(b, float(j + 1) / n), col, 1.0, true)
		draw_string(Ui.sans(500), Vector2(r.position.x + 11, r.position.y + 17), text, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 16, 12, Ui.INK_FAINT)

	# A threshold slider from x to x + w, centred on y, its value after it.
	func _slider_row(s: int, c: int, t: float, x: float, w: float, y: float) -> void:
		var spec: Array = Rules.CONDS[c]
		var track := Rect2(x, y - 1, maxf(40.0, w), 2)
		hits["track%d" % s] = track
		var u := (t - float(spec[2])) / (float(spec[3]) - float(spec[2]))
		draw_rect(track, Color(Ui.LINE, 0.6))
		draw_rect(Rect2(track.position, Vector2(track.size.x * u, 2)), Ui.ACCENT)
		var kx := track.position.x + track.size.x * u
		if not ed.readonly:
			draw_circle(Vector2(kx, y), 5.5 + (1.5 if _slider == s else 0.0), Color.WHITE)
			draw_arc(Vector2(kx, y), 5.5, 0, TAU, 18, Ui.ACCENT, 1.5, true)
		else:
			draw_circle(Vector2(kx, y), 3.5, Ui.ACCENT)
		draw_string(Ui.mono("Medium"), Vector2(track.end.x + 12, y + 4), Rules.threshold_text(c, t), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Ui.INK)

	# The frame around the slot a drag would fill.
	func _drop_frame(r: Rect2) -> void:
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(9)
		sb.anti_aliasing = true
		sb.bg_color = Color(Ui.ACCENT, 0.08)
		sb.border_color = Ui.ACCENT
		sb.set_border_width_all(2)
		draw_style_box(sb, r)

	# One condition group: [不] chip, slider, value, inside g.
	func _cond_group(s: int, cd: Dictionary, g: Rect2, sel: bool, f: Font) -> void:
		var c: int = cd["c%d" % s]
		var y := g.position.y + (g.size.y - 24.0) * 0.5
		var neg: bool = cd.get("n%d" % s, false)
		var cx := g.position.x + 6.0
		if ed.logic and not ed.readonly:
			# 不: a round switch in front of the condition, shown on the card
			# under the cursor or selected (or when set): a column of them on
			# every card read as noise (review round 2).
			var nr := Rect2(cx, y + 1, 22, 22)
			hits["neg%d" % s] = nr
			var na := 1.0 if (neg or sel) else _hover
			if na > 0.01:
				draw_circle(nr.get_center(), 11.0, Color(Ui.WARN, 0.95) if neg else Color(Ui.WARN, (0.06 + 0.1 * _hover) * na))
				draw_arc(nr.get_center(), 11.0, 0, TAU, 24, Color(Ui.WARN, 0.7 * na), 1.0, true)
				draw_string(f, nr.get_center() + Vector2(-6, 5), "不", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE if neg else Color(Ui.WARN, 0.8 * na))
			else:
				draw_line(nr.get_center() + Vector2(-3, 0), nr.get_center() + Vector2(3, 0), Color(Ui.INK_FAINT, 0.35), 1.0, true)
			cx += 28.0
		elif neg:
			draw_string(f, Vector2(cx, y + 17), "不", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Ui.WARN)
			cx += 18.0
		var x := _chip(cx, y, Rules.CONDS[c][0], Ui.WARN if neg else Ui.ACCENT, false, "chip%d" % s, true)
		if Rules.has_threshold(c):
			_slider_row(s, c, float(cd["t%d" % s]), x + 8.0, g.end.x - x - 90.0, y + 12.0)

	func _draw() -> void:
		var cd := _cd()
		if cd.is_empty():
			return
		hits.clear()
		var sel: bool = ed.selected == index
		var over: bool = index >= ed.slots
		var warn: String = ed.warning(index)
		var r := Rect2(Vector2.ZERO, size)
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(10)
		sb.anti_aliasing = true
		sb.bg_color = Color(1, 1, 1, 0.4 if over else 0.66)
		sb.border_color = Ui.ACCENT if sel else Color(Ui.LINE_STRONG, 0.35)
		sb.set_border_width_all(2 if sel else 1)
		sb.shadow_color = Color(0.1, 0.3, 0.4, 0.05)
		sb.shadow_size = 4
		if ed.lift == index:
			# Picked up: solid, outlined, lifted off the page.
			sb.bg_color = Color(1, 1, 1, 0.97)
			sb.border_color = Ui.ACCENT
			sb.set_border_width_all(2)
			sb.shadow_color = Color(0.05, 0.3, 0.42, 0.2)
			sb.shadow_size = 22
			sb.shadow_offset = Vector2(0, 8)
		draw_style_box(sb, r.grow(-1.0))
		# The row: badge | 如果 [group 1] 且 [group 2] | → 那么 [action] | × ⋮⋮
		var row := Rect2(0, 0, size.x, CARD_H)
		var cy := row.get_center().y
		var f := Ui.sans(700)
		draw_circle(Vector2(30, cy), 13, Ui.ACCENT if sel else Color(Ui.ACCENT, 0.14))
		var num := str(ed.rank_in_state(index) + 1)
		var mono := Ui.mono("SemiBold")
		var nw := mono.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		draw_string(mono, Vector2(30 - nw * 0.5, cy + 5), num, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE if sel else Ui.ACCENT)
		# Two condition columns of a set width, the action right after them
		# (a wide panel left the action stranded at the far edge).
		var x0 := 96.0
		var gw := clampf((size.x - (330.0 if not ed.readonly else 250.0) - 24.0 - x0 - 44.0) * 0.5, 200.0, 320.0)
		var then_x := x0 + gw * 2.0 + 44.0 + 30.0
		var g1 := Rect2(x0, 8, gw, CARD_H - 16)
		var g2 := Rect2(x0 + gw + 44.0, 8, gw, CARD_H - 16)
		var ga := Rect2(then_x + 56.0, 8, minf(200.0, size.x - then_x - 56.0 - (96.0 if not ed.readonly else 16.0)), CARD_H - 16)
		# Drop zones (a little wider than the slots they fill).
		hits["z_g1"] = Rect2(60, 0, (g2.position.x - 22.0 if cd.c1 != Rules.C_NONE else then_x) - 60.0, CARD_H)
		hits["z_g2"] = Rect2(g2.position.x - 22.0, 0, then_x - g2.position.x + 22.0, CARD_H)
		hits["z_act"] = Rect2(then_x, 0, ga.end.x - then_x + 8.0, CARD_H)
		draw_string(f, Vector2(56, cy + 5), "如果", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Ui.INK_SOFT)
		if cd.c1 == Rules.C_NONE:
			_chip(g1.position.x + 6.0, cy - 12.0, "总是", Ui.INK_FAINT, false, "chip1", false)
			if not ed.readonly:
				draw_string(Ui.sans(500), Vector2(g1.position.x + 70.0, cy + 5), "（拖一个条件到这里）", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Ui.INK_FAINT)
		else:
			_cond_group(1, cd, g1, sel, f)
		var any: bool = cd.get("any", false)
		var jx := g1.end.x + 22.0
		if cd.c2 != Rules.C_NONE:
			if ed.logic and not ed.readonly:
				# 且 / 或: a small switch.
				var jr := Rect2(jx - 15.0, cy - 10.0, 30, 20)
				hits["join"] = jr
				var jsb := StyleBoxFlat.new()
				jsb.set_corner_radius_all(10)
				jsb.anti_aliasing = true
				jsb.bg_color = Color(Ui.ACCENT, 0.9) if any else Color(Ui.ACCENT, 0.08 + 0.08 * _hover)
				jsb.border_color = Color(Ui.ACCENT, 0.6)
				jsb.set_border_width_all(1)
				draw_style_box(jsb, jr)
				draw_string(f, Vector2(jx - 7.0, cy + 5), "或" if any else "且", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE if any else Ui.INK_SOFT)
			else:
				draw_string(f, Vector2(jx - 7.0, cy + 5), "或" if any else "且", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Ui.INK_SOFT)
			_cond_group(2, cd, g2, sel, f)
		elif cd.c1 != Rules.C_NONE and not ed.readonly and (sel or zone == "g2"):
			hits["chip2"] = Rect2(g2.position.x + 6.0, cy - 12.0, 132, 24)
			_empty_slot(hits.chip2, "且 第二个条件")
		# THEN: a thin arrow, then the action.
		var ax := then_x + 2.0
		draw_line(Vector2(ax - 18.0, cy), Vector2(ax - 4.0, cy), Color(Ui.INK_FAINT, 0.8), 1.2, true)
		draw_line(Vector2(ax - 9.0, cy - 4.0), Vector2(ax - 4.0, cy), Color(Ui.INK_FAINT, 0.8), 1.2, true)
		draw_line(Vector2(ax - 9.0, cy + 4.0), Vector2(ax - 4.0, cy), Color(Ui.INK_FAINT, 0.8), 1.2, true)
		draw_string(f, Vector2(then_x + 8.0, cy + 5), "那么", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Ui.INK_SOFT)
		_chip(ga.position.x, cy - 12.0, Rules.ACTS[cd.act][0], Ui.ACCENT, true, "act", false)
		# The one slot a dragged piece would fill.
		match zone:
			"g1": _drop_frame(Rect2(g1.position.x - 2.0, g1.position.y, (g1.size.x if cd.c1 != Rules.C_NONE else then_x - 40.0 - g1.position.x) + 4.0, g1.size.y))
			"g2": _drop_frame(g2.grow(2.0))
			"act": _drop_frame(Rect2(ga.position.x - 6.0, ga.position.y, ga.size.x + 8.0, ga.size.y))
		if not ed.readonly:
			# Delete, then the handle that picks the card up.
			var dr := Rect2(size.x - 82, cy - 11, 22, 22)
			hits["delete"] = dr
			var dc := dr.get_center()
			var da := 0.25 + 0.75 * _hover
			draw_arc(dc, 9, 0, TAU, 20, Color(Ui.ALERT, 0.35 * da), 1.0, true)
			draw_line(dc - Vector2(3.5, 3.5), dc + Vector2(3.5, 3.5), Color(Ui.ALERT, da), 1.4, true)
			draw_line(dc + Vector2(-3.5, 3.5), dc + Vector2(3.5, -3.5), Color(Ui.ALERT, da), 1.4, true)
			hits["handle"] = Rect2(size.x - 46, cy - 15, 26, 30)
			draw_line(Vector2(size.x - 52, 12), Vector2(size.x - 52, CARD_H - 12), Color(Ui.LINE, 0.5), 1.0)
			for k in 3:
				for j in 2:
					draw_circle(Vector2(size.x - 36 + j * 6, cy - 6 + k * 6), 1.5, Color(Ui.INK_FAINT, 0.55 + 0.45 * _hover))
		if warn != "":
			draw_string(Ui.sans(600), Vector2(56, CARD_H + 8.0), "⚠ " + warn, HORIZONTAL_ALIGNMENT_LEFT, size.x - 72, 11, Ui.WARN)
