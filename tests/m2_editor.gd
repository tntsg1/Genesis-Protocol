extends SceneTree
# M2 editor test, driven by input events pushed into the viewport (the OS
# mouse is never touched). Checks every interaction of the deck editor, the
# library save/load round trip, and that a released species' organisms carry
# exactly the edited deck. Run: tools/run_test.sh tests/m2_editor.gd

var scene: Node2D
var d: Control
var fails := 0


func _initialize() -> void:
	root.add_child(preload("res://tests/test_window.gd").new())
	scene = load("res://scenes/showcase.tscn").instantiate()
	scene.seed = 1000
	root.add_child(scene)
	current_scene = scene
	_run.call_deferred()


func _wait(n: int) -> void:
	for i in n:
		await process_frame


func check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func _mouse(at: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = at
	e.global_position = at
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	root.push_input(e)


var _last := Vector2.ZERO


func _move(at: Vector2, held: bool) -> void:
	var e := InputEventMouseMotion.new()
	# Godot starts a drag from the accumulated `relative`, so fill it in.
	e.relative = at - _last
	_last = at
	e.position = at
	e.global_position = at
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	root.push_input(e)


func click(at: Vector2) -> void:
	_move(at, false)
	await _wait(2)
	_mouse(at, true)
	await _wait(2)
	_mouse(at, false)
	await _wait(4)


func drag(from: Vector2, to: Vector2) -> void:
	_move(from, false)
	await _wait(2)
	_mouse(from, true)
	await _wait(2)
	for k in range(1, 13):
		_move(from.lerp(to, k / 12.0), true)
		await _wait(1)
	_mouse(to, false)
	await _wait(6)


# Screen centre of a control (the UI layer maps 1:1 to the 1920x1080 window).
func centre(c: Control) -> Vector2:
	return c.get_global_rect().get_center()


func _run() -> void:
	scene.advance(5.0)
	var lib_path := SpeciesLibrary.path()
	check(lib_path.contains("test_"), "tests use their own library file (%s)" % lib_path)
	if FileAccess.file_exists(lib_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(lib_path))
	scene.open_designer()
	d = scene.designer
	while d.busy: # the dive-in plays first and cannot be skipped
		await process_frame
	# The deck lives on the rules page.
	await click(centre(d.tab_buttons["rules"]))
	await _wait(30)
	var ed: Control = d.deck_editor
	check(ed.deck.size() == 4, "starts with the 4-card default deck")
	check(ed.slots == 5, "neural 3 gives 5 slots")

	# Add a card by clicking "+ 添加规则".
	await click(centre(d.add_button))
	await _wait(20)
	check(ed.deck.size() == 5, "clicking add creates a card")
	var k: int = ed.selected
	check(k == 4, "the new card is selected")
	# Click library pieces: a condition, a second condition, an action.
	var pieces := {}
	for chip in _all(d, d.PieceChip):
		pieces[chip.kind + str(chip.id)] = chip
	await click(centre(pieces["cond" + str(Rules.C_CROWD)]))
	await click(centre(pieces["cond" + str(Rules.C_ENERGY_BELOW)]))
	await click(centre(pieces["act" + str(Rules.A_FOLLOW)]))
	var cd: Dictionary = ed.deck[k]
	check(cd.c1 == Rules.C_CROWD and cd.c2 == Rules.C_ENERGY_BELOW and cd.act == Rules.A_FOLLOW,
		"clicking pieces fills the selected card: %s" % Rules.card_text(cd))
	await _wait(20)
	await _shot("m2_editor_built")
	# Drag the first threshold knob (crowd) to the far right -> 12.
	var view: Control = ed.views[k]
	var track: Rect2 = view.hits["track1"]
	var knob := view.get_global_rect().position + Vector2(track.position.x + track.size.x * (3.0 - 1.0) / 11.0, track.position.y + 1)
	await drag(knob, view.get_global_rect().position + Vector2(track.end.x + 20, track.position.y + 1))
	check(roundi(ed.deck[k].t1) == 12, "dragging the knob sets the threshold (got %s)" % ed.deck[k].t1)
	# Drag a library piece onto card 1 (replace its action with rest).
	var c0: Control = ed.views[0]
	await drag(centre(pieces["act" + str(Rules.A_REST)]), centre(c0))
	check(ed.deck[0].act == Rules.A_REST, "dropping an action piece on a card sets it")
	# Undo that.
	var e := InputEventKey.new()
	e.keycode = KEY_Z
	e.ctrl_pressed = true
	e.pressed = true
	root.push_input(e)
	await _wait(4)
	check(ed.deck[0].act == Rules.A_FLEE, "Ctrl+Z restores the previous action")
	# Reorder: drag card 5 by its handle onto card 1.
	var last: Control = ed.views[4]
	var handle: Rect2 = last.hits["handle"]
	var before: Dictionary = ed.deck[4].duplicate()
	await drag(last.get_global_rect().position + handle.get_center(), centre(ed.views[0]))
	await _wait(30)
	check(ed.deck[0].c1 == before.c1 and ed.deck[0].act == before.act, "dragging a card by its handle moves it to the top")
	# Slot limit: with 5 cards and 5 slots, add is disabled.
	check(d.add_button.disabled, "add is disabled when the slots are full")
	# Lower neural to 1 -> 3 slots -> release is blocked with a reason.
	d.gene_sliders[6].value = 1.0
	d.genes[6] = 1.0
	ed.slots = Rules.slots(1.0)
	ed._sync_views()
	d._refresh()
	await _wait(20)
	check(d.go.disabled and d.go_hint.text.contains("卡槽"), "too many cards for the slots blocks release: %s" % d.go_hint.text)
	await _shot("m2_editor_overflow")
	# Delete two cards with the × on the card.
	for n in 2:
		var v: Control = ed.views[ed.deck.size() - 1]
		await click(v.get_global_rect().position + v.hits["delete"].get_center())
		await _wait(10)
	check(ed.deck.size() == 3 and not d.go.disabled, "deleting cards with × unblocks release")
	# A warning: an unconditional rest card on top shadows the others.
	ed.set_deck([Rules.card(Rules.C_NONE, 0, 0, 0, Rules.A_REST)] + ed.deck.slice(0, 2), true)
	await _wait(10)
	check(ed.warning(1) != "", "a card below an unconditional rest card gets a warning")
	ed.undo()
	await _wait(10)
	# Save to the library, change something, load it back.
	d.name_edit.text = "测试物种"
	var saved_deck: Array = ed.deck.duplicate(true)
	d.save_design()
	var again := SpeciesLibrary.load_all()
	check(again.size() == 1 and again[0].name == "测试物种" and again[0].deck.size() == saved_deck.size(), "save writes the design to the library file")
	ed.set_deck(Rules.default_deck(0), true)
	await click(centre(d.tab_buttons["library"]))
	await _wait(40)
	await _shot("m2_library")
	d.load_design(again[0])
	await _wait(30)
	check(ed.deck.size() == saved_deck.size() and ed.deck[0].act == saved_deck[0].act, "loading a saved design restores its deck")
	await click(centre(d.tab_buttons["handbook"]))
	await _wait(40)
	await _shot("m2_handbook")
	await click(centre(d.tab_buttons["genome"]))
	await _wait(30)
	# Release and check the organisms carry the deck.
	var released_deck: Array = ed.deck.duplicate(true)
	d.release()
	while scene.designer != null: # the pull-out plays first
		await process_frame
	scene._do_release(Vector2(1000, 1000))
	await create_timer(scene.CAPSULE_OPEN + 0.2).timeout # it incubates first
	var s: int = scene.labels.size() - 1
	var pts: PackedVector2Array = scene.sim.get_positions(s)
	var info: Dictionary = scene.sim.get_agent(scene.sim.find_agent(pts[0], 3.0))
	var same: bool = info.deck.size() == released_deck.size()
	for j in mini(info.deck.size(), released_deck.size()):
		same = same and info.deck[j].act == released_deck[j].act and info.deck[j].c1 == released_deck[j].c1
	check(same, "released organisms carry the edited deck (%d cards)" % info.deck.size())
	check(info.slots == 3, "and the neural level (3 slots)")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(lib_path))
	print("RESULT: ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(0 if fails == 0 else 1)


func _all(node: Node, type) -> Array:
	var out := []
	for c in node.get_children():
		if is_instance_of(c, type):
			out.append(c)
		out.append_array(_all(c, type))
	return out


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://proofs/%s.png" % name))
