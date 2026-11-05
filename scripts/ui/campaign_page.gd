extends Control
# Campaign page (DECISIONS M4 Q3/Q4): a cross-section of Europa's ice shell
# on the left - the base on the surface, the drill shaft down through the ice
# into the ocean, one sampling station per level, deeper is harder - and the
# selected level's commission on the right (the briefing card). Up/Down or a
# click picks a station, Enter starts, Esc goes back to the menu.
# Eighth round (no cuts anywhere): the page comes in behind a scan line
# sweeping down a white curtain - the section draws itself as it passes
# (surface, base, strata, the shaft drilling down, stations popping on) and
# the card materialises line by line; leaving, the line sweeps back up. A
# new station wipes the card's content out and back in, a lead line runs
# from the station to the card. 进入实验: a light drops down the shaft to the
# station, and showcase.start_level opens a lens there (IrisFx) into the
# level's dish.
# Ninth round: the section is a live 3D model of the drill site
# (scripts/ui/campaign_model.gd) with a small Europa in its corner.

signal start_level(level: Dictionary)
signal closed

var host: Node2D
var chapter_label: Label
var chapter_en: Label
var wash: ColorRect
const EuropaModel := preload("res://scripts/ui/campaign_model.gd")
var section: Control
var card: GlassPanel
var card_box: VBoxContainer
var card_scroll: ScrollContainer
var research_label: Label
var selected := 0
var shown := false
var reveal := 1.0 # the curtain's scan line: 0 above the top .. 1 past the bottom
var wash_mat: ShaderMaterial
var fxl: Control # over everything: the scan line, the lead line
var top_bar: Control
var link_t := 0.0 # the lead line to the card drawing out
var swap: Tween
var diving := false
# One map per chapter: the header's arrows (and ← / →) go to the chapter
# before / after; a chapter opens when its first level does.
var prev_ch: Widgets.Pill
var next_ch: Widgets.Pill
var ch_note: Label


