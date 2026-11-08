extends Node
# Environmental interventions (GDD 6, DECISIONS M4 Q4/Q5): the player cannot
# touch an organism, only the water. Each costs biomass points, which your
# own living organisms produce; each has a short cooldown and keys 1-4
# (scripts/ui/tool_tray.gd shows them).
#   nutrient  click: a pinch of nutrients (also a right click anywhere)
#   membrane  drag: a membrane nothing can cross, for 45 s
#   warm/cold click: a spot 12 deg C warmer or colder, for 40 s (its key again toggles)
#   current   drag: a current along the drag, for 30 s
#   irritant  click by the guardian's head (level 24, in the current's slot
#             and key): it draws its corona in for a few seconds
#   iron      click (chapter 6, in the phage's slot and key): iron dust soaks
#             up the oxygen there for 40 s, an anoxic patch
# In a campaign level only the level's interventions are open; the others
# show as locked. The showcase forwards input; this draws on its overlay.

const SPECS := {
	nutrient = {name = "营养投放", cost = 15.0, cool = 2.0, opens = 1},
	membrane = {name = "隔离膜", cost = 30.0, cool = 6.0, opens = 2},
	heat = {name = "局部升降温", cost = 35.0, cool = 8.0, opens = 4},
	current = {name = "洋流引导", cost = 30.0, cool = 6.0, opens = 5},
	phage = {name = "投放病毒", cost = 30.0, cool = 10.0, opens = 18},
	irritant = {name = "刺激头冠", cost = 30.0, cool = 8.0, opens = 24},
	iron = {name = "撒铁粉", cost = 35.0, cool = 8.0, opens = 27},
	brine = {name = "撒盐", cost = 35.0, cool = 8.0, opens = 31},
	stir = {name = "搅动泥层", cost = 30.0, cool = 8.0, opens = 35},
}
const ORDER := ["nutrient", "membrane", "heat", "current", "phage", "irritant", "iron", "brine", "stir"]
const STIR_R := 200.0 # chapter 8: stirring carries oxygen down into the mud and thins the sulfide
const STIR_TIME := 30.0
const BRINE_R := 170.0 # chapter 7: salt keeps the water there from freezing (sea-ice brine channels)
const BRINE_TIME := 60.0
const IRON_R := 220.0 # chapter 6: iron dust soaks up the oxygen here (banded iron formations)
const IRON_TIME := 40.0
const IRRITANT_REACH := 170.0 # how near its head a drop must land (µm)
const PHAGE_R := 90.0
const PHAGE_N := 80
const MEMBRANE_TIME := 45.0
const HEAT_TIME := 40.0
const CURRENT_TIME := 30.0
const MAX_POINTS := 300.0

var host: Node2D
var points := 60.0
var cooldown := {}
var cold := false # the warm/cold switch for "heat"
var drag_from := Vector2.INF
var drag_to := Vector2.INF
var _income_t := 0.0
var used := {} # kind -> times used this run (the guide waits on it)
var puffs := [] # level 24: irritant drops, [where, when] (drawn while they spread)


func reset(start_points := 60.0) -> void:
	points = start_points
	cooldown.clear()
	used.clear()
	puffs.clear()
	drag_from = Vector2.INF


func open_here(kind: String) -> bool:
	var l: Dictionary = host.level_runner.level if host.level_runner else {}
	return l.is_empty() or l.get("interventions", []).has(kind)


# Free and never cooling down: the sandbox (no level running; 2026-10-30
# "这个也弄成无限的"), or developer mode's switch.
func unlimited() -> bool:
	return DevMode.on(DevMode.free_iv) or host.level_runner == null


func ready_to_use(kind: String) -> bool:
	if unlimited():
		return open_here(kind)
	return open_here(kind) and points >= SPECS[kind].cost and cooldown.get(kind, 0.0) <= 0.0


