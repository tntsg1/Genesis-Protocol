extends SceneTree
# Recommended values (DECISIONS 推荐数值, Q283–Q285): for each guided level,
# start from the design its guide ends on (proofs/guide_designs.txt, written
# by tests/guide_audit.gd) and climb: each open gene of each species one level
# up and one down (within the level's budget); in the virus levels also the
# virus (a point moved from one trait to another) and when it is dropped; in
# the body levels, if the guide's body does not always pass, one block's type
# at a time. A few seeds each; a candidate replaces the best only if it
# passes more (goal, then challenge). The winners go to data/recommend.json
# ({id: {genes, wins, seeds, extra?, virus?, drops?, drop_kind?, blocks?}}),
# merged with what is there.
# Env LEVELS="6-5,7-1" limits it; SEEDS (default 3); ROUNDS (2); FORCE=1
# works a level out again.
# Run: godot --headless --path . -s tests/recommend_bot.gd

const OUT := "res://data/recommend.json"
# Where the calibration found the virus levels pass (tests/probe_44.gd,
# tests/cmp_45.gd): the climb starts there, not at the bench's 3/3/3/3.
const VIRUS_START := {
	"4-4": {virus = {burst = 2, speed = 2, shell = 5, stick = 3, temperate = false}, drops = [60.0, 72.0], kind = "phage"},
	"4-5": {virus = {burst = 4, speed = 5, shell = 1, stick = 2, temperate = true}, drops = [10.0, 30.0], kind = "drop_own"},
}
const TRAITS := ["burst", "speed", "shell", "stick"]


func _initialize() -> void:
	var f := FileAccess.open(ProjectSettings.globalize_path("res://proofs/guide_designs.txt"), FileAccess.READ)
	if f == null:
		print("no proofs/guide_designs.txt: run tests/guide_audit.gd first")
		quit()
		return
	var designs: Dictionary = str_to_var(f.get_as_text())
	var only := OS.get_environment("LEVELS").split(",", false)
	var seeds := int(OS.get_environment("SEEDS")) if OS.get_environment("SEEDS") != "" else 3
	var rounds := int(OS.get_environment("ROUNDS")) if OS.get_environment("ROUNDS") != "" else 2
	var out := {}
	if FileAccess.file_exists(OUT):
		var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(OUT))
		if j is Dictionary:
			out = j
	for id: String in designs:
		if not only.is_empty() and not only.has(id):
			continue
		# (Already worked out: kept, unless asked again with FORCE=1.)
		if out.has(id) and only.is_empty() and OS.get_environment("FORCE") == "":
			continue
		var g: Dictionary = designs[id]
		var l: Dictionary = Levels.by_id(id)
		var best := _start(l, g)
		var best_score := _score(l, g, best, seeds)
		print("%s 起点 %s → %s" % [id, _short(best), str(best_score)])
		for r in rounds:
			var improved := false
			for cand: Dictionary in _neighbours(l, best, best_score[0] < seeds):
				var sc: Array = _score(l, g, cand, seeds)
				if _better(sc, best_score):
					best = cand
					best_score = sc
					improved = true
			print("%s 第 %d 轮 %s → %s" % [id, r + 1, _short(best), str(best_score)])
			if not improved:
				break
		var rec := {genes = best.genes[0], wins = best_score[0], seeds = seeds}
		if best.genes.size() > 1:
			rec.extra = best.genes.slice(1)
		if best.has("virus"):
			rec.virus = best.virus
			rec.drops = best.drops
			rec.drop_kind = best.kind
		if not (best.get("blocks", []) as Array).is_empty():
			rec.blocks = best.blocks
		out[id] = rec
		var w := FileAccess.open(ProjectSettings.globalize_path(OUT), FileAccess.WRITE)
		w.store_string(JSON.stringify(out, "\t"))
		w.close()
	quit()


# The guide's design as a candidate: genes per species slot, the virus and
# its drops, the body.
func _start(l: Dictionary, g: Dictionary) -> Dictionary:
	var c := {genes = []}
	if g.has("slot_designs"):
		for s: Dictionary in g.slot_designs:
			c.genes.append((s.genes as Array).duplicate())
	else:
		c.genes.append((g.genes as Array).duplicate())
	if VIRUS_START.has(l.id):
		var v: Dictionary = VIRUS_START[l.id]
		c.virus = (v.virus as Dictionary).duplicate()
		c.drops = (v.drops as Array).duplicate()
		c.kind = v.kind
	if not (g.get("blocks", []) as Array).is_empty():
		c.blocks = (g.blocks as Array).duplicate(true)
	return c


