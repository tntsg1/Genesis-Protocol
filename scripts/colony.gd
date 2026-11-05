class_name Colony
extends RefCounted
# A body built from blocks (level 21, Volvox): what a blueprint can do. The
# designer shows these numbers and the kernel gets them as they are, so the
# player's figures are the game's. A blueprint is a list of [x, y, type]; +x is
# the way it swims.
#   flagellum blocks push, but only on the rim: one walled in by others beats
#   against its neighbours.
#   germ blocks carry the young. Grit in the stream stops at the first block it
#   meets, so a germ block with another block ahead of it is safe.
#   The wider the body the harder the water pushes back, and the more of each
#   clump of algae it catches: a thin one goes through a clump and keeps a part.
# Level 22 (tardigrade):
#   armour blocks: a hunter bites the rim block nearest it; armour gives up
#   little (sim_core.cpp bite_colony). Walled in, it guards nothing.
#   store blocks bank what is left over while the young grow and pay it back
#   when the body runs low (a famine).
# Level 23 (planarian): a bite breaks a block (armour cracks first); broken
#   blocks grow back by themselves, twelve times as fast (level 23) beside a regeneration
#   block; a body bitten in two grows each half whole again.

const BLOCK := 22.0 # µm (sim_core.cpp COL_BLOCK)
const FLAG := 1
const GERM := 6
const ARMOR := 7
const STORE := 8
const REGEN := 9
const MIN_BLOCKS := 3
const MAX_BLOCKS := 12
const SKIN_PAD := 18.0 # µm of jelly room round the blocks
const SKIN_GAP := 5.0 # how far the jelly stands off the blocks, µm
const SKIN_MELT := 12.0
const SKIN_RANGE := 40.0 # the µm a full texture value stands for
const RADIUS := 14.0 # what the kernel's size rules see: the same for every body
const MIN_NET := 6.0 # µm/s over the stream: less than this never gets there in time
const EAT_RATE := 17.85 # energy a second off the algae at width 1 (sim_core.cpp: 9 * r / 6 * 0.85)

# The balance, in one place (tests/probe_52.gd overrides these).
const TUNE := {push = 24.0, drag = 3.0, keep = 0.6, keep_w = 0.2, turn = 3.2, block_e = 18.0, germ_e = 0.6, burn = 1.0}


static func has_block(cells: Array, x: int, y: int) -> bool:
	for c: Array in cells:
		if int(c[0]) == x and int(c[1]) == y:
			return true
	return false


static func type_at(cells: Array, x: int, y: int) -> int:
	for c: Array in cells:
		if int(c[0]) == x and int(c[1]) == y:
			return int(c[2])
	return 0


# Walled in on all four sides.
static func inner(cells: Array, x: int, y: int) -> bool:
	return has_block(cells, x + 1, y) and has_block(cells, x - 1, y) and has_block(cells, x, y + 1) and has_block(cells, x, y - 1)


# Nothing ahead of it in its own row: the first thing grit meets.
static func exposed(cells: Array, x: int, y: int) -> bool:
	for c: Array in cells:
		if int(c[1]) == y and int(c[0]) > x:
			return false
	return true


static func connected(cells: Array) -> bool:
	if cells.is_empty():
		return false
	var seen := {}
	var todo: Array = [[int(cells[0][0]), int(cells[0][1])]]
	while not todo.is_empty():
		var c: Array = todo.pop_back()
		var key := "%d,%d" % c
		if seen.has(key) or not has_block(cells, c[0], c[1]):
			continue
		seen[key] = true
		for d: Array in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
			todo.append([c[0] + d[0], c[1] + d[1]])
	return seen.size() == cells.size()