func why_not(kind: String) -> String:
	if not open_here(kind):
		return "%s 在第 %d 关开放" % [SPECS[kind].name, SPECS[kind].opens]
	if points < SPECS[kind].cost:
		return "生物质点不足：%s 需要 %d 点" % [SPECS[kind].name, int(SPECS[kind].cost)]
	return "%s 冷却中" % SPECS[kind].name


# Your own organisms make biomass points: the released species in the sandbox
# (plus a trickle), the designed species in a level.
func tick(sim_dt: float) -> void:
	for k in cooldown:
		cooldown[k] = maxf(0.0, cooldown[k] - sim_dt)
	_income_t += sim_dt
	if _income_t < 0.5:
		return
	var dt := _income_t
	_income_t = 0.0
	var mine := 0
	if host.level_runner:
		if host.level_runner.sp_index >= 0:
			mine = host.sim.get_positions(host.level_runner.sp_index).size()
	else:
		for i in range(host.base_species, host.colors.size()):
			mine += host.sim.get_positions(i).size()
	var rate := 0.5 + 0.05 * minf(float(mine), 400.0)
	if not host.level_runner:
		rate += 1.5
	points = minf(MAX_POINTS, points + rate * dt)


# Level 24 puts the irritant in the current's slot (its card, its key).
func slot_kind(kind: String) -> String:
	if host.level_runner == null:
		return kind # (the sandbox: every tool in its own slot)
	if kind == "phage" and open_here("iron"):
		return "iron"
	if kind == "phage" and open_here("stir"):
		return "stir"
	if kind == "heat" and open_here("brine"):
		return "brine"
	return "irritant" if kind == "current" and open_here("irritant") else kind


# Pick an intervention (dock button or key). Picking heat again flips it.
func select(kind: String) -> void:
	kind = slot_kind(kind)
	# The sandbox: the virus is the player's own design (the designer's
	# 病毒设计 page) and needs a host picked first.
	if kind == "phage" and host.level_runner == null and host.sandbox_world.virus_host < 0:
		host.hud_root.notify("先在生命设计器的「病毒设计」页设计病毒、选好它感染谁", Ui.WARN)
		Audio.sfx("ui_deny")
		return
	if host.mode == kind:
		if kind == "heat":
			cold = not cold
			_hint(kind)
			return
		host.set_mode("")
		return
	if not ready_to_use(kind):
		host.hud_root.notify(why_not(kind), Ui.WARN)
		Audio.sfx("ui_deny")
		return
	host.set_mode(kind)
	_hint(kind)


func _hint(kind: String) -> void:
	var t := ""
	match kind:
		"nutrient": t = "点击培养皿投放营养（%d 点）　·　右键 / Esc 取消" % int(SPECS.nutrient.cost)
		"membrane": t = "按住拖出一道隔离膜，45 秒内谁也过不去（%d 点）　·　右键 / Esc 取消" % int(SPECS.membrane.cost)
		"heat": t = "点击放一个%s点，持续 40 秒（%d 点）　·　再按 %s 切换%s　·　右键 / Esc 取消" % ["降温" if cold else "升温", int(SPECS.heat.cost), Keys.name_of(Keys.code("heat")), "升温" if cold else "降温"]
		"current": t = "按住拖出洋流的方向和力度，持续 30 秒（%d 点）　·　右键 / Esc 取消" % int(SPECS.current.cost)
		"phage": t = "点击投放一团病毒（%d 点）　·　右键 / Esc 取消" % int(SPECS.phage.cost)
		"irritant": t = "点喷口守卫的头部，放一小团刺激物：头冠缩回约 6 秒（%d 点）　·　右键 / Esc 取消" % int(SPECS.irritant.cost)
		"brine": t = "点击撒一片盐：60 秒内那里的水不会结冰（%d 点）　·　右键 / Esc 取消" % int(SPECS.brine.cost)
		"stir": t = "点击搅动一片泥水：30 秒内氧气被带下去、硫化氢被冲淡（%d 点）　·　右键 / Esc 取消" % int(SPECS.stir.cost)
		"iron": t = "点击撒一片铁粉：40 秒内吸掉那里的氧气（%d 点）　·　右键 / Esc 取消" % int(SPECS.iron.cost)
	host.hud_root.show_hint(t)


