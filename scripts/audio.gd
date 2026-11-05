class_name Audio
extends Node
# Music and sound (DECISIONS, after the first playtest): one ambient track per
# scene (menu, dish, lab = the designer) crossfading as the player moves, a
# short sting on results, and sound effects from recorded material
# (assets/audio, made by tools/compose_music.py). Static helpers create the
# one instance on first use, so no autoload is needed (tests stay simple).
# Volumes (0..1) live in the settings file next to the keys.

const MUSIC := {menu = "res://assets/audio/music/menu.ogg", dish = "res://assets/audio/music/dish.ogg",
	lab = "res://assets/audio/music/lab.ogg", result = "res://assets/audio/music/result.ogg"}
const FADE := 2.2
# Minimum seconds between two plays of the same effect (frequent events).
const GAP := {bubble = 0.35, engulf = 0.5, mutation = 1.2, ui_click = 0.05, gene_up = 0.06, holo_on = 0.09, holo_tick = 0.05}

static var _me: Audio

var music_a: AudioStreamPlayer
var music_b: AudioStreamPlayer
var current := ""
var pool: Array[AudioStreamPlayer] = []
var cache := {}
var last := {}
var music_vol := 0.35 # 低 by default (playtest: the music was too loud)
var duck_db := 0.0 # pause: the music steps back and goes muffled
var _lpf: AudioEffectLowPassFilter
var _ducked := false
var sfx_vol := 0.8


static func get_instance() -> Audio:
	if _me == null or not is_instance_valid(_me):
		_me = Audio.new()
		_me.name = "Audio"
		(Engine.get_main_loop() as SceneTree).root.add_child.call_deferred(_me)
	return _me


# Scene music: crossfades to `name` ("" fades out).
static func music(name: String) -> void:
	get_instance()._music(name)


static func sfx(name: String, volume_db := 0.0, pitch := 1.0) -> void:
	get_instance()._sfx(name, volume_db, pitch)


# A short sting over the music (results), which ducks under it for a moment.
static func sting(name: String) -> void:
	get_instance()._sting(name)


# Paused: the music drops back and goes muffled (no bare drone over a
# frozen dish); resumed: it comes back.
static func duck(on: bool) -> void:
	get_instance()._duck(on)


static func set_volumes(m: float, s: float) -> void:
	var me := get_instance()
	me.music_vol = m
	me.sfx_vol = s
	me._apply_volumes()
	var cf := ConfigFile.new()
	cf.load(Keys.path())
	cf.set_value("audio", "music", m)
	cf.set_value("audio", "sfx", s)
	cf.save(Keys.path())


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	music_a = AudioStreamPlayer.new()
	music_b = AudioStreamPlayer.new()
	for p in [music_a, music_b]:
		p.bus = &"Music"
		p.volume_db = -80.0
		add_child(p)
	for k in 12:
		var p := AudioStreamPlayer.new()
		p.bus = &"SFX"
		add_child(p)
		pool.append(p)
	var cf := ConfigFile.new()
	if cf.load(Keys.path()) == OK:
		music_vol = float(cf.get_value("audio", "music", music_vol))
		sfx_vol = float(cf.get_value("audio", "sfx", sfx_vol))
	# Tests (-s) are silent unless asked (-- --audio): they run while the
	# player is at the desk.
	var args := OS.get_cmdline_args()
	if ("-s" in args or "--script" in args) and not "--audio" in OS.get_cmdline_user_args():
		music_vol = 0.0
		sfx_vol = 0.0
	_apply_volumes()


func _duck(on: bool) -> void:
	if on == _ducked:
		return
	_ducked = on
	var mi := AudioServer.get_bus_index(&"Music")
	if mi >= 0 and _lpf == null:
		_lpf = AudioEffectLowPassFilter.new()
		_lpf.cutoff_hz = 20000.0
		AudioServer.add_bus_effect(mi, _lpf)
	var t := create_tween().set_parallel()
	t.tween_method(func(v: float) -> void:
		duck_db = v
		_apply_volumes(), duck_db, -16.0 if on else 0.0, 0.6)
	if _lpf:
		t.tween_property(_lpf, "cutoff_hz", 700.0 if on else 20000.0, 0.6).set_trans(Tween.TRANS_SINE)


func _apply_volumes() -> void:
	var mi := AudioServer.get_bus_index(&"Music")
	var si := AudioServer.get_bus_index(&"SFX")
	if mi >= 0:
		AudioServer.set_bus_volume_db(mi, linear_to_db(maxf(music_vol, 0.0001)) + duck_db)
		AudioServer.set_bus_mute(mi, music_vol <= 0.001)
	if si >= 0:
		AudioServer.set_bus_volume_db(si, linear_to_db(maxf(sfx_vol, 0.0001)))
		AudioServer.set_bus_mute(si, sfx_vol <= 0.001)


func _stream(path: String) -> AudioStream:
	if not cache.has(path):
		cache[path] = load(path) if ResourceLoader.exists(path) else null
	return cache[path]


var _pending_music := "" # asked for before this node was in the tree


func _music(name: String) -> void:
	# The first request comes while the menu builds, a frame before this
	# node joins the tree (added deferred): play it once it is in.
	if not is_inside_tree():
		if _pending_music == "" and not ready.is_connected(_play_pending):
			ready.connect(_play_pending, CONNECT_ONE_SHOT)
		_pending_music = name
		return
	if name == current:
		return
	current = name
	var incoming := music_b if music_a.playing and music_a.volume_db > -40.0 else music_a
	var outgoing := music_a if incoming == music_b else music_b
	if name != "":
		var st := _stream(MUSIC[name])
		if st is AudioStreamOggVorbis:
			(st as AudioStreamOggVorbis).loop = true
		incoming.stream = st
		incoming.volume_db = -40.0
		incoming.play(randf() * 20.0 if name != "result" else 0.0)
		create_tween().tween_property(incoming, "volume_db", 0.0, FADE).set_trans(Tween.TRANS_SINE)
	var t := create_tween()
	t.tween_property(outgoing, "volume_db", -60.0, FADE).set_trans(Tween.TRANS_SINE)
	t.tween_callback(outgoing.stop)


func _play_pending() -> void:
	_music(_pending_music)


func _sting(name: String) -> void:
	var p := _free_player()
	p.bus = &"Music"
	p.stream = _stream(MUSIC[name])
	p.volume_db = -2.0
	p.pitch_scale = 1.0
	p.play()
	for m in [music_a, music_b]:
		if m.playing and m.volume_db > -30.0:
			var t := create_tween()
			t.tween_property(m, "volume_db", -14.0, 0.4)
			t.tween_interval(5.0)
			t.tween_property(m, "volume_db", 0.0, 3.0)


func _sfx(name: String, volume_db: float, pitch: float) -> void:
	if not is_inside_tree():
		return # created this very frame (it joins the tree deferred)
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(last.get(name, -10.0)) < float(GAP.get(name, 0.03)):
		return
	last[name] = now
	var st := _stream("res://assets/audio/sfx/%s.ogg" % name)
	if st == null:
		return
	var p := _free_player()
	p.bus = &"SFX"
	p.stream = st
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()


func _free_player() -> AudioStreamPlayer:
	for p in pool:
		if not p.playing:
			return p
	return pool[0]
