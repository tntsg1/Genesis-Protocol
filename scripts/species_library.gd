class_name SpeciesLibrary
extends RefCounted
# Saved species designs: name, colour, genes, neural capacity and deck.
# Stored as JSON in user://. Test runs (-s / --script) use their own file so
# they can never touch the player's library.

const VERSION := 1


static func path() -> String:
	var args := OS.get_cmdline_args()
	if "-s" in args or "--script" in args:
		return "user://test_species_library.json"
	return "user://species_library.json"


static func load_all() -> Array:
	if not FileAccess.file_exists(path()):
		return []
	var f := FileAccess.open(path(), FileAccess.READ)
	if f == null:
		return []
	var data: Variant = JSON.parse_string(f.get_as_text())
	if data is Dictionary and data.get("version", 0) == VERSION and data.get("designs") is Array:
		return _decode(data.designs)
	return []


static func save_all(designs: Array) -> bool:
	var tmp := path() + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify({version = VERSION, designs = _encode(designs)}, "\t"))
	f.close()
	# Write then rename, so a crash mid-save never leaves a broken library.
	var dir := DirAccess.open("user://")
	if dir.file_exists(path().get_file()):
		dir.copy(path().get_file(), path().get_file() + ".bak")
	return dir.rename(tmp.get_file(), path().get_file()) == OK


static func _encode(designs: Array) -> Array:
	var out := []
	for d in designs:
		var e: Dictionary = d.duplicate(true)
		var c: Color = d.color
		e.color = [c.r, c.g, c.b]
		out.append(e)
	return out


static func _decode(raw: Array) -> Array:
	var out := []
	for e in raw:
		if not (e is Dictionary and e.has("genes") and e.has("deck")):
			continue
		var d: Dictionary = e.duplicate(true)
		var c: Array = e.get("color", [0.5, 0.6, 1.0])
		d.color = Color(c[0], c[1], c[2])
		for cd in d.deck:
			for k in ["c1", "c2", "act"]:
				cd[k] = int(cd[k])
		out.append(d)
	return out