func drags(kind: String) -> bool:
	return kind == "membrane" or kind == "current"


func begin_drag(at: Vector2) -> void:
	drag_from = at
	drag_to = at


func update_drag(at: Vector2) -> void:
	if drag_from != Vector2.INF:
		var d := at - drag_from
		var cap := 360.0 if host.mode == "membrane" else 260.0
		drag_to = drag_from + d.limit_length(cap)


func finish_drag() -> void:
	if drag_from == Vector2.INF:
		return
	var a := drag_from
	var b := drag_to
	drag_from = Vector2.INF
	if a.distance_to(b) < 30.0:
		host.hud_root.notify("拖得再长一点", Ui.WARN)
		return
	if host.mode == "membrane":
		_spend("membrane")
		host.sim.add_barrier(a, b, MEMBRANE_TIME)
		Audio.sfx("ui_place")
		host.fx.particle((a + b) * 0.5, Vector2.ZERO, a.distance_to(b) * 0.6, Ui.ACCENT, host.fx.RING, 0.7)
	elif host.mode == "current":
		_spend("current")
		var v := (b - a) / 260.0 * 70.0 # up to 70 µm/s
		host.sim.add_current(a.lerp(b, 0.5), 170.0, v, CURRENT_TIME)
		Audio.sfx("current")
	_after(host.mode)


# A click in a click-to-place mode (or a right click for nutrients).
func place(kind: String, at: Vector2) -> void:
	if not ready_to_use(kind):
		host.hud_root.notify(why_not(kind), Ui.WARN)
		Audio.sfx("ui_deny")
		return
	if kind == "irritant":
		# Only where its head is; a miss costs nothing.
		var held: float = host.sim.irritate(at, IRRITANT_REACH)
		if held < 0.0:
			if held < -1.5:
				host.hud_root.notify("头冠已经缩着，没扣点数", Ui.WARN)
			else:
				host.hud_root.notify("离头部太远，没扣点数", Ui.WARN)
			Audio.sfx("ui_deny")
			return
		_spend(kind)
		puffs.append([at, Time.get_ticks_msec() / 1000.0])
		Audio.sfx("nutrient", -6.0, 1.3)
		host.hud_root._event("头冠缩回 %.1f 秒%s；它头边裂了甲的群体 12 秒内安全" % [held, "（它在习惯）" if held < 5.9 else ""], Ui.ACCENT, at)
		_after(kind)
		return
	_spend(kind)
	match kind:
		"nutrient":
			host.sim.add_nutrient(at, 45.0, 150.0)
			host.fx.nutrient_splash(at)
			Audio.sfx("nutrient", 0.0, randf_range(0.95, 1.05))
		"phage":
			host.sim.add_phages(at, PHAGE_R, PHAGE_N)
			if host.level_runner and host.level_runner.eval:
				host.level_runner.eval.shots += 1
				host.level_runner.eval.shot_times.append(host.level_runner.eval.t)
			host.hud_root._event("投放了一团病毒", Ui.ACCENT, at)
			Audio.sfx("nutrient", -4.0, 0.7)
		"brine":
			host.sim.add_brine(at, BRINE_R, 22.0, BRINE_TIME)
			host.hud_root._event("撒下盐：这片水 60 秒内不会结冰", BRINE_COL, at)
			Audio.sfx("nutrient", -4.0, 1.1)
		"stir":
			host.sim.add_stir(at, STIR_R, STIR_TIME)
			host.hud_root._event("搅动泥层：氧气被带下去，硫化氢被冲淡", STIR_COL, at)
			Audio.sfx("nutrient", -4.0, 0.6)
		"iron":
			host.sim.add_iron(at, IRON_R, IRON_TIME)
			host.hud_root._event("撒下铁粉：这片水的氧气会被吸掉", IRON_COL, at)
			Audio.sfx("nutrient", -4.0, 0.8)
		"heat":
			host.sim.add_temp_spot(at, 190.0, -12.0 if cold else 12.0, HEAT_TIME)
			Audio.sfx("cold" if cold else "warm")
			host.fx.particle(at, Vector2.ZERO, 300.0, Color(0.5, 0.75, 1.0) if cold else Color(1.0, 0.6, 0.35), host.fx.RING, 1.2)
	_after(kind)