func _neighbours(l: Dictionary, base: Dictionary, body_too: bool) -> Array:
	var out := []
	# Genes: each open gene of each species, one up and one down.
	for s in (base.genes as Array).size():
		for k: int in l.get("genes_open", []):
			for dv in [1.0, -1.0]:
				var gs: Array = (base.genes[s] as Array).duplicate()
				gs[k] = clampf(float(gs[k]) + dv, 1.0, 5.0)
				if gs == base.genes[s]:
					continue
				var used := 0.0
				for v in gs:
					used += float(v) - 1.0
				if used > float(l.get("budget", 99)) + 0.001:
					continue
				var c := base.duplicate(true)
				c.genes[s] = gs
				out.append(c)
	if base.has("virus"):
		# A point from one trait to another (12 in all, each 1..5).
		for a: String in TRAITS:
			for b: String in TRAITS:
				if a == b or int(base.virus[a]) <= 1 or int(base.virus[b]) >= 5:
					continue
				var c := base.duplicate(true)
				c.virus[a] = int(c.virus[a]) - 1
				c.virus[b] = int(c.virus[b]) + 1
				out.append(c)
		# The first drop sooner or later, the gap shorter or longer.
		var d0: float = base.drops[0]
		var gap: float = float(base.drops[1]) - d0
		for nd: Array in [[d0 - 15.0, gap], [d0 + 15.0, gap], [d0, gap - 10.0], [d0, gap + 10.0]]:
			if float(nd[0]) < 5.0 or float(nd[1]) < 5.0:
				continue
			var c := base.duplicate(true)
			c.drops = [float(nd[0]), float(nd[0]) + float(nd[1])]
			out.append(c)
	if body_too and not (base.get("blocks", []) as Array).is_empty():
		# One block's type at a time, among the kinds the level offers.
		var kinds: Array = (l.get("colony", {}) as Dictionary).get("kinds", [1, 6])
		for i in (base.blocks as Array).size():
			for kd: int in kinds:
				if int(base.blocks[i][2]) == kd:
					continue
				var c := base.duplicate(true)
				c.blocks[i][2] = kd
				out.append(c)
	return out


# One species slot's parameters, as the designer makes them (_params_from).
func _params(l: Dictionary, s: Dictionary, genes: Array) -> Dictionary:
	var d := LevelEval.design_from_genes(genes, (s.deck as Array).duplicate(true), Color(0.5, 0.8, 0.9), float(s.get("temp_opt", 12.0)), true, (s.get("organs", []) as Array).duplicate(), l.id)
	var p: Dictionary = d.params
	# (How it breathes: the level's own unless the level opens the switch.)
	p.resp = int(s.get("resp", 0)) if l.get("resp_open", false) else int(l.get("resp", 0))
	var lf := float(s.get("life", 1.0))
	p.life = lf
	p.lifespan = float(p.lifespan) * lf
	p.slow_divide = 1.0 + 0.4 * (lf - 1.0) if lf >= 1.0 else 1.0 - 0.4 * (1.0 - lf)
	p.acid_tol = float(s.get("acid_tol", 0.0))
	p.eukaryote = bool(s.get("euk", false))
	return {used = d.used, params = p}


# [goal wins, challenge wins, -budget used].
func _score(l: Dictionary, g: Dictionary, c: Dictionary, seeds: int) -> Array:
	var slots: Array = g.get("slot_designs", [g])
	var d := _params(l, slots[0], c.genes[0])
	if c.has("blocks"):
		d.params.blocks = c.blocks
	if (c.genes as Array).size() > 1:
		d.extra = []
		for k in range(1, (c.genes as Array).size()):
			d.extra.append(_params(l, slots[k], c.genes[k]).params)
	d.plan = []
	if c.has("virus"):
		d.virus = c.virus
		for at: float in c.drops:
			d.plan.append({at = at, kind = c.kind, n = 80})
	if l.id == "6-5":
		# (The net only gives way to iron dust: a player drops it as the guide says.)
		for at_t in range(20, 340, 15):
			d.plan.append({at = float(at_t), kind = "iron"})
	d.plan.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.at) < float(b.at))
	var res := []
	res.resize(seeds)
	var s0 := randi() % 900000
	var task := WorkerThreadPool.add_group_task(func(k: int) -> void:
		var ev := LevelEval.simulate(l.duplicate(true), d.duplicate(true), s0 + k)
		res[k] = ev.stars(), seeds)
	WorkerThreadPool.wait_for_group_task_completion(task)
	var goal := 0
	var ch := 0
	for r: Array in res:
		goal += 1 if r[0] else 0
		ch += 1 if r[1] else 0
	var used := 0.0
	for gs: Array in c.genes:
		for v in gs:
			used += float(v) - 1.0
	return [goal, ch, -used]


# Only a set that passes more (goal, then challenge) replaces the guide's
# own: same results for fewer points is no reason to undo what it taught.
func _better(a: Array, b: Array) -> bool:
	for k in 2:
		if a[k] != b[k]:
			return a[k] > b[k]
	return false


func _short(c: Dictionary) -> String:
	var s := str(c.genes)
	if c.has("virus"):
		s += " 病毒 %s 投 %s" % [str(c.virus), str(c.drops)]
	if c.has("blocks"):
		s += " 身体 %d 块" % (c.blocks as Array).size()
	return s
