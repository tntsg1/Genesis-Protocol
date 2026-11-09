extends SceneTree
# Recommended values (DECISIONS 推荐数值): for each guided level, start from
# the design its guide ends on (proofs/guide_designs.txt, written by
# tests/guide_audit.gd), try each open gene one level up and one down
# (within the level's budget), a few seeds each, and keep the set that passes
# most; a second round from there if it helped. The winners go to
# data/recommend.json ({id: {genes, wins, seeds}}), merged with what is there.
# Levels whose design is more than genes (bodies, viruses, several species)
# are left out. Env LEVELS="6-5,7-1" limits it; SEEDS (default 3); ROUNDS (2).
# Run: godot --headless --path . -s tests/recommend_bot.gd

const OUT := "res://data/recommend.json"
const SKIP := ["4-4", "4-5", "5-1", "5-2", "5-3", "5-4", "5-5"]


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
		if SKIP.has(id) or (not only.is_empty() and not only.has(id)):
			continue
		# (Already worked out: kept, unless asked again with FORCE=1.)
		if out.has(id) and only.is_empty() and OS.get_environment("FORCE") == "":
			continue
		var g: Dictionary = designs[id]
		if int(g.get("slots", 0)) > 1:
			continue
		var l: Dictionary = Levels.by_id(id)
		var best: Array = (g.genes as Array).duplicate()
		var best_score := _score(l, g, best, seeds)
		print("%s 起点 %s → %s" % [id, str(best), str(best_score)])
		for r in rounds:
			var improved := false
			for cand: Array in _neighbours(l, g, best):
				var sc: Array = _score(l, g, cand, seeds)
				if _better(sc, best_score):
					best = cand
					best_score = sc
					improved = true
			print("%s 第 %d 轮 %s → %s" % [id, r + 1, str(best), str(best_score)])
			if not improved:
				break
		out[id] = {genes = best, wins = best_score[0], seeds = seeds}
		var w := FileAccess.open(ProjectSettings.globalize_path(OUT), FileAccess.WRITE)
		w.store_string(JSON.stringify(out, "\t"))
		w.close()
	quit()


# Every open gene one up and one down, inside 1..5 and the budget.
func _neighbours(l: Dictionary, g: Dictionary, base: Array) -> Array:
	var out := []
	for k: int in l.get("genes_open", []):
		for dv in [1.0, -1.0]:
			var c := base.duplicate()
			c[k] = clampf(float(c[k]) + dv, 1.0, 5.0)
			if c == base:
				continue
			var used := 0.0
			for v in c:
				used += float(v) - 1.0
			if l.get("resp_open", false):
				used += Resp.cost(int(g.get("resp", 0)))
			if used > float(l.get("budget", 99)) + 0.001:
				continue
			out.append(c)
	return out


# [goal wins, challenge wins, -budget used]: more is better, in that order.
func _score(l: Dictionary, g: Dictionary, genes: Array, seeds: int) -> Array:
	var d := LevelEval.design_from_genes(genes, (g.deck as Array).duplicate(true), Color(0.5, 0.8, 0.9), float(g.get("temp_opt", 12.0)), true, (g.organs as Array).duplicate(), l.id)
	d.params.resp = int(g.get("resp", l.get("resp", 0)))
	d.params.life = float(g.get("life", 1.0))
	d.params.lifespan = float(d.params.lifespan) * float(g.get("life", 1.0))
	d.params.slow_divide = 1.0 + 0.4 * (float(g.get("life", 1.0)) - 1.0) if float(g.get("life", 1.0)) >= 1.0 else 1.0 - 0.4 * (1.0 - float(g.get("life", 1.0)))
	d.params.acid_tol = float(g.get("acid_tol", 0.0))
	d.params.eukaryote = bool(g.get("euk", false))
	if l.id == "6-5":
		# (The net only gives way to iron dust: a player drops it as the guide says.)
		var iron := []
		for at_t in range(20, 340, 15):
			iron.append({at = float(at_t), kind = "iron"})
		d.plan = iron
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
	for v in genes:
		used += float(v) - 1.0
	return [goal, ch, -used]


func _better(a: Array, b: Array) -> bool:
	for k in a.size():
		if a[k] != b[k]:
			return a[k] > b[k]
	return false