func _spend(kind: String) -> void:
	used[kind] = int(used.get(kind, 0)) + 1
	if unlimited():
		return
	points -= SPECS[kind].cost
	cooldown[kind] = SPECS[kind].cool


# Stay in the mode while it can be used again, so a few drops in a row are
# quick; leave it when the points run out.
func _after(kind: String) -> void:
	if not ready_to_use(kind):
		host.set_mode("")


# Active interventions and the one being placed, on the world overlay
# (2026-10-29 rework: "使用时的画面效果怪"). A membrane is a lipid bilayer
# (two rows of heads); a warm spot glows and its ripples run outward, a
# cold one's run inward; a current is a disc of chevrons flowing its way.
# Each says what it is and how long it has left in a small label at a fixed
# size on screen. While a tool is in hand, its reach shows under the cursor.
func draw(o: Node2D, zoom: float) -> void:
	var px := 1.0 / zoom
	var t := Time.get_ticks_msec() / 1000.0
	for iv: Dictionary in host.sim.get_interventions():
		var f: float = iv.fade
		var left := int(ceil(float(iv.get("left", 0.0))))
		match String(iv.kind):
			"membrane":
				_bilayer(o, iv.a, iv.b, Ui.ACCENT, f, px, t)
				var mid: Vector2 = (iv.a + iv.b) * 0.5
				var n: Vector2 = (iv.b - iv.a).orthogonal().normalized()
				_label(o, mid + n * 16.0 * px, "隔离膜 · %ds" % left, Ui.ACCENT, f, zoom)
			"brine":
				var c: Vector2 = iv.center
				var r: float = iv.radius
				o.draw_circle(c, r, Color(BRINE_COL, 0.07 * f))
				_dashed(o, c, r, Color(BRINE_COL, 0.75 * f), px)
				for k in 60:
					var a := k * 2.39996
					var rr := r * 0.95 * sqrt(fposmod(k * 0.618 + 0.3, 1.0))
					var q := c + Vector2.from_angle(a) * rr
					var sz := (1.6 + fposmod(k * 0.41, 1.0) * 1.4) * px * 1.5
					o.draw_rect(Rect2(q - Vector2(sz, sz), Vector2(sz, sz) * 2.0), Color(BRINE_COL.lightened(0.4), 0.7 * f))
				_label(o, c + Vector2(0, -r - 12.0 * px), "盐水 · 不结冰 · %ds" % left, BRINE_COL.darkened(0.2), f, zoom)
			"warm", "cold":
				var c: Vector2 = iv.center
				var r: float = iv.radius
				var warm: bool = iv.kind == "warm"
				var col := _heat_col(not warm)
				for k in 7:
					o.draw_circle(c, r * (1.0 - k * 0.13), Color(col, 0.035 * f))
				_dashed(o, c, r, Color(col.darkened(0.15), 0.9 * f), px)
				for i in 2:
					var ph := fposmod(t * 0.35 + i * 0.5, 1.0)
					var rr := r * (0.2 + 0.8 * ph) if warm else r * (1.0 - 0.8 * ph)
					o.draw_arc(c, rr, 0.0, TAU, 64, Color(col, 0.7 * f * sin(ph * PI)), 2.0 * px, true)
				_label(o, c + Vector2(0, -r - 12.0 * px), "%+d°C · %ds" % [int(iv.delta), left], col.darkened(0.2), f, zoom)
			"stir":
				var c: Vector2 = iv.center
				var r: float = iv.radius
				o.draw_circle(c, r, Color(STIR_COL, 0.06 * f))
				_dashed(o, c, r, Color(STIR_COL, 0.7 * f), px)
				for k in 3:
					var a0 := t * (1.2 - 0.3 * k) + k * 2.1
					o.draw_arc(c, r * (0.35 + 0.22 * k), a0, a0 + PI * 1.2, 32, Color(STIR_COL, 0.55 * f), 2.0 * px, true)
				_label(o, c + Vector2(0, -r - 12.0 * px), "搅动 · 带氧下沉 · %ds" % left, STIR_COL.darkened(0.2), f, zoom)
			"iron":
				var c: Vector2 = iv.center
				var r: float = iv.radius
				o.draw_circle(c, r, Color(IRON_COL, 0.06 * f))
				_dashed(o, c, r, Color(IRON_COL, 0.7 * f), px)
				for k in 90:
					var a := k * 2.39996
					var rr := r * 0.95 * sqrt(fposmod(k * 0.618 + 0.11, 1.0))
					var sink := fposmod(t * 0.08 + k * 0.137, 1.0)
					o.draw_circle(c + Vector2.from_angle(a) * rr + Vector2(0, 6.0 * sink), (1.4 + fposmod(k * 0.37, 1.0)) * px * 1.5, Color(IRON_COL, (0.35 + 0.4 * (1.0 - sink)) * f))
				_label(o, c + Vector2(0, -r - 12.0 * px), "铁粉 · 吸氧 · %ds" % left, IRON_COL.darkened(0.2), f, zoom)
			"current":
				var c: Vector2 = iv.center
				var r: float = iv.radius
				var v: Vector2 = iv.velocity
				var dir := v.normalized()
				var side := dir.orthogonal()
				o.draw_circle(c, r, Color(Ui.ACCENT, 0.06 * f))
				_dashed(o, c, r, Color(Ui.ACCENT, 0.75 * f), px)
				var sp := clampf(v.length() / 70.0, 0.25, 1.0)
				for lane in 9:
					var off := (lane - 4) / 4.0 * r * 0.8
					var span := sqrt(maxf(r * r - off * off, 0.0))
					for k in 3:
						var ph := fposmod(t * 0.45 * sp + k / 3.0 + lane * 0.13, 1.0)
						var along := -span + 2.0 * span * ph
						var p := c + side * off + dir * along
						var a := sin(ph * PI) * f
						var h := 9.0 * px
						o.draw_line(p, p - dir * h + side * h * 0.7, Color(Ui.ACCENT.darkened(0.15), a), 2.2 * px, true)
						o.draw_line(p, p - dir * h - side * h * 0.7, Color(Ui.ACCENT.darkened(0.15), a), 2.2 * px, true)
				_label(o, c + Vector2(0, -r - 12.0 * px), "洋流 %d µm/s · %ds" % [int(v.length()), left], Ui.ACCENT, f, zoom)
	# Being placed: the drag, with its length; before a drag or a click,
	# what the tool would reach, under the cursor.
	if drag_from != Vector2.INF:
		var d := drag_to - drag_from
		if host.mode == "membrane":
			_bilayer(o, drag_from, drag_to, Ui.ACCENT, 0.6, px, t)
			_label(o, drag_to + Vector2(0, -16) * px, "%d / 360 µm" % int(d.length()), Ui.ACCENT, 1.0, zoom)
		else:
			var dir := d.normalized()
			o.draw_line(drag_from, drag_to, Color(Ui.ACCENT, 0.85), 2.0 * px, true)
			o.draw_line(drag_to, drag_to - dir.rotated(0.5) * 14.0 * px, Ui.ACCENT, 2.0 * px, true)
			o.draw_line(drag_to, drag_to - dir.rotated(-0.5) * 14.0 * px, Ui.ACCENT, 2.0 * px, true)
			_dashed(o, drag_from.lerp(drag_to, 0.5), 170.0, Color(Ui.ACCENT, 0.35), px)
			_label(o, drag_to + Vector2(0, -16) * px, "%d µm/s" % int(d.length() / 260.0 * 70.0), Ui.ACCENT, 1.0, zoom)
		return
	_irritant(o, zoom, px, t)
	if host.mode in ["nutrient", "heat", "membrane", "current", "phage", "irritant", "iron", "brine", "stir"] and host.pointer:
		var at: Vector2 = host.get_viewport().get_canvas_transform().affine_inverse() * host.pointer.pos
		match host.mode:
			"nutrient":
				_dashed(o, at, 45.0, Color(Ui.ACCENT, 0.8), px)
				o.draw_circle(at, 45.0, Color(Ui.ACCENT, 0.06))
			"brine":
				_dashed(o, at, BRINE_R, Color(BRINE_COL, 0.8), px)
				o.draw_circle(at, BRINE_R, Color(BRINE_COL, 0.05))
				_label(o, at + Vector2(0, -BRINE_R - 12.0 * px), "撒盐 · 60 秒不结冰", BRINE_COL.darkened(0.2), 1.0, zoom)
			"stir":
				_dashed(o, at, STIR_R, Color(STIR_COL, 0.8), px)
				o.draw_circle(at, STIR_R, Color(STIR_COL, 0.05))
				_label(o, at + Vector2(0, -STIR_R - 12.0 * px), "搅动泥层 · 30 秒", STIR_COL.darkened(0.2), 1.0, zoom)
			"iron":
				_dashed(o, at, IRON_R, Color(IRON_COL, 0.8), px)
				o.draw_circle(at, IRON_R, Color(IRON_COL, 0.05))
				_label(o, at + Vector2(0, -IRON_R - 12.0 * px), "撒铁粉 · 40 秒", IRON_COL.darkened(0.2), 1.0, zoom)
			"phage":
				_dashed(o, at, PHAGE_R, Color(0.5, 0.3, 0.82, 0.8), px)
				o.draw_circle(at, PHAGE_R, Color(0.5, 0.3, 0.82, 0.05))
			"irritant":
				# Its head's reach, and whether the cursor is in it.
				var head := _head()
				var near := head.is_finite() and at.distance_to(head) <= IRRITANT_REACH
				if head.is_finite():
					_dashed(o, head, IRRITANT_REACH, Color(IRRITANT_COL, 0.55 if near else 0.3), px)
				o.draw_circle(at, 30.0, Color(IRRITANT_COL, 0.12 if near else 0.04))
				var rr: PackedFloat32Array = host.sim.get_rotifer_retract()
				var words := "离头部太远"
				if near and rr[0] > 0.0:
					words = "头冠已经缩着"
				elif near:
					words = "放在这里：头冠缩回 %.1f 秒%s" % [rr[2], "（它在习惯）" if rr[2] < 5.9 else ""]
				_label(o, at + Vector2(0, -30.0 - 12.0 * px), words, IRRITANT_COL.darkened(0.2) if near else Ui.INK_FAINT, 1.0, zoom)
			"heat":
				var col := _heat_col(cold)
				_dashed(o, at, 190.0, Color(col, 0.8), px)
				o.draw_circle(at, 190.0, Color(col, 0.05))
				_label(o, at + Vector2(0, -190.0 - 12.0 * px), "%s · 40 秒" % ("−12°C" if cold else "+12°C"), col.darkened(0.2), 1.0, zoom)
			_:
				_label(o, at + Vector2(0, -22) * px, "按住拖动", Ui.ACCENT, 1.0, zoom)