# What the blueprint comes to. Keys beside the kernel's: n, germ, rim (working
# flagella), walled (idle ones), width, length, unsafe (germ blocks in the open);
# level 22: armor, armor_walled (guarding nothing), store, gaps (rim blocks a
# hunter can bite that are not armour).
static func stats(cells: Array, tune := {}) -> Dictionary:
	var t := TUNE.duplicate()
	t.merge(tune, true)
	var rim := 0
	var walled := 0
	var germ := 0
	var unsafe := 0
	var armor := 0
	var armor_walled := 0
	var store := 0
	var regen := 0
	var gaps := 0
	var rows := {}
	var cols := {}
	for c: Array in cells:
		var x := int(c[0])
		var y := int(c[1])
		rows[y] = true
		cols[x] = true
		var kind := int(c[2])
		var open := not inner(cells, x, y)
		if kind != ARMOR and open:
			gaps += 1
		if kind == GERM:
			germ += 1
			if exposed(cells, x, y):
				unsafe += 1
		elif kind == ARMOR:
			armor += 1
			armor_walled += 0 if open else 1
		elif kind == STORE:
			store += 1
		elif kind == REGEN:
			regen += 1
		elif not open:
			walled += 1
		else:
			rim += 1
	var width := rows.size()
	var length := cols.size()
	var energy: float = float(t.block_e) * cells.size() * (1.0 + float(t.germ_e) * (maxi(germ, 1) - 1))
	var keep: float = minf(1.0, float(t.keep) + float(t.keep_w) * (width - 1))
	return {n = cells.size(), germ = germ, rim = rim, walled = walled, unsafe = unsafe, width = width, length = length,
		armor = armor, armor_walled = armor_walled, store = store, gaps = gaps,
		regen = regen, regen_cover = regen_cover(cells),
		speed = float(t.push) * rim / (width + float(t.drag)),
		turn = float(t.turn) / pow(maxf(length, 1.0), 0.7),
		keep = keep,
		burn_k = float(t.burn),
		energy = energy,
		eat_time = energy / (EAT_RATE * keep)}


# Level 23: how many blocks sit beside a regeneration block (they regrow fast).
static func regen_cover(cells: Array) -> int:
	var n := 0
	for c: Array in cells:
		if int(c[2]) == REGEN:
			continue
		for d: Array in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
			if type_at(cells, int(c[0]) + d[0], int(c[1]) + d[1]) == REGEN:
				n += 1
				break
	return n


# The blueprint centred on its bounding box, as the kernel takes it.
static func centred(cells: Array) -> PackedVector3Array:
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	for c: Array in cells:
		lo = lo.min(Vector2(c[0], c[1]))
		hi = hi.max(Vector2(c[0], c[1]))
	var mid := (lo + hi) * 0.5
	var out := PackedVector3Array()
	for c: Array in cells:
		out.append(Vector3(float(c[0]) - mid.x, float(c[1]) - mid.y, float(c[2])))
	return out


# The side of the square its jelly is drawn in.
static func skin_side(cells: Array) -> float:
	var s := stats(cells)
	return maxf(s.width, s.length) * BLOCK + 2.0 * SKIN_PAD


# The distance to the blueprint's outline, for shaders/colony_skin.gdshader:
# one round cell per block, melted together, so the jelly swells softly over
# each cell like a morula's and has no corners or straight runs; blended a
# little toward the oval round the whole body, so its sides bow out like a
# ball of gel's while it still follows the shape the player built.
static func bake_skin(cells: Array, size: int) -> ImageTexture:
	var side := skin_side(cells)
	var body := centred(cells)
	var data := PackedByteArray()
	data.resize(size * size)
	var r := BLOCK * 0.5 + 3.0
	var melt := SKIN_MELT * 0.35
	var reach := Vector2.ZERO
	for b in body:
		reach = reach.max(Vector2(absf(b.x), absf(b.y)) * BLOCK)
	var oval := (reach + Vector2.ONE * r) * 1.4142
	for j in size:
		var py := ((j + 0.5) / size - 0.5) * side
		for i in size:
			var px := ((i + 0.5) / size - 0.5) * side
			var d := 1e6
			for b in body:
				var disc := Vector2(px - b.x * BLOCK, py - b.y * BLOCK).length() - r
				# A smooth minimum: neighbouring cells flow into each other.
				var h := clampf(0.5 + 0.5 * (disc - d) / melt, 0.0, 1.0)
				d = lerpf(disc, d, h) - melt * h * (1.0 - h)
			var de := (Vector2(px, py) / oval).length() - 1.0
			d = lerpf(d, de * minf(oval.x, oval.y), 0.45) - SKIN_GAP
			data[j * size + i] = int(clampf(0.5 + d / (2.0 * SKIN_RANGE), 0.0, 1.0) * 255.0)
	return ImageTexture.create_from_image(Image.create_from_data(size, size, false, Image.FORMAT_R8, data))