func setup(showcase: Node2D) -> void:
	host = showcase
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

	wash = ColorRect.new()
	wash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wash.mouse_filter = Control.MOUSE_FILTER_STOP
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
#include "res://shaders/night.gdshaderinc"
uniform float front = 2.0;
void fragment() {
	float g = SCREEN_UV.y - front;
	float a = 0.9 * (1.0 - smoothstep(-0.004, 0.0, g));
	float band = exp(-abs(g) * 70.0) * step(g, 0.0);
	vec3 col = mix(vec3(0.972, 0.986, 0.995), vec3(0.78, 0.96, 1.0), band * 0.6);
	COLOR = vec4(mix(col, night_ui_lin(col), night), max(a, band * 0.3));
}"""
	wash_mat = ShaderMaterial.new()
	wash_mat.shader = sh
	wash.material = wash_mat
	add_child(wash)

	var top := HBoxContainer.new()
	top.position = Vector2(64, 40)
	top.add_theme_constant_override("separation", 18)
	add_child(top)
	var back := Widgets.Pill.new("‹  返回  Esc", 0, Ui.sans(500))
	back.custom_minimum_size.x = 120
	back.pressed.connect(close)
	top.add_child(back)
	var cap := VBoxContainer.new()
	cap.add_theme_constant_override("separation", 0)
	chapter_label = Ui.label("第一章 · 单细胞篇", 20, Ui.INK, Ui.sans(600))
	cap.add_child(chapter_label)
	chapter_en = Ui.label("CHAPTER I  ·  EUROPA  ·  DRILL SITE E-07", 11, Ui.INK_FAINT, Ui.mono("Medium"))
	cap.add_child(chapter_en)
	top.add_child(cap)
	prev_ch = Widgets.Pill.new("", 0, Ui.sans(500))
	prev_ch.custom_minimum_size = Vector2(118, 34)
	prev_ch.pressed.connect(func() -> void: _switch_chapter(shown_chapter() - 1))
	top.add_child(prev_ch)
	next_ch = Widgets.Pill.new("", 0, Ui.sans(600))
	next_ch.custom_minimum_size = Vector2(118, 34)
	next_ch.pressed.connect(func() -> void: _switch_chapter(shown_chapter() + 1))
	top.add_child(next_ch)
	ch_note = Ui.label("", 13, Ui.INK_SOFT, Ui.sans(500))
	ch_note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ch_note.modulate.a = 0.0
	top.add_child(ch_note)
	top_bar = top

	research_label = Ui.label("", 13, Ui.INK_SOFT, Ui.mono("Medium"))
	# Nothing spends research yet: off screen until it does (review round 6).
	research_label.visible = false
	research_label.anchor_left = 1.0
	research_label.anchor_right = 1.0
	research_label.offset_left = -360
	research_label.offset_right = -64
	research_label.offset_top = 52
	research_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(research_label)

	section = EuropaModel.new()
	section.page = self
	section.anchor_top = 0.0
	section.anchor_bottom = 1.0
	section.offset_left = 40
	section.offset_right = 870
	section.offset_top = 96
	section.offset_bottom = -24
	add_child(section)

	card = GlassPanel.new(Vector4(30, 26, 30, 26))
	card.anchor_left = 1.0
	card.anchor_right = 1.0
	card.anchor_top = 0.0
	card.anchor_bottom = 1.0
	card.offset_left = -1040
	card.offset_right = -96
	card.offset_top = 130
	card.offset_bottom = -90
	add_child(card)
	card_scroll = ScrollContainer.new()
	card_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	card_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	card_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.body.add_child(card_scroll)
	card_box = VBoxContainer.new()
	card_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card_box.add_theme_constant_override("separation", 10)
	card_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_scroll.add_child(card_box)

	fxl = Control.new()
	fxl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fxl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fxl.draw.connect(_draw_fx)
	add_child(fxl)


func open() -> void:
	Audio.music("menu")
	Audio.sfx("ui_open")
	Audio.sfx("holo_boot", -10.0, 0.9)
	CampaignSave.ensure()
	visible = true
	shown = true
	diving = false
	modulate.a = 1.0
	if swap:
		swap.kill()
		swap = null
	_sweep(0.0, 1.0, 1.5, 0.12)
	section.enter()
	link_t = 0.0
	# Start on the first open level not yet completed.
	selected = 0
	for l: Dictionary in Levels.ALL:
		if Levels.playable(l) and CampaignSave.unlocked(l.index):
			selected = l.index - 1
			if not CampaignSave.stars(l.id)[0]:
				break
	research_label.text = "研究点  %d　·　拿到新星就得" % CampaignSave.research()
	research_label.tooltip_text = "每拿到一颗新星得研究点；以后在长局里用来解锁研究"
	research_label.mouse_filter = Control.MOUSE_FILTER_STOP
	_select(selected, true)
	card.appear(0.3)


# The curtain's scan line from `a` to `b` (see reveal).
func _sweep(a: float, b: float, seconds: float, delay := 0.0) -> Tween:
	reveal = a
	_apply_reveal()
	var t := create_tween()
	t.tween_interval(delay)
	t.tween_method(func(v: float) -> void:
		reveal = v
		_apply_reveal(), a, b, seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT if b > a else Tween.EASE_IN)
	return t


func scan_y() -> float:
	return lerpf(-0.04, 1.06, reveal) * size.y


func _apply_reveal() -> void:
	var f := lerpf(-0.04, 1.06, reveal)
	var on := reveal < 0.999
	wash_mat.set_shader_parameter("front", f if on else 2.0)
	card.set_wipe(Vector2(0, 1), f if on else 9.0)
	var k := clampf((scan_y() - 30.0) / 120.0, 0.0, 1.0)
	top_bar.modulate.a = k
	research_label.modulate.a = k
	fxl.queue_redraw()
	section.queue_redraw()


func close() -> void:
	if not shown:
		return
	shown = false
	Audio.sfx("holo_off", -10.0)
	var t := _sweep(1.0, 0.0, 0.6)
	t.tween_callback(func() -> void: visible = false)
	# The menu comes back up as the curtain lifts.
	get_tree().create_timer(0.18).timeout.connect(func() -> void: closed.emit())


# The level's lens has the frame frozen (IrisFx): the page just goes.
func hide_for_level() -> void:
	shown = false
	visible = false
	diving = false
	section.descent = -1.0


func _select(i: int, instant := false) -> void:
	var was := selected
	selected = clampi(i, 0, Levels.ALL.size() - 1)
	section.select(selected, instant)
	# The heading follows the chapter of the selected level.
	var ch: int = int(String(Levels.ALL[selected].id).get_slice("-", 0))
	section.preview_ch = 0
	_chapter_head(ch)
	if instant or reveal < 0.999 or not is_visible_in_tree():
		_fill_card(Levels.ALL[selected])
		return
	if selected == was and swap == null:
		return
	# The card's content wipes out downward and the new one scans in behind.
	Audio.sfx("holo_tick", -10.0, 1.1)
	link_t = 0.0
	card.glitch(0.5)
	var r := card.get_global_rect()
	var top := r.position.y / size.y - 0.02
	var bot := r.end.y / size.y + 0.02
	if swap:
		swap.kill()
	swap = create_tween()
	swap.tween_method(func(v: float) -> void: card.set_wipe(Vector2(0, -1), v), -top, -bot, 0.14).set_trans(Tween.TRANS_SINE)
	swap.tween_callback(func() -> void:
		_fill_card(Levels.ALL[selected])
		Holo.type_in(card.body, 0.01))
	swap.tween_method(func(v: float) -> void: card.set_wipe(Vector2(0, 1), v), top, bot, 0.42).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	swap.tween_callback(func() -> void:
		card.set_wipe(Vector2(0, 1), 9.0)
		swap = null)


const CH_NAMES := ["第一章", "第二章", "第三章", "第四章", "第五章", "第六章", "第七章", "第八章", "第九章", "第十章"]
const ROMAN := ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"]
# The ten chapters' titles and where they are (design/CAMPAIGN.md v3).
const TITLES := ["单细胞篇", "捕食篇", "群居篇", "噬体篇", "多细胞篇", "播种篇", "寒夜篇", "腐土篇", "演化篇", "终章"]
const WHERE := ["EUROPA  ·  DRILL SITE E-07", "EUROPA  ·  DRILL SITE E-07", "EUROPA  ·  DEEP DARK WATER", "EUROPA  ·  ICE CREVASSE",
	"EUROPA  ·  HYDROTHERMAL VENT", "PLANET I  ·  HOT-SPRING SEABED", "PLANET II  ·  FROZEN SEA", "PLANET III  ·  ACID SWAMP",
	"PLANET IV  ·  CRYSTAL WASTE", "PLANET V  ·  LIGHTLESS ABYSS"]


static func chapter_name(c: int) -> String:
	return "%s · %s" % [CH_NAMES[c - 1], TITLES[c - 1]] if c >= 1 and c <= 10 else ""


func _chapter_head(ch: int) -> void:
	chapter_label.text = chapter_name(ch)
	chapter_en.text = "CHAPTER %s  ·  %s" % [ROMAN[ch - 1], WHERE[ch - 1]]
	_chapter_pills(ch)


# The chapter on show (a previewed one, else the selected level's).
func shown_chapter() -> int:
	return section.preview_ch if section.preview_ch > 0 else chapter_of(selected)


# A chapter whose levels are not made yet: developer mode can look at its map.
static func can_preview(c: int) -> bool:
	return c >= 1 and c <= 10 and chapter_levels(c).is_empty() and DevMode.active


static func chapter_of(i: int) -> int:
	return int(String(Levels.ALL[i].id).get_slice("-", 0))


# The chapter's levels (indices into Levels.ALL), in order.
static func chapter_levels(c: int) -> Array:
	return range(Levels.ALL.size()).filter(func(i: int) -> bool: return chapter_of(i) == c)


static func chapter_open(c: int) -> bool:
	var idx := chapter_levels(c)
	if idx.is_empty():
		return false
	var l: Dictionary = Levels.ALL[idx[0]]
	return Levels.playable(l) and CampaignSave.unlocked(l.index)


func _chapter_pills(ch: int) -> void:
	prev_ch.visible = ch > 1 and (not chapter_levels(ch - 1).is_empty() or can_preview(ch - 1))
	if prev_ch.visible:
		prev_ch.text = "‹  " + CH_NAMES[ch - 2]
		prev_ch.tooltip_text = "←"
	next_ch.visible = ch < 10 and (not chapter_levels(ch + 1).is_empty() or can_preview(ch + 1))
	if next_ch.visible:
		var open := chapter_open(ch + 1) or can_preview(ch + 1)
		next_ch.text = CH_NAMES[ch] + ("  ›" if open else "  · 未开放")
		next_ch.modulate.a = 1.0 if open else 0.55
		next_ch.active = open and _chapter_done(ch)
		next_ch.tooltip_text = "→" if open else "完成%s的全部委托后开放" % CH_NAMES[ch - 1]


# Every level of the chapter passed (the next map is waiting).
static func _chapter_done(c: int) -> bool:
	return chapter_levels(c).all(func(i: int) -> bool: return CampaignSave.stars(Levels.ALL[i].id)[0])


# To another chapter's map: its first level not yet passed (else its last
# open one); a chapter not yet open says when it opens.
func _switch_chapter(c: int) -> void:
	var idx := chapter_levels(c)
	if idx.is_empty():
		if can_preview(c):
			_preview(c)
		return
	if not chapter_open(c):
		Audio.sfx("ui_click", -10.0, 0.7)
		ch_note.text = "完成%s的全部委托后开放" % CH_NAMES[c - 2]
		ch_note.modulate.a = 1.0
		var t := Ui.tween(ch_note)
		t.tween_interval(1.6)
		t.tween_property(ch_note, "modulate:a", 0.0, 0.5)
		return
	var pick: int = idx[0]
	for i: int in idx:
		var l: Dictionary = Levels.ALL[i]
		if Levels.playable(l) and CampaignSave.unlocked(l.index):
			pick = i
			if not CampaignSave.stars(l.id)[0]:
				break
	Audio.sfx("holo_tick", -6.0)
	_select(pick)


# Developer mode: a chapter with no levels yet, its map alone; the card says so.
func _preview(c: int) -> void:
	card_scroll.scroll_vertical = 0
	Audio.sfx("holo_tick", -6.0)
	section.preview_ch = c
	_chapter_head(c)
	for n in card_box.get_children():
		card_box.remove_child(n)
		n.queue_free()
	card_box.add_child(Ui.caption("地图预览", "CHAPTER %s  ·  PREVIEW" % ROMAN[c - 1]))
	card_box.add_child(Ui.label(chapter_name(c), 34, Ui.INK, Ui.sans(700)))
	card_box.add_child(Ui.label(WHERE[c - 1], 13, Ui.ACCENT, Ui.mono("SemiBold")))
	var note := Ui.label("这一章的关卡还在制作中：这是它的地图（开发者模式预览）。", 15, Ui.INK_SOFT, Ui.sans(500))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 800
	card_box.add_child(note)


# Up / down stay on the chapter's map.
func _step(d: int) -> void:
	if section.preview_ch > 0:
		return
	var j := selected + d
	if j >= 0 and j < Levels.ALL.size() and chapter_of(j) == chapter_of(selected):
		_select(j)


func can_start(l: Dictionary) -> bool:
	return Levels.playable(l) and CampaignSave.unlocked(l.index)


func _start() -> void:
	var l: Dictionary = Levels.ALL[selected]
	if diving or not shown or section.preview_ch > 0:
		return
	if can_start(l):
		# A light drops down the shaft to the station; the lens opens there.
		diving = true
		Audio.sfx("ui_confirm")
		Audio.sfx("holo_banner", -10.0, 0.8)
		section.descend()
		get_tree().create_timer(EuropaModel.DESCENT + 0.05).timeout.connect(func() -> void:
			if diving:
				start_level.emit(l))
	else:
		Audio.sfx("ui_deny")
		card.glitch(0.8)


# Where the lens into the level opens (screen).
func station_screen() -> Vector2:
	return section.get_global_transform() * section.station_pos(selected)


# Over the page: the curtain's scan line with its depth readout, and the
# lead line from the selected station to the card.
func _draw_fx() -> void:
	var y := scan_y()
	if reveal < 0.999 and y > -10.0 and y < size.y + 10.0:
		var w := size.x
		for i in 6:
			var h := 2.0 + i * 6.0
			fxl.draw_rect(Rect2(0, y - h, w, h), Color(0.6, 0.93, 1.0, 0.035))
		fxl.draw_rect(Rect2(0, y - 0.75, w, 1.5), Color(1.5, 2.5, 2.8, 0.95))
		var mono := Ui.mono("Medium")
		var depth: float = section.scan_depth()
		var txt := "SCAN  %04d  ·  DEPTH %.2f km" % [int(y), depth]
		fxl.draw_string(mono, Vector2(w - 330, y - 8), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(Ui.ACCENT, 0.9))
		for k in 41:
			var x := w * k / 40.0
			fxl.draw_line(Vector2(x, y), Vector2(x, y + (6.0 if k % 5 == 0 else 3.0)), Color(Ui.ACCENT, 0.5), 1.0)
	if reveal >= 0.999 and shown and link_t > 0.0:
		_draw_link()


func _draw_link() -> void:
	var p: Vector2 = section.get_global_transform() * section.label_end(selected)
	var cr := card.get_global_rect()
	var x1 := cr.position.x - 34.0
	var y1 := cr.position.y + 64.0
	var pts := PackedVector2Array([p, Vector2(x1, p.y), Vector2(x1, y1), Vector2(cr.position.x - 8.0, y1)])
	var total := 0.0
	for k in 3:
		total += pts[k].distance_to(pts[k + 1])
	var left := total * (1.0 - pow(1.0 - link_t, 3.0))
	var col := Color(Ui.ACCENT, 0.55)
	var tip := p
	for k in 3:
		var seg := maxf(pts[k].distance_to(pts[k + 1]), 0.001)
		tip = pts[k].lerp(pts[k + 1], clampf(left / seg, 0.0, 1.0))
		fxl.draw_line(pts[k], tip, col, 1.2, true)
		left -= seg
		if left <= 0.0:
			break
	fxl.draw_circle(p, 3.0, Ui.ACCENT)
	if link_t < 1.0:
		fxl.draw_circle(tip, 3.5, Color(1.5, 2.5, 2.8))
		return
	# A pulse running along it, over and over.
	var run := fposmod(Time.get_ticks_msec() / 1000.0 * 420.0, total + 200.0)
	var acc := 0.0
	for k in 3:
		var seg := maxf(pts[k].distance_to(pts[k + 1]), 0.001)
		if run >= acc and run < acc + seg:
			fxl.draw_circle(pts[k].lerp(pts[k + 1], (run - acc) / seg), 2.5, Color(1.3, 2.3, 2.6, 0.9))
		acc += seg
	var d := pts[3]
	fxl.draw_colored_polygon(PackedVector2Array([d + Vector2(0, -5), d + Vector2(5, 0), d + Vector2(0, 5), d + Vector2(-5, 0)]), Ui.ACCENT)


func _fill_card(l: Dictionary) -> void:
	card_scroll.scroll_vertical = 0
	for c in card_box.get_children():
		card_box.remove_child(c)
		c.queue_free()
	card_box.add_child(Ui.caption("实验委托", "COMMISSION %s" % l.id))
	var title := HBoxContainer.new()
	title.add_theme_constant_override("separation", 14)
	title.add_child(Ui.label(l.name, 34, Ui.INK, Ui.sans(700)))
	var en := Ui.label(l.en, 13, Ui.ACCENT, Ui.mono("SemiBold"))
	en.size_flags_vertical = Control.SIZE_SHRINK_END
	title.add_child(en)
	card_box.add_child(title)
	var subtitle := "深度 %.1f km  ·  %s" if l.id in ["3-1", "3-2", "3-3", "3-4", "4-1", "4-2", "4-3", "4-4", "4-5", "2-1", "2-2", "2-3", "2-4", "2-5", "5-1", "5-2", "5-3", "5-4", "5-5"] else "深度 %.1f km  ·  教会你：%s"
	card_box.add_child(Ui.label(subtitle % [l.depth, l.teach], 13, Ui.INK_SOFT, Ui.sans(500)))
	if not Levels.playable(l):
		_rule()
		card_box.add_child(Ui.label("这一站的样本还在分析中，将在下一阶段开放。", 15, Ui.INK_SOFT, Ui.sans()))
		return
	if not CampaignSave.unlocked(l.index):
		_rule()
		card_box.add_child(Ui.label("完成上一站的委托后开放。", 15, Ui.INK_SOFT, Ui.sans()))
		return
	_rule()
	var who := HBoxContainer.new()
	who.add_theme_constant_override("separation", 10)
	var badge := Emblem.new()
	who.add_child(badge)
	var wv := VBoxContainer.new()
	wv.add_theme_constant_override("separation", 0)
	# (Chapter 6 on: the seed ship's AI commissions the work, far from Europa.)
	var sender: Dictionary = l.get("director", Levels.DIRECTOR)
	wv.add_child(Ui.label(sender.name, 14, Ui.INK, Ui.sans(600)))
	wv.add_child(Ui.label(sender.title, 11, Ui.INK_FAINT, Ui.sans(500)))
	who.add_child(wv)
	card_box.add_child(who)
	var brief := Ui.label(l.brief, 15, Ui.INK, Ui.sans())
	brief.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	brief.custom_minimum_size.x = 860
	card_box.add_child(brief)
	_rule()
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 8)
	card_box.add_child(grid)
	var st: Array = CampaignSave.stars(l.id)
	_row(grid, "目标", l.goal.text, st[0])
	_row(grid, "附加挑战", l.challenge.text, st[1])
	if l.has("star_blocks"):
		var blocks_text := "使用不超过 %d 个身体块完成主要目标。" if l.id in ["5-2", "5-3", "5-4"] else ("使用不超过 %d 个身体块完成目标。" if l.id == "5-5" else "身体在 %d 块以内完成目标")
		_row(grid, "小身体", blocks_text % int(l.star_blocks), st[2])
	elif l.has("star_shots"):
		_row(grid, "省着用", ("投放病毒不超过 %d 次，并完成主要目标。" if l.id in ["4-4", "4-5"] else "最多投放 %d 次病毒完成目标") % int(l.star_shots), st[2])
	else:
		var budget_text := "基因预算不超过 %d 点。" if l.id in ["2-1", "2-2", "2-3", "2-4", "2-5"] else "使用不超过 %d 点基因预算完成主要目标。" if l.id in ["3-1", "3-2", "3-3", "3-4", "4-1", "4-2", "4-3"] else ("完成目标，基因预算消耗不超过 %d 点。" if l.id == "5-1" else "基因预算用到 %d 点以内完成目标")
		_row(grid, "低预算", budget_text % l.star_budget, st[2])
		_row(grid, "基因预算", "%d 点" % l.budget, null)
	var tl := int(l.time_limit)
	_row(grid, "限时", "%s（可暂停、加速）" % ("%d 分钟" % (tl / 60) if tl % 60 == 0 else "%d 分 %d 秒" % [tl / 60, tl % 60]), null)
	var names := []
	for g: int in l.genes_open:
		names.append(["速度", "感知", "外壳", "攻击", "繁殖", "代谢", "神经", "耐温"][g])
	if not names.is_empty():
		_row(grid, "开放基因", "、".join(names), null)
	var iv := []
	for k: String in l.interventions:
		iv.append("局部升温" if l.id in ["2-1", "2-2", "2-3", "2-4", "2-5", "5-1"] and k == "heat" else {nutrient = "营养投放", membrane = "隔离膜", heat = "局部升降温", current = "洋流引导", phage = "投放病毒", irritant = "刺激头冠", iron = "撒铁粉", brine = "撒盐"}.get(k, k))
	_row(grid, "可用干预", "、".join(iv), null)
	_row(grid, "已知情况", "\n".join(l.threats), null)
	_rule()
	var log := Typewriter.new(l.ai_log, "" if l.id in ["3-1", "3-2", "3-3", "3-4", "4-1", "4-2", "4-3", "4-4", "4-5", "2-1", "2-2", "2-3", "2-4", "2-5", "5-1", "5-2", "5-3", "5-4", "5-5"] else "「创生协议」  ")
	card_box.add_child(log)
	# What the marks mean (playtest review: "☆☆☆ 没有图例").
	var legend_text := "每关有 3 颗星，分别对应主要目标、附加挑战和低预算挑战。完成对应条件即可获得。\n通关后，可以在结算报告中查看哪些挑战还没有完成。" if l.id in ["2-1", "2-2", "2-3", "2-4", "2-5"] else "每关最多获得 3 颗星，分别对应主要目标、附加挑战和低预算挑战。满足条件即可获得对应的星星。\n通关后，可以在结算报告中查看未完成的挑战条件。" if l.id in ["3-1", "3-2", "3-3", "3-4", "4-1", "4-2", "4-3", "2-1", "2-2", "2-3", "2-4", "2-5", "5-1"] else "左边每关后面的三个 ☆ 分别代表：完成目标 · 附加挑战 · %s。完成一项，就会点亮对应的星。没通过的关卡，可以在结算报告里查看过关提示。" % ("小身体" if l.has("star_blocks") else ("省着用" if l.has("star_shots") else "低预算"))
	if l.id in ["4-4", "4-5"]:
		legend_text = "每关最多获得 3 颗星，分别对应主要目标、附加挑战和省着用挑战。满足条件即可获得对应的星星。\n通关后，可以在结算报告中查看未完成的挑战条件。"
	if l.id in ["5-2", "5-3", "5-4", "5-5"]:
		legend_text = "每关最多获得 3 颗星，分别对应主要目标、附加挑战和特殊挑战。满足条件即可获得对应的星星。\n通关后，可以在结算报告中查看未完成的挑战条件。"
	var legend := Ui.label(legend_text, 12, Ui.INK_SOFT, Ui.sans(500))
	legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	legend.custom_minimum_size.x = 800
	card_box.add_child(legend)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card_box.add_child(spacer)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 14)
	var rec: Dictionary = CampaignSave.level(l.id)
	var nstar: int = (rec.get("stars", [false, false, false]) as Array).count(true) if rec else 0
	var info := Ui.label(("尝试 %d 次 · 最好 %d / 3 星" % [int(rec.get("attempts", 0)), nstar]) if rec and int(rec.get("attempts", 0)) > 0 else "尚未尝试", 12, Ui.INK_SOFT, Ui.mono())
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(info)
	var fs := Control.new()
	fs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(fs)
	var go := Widgets.Pill.new("进入实验  Enter", 0, Ui.sans(600))
	go.custom_minimum_size = Vector2(200, 40)
	go.active = true
	go.pressed.connect(_start)
	foot.add_child(go)
	card_box.add_child(foot)


func _rule() -> void:
	var r := ColorRect.new()
	r.color = Ui.LINE
	r.custom_minimum_size = Vector2(0, 1)
	card_box.add_child(r)


func _row(grid: GridContainer, key: String, text: String, star: Variant) -> void:
	var k := HBoxContainer.new()
	k.add_theme_constant_override("separation", 6)
	if star != null:
		var s := StarMark.new()
		s.on = bool(star)
		k.add_child(s)
	k.add_child(Ui.label(key, 13, Ui.INK_SOFT, Ui.sans(600)))
	k.custom_minimum_size.x = 110
	grid.add_child(k)
	var v := Ui.label(text, 14, Ui.INK, Ui.sans())
	v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.custom_minimum_size.x = 700
	grid.add_child(v)


func _unhandled_input(event: InputEvent) -> void:
	if not shown:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_DOWN:
				_step(1)
			KEY_UP:
				_step(-1)
			KEY_LEFT, KEY_PAGEUP:
				_switch_chapter(shown_chapter() - 1)
			KEY_RIGHT, KEY_PAGEDOWN:
				_switch_chapter(shown_chapter() + 1)
			KEY_ENTER, KEY_KP_ENTER:
				_start()
			KEY_ESCAPE:
				close()
			_:
				return
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if visible:
		section.queue_redraw()
		if reveal >= 0.999 and shown:
			link_t = minf(1.0, link_t + delta / 0.38)
		fxl.queue_redraw()


# A small star: hollow until earned.
class StarMark extends Control:
	var on := false

	func _init() -> void:
		custom_minimum_size = Vector2(14, 14)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var pts := PackedVector2Array()
		for k in 10:
			var a := -PI / 2.0 + k * PI / 5.0
			var r := 6.5 if k % 2 == 0 else 2.8
			pts.append(Vector2(7, 7) + Vector2(cos(a), sin(a)) * r)
		if on:
			draw_colored_polygon(pts, Ui.ACCENT)
		pts.append(pts[0])
		draw_polyline(pts, Ui.ACCENT if on else Ui.INK_FAINT, 1.0, true)


# The base's emblem: a hexagon round a drill bit.
class Emblem extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(36, 36)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var pts := PackedVector2Array()
		for k in 7:
			var a := PI / 6.0 + k * PI / 3.0
			pts.append(c + Vector2(cos(a), sin(a)) * 16.0)
		draw_polyline(pts, Ui.ACCENT, 1.4, true)
		draw_line(c + Vector2(0, -9), c + Vector2(0, 7), Ui.INK, 1.4, true)
		draw_colored_polygon(PackedVector2Array([c + Vector2(-4, 4), c + Vector2(4, 4), c + Vector2(0, 11)]), Ui.INK)
		draw_line(c + Vector2(-7, -9), c + Vector2(7, -9), Ui.INK, 1.4, true)


# The AI's log line, typed out.
class Typewriter extends Label:
	var full := ""
	var prefix := ""
	var t := 0.0

	func _init(text_in: String, prefix_in: String = "「创生协议」  ") -> void:
		full = text_in
		prefix = prefix_in
		text = ""
		add_theme_font_override("font", Ui.mono("Medium"))
		add_theme_font_size_override("font_size", 13)
		add_theme_color_override("font_color", Ui.ACCENT)
		autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		custom_minimum_size.x = 860
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		# (The prefix is 8 characters: comparing against full + 2 stopped
		# the typing 6 characters short, "…直到" cut off.)
		var n := mini(int(t * 38.0), full.length())
		if text.is_empty() or n < full.length() or not text.ends_with(full):
			t += delta
			n = mini(int(t * 38.0), full.length())
			text = prefix + full.substr(0, n)