const IRRITANT_COL := Color(0.86, 0.62, 0.2)
const IRON_COL := Color(0.72, 0.36, 0.2)
const STIR_COL := Color(0.62, 0.5, 0.32)
const BRINE_COL := Color(0.55, 0.78, 0.95)


# The guardian's head (its corona), or INF without one.
func _head() -> Vector2:
	var rot: PackedFloat32Array = host.sim.get_rotifers(1.0)
	if rot.size() < 6:
		return Vector2.INF
	return Vector2(rot[0], rot[1]) + Vector2.from_angle(rot[2]) * 88.0


# Level 24: the irritant spreading where it was dropped (fine amber grains
# drifting out and fading), and over its head how long the corona stays in.
func _irritant(o: Node2D, zoom: float, px: float, t: float) -> void:
	if not open_here("irritant"):
		return
	var keep := []
	for p: Array in puffs:
		var age: float = t - float(p[1])
		if age > 2.5:
			continue
		keep.append(p)
		var at: Vector2 = p[0]
		var f := 1.0 - age / 2.5
		for k in 22:
			var a := k * 2.39996
			var r := (8.0 + 46.0 * sqrt(fposmod(k * 0.618, 1.0))) * (0.4 + 0.6 * minf(age / 1.2, 1.0))
			o.draw_circle(at + Vector2.from_angle(a) * r, (1.6 + 0.8 * fposmod(k * 0.37, 1.0)) * px * 1.6, Color(IRRITANT_COL, 0.75 * f))
	puffs = keep
	var rr: PackedFloat32Array = host.sim.get_rotifer_retract()
	if rr.size() >= 2 and rr[0] > 0.0:
		var head := _head()
		if head.is_finite():
			_label(o, head + Vector2(0, -60.0 - 14.0 * px), "头冠缩回 · %.1f 秒" % rr[0], IRRITANT_COL.darkened(0.25), 1.0, zoom)