static var _seeds := PackedVector4Array()


# Where the cells of a germ block's embryo sit on its sphere, cleavage by
# cleavage, for shaders/colony.gdshader: 2, 4, ... 64 points (levels 1-6, 126
# in all, level n from index 2^n - 2; point j's mother is point j / 2 of the
# level before). The first two cleavages cut through the poles (+y is where
# the phialopore opens), so they meet in a cross there, as in Volvox. At the
# sixth, 16 cells of the posterior half divide unequally: w = 1 marks the big
# daughter, a gonidium.
static func embryo_seeds() -> PackedVector4Array:
	if not _seeds.is_empty():
		return _seeds
	var levels: Array[PackedVector3Array] = [PackedVector3Array([Vector3.RIGHT, Vector3.LEFT])]
	var cut := PackedVector3Array([Vector3.RIGHT, Vector3.RIGHT])
	for n in range(2, 7):
		var up: PackedVector3Array = levels[-1]
		var pts := PackedVector3Array()
		var cuts := PackedVector3Array()
		var d := 0.5 * sqrt(4.0 * PI / pow(2.0, n))
		for k in up.size():
			var p := up[k]
			var t := Vector3.BACK if n == 2 else p.cross(cut[k]).normalized()
			pts.append((p + t * d).normalized())
			pts.append((p - t * d).normalized())
			cuts.append(t)
			cuts.append(t)
		# A little room-making: the daughters spread over the sphere evenly.
		for it in (0 if n == 2 else 24):
			var moved := PackedVector3Array(pts)
			for i in pts.size():
				var f := Vector3.ZERO
				for j in pts.size():
					if i != j:
						var r := pts[i] - pts[j]
						f += r / pow(maxf(r.length(), 0.05), 3.0)
				f -= pts[i] * f.dot(pts[i])
				moved[i] = (pts[i] + f * 0.02 * d * d).normalized()
			pts = moved
		levels.append(pts)
		cut = cuts
	# The gonidia: 16 of the 20 lowest of the 32 (the posterior half, away from
	# +y), spread out, each one's lower daughter.
	var free: Array[int] = []
	free.assign(range(32))
	free.sort_custom(func(a: int, b: int) -> bool: return levels[4][a].y < levels[4][b].y)
	free.resize(20)
	var picked: Array[int] = []
	while picked.size() < 16 and not free.is_empty():
		var best := 0
		var far := -1.0
		for i in free.size():
			var near := 9.0 if picked.is_empty() else 1e9
			for m in picked:
				near = minf(near, levels[4][free[i]].distance_to(levels[4][m]))
			if picked.is_empty():
				near = -levels[4][free[i]].y
			if near > far:
				far = near
				best = i
		picked.append(free[best])
		free.remove_at(best)
	var big := {}
	for m in picked:
		big[2 * m + (0 if levels[5][2 * m].y < levels[5][2 * m + 1].y else 1)] = true
	for n in levels.size():
		for j in levels[n].size():
			var p: Vector3 = levels[n][j]
			_seeds.append(Vector4(p.x, p.y, p.z, 1.0 if n == 5 and big.has(j) else 0.0))
	return _seeds


# The 16 gonidia of embryo_seeds().
static func embryo_gonidia() -> PackedVector3Array:
	var out := PackedVector3Array()
	for s in embryo_seeds():
		if s.w > 0.5:
			out.append(Vector3(s.x, s.y, s.z))
	return out


# Species parameters for SimCore.
static func params(cells: Array, tune := {}) -> Dictionary:
	var s := stats(cells, tune)
	return {colony = true, body = centred(cells), radius = RADIUS, cohesion = 0.0, burn = s.n / 8.0 * float(s.burn_k),
		col_speed = s.speed, col_turn = s.turn, col_keep = s.keep, col_e = s.energy, col_skin = skin_side(cells)}
