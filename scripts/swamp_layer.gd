class_name SwampLayer
extends Node2D
# Chapter 8 in the dish (design/第八章_腐土篇方案.md), under the cells:
#   the mud's layers: water clear above, then brown silt thickening down,
#     the deepest band dark and greenish where the sulfide is;
#   toxin A (rose) and B (teal) as soft clouds, acid rain soaking down as a
#     yellow-green stain (three field textures, coloured by a shader);
#   the slime mould (8-5): bright yellow tubes from its body to the food
#     points, the points flagged in the player's colour once held.
# `top` (added over the cells) draws the symbionts inside the cells that
# carry one: two or three small violet grains.

const MUD := Color(0.36, 0.26, 0.16)
const SULFIDE := Color(0.12, 0.16, 0.1)
const SLIME := Color(0.95, 0.8, 0.3)
const SLIME_EDGE := Color(0.7, 0.5, 0.12)
const PURPLE := Color(0.78, 0.5, 0.95)
const FIELD_SHADER := """
shader_type canvas_item;
uniform sampler2D tox_a : filter_linear;
uniform sampler2D tox_b : filter_linear;
uniform sampler2D rain : filter_linear;
void fragment() {
	float a = clamp(texture(tox_a, UV).r * 1.6, 0.0, 1.0);
	float b = clamp(texture(tox_b, UV).r * 1.6, 0.0, 1.0);
	float r = clamp(texture(rain, UV).r * 0.18, 0.0, 1.0);
	vec3 col = vec3(0.0);
	float al = 0.0;
	col += vec3(0.95, 0.35, 0.55) * a; al += a * 0.45;
	col += vec3(0.25, 0.85, 0.8) * b; al += b * 0.45;
	col += vec3(0.75, 0.85, 0.2) * r; al += r * 0.35;
	COLOR = vec4(col / max(a + b + r, 1e-3), clamp(al, 0.0, 0.6));
}
"""

var host: Node2D
var top: Node2D
var fields: Sprite2D
var tubes: Node2D
var mud := {}
var _t := 0.0
var _imgs := {}


func _init() -> void:
	fields = Sprite2D.new()
	fields.centered = false
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = FIELD_SHADER
	m.shader = sh
	fields.material = m
	add_child(fields)
	tubes = Node2D.new()
	tubes.draw.connect(_draw_slime)
	add_child(tubes)
	top = Node2D.new()
	top.draw.connect(_draw_symb)


func reset() -> void:
	var l: Dictionary = host.level_runner.level if host.level_runner else {}
	var w: Dictionary = l.get("world", {})
	mud = w.get("mud", {})
	# (The sandbox: always on, the mud when its switch is.)
	var sandbox: bool = host.level_runner == null
	if sandbox:
		mud = LevelsCh8.MUD if host.sandbox_world.is_on("mud") else {}
	visible = (l.get("id", "") as String).begins_with("8-") or sandbox
	top.visible = visible
	fields.visible = false
	_imgs.clear()
	queue_redraw()


func _process(delta: float) -> void:
	if not visible or host == null:
		return
	_t -= delta
	if _t <= 0.0:
		_t = 0.25
		_update_fields()
	tubes.queue_redraw()
	top.queue_redraw()


# The three fields as float textures (no per-cell loop in script).
func _update_fields() -> void:
	var sim: SimCore = host.sim
	var n := int(ceil(2200.0 / 16.0))
	var any := false
	var mat: ShaderMaterial = fields.material
	for key in ["tox_a", "tox_b", "rain"]:
		var f: PackedFloat32Array = sim.get_rain_field() if key == "rain" else sim.get_tox_field(0 if key == "tox_a" else 1)
		if f.size() != n * n:
			return
		var img := Image.create_from_data(n, n, false, Image.FORMAT_RF, f.to_byte_array())
		if _imgs.has(key):
			(_imgs[key] as ImageTexture).update(img)
		else:
			_imgs[key] = ImageTexture.create_from_image(img)
			mat.set_shader_parameter(key, _imgs[key])
		any = any or _max(f) > 0.01
	fields.texture = _imgs["tox_a"]
	fields.scale = Vector2(16.0, 16.0)
	fields.visible = any


func _max(f: PackedFloat32Array) -> float:
	var m := 0.0
	for k in range(0, f.size(), 7):
		m = maxf(m, f[k])
	return m