static func _heat_col(is_cold: bool) -> Color:
	return Color(0.3, 0.6, 1.0) if is_cold else Color(1.0, 0.5, 0.28)


# A lipid bilayer from a to b: two leaflets of heads with tails between.
func _bilayer(o: Node2D, a: Vector2, b: Vector2, col: Color, f: float, px: float, t: float) -> void:
	var d := b - a
	var n := d.orthogonal().normalized()
	o.draw_line(a, b, Color(col, 0.2 * f), 12.0 * px, true)
	var steps := maxi(2, int(d.length() / (7.0 * px)))
	for k in steps + 1:
		var p := a.lerp(b, float(k) / steps)
		var wob := sin(t * 3.0 + k * 0.7) * 0.6 * px
		for s in [-1.0, 1.0]:
			var head: Vector2 = p + n * (s * 4.0 * px + wob)
			o.draw_line(head, p + n * (s * 1.0 * px + wob), Color(col.darkened(0.2), 0.7 * f), 1.2 * px, true)
			o.draw_circle(head, 2.0 * px, Color(col.darkened(0.15), f))
	o.draw_circle(a, 3.2 * px, Color(col, f))
	o.draw_circle(b, 3.2 * px, Color(col, f))


func _dashed(o: Node2D, c: Vector2, r: float, col: Color, px: float) -> void:
	var n := 48
	for k in n:
		var a0 := TAU * k / n
		o.draw_arc(c, r, a0, a0 + TAU / n * 0.55, 4, col, 2.0 * px, true)


# Text at a fixed size on screen, over a soft white outline.
func _label(o: Node2D, at: Vector2, text: String, col: Color, a: float, zoom: float) -> void:
	var f := Ui.mono("Medium")
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	o.draw_set_transform(at, 0.0, Vector2.ONE / zoom)
	o.draw_string_outline(f, Vector2(-w * 0.5, 4), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 5, Color(1, 1, 1, 0.9 * a))
	o.draw_string(f, Vector2(-w * 0.5, 4), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(col.darkened(0.35), a))
	o.draw_set_transform(Vector2.ZERO)
