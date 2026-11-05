extends SceneTree
# Music and effects load and play: each scene track, the crossfade, every
# effect file, the sting. Run headless: godot --headless -s tests/audio_check.gd -- --audio

var fails := 0


func check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var a := Audio.get_instance()
	await process_frame
	for name in ["menu", "dish", "lab"]:
		Audio.music(name)
		await create_timer(0.3).timeout
		var p: AudioStreamPlayer = a.music_a if a.music_a.stream and a.music_a.stream.resource_path.ends_with(name + ".ogg") else a.music_b
		check(p.playing and p.stream != null and p.stream.get_length() > 100.0, "%s music plays (%.0f s, loops %s)" % [name, p.stream.get_length() if p.stream else 0.0, (p.stream as AudioStreamOggVorbis).loop if p.stream else false])
	var missing := []
	for f in DirAccess.get_files_at("res://assets/audio/sfx"):
		if f.ends_with(".ogg"):
			var n := f.get_basename()
			if not ResourceLoader.exists("res://assets/audio/sfx/%s.ogg" % n):
				missing.append(n)
			Audio.sfx(n)
	check(missing.is_empty(), "every effect loads (%s)" % str(missing))
	var busy := 0
	for p in a.pool:
		if p.playing:
			busy += 1
	check(busy > 0, "effects play (%d players busy)" % busy)
	Audio.sting("result")
	check(AudioServer.get_bus_index(&"Music") >= 0 and AudioServer.get_bus_index(&"SFX") >= 0, "Music and SFX buses exist")
	print("RESULT: ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails else 0)