func _draw() -> void:
	if mud.is_empty():
		return
	# The mud: strips across the dish, clipped to its circle.
	var c: Vector2 = host.DISH_CENTER
	var r := 1060.0
	var y0 := float(mud.get("o2_full", 650.0))
	var y1 := c.y + r
	var steps := 48
	for k in steps:
		var a := lerpf(y0, y1, float(k) / steps)
		var b := lerpf(y0, y1, float(k + 1) / steps)
		var u := (a - y0) / maxf(1.0, y1 - y0)
		var hs := clampf((a - float(mud.get("h2s_from", 1150.0))) / maxf(1.0, float(mud.get("h2s_full", 1850.0)) - float(mud.get("h2s_from", 1150.0))), 0.0, 1.0)
		var col := MUD.lerp(SULFIDE, hs)
		col.a = 0.1 + 0.55 * u
		var ha := sqrt(maxf(0.0, r * r - (a - c.y) * (a - c.y)))
		var hb := sqrt(maxf(0.0, r * r - (b - c.y) * (b - c.y)))
		draw_colored_polygon(PackedVector2Array([Vector2(c.x - ha, a), Vector2(c.x + ha, a), Vector2(c.x + hb, b), Vector2(c.x - hb, b)]), col)
	# Silt specks, fixed.
	for k in 260:
		var p := Vector2(c.x + (fposmod(k * 0.618, 1.0) - 0.5) * 2.0 * r, lerpf(y0, y1, fposmod(k * 0.377 + 0.13, 1.0)))
		if p.distance_to(c) < r - 10.0:
			draw_circle(p, 1.2 + fposmod(k * 0.29, 1.0) * 1.8, Color(MUD.lightened(0.2), 0.35))


func _draw_slime() -> void:
	var s: Dictionary = host.sim.get_slime()
	if not bool(s.get("on", false)):
		return
	var zoom: float = host.cam.zoom.x
	var px := 1.0 / zoom
	var t := Time.get_ticks_msec() / 1000.0
	var dead := bool(s.get("dead", false))
	var fade := 0.35 if dead else 1.0
	var reach := float(s.get("reach", 12.0))
	for td: Dictionary in s.tubes:
		var pts: PackedVector2Array = td.pts
		if pts.size() < 2:
			continue
		tubes.draw_polyline(pts, Color(SLIME_EDGE, 0.35 * fade), reach * 1.6 + 3.0, true)
		tubes.draw_polyline(pts, Color(SLIME, 0.55 * fade), reach * 1.6, true)
		tubes.draw_polyline(pts, Color(1.0, 0.95, 0.7, 0.35 * fade), reach * 0.4, true)
		# Shuttle streaming: bright beads running out along the tube.
		var total := 0.0
		for k in range(1, pts.size()):
			total += pts[k].distance_to(pts[k - 1])
		var beads := int(total / 60.0)
		for b in beads:
			var at := fposmod(t * 30.0 + b * 60.0, maxf(total, 1.0))
			var acc := 0.0
			for k in range(1, pts.size()):
				var seg := pts[k].distance_to(pts[k - 1])
				if acc + seg >= at:
					tubes.draw_circle(pts[k - 1].lerp(pts[k], (at - acc) / maxf(seg, 0.01)), reach * 0.35, Color(1, 1, 0.85, 0.45 * fade))
					break
				acc += seg
	var c: Vector2 = s.center
	var core := float(s.get("core", 60.0))
	for k in 12:
		var a := TAU * k / 12.0 + 0.2 * sin(t * 0.7 + k)
		tubes.draw_circle(c + Vector2.from_angle(a) * core * 0.55, core * 0.5, Color(SLIME, 0.5 * fade))
	tubes.draw_circle(c, core, Color(SLIME, 0.8 * fade))
	tubes.draw_arc(c, core + 8.0, -PI * 0.5, -PI * 0.5 + TAU * clampf(float(s.get("energy_frac", 0.0)), 0.0, 1.0), 48, Color(SLIME_EDGE, 0.95), 3.0 * px, true)
	# The food points: a ring, the player's colour once held.
	var mine: Color = host.level_runner.design.get("params", {}).get("color", Ui.ACCENT) if host.level_runner else Ui.ACCENT
	var hold: Array = host.level_runner.eval.hold_t if host.level_runner and host.level_runner.eval else []
	var need := float(host.level_runner.level.get("slime", {}).get("hold_t", 15.0)) if host.level_runner else 15.0
	for k in (s.points as Array).size():
		var p: Dictionary = s.points[k]
		var at: Vector2 = p.pos
		var held := int(p.owner) == 1
		var col: Color = mine if held else (SLIME if bool(p.linked) else Color(1, 1, 1, 0.6))
		tubes.draw_arc(at, 150.0, 0, TAU, 72, Color(col, 0.7), 2.0 * px, true)
		if held:
			tubes.draw_circle(at, 150.0, Color(mine, 0.08))
		elif k < hold.size() and float(hold[k]) > 0.0:
			tubes.draw_arc(at, 158.0, -PI * 0.5, -PI * 0.5 + TAU * clampf(float(hold[k]) / need, 0.0, 1.0), 64, Color(mine, 0.95), 4.0 * px, true)


func _draw_symb() -> void:
	var pts: PackedVector2Array = host.sim.get_symb_positions()
	for p in pts:
		var h := fposmod(p.x * 0.137 + p.y * 0.071, 1.0)
		for g in 3:
			var a := TAU * (h + g / 3.0)
			top.draw_circle(p + Vector2.from_angle(a) * 2.6, 1.1, Color(PURPLE, 0.95))
