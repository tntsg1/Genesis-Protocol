extends RefCounted
# The maps of chapters 3 to 10 (design/CAMPAIGN.md), one class each on
# scripts/ui/campaign_scene.gd: a place as scan data and the chapter's
# real-world prototype as the hologram over it.
#   3 群居篇  deep dark water: swarms that light up in waves, signal rings;
#             emblem a Vibrio (quorum sensing)
#   4 噬体篇  an ice crevasse narrowing down, virus crystals adrift; emblem a
#             T4 phage that fires its DNA into a membrane
#   5 多细胞篇 one giant black smoker on its mound; emblem a Volvox colony
#   6 播种篇  planet 1, a hot-spring seabed of stromatolites, oxygen rising;
#             emblem the seed ship 创生协议 and its beam
#   7 寒夜篇  planet 2, a frozen sea: crevasse maze, watermelon snow, aurora;
#             emblem an endospore
#   8 腐土篇  planet 3, an acid swamp cut open to its coloured mud layers,
#             reeds and bubbles; emblem a slime-mould network
#   9 演化篇  planet 4, a salt flat of crystal spires under radiation;
#             emblem a tree of life from one ancestor
#   10 终章   planet 5, a lightless trench whose floor is one living mat;
#             emblem the apex colony

const Scene := preload("res://scripts/ui/campaign_scene.gd")


static func make(ch: int, model: Control, parent: Node3D) -> Scene:
	match ch:
		3: return Ch3.new(model, parent, ch)
		4: return Ch4.new(model, parent, ch)
		5: return Ch5.new(model, parent, ch)
		6: return Ch6.new(model, parent, ch)
		7: return Ch7.new(model, parent, ch)
		8: return Ch8.new(model, parent, ch)
		9: return Ch9.new(model, parent, ch)
		10: return Ch10.new(model, parent, ch)
	return null


# --- 3 · deep dark water -----------------------------------------------------------

class Ch3 extends "res://scripts/ui/campaign_scene.gd":
	var swarms: Array[Vector3] = []

	func configure() -> void:
		place = "深层暗水"
		place_en = "DEEP DARK WATER  ·  EUROPA  9.6 km –"
		emblem = "群体感应 · 夜光弧"
		emblem_en = "QUORUM SENSING  ·  VIBRIO FISCHERI"
		hot = Color(0.12, 0.82, 0.8)
		motes = Vector2(-0.5, 6.1)
		holo_c = Vector3(-2.3, -1.9, -0.7)
		for s: Array in [[1.6, -1.4, -1.0], [2.8, -2.6, 0.9], [-0.6, -3.0, 1.4], [1.0, -4.1, -0.6], [-1.7, -4.6, 0.2], [2.6, -5.1, -1.2], [-2.9, -3.6, -1.5], [0.2, -5.7, 1.6]]:
			swarms.append(Vector3(s[0], s[1], s[2]))

	func bake(c, h) -> void:
		var rng: RandomNumberGenerator = c.rng
		drift(c, 5000, Color(0.05, 0.5, 0.72), Color(0.12, 0.25, 0.55))
		# Thermoclines: faint sheets swaying.
		for y: float in [-1.2, -2.7, -4.3]:
			for k in 2600:
				c.add(Vector3(rng.randf_range(-HALF.x, HALF.x), y + rng.randfn() * 0.03, rng.randf_range(-HALF.y, HALF.y)), Color(0.1, 0.45, 0.65, 0.12), 1.3, 4.0, y)
		# The swarms: each lights up in turn, the wave running across them.
		for s in swarms:
			var grp := s.x * 0.9 - s.y * 0.6
			for k in 1100:
				var d := Vector3(rng.randfn() * 0.42, rng.randfn() * 0.24, rng.randfn() * 0.36)
				c.add(s + d, Color(0.06, 0.55, 0.6, rng.randf_range(0.28, 0.55)), rng.randf_range(1.3, 1.9), 3.0, grp)
			ball(c, s, 0.1, 80, Color(0.2, 0.75, 0.75, 0.7), 2.0, false, 3.0, grp)
		# The floor far below: soft sediment.
		ground(c, func(x: float, z: float) -> float: return bottom + 0.15 + _n(x * 0.5, z * 0.5, 31.0) * 0.12, 0.08, func(_y: float) -> Color: return Color(0.18, 0.28, 0.46, 0.3), 0.05, 0.12)
		# The Vibrio: a curved rod, ringed; signal molecules round it.
		var arc := func(t: float) -> Vector3:
			var a := lerpf(-0.7, 0.7, t)
			return Vector3(sin(a) * 1.15, 0.0, cos(a) * 1.15 - 1.15)
		for i in 60:
			var t := i / 59.0
			var cc: Vector3 = arc.call(t)
			var tan: Vector3 = (arc.call(minf(1.0, t + 0.01)) - arc.call(maxf(0.0, t - 0.01))).normalized()
			var u := tan.cross(Vector3.UP).normalized()
			var v := tan.cross(u)
			var r := 0.3 * sqrt(maxf(0.0, 1.0 - pow(t * 2.0 - 1.0, 8.0)))
			for k in 36:
				var a := TAU * k / 36.0
				h.add(cc + (u * cos(a) + v * sin(a)) * r, Color(0.06, 0.6, 0.72, 0.5), 1.4)
		ball(h, Vector3(0.05, 0.0, -0.1), 0.16, 500, Color(0.15, 0.7, 0.62, 0.55), 1.5)
		for k in 260:
			var d := dir3(h.rng as RandomNumberGenerator) * (h.rng as RandomNumberGenerator).randf_range(0.6, 1.25)
			h.add(d, Color(0.1, 0.8, 0.7, 0.7), 2.0, 3.0, d.length() * 3.0)

	# Signal rings spreading from the swarms; the Vibrio's flagellum.
	func animate(time: float, _delta: float) -> void:
		anim.clear_surfaces()
		anim.surface_begin(Mesh.PRIMITIVE_LINES)
		for k in swarms.size():
			var u := fposmod(time * 0.35 + k * 0.37, 1.0)
			var r := 0.3 + u * 1.6
			var seg := 40
			for j in seg:
				if j % 2 == 1:
					continue
				var a0 := TAU * j / seg
				var a1 := TAU * (j + 1) / seg
				anim.surface_set_color(Color(1, 1, 1, 1.0 - u))
				anim.surface_add_vertex(swarms[k] + Vector3(cos(a0) * r, 0.0, sin(a0) * r))
				anim.surface_set_color(Color(1, 1, 1, 1.0 - u))
				anim.surface_add_vertex(swarms[k] + Vector3(cos(a1) * r, 0.0, sin(a1) * r))
		anim.surface_end()
		holo_lines.clear_surfaces()
		holo_lines.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		var base := Vector3(sin(0.7) * 1.15, 0.0, cos(0.7) * 1.15 - 1.15)
		for i in 40:
			var t := i / 39.0
			holo_lines.surface_add_vertex(base + Vector3(t * 0.9, sin(t * 12.0 - time * 8.0) * 0.08 * t, cos(t * 12.0 - time * 8.0) * 0.08 * t))
		holo_lines.surface_end()

	func spots(n: int) -> Array:
		# A tether winding down past the swarms.
		var out := []
		for k in n:
			var t := (k + 0.5) / maxf(1.0, n)
			out.append(Vector3(0.55 + sin(t * 5.0) * 0.6, lerpf(top - 0.6, bottom + 0.6, t), 0.35 + cos(t * 5.0) * 0.4))
		return out

	func more_labels(a: float) -> void:
		tag(swarms[4], Vector2(-150, 34), "夜光弧菌群", "BIOLUMINESCENT SWARM", Color(0.1, 0.62, 0.62), a)


# --- 4 · the ice crevasse --------------------------------------------------------

class Ch4 extends "res://scripts/ui/campaign_scene.gd":
	func configure() -> void:
		place = "冰缝深处"
		place_en = "ICE CREVASSE  ·  EUROPA"
		emblem = "噬菌体 · 裂囊针"
		emblem_en = "BACTERIOPHAGE T4  ·  ×80 000"
		emblem_col = Color(0.62, 0.3, 0.62)
		holo_c = Vector3(-2.4, -2.2, -0.4)
		holo_r = 1.15
		motes = Vector2(-0.6, 6.0)

	# The crevasse's half width at depth y, its middle at (y, z).
	func half_w(y: float, z: float) -> float:
		var t := clampf((y - bottom) / (top - bottom), 0.0, 1.0)
		return 0.2 + 1.9 * pow(t, 1.6) + _n(y * 1.3, z * 1.3, 44.0) * 0.12

	func mid_x(y: float, z: float) -> float:
		return 0.55 + sin(z * 0.9 + y * 0.4) * 0.25 + _n(y * 0.6, z * 0.6, 45.0) * 0.15

	func bake(c, h) -> void:
		var rng: RandomNumberGenerator = c.rng
		# The walls: jagged, the ice's grain in bands down them.
		var y := top
		while y > bottom:
			var z := -HALF.y
			while z < HALF.y:
				for side: float in [-1.0, 1.0]:
					var x := mid_x(y, z) + side * (half_w(y, z) + absf(_n(y * 4.0, z * 4.0, 46.0)) * 0.18)
					var band := absf(fposmod(y * 3.0 + _n(z, y, 47.0) * 0.5, 1.0) - 0.5)
					var line := smoothstep(0.42, 0.48, band)
					if line > 0.2 or rng.randf() < 0.7:
						var col := Color(0.35, 0.55, 0.68).lerp(Color(0.05, 0.32, 0.52), clampf(-y / 6.5, 0.0, 1.0))
						col.a = 0.34 + line * 0.45
						c.add(Vector3(x, y, z), col, 1.5)
				z += 0.04
			y -= 0.04
		# The ice either side, cut at the front: strata.
		for xs: float in [-1.0, 1.0]:
			var x := -HALF.x if xs < 0.0 else 0.0
			while (xs < 0.0 and x < 0.0) or (xs > 0.0 and x < HALF.x):
				var yy := top
				while yy > bottom:
					var w := mid_x(yy, HALF.y) + xs * half_w(yy, HALF.y)
					if (xs < 0.0 and x < w) or (xs > 0.0 and x > w):
						var band := absf(fposmod(yy * 6.0 + _n(x, yy, 48.0) * 0.6, 1.0) - 0.5)
						if band > 0.38 or rng.randf() < 0.15:
							c.add(Vector3(x, yy, HALF.y), Color(0.3, 0.55, 0.68, 0.14 + (0.2 if band > 0.38 else 0.0)), 1.4)
					yy -= 0.05
				x += 0.04
		# The surface's lineae, faint.
		ground(c, func(x: float, z: float) -> float: return top, 0.5, func(_y: float) -> Color: return Color(0.55, 0.68, 0.76, 0.12), 0.07, 0.08)
		# Virus crystals adrift in the crack: little bright clusters.
		for k in 90:
			var yy := rng.randf_range(bottom + 0.3, top - 0.3)
			var zz := rng.randf_range(-HALF.y, HALF.y) * 0.9
			var at := Vector3(mid_x(yy, zz) + rng.randfn() * half_w(yy, zz) * 0.4, yy, zz)
			ball(c, at, 0.035, 14, Color(0.6, 0.35, 0.65, 0.75), 1.6)
		drift(c, 3000, Color(0.3, 0.6, 0.75), Color(0.1, 0.3, 0.55))
		# T4: an icosahedral head, the tail, the baseplate, six fibres; a
		# patch of membrane below it.
		var phi := (1.0 + sqrt(5.0)) * 0.5
		var vs: Array[Vector3] = []
		for s1: float in [-1.0, 1.0]:
			for s2: float in [-1.0, 1.0]:
				vs.append(Vector3(0, s1, s2 * phi))
				vs.append(Vector3(s1, s2 * phi, 0))
				vs.append(Vector3(s2 * phi, 0, s1))
		var head := Vector3(0, 0.55, 0)
		var sc := Vector3(0.32, 0.42, 0.32)
		for i in vs.size():
			for j in range(i + 1, vs.size()):
				if absf(vs[i].distance_to(vs[j]) - 2.0) < 0.01:
					for k in 26:
						var p := vs[i].lerp(vs[j], k / 25.0).normalized() * Vector3(1.0, 1.25, 1.0)
						h.add(head + p * sc, Color(0.55, 0.3, 0.62, 0.75), 1.5)
		ball(h, head, 0.24, 900, Color(0.55, 0.3, 0.62, 0.22), 1.3)
		for k in 40:
			var yy := lerpf(0.12, -0.55, k / 39.0)
			for j in 16:
				var a := TAU * j / 16.0
				h.add(Vector3(cos(a) * 0.07, yy, sin(a) * 0.07), Color(0.1, 0.55, 0.68, 0.6), 1.3)
		for j in 6:
			var a := TAU * j / 6.0
			for k in 30:
				var t := k / 29.0
				var reach := Vector3(cos(a), 0.0, sin(a))
				h.add(Vector3(0, -0.58, 0) + reach * (0.12 + t * 0.55) + Vector3(0, -sin(t * PI) * 0.18 - t * 0.25, 0), Color(0.1, 0.55, 0.68, 0.65), 1.4)
		for k in 900:
			var x := (h.rng as RandomNumberGenerator).randf_range(-1.2, 1.2)
			var zz := (h.rng as RandomNumberGenerator).randf_range(-0.8, 0.8)
			h.add(Vector3(x, -1.05 - (x * x + zz * zz) * 0.08, zz), Color(0.2, 0.62, 0.55, 0.35), 1.4)

	# Every 3.6 s the tail fires: DNA spirals down into the membrane.
	func animate(time: float, _delta: float) -> void:
		holo_lines.clear_surfaces()
		var u := fposmod(time / 3.6, 1.0)
		if u > 0.55:
			return
		var reach := minf(1.0, u / 0.3)
		holo_lines.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		for i in 50:
			var t := i / 49.0 * reach
			var y := lerpf(-0.6, -1.15, t)
			holo_lines.surface_add_vertex(Vector3(cos(t * 30.0) * 0.03, y, sin(t * 30.0) * 0.03))
		holo_lines.surface_end()

	func spots(n: int) -> Array:
		var out := []
		for k in n:
			var t := (k + 0.5) / maxf(1.0, n)
			var y := lerpf(top - 0.6, bottom + 0.5, t)
			out.append(Vector3(mid_x(y, 0.35), y, 0.35))
		return out


# --- 5 · the giant vent ----------------------------------------------------------

class Ch5 extends "res://scripts/ui/campaign_scene.gd":
	const BASE := -6.2
	var tip := Vector3.ZERO

	func configure() -> void:
		place = "热液喷口"
		place_en = "HYDROTHERMAL VENT  ·  EUROPA SEAFLOOR"
		emblem = "多细胞群体 · 团藻"
		emblem_en = "COLONY  ·  VOLVOX  ·  ×400"
		emblem_col = Color(0.15, 0.6, 0.4)
		holo_c = Vector3(-2.4, -2.0, -0.6)
		rise = 3.4
		motes = Vector2(-0.5, 5.6)

	func floor_h(x: float, z: float) -> float:
		var r2 := (x - 0.9) ** 2 + (z + 0.2) ** 2
		return BASE + 0.9 * exp(-r2 / 2.2) + _n(x * 0.5, z * 0.5, 51.0) * 0.12

	func bake(c, h) -> void:
		var rng: RandomNumberGenerator = c.rng
		ground(c, floor_h, 0.07, func(y: float) -> Color: return Color(0.2, 0.28, 0.46, 0.35), 0.036, 0.2)
		section(c, floor_h, HALF.y, bottom, Color(0.2, 0.28, 0.46))
		# The tower: 4 km of chimney, flanges stepping out of it.
		var at := Vector3(0.9, floor_h(0.9, -0.2) - 0.05, -0.2)
		var hgt := 4.0
		var n := int(hgt / 0.03)
		for j in n:
			var t := float(j) / n
			var r := lerpf(0.55, 0.12, pow(t, 0.7)) * (1.0 + 0.3 * _n(t * 9.0, 0.0, 52.0))
			for fl: float in [0.22, 0.41, 0.58, 0.74]:
				r *= 1.0 + 1.1 * exp(-pow((t - fl) / 0.018, 2.0))
			var lean := Vector2(sin(t * 2.0) * 0.12, cos(t * 1.6) * 0.08) * t
			var cnt := maxi(10, int(TAU * r / 0.016))
			for k in cnt:
				if rng.randf() < 0.4:
					continue
				var a := TAU * k / cnt + j * 0.31
				c.add(Vector3(at.x + lean.x + cos(a) * r, at.y + t * hgt, at.z + lean.y + sin(a) * r), Color(INK.lerp(Color(0.1, 0.4, 0.55), 0.4 * t), 0.24 + 0.14 * rng.randf()), 1.3)
		tip = at + Vector3(sin(2.0) * 0.12, hgt + 0.03, cos(1.6) * 0.08)
		plume(c, tip, 4200, Color(0.3, 0.85, 0.95, 0.32), 0.1)
		ball(c, tip, 0.12, 400, Color(0.55, 0.95, 1.0, 0.5), 2.2)
		# Little chimneys and life round the foot.
		for s: Array in [[-1.4, 1.1, 0.9], [2.6, 0.9, 1.1], [-0.4, -1.6, 0.7], [2.9, -1.5, 0.8]]:
			var b := Vector3(s[0], floor_h(s[0], s[1]), s[1])
			for j in 24:
				var t := j / 23.0
				var r := lerpf(0.12, 0.04, t)
				for k in 12:
					var a := TAU * k / 12.0
					c.add(b + Vector3(cos(a) * r, t * float(s[2]), sin(a) * r), Color(INK, 0.35), 1.3)
			plume(c, b + Vector3(0, float(s[2]), 0), 700, Color(0.3, 0.85, 0.95, 0.28))
		for k in 5000:
			var o := Vector2(rng.randfn(), rng.randfn()) * 0.9
			var x := 0.9 + o.x
			var z := -0.2 + o.y
			c.add(Vector3(x, floor_h(x, z) + 0.02, z), Color(0.12, 0.6, 0.45, rng.randf_range(0.2, 0.5)), rng.randf_range(1.3, 2.0), 3.0, o.length() * 3.0)
		drift(c, 5000, Color(0.05, 0.55, 0.75), Color(0.12, 0.3, 0.58))
		# Volvox: a sphere of cells (little rings) with daughter colonies in it.
		var golden := PI * (3.0 - sqrt(5.0))
		var cells := 520
		for i in cells:
			var yy := 1.0 - 2.0 * (i + 0.5) / cells
			var rr := sqrt(1.0 - yy * yy)
			var d := Vector3(cos(golden * i) * rr, yy, sin(golden * i) * rr)
			var u := d.cross(Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT).normalized()
			var v := d.cross(u)
			for k in 7:
				var a := TAU * k / 7.0
				h.add(d * 0.95 + (u * cos(a) + v * sin(a)) * 0.035, Color(0.15, 0.6, 0.42, 0.65), 1.3, 3.0, d.y * 3.0)
		ball(h, Vector3.ZERO, 0.93, 1500, Color(0.15, 0.55, 0.45, 0.1), 1.2, true)
		for dc: Vector3 in [Vector3(0.35, 0.25, 0.1), Vector3(-0.3, -0.2, 0.3), Vector3(0.05, -0.35, -0.35), Vector3(-0.25, 0.35, -0.2)]:
			ball(h, dc, 0.2, 260, Color(0.2, 0.62, 0.35, 0.6), 1.5, true)
			ball(h, dc, 0.12, 80, Color(0.25, 0.65, 0.4, 0.5), 1.4)

	func spots(n: int) -> Array:
		# Round and up the tower, the deepest at its foot.
		var out := []
		for k in n:
			var t := (k + 0.5) / maxf(1.0, n)
			var a := t * TAU * 1.2
			out.append(Vector3(0.9 + cos(a) * 1.1, lerpf(-1.4, BASE + 0.5, t), -0.2 + sin(a) * 1.1))
		return out

	func more_labels(a: float) -> void:
		tag(tip, Vector2(-170, -40), "巨型黑烟囱", "BLACK SMOKER  ·  4 km  ·  380 °C", Color(0.07, 0.55, 0.66), a)


# --- 6 · planet 1: the hot-spring seabed -----------------------------------------

class Ch6 extends "res://scripts/ui/campaign_scene.gd":
	const SEA := -5.8
	var domes: Array = []
	var ship := Vector3(-2.3, -1.4, -0.7)

	func configure() -> void:
		place = "热泉海床"
		place_en = "HOT-SPRING SEABED  ·  PLANET I"
		emblem = "播种飞船 · 创生协议"
		emblem_en = "SEED SHIP  ·  GENESIS PROTOCOL"
		holo_c = ship
		holo_r = 1.05
		rise = 4.4
		motes = Vector2(-0.4, 5.4)
		for d: Array in [[-1.6, 0.8, 0.5, 0.55], [-0.4, -1.2, 0.7, 0.75], [1.2, 1.3, 0.45, 0.5], [2.4, -0.6, 0.65, 0.7], [0.4, 0.4, 0.38, 0.42], [3.1, 1.6, 0.4, 0.45], [-3.0, -1.4, 0.5, 0.55]]:
			domes.append(d)

	func floor_h(x: float, z: float) -> float:
		var y := SEA + _n(x * 0.4, z * 0.4, 61.0) * 0.18
		for d: Array in domes:
			var r2: float = ((x - float(d[0])) ** 2 + (z - float(d[1])) ** 2) / (float(d[2]) * float(d[2]))
			if r2 < 1.0:
				y = maxf(y, SEA + float(d[3]) * sqrt(1.0 - r2))
		return y

	func bake(c, h) -> void:
		var rng: RandomNumberGenerator = c.rng
		# Stromatolites: domes of layer on layer (contours every 30 m).
		ground(c, floor_h, 0.03, func(y: float) -> Color: return Color(0.25, 0.38, 0.42, 0.45).lerp(Color(0.1, 0.48, 0.38, 0.7), clampf((y - SEA) / 0.7, 0.0, 1.0)), 0.03, 0.18)
		section(c, floor_h, HALF.y, bottom, Color(0.28, 0.36, 0.42))
		# Hot springs: shimmering pools, and oxygen rising off the domes.
		for d: Array in domes:
			plume(c, Vector3(d[0], SEA + float(d[3]), d[1]), 900, Color(0.85, 0.97, 1.0, 0.45), float(d[2]) * 0.5)
		for s: Vector2 in [Vector2(1.9, 0.2), Vector2(-2.2, -0.3)]:
			ball(c, Vector3(s.x, SEA + 0.04, s.y), 0.25, 700, Color(0.4, 0.85, 0.95, 0.4), 1.6, false, 3.0, s.x)
		# The sea's surface far above, swaying; drifting particles.
		for k in 9000:
			c.add(Vector3(rng.randf_range(-HALF.x, HALF.x), top + rng.randfn() * 0.03, rng.randf_range(-HALF.y, HALF.y)), Color(0.2, 0.6, 0.8, 0.2), 1.4, 4.0, rng.randf() * 0.5)
		drift(c, 4000, Color(0.1, 0.6, 0.8), Color(0.2, 0.45, 0.6))
		# The seed ship: a long hull ringed with frames, wings of panels,
		# an engine bell.
		for i in 70:
			var t := i / 69.0
			var x := lerpf(-1.1, 1.1, t)
			var r := 0.22 * sqrt(maxf(0.0, 1.0 - pow(t * 2.0 - 1.0, 6.0))) + 0.04
			for k in 24:
				var a := TAU * k / 24.0
				h.add(Vector3(x, sin(a) * r, cos(a) * r), Color(0.04, 0.5, 0.66, 0.8 if i % 7 == 0 else 0.45), 1.5)
		for side: float in [-1.0, 1.0]:
			for k in 1600:
				var x := (h.rng as RandomNumberGenerator).randf_range(-0.6, 0.4)
				var w := (h.rng as RandomNumberGenerator).randf_range(0.0, 1.0)
				var gx := absf(fposmod(x * 10.0, 1.0) - 0.5) > 0.42 or absf(fposmod(w * 8.0, 1.0) - 0.5) > 0.42
				h.add(Vector3(x - w * 0.25, 0.0, side * (0.25 + w * 0.7)), Color(0.08, 0.5, 0.68, 0.75 if gx else 0.3), 1.4)
		ball(h, Vector3(-1.15, 0, 0), 0.12, 300, Color(0.4, 0.9, 1.0, 0.6), 1.8, true)

	# The seed beam: down from the ship, rings travelling it.
	func animate(time: float, _delta: float) -> void:
		anim.clear_surfaces()
		anim.surface_begin(Mesh.PRIMITIVE_LINES)
		var foot := Vector3(ship.x + 0.6, SEA + 0.4, ship.z + 0.3)
		for j in 8:
			var a := TAU * j / 8.0
			anim.surface_add_vertex(ship + Vector3(0.0, -0.25, 0.0))
			anim.surface_add_vertex(foot + Vector3(cos(a), 0, sin(a)) * 0.45)
		for k in 4:
			var u := fposmod(time * 0.3 + k * 0.25, 1.0)
			var at := (ship + Vector3(0, -0.25, 0)).lerp(foot, u)
			var r := 0.45 * u
			for j in 24:
				anim.surface_add_vertex(at + Vector3(cos(TAU * j / 24.0), 0, sin(TAU * j / 24.0)) * r)
				anim.surface_add_vertex(at + Vector3(cos(TAU * (j + 1) / 24.0), 0, sin(TAU * (j + 1) / 24.0)) * r)
		anim.surface_end()

	func tick(time: float, delta: float) -> void:
		super.tick(time, delta)
		if baked:
			holo.rotation.y = 0.3 + sin(time * 0.2) * 0.25


# --- 7 · planet 2: the frozen sea ---------------------------------------------------

class Ch7 extends "res://scripts/ui/campaign_scene.gd":
	const ICE_TOP := 0.0
	const ICE_BOT := -2.4

	func configure() -> void:
		place = "冰封海"
		place_en = "FROZEN SEA  ·  PLANET II  ·  POLAR NIGHT"
		emblem = "芽孢"
		emblem_en = "ENDOSPORE  ·  ×20 000"
		emblem_col = Color(0.5, 0.35, 0.62)
		top = 1.8
		bottom = -6.4
		focus = -2.3
		dist = 29.0
		holo_c = Vector3(-2.5, 0.9, -0.8)
		holo_r = 0.85
		motes = Vector2(ICE_BOT - 0.1, 3.9)

	func bake(c, h) -> void:
		var rng: RandomNumberGenerator = c.rng
		# The ice: its top as a maze of cracks, watermelon snow in patches.
		ground(c, func(x: float, z: float) -> float: return ICE_TOP + _n(x * 0.6, z * 0.6, 71.0) * 0.06, 0.02, func(_y: float) -> Color: return Color(0.55, 0.7, 0.8, 0.22), 0.04, 0.2)
		var x := -HALF.x
		while x < HALF.x:
			var z := -HALF.y
			while z < HALF.y:
				var gx := absf(fposmod(x * 1.4 + _n(z * 1.5, 0.0, 72.0) * 0.6, 1.0) - 0.5)
				var gz := absf(fposmod(z * 1.4 + _n(x * 1.5, 0.0, 73.0) * 0.6, 1.0) - 0.5)
				var on_x := 1.0 if _n(x * 0.9, z * 0.9, 74.0) >= 0.0 else 0.0
				var on_z := 1.0 if _n(x * 0.9, z * 0.9, 75.0) >= 0.0 else 0.0
				var crack := maxf(smoothstep(0.44, 0.49, gx) * on_x, smoothstep(0.44, 0.49, gz) * on_z)
				if crack > 0.3:
					c.add(Vector3(x, ICE_TOP + 0.01, z), Color(0.1, 0.32, 0.5, 0.6), 1.6)
				var snow := _n(x * 1.2, z * 1.2, 76.0)
				if snow > 0.25 and rng.randf() < 0.6:
					c.add(Vector3(x, ICE_TOP + 0.02, z), Color(0.85, 0.42, 0.55, 0.35 + (snow - 0.25)), 1.6)
				z += 0.03
			x += 0.03
		# The ice's body cut at the front, and its underside.
		section(c, func(_x: float, _z: float) -> float: return ICE_TOP, HALF.y, ICE_BOT, Color(0.4, 0.62, 0.74))
		ground(c, func(x: float, z: float) -> float: return ICE_BOT + _n(x * 0.8, z * 0.8, 77.0) * 0.15, 0.06, func(_y: float) -> Color: return Color(0.1, 0.62, 0.78, 0.3), 0.04, 0.2)
		drift(c, 5000, Color(0.05, 0.55, 0.75), Color(0.12, 0.3, 0.6))
		# The aurora: curtains swaying over the ice.
		for k in 3:
			var z0 := -1.6 + k * 1.3
			for i in 2600:
				var xx := rng.randf_range(-HALF.x, HALF.x)
				var zz := z0 + sin(xx * 0.8 + k) * 0.5
				var yy := rng.randf_range(0.5, 1.7)
				var f := (yy - 0.5) / 1.2
				var col := Color(0.2, 0.85, 0.7).lerp(Color(0.6, 0.4, 0.85), f)
				c.add(Vector3(xx, yy, zz), Color(col, 0.35 * (1.0 - f) + 0.08), 1.6, 4.0, xx * 0.7 + k)
		# The endospore: core, cortex, coat - shells within shells.
		lattice(h, Vector3.ZERO, Vector3(0.62, 0.85, 0.62), Color(0.5, 0.35, 0.62, 0.55), 12, 10, 1600, 0.03)
		ball(h, Vector3.ZERO, 0.62, 1800, Color(0.3, 0.5, 0.66, 0.2), 1.3, true)
		ball(h, Vector3.ZERO, 0.4, 1200, Color(0.15, 0.6, 0.7, 0.32), 1.4, true)
		ball(h, Vector3.ZERO, 0.22, 600, Color(0.2, 0.65, 0.62, 0.6), 1.6)

	func spots(n: int) -> Array:
		# Down a crack through the ice into the sea.
		var out := []
		for k in n:
			var t := (k + 0.5) / maxf(1.0, n)
			out.append(Vector3(0.55, lerpf(ICE_TOP - 0.3, bottom + 0.6, t), 0.35))
		return out

	func more_labels(a: float) -> void:
		tag(Vector3(1.5, 1.4, -0.3), Vector2(40, -30), "极光", "AURORA", Color(0.35, 0.55, 0.7), a)
		tag(Vector3(-0.8, ICE_TOP, 1.4), Vector2(-60, 30), "西瓜雪", "SNOW ALGAE", Color(0.75, 0.35, 0.5), a)


# --- 8 · planet 3: the acid swamp ---------------------------------------------------

class Ch8 extends "res://scripts/ui/campaign_scene.gd":
	const MUD := -1.0 # the mud's top
	const BANDS := [[-1.0, Color(0.2, 0.62, 0.4)], [-2.2, Color(0.55, 0.45, 0.25)], [-3.3, Color(0.72, 0.35, 0.52)], [-4.5, Color(0.45, 0.3, 0.6)], [-6.6, Color(0.18, 0.2, 0.32)]]
	var veins: Array = [] # [from, to] segments of the network (local)

	func configure() -> void:
		place = "酸性沼泽"
		place_en = "ACID SWAMP  ·  PLANET III"
		emblem = "黏菌网络 · 菌毯意识"
		emblem_en = "SLIME MOULD  ·  PHYSARUM"
		emblem_col = Color(0.55, 0.5, 0.2)
		top = 0.4
		focus = -3.1
		dist = 26.5
		holo_c = Vector3(-2.4, -0.4, -0.6)
		holo_r = 1.05
		rise = 1.2
		motes = Vector2(0.3, 1.2)

	func band_col(y: float) -> Color:
		for k in range(BANDS.size() - 1):
			var a: Array = BANDS[k]
			var b: Array = BANDS[k + 1]
			if y <= a[0] and y > b[0]:
				return (a[1] as Color).lerp(b[1], smoothstep(a[0], b[0], y))
		return BANDS[BANDS.size() - 1][1]

	func bake(c, h) -> void:
		var rng: RandomNumberGenerator = c.rng
		# The column: the mud cut open at the front and the side, banded by
		# who lives at that depth (Winogradsky's colours).
		for face: int in 2:
			var u := -HALF.x
			while u < (HALF.x if face == 0 else HALF.y):
				var y := MUD
				while y > bottom:
					if rng.randf() < 0.8:
						var col := band_col(y)
						col.a = 0.42 + 0.3 * absf(_n(u * 2.0, y * 4.0, 81.0))
						var p := Vector3(u, y, HALF.y) if face == 0 else Vector3(HALF.x, y, u)
						c.add(p, col, 1.5)
					y -= 0.045
				u += 0.03
		ground(c, func(x: float, z: float) -> float: return MUD + _n(x * 0.7, z * 0.7, 82.0) * 0.08, 0.04, func(_y: float) -> Color: return Color(0.25, 0.45, 0.35, 0.3), 0.04, 0.2)
		# Reeds, swaying; bubbles rising out of the mud.
		for k in 160:
			var b := Vector3(rng.randf_range(-HALF.x, HALF.x), MUD, rng.randf_range(-HALF.y, HALF.y))
			var hh := rng.randf_range(0.4, 1.3)
			for j in 26:
				c.add(b + Vector3(0, hh * j / 25.0, 0), Color(0.25, 0.5, 0.35, 0.5), 1.4, 4.0, b.x)
		for k in 18:
			plume(c, Vector3(rng.randf_range(-3.5, 3.5), MUD, rng.randf_range(-2.2, 2.2)), 160, Color(0.7, 0.85, 0.8, 0.45), 0.08)
		for k in 3500:
			c.add(Vector3(rng.randf_range(-HALF.x, HALF.x), MUD + 0.15 + rng.randfn() * 0.04, rng.randf_range(-HALF.y, HALF.y)), Color(0.35, 0.6, 0.55, 0.14), 1.3, 4.0, rng.randf())
		# Physarum: a network grown out from the middle, veins pulsing outward.
		var grow := func(from: Vector3, dir: float, len: float, depth: int, self_ref: Callable) -> void:
			var to := from + Vector3(cos(dir), 0.0, sin(dir)) * len
			if to.length() > 1.2:
				return
			veins.append([from, to])
			var n := int(len / 0.012)
			for i in n:
				var p := from.lerp(to, float(i) / n)
				h.add(p, Color(0.6, 0.5, 0.15, 0.9 - depth * 0.08), 1.9 + (5 - depth) * 0.25, 3.0, -p.length() * 6.0)
			if depth < 5:
				for s: float in [-0.5, 0.45]:
					self_ref.call(to, dir + s + (h.rng as RandomNumberGenerator).randf_range(-0.2, 0.2), len * 0.78, depth + 1, self_ref)
		for k in 6:
			grow.call(Vector3.ZERO, TAU * k / 6.0, 0.32, 0, grow)
		ball(h, Vector3.ZERO, 0.1, 300, Color(0.65, 0.58, 0.25, 0.7), 1.8)
		for k in 1400:
			var d := Vector2.from_angle((h.rng as RandomNumberGenerator).randf() * TAU) * sqrt((h.rng as RandomNumberGenerator).randf()) * 1.25
			h.add(Vector3(d.x, -0.04, d.y), Color(0.2, 0.5, 0.55, 0.12), 1.3)

	func tick(time: float, delta: float) -> void:
		super.tick(time, delta)
		if baked:
			holo.rotation.y = time * 0.08

	func spots(n: int) -> Array:
		var out := []
		for k in n:
			var t := (k + 0.5) / maxf(1.0, n)
			out.append(Vector3(0.55, lerpf(MUD - 0.3, bottom + 0.6, t), 0.35))
		return out

	func more_labels(a: float) -> void:
		tag(Vector3(HALF.x, -2.8, HALF.y), Vector2(30, 20), "泥层分带", "WINOGRADSKY LAYERS", Color(0.6, 0.35, 0.5), a)


# --- 9 · planet 4: the crystal wasteland ------------------------------------------

class Ch9 extends "res://scripts/ui/campaign_scene.gd":
	const FLAT := -3.2
	var crystals: Array = []

	func configure() -> void:
		place = "晶体荒原"
		place_en = "CRYSTAL WASTE  ·  PLANET IV  ·  HIGH RADIATION"
		emblem = "生命之树 · 同一个祖先"
		emblem_en = "ADAPTIVE RADIATION  ·  ONE ANCESTOR"
		emblem_col = Color(0.3, 0.55, 0.65)
		focus = -3.0
		holo_c = Vector3(-2.4, -1.3, -0.6)
		holo_r = 1.1
		for k: Array in [[1.2, -0.8, 2.4, 0.3, 0.25], [2.4, 0.9, 1.6, 0.22, -0.3], [-0.4, 1.4, 1.2, 0.18, 0.4], [3.0, -1.6, 1.9, 0.26, 0.1], [0.4, 0.2, 1.0, 0.15, -0.2], [-1.2, -1.5, 1.4, 0.2, 0.35], [1.8, 1.9, 0.9, 0.14, 0.2]]:
			crystals.append(k)

	func bake(c, h) -> void:
		var rng: RandomNumberGenerator = c.rng
		# The salt flat: polygons of cracks.
		var x := -HALF.x
		while x < HALF.x:
			var z := -HALF.y
			while z < HALF.y:
				var q := Vector2(x, z) * 1.6
				var cell := Vector2(floor(q.x), floor(q.y))
				var best := 9.0
				var second := 9.0
				for dx in [-1, 0, 1]:
					for dz in [-1, 0, 1]:
						var g := cell + Vector2(dx, dz)
						var site := g + Vector2(0.5 + 0.4 * _n(g.x * 3.1, g.y * 3.1, 91.0), 0.5 + 0.4 * _n(g.x * 2.7, g.y * 2.7, 92.0))
						var dd := q.distance_to(site)
						if dd < best:
							second = best
							best = dd
						elif dd < second:
							second = dd
				var edge := 1.0 - smoothstep(0.0, 0.06, second - best)
				if edge > 0.3 or rng.randf() < 0.12:
					c.add(Vector3(x, FLAT, z), Color(0.35, 0.5, 0.62, 0.18 + edge * 0.45), 1.4 + edge * 0.4)
				z += 0.03
			x += 0.03
		section(c, func(_x: float, _z: float) -> float: return FLAT, HALF.y, bottom, Color(0.4, 0.45, 0.6))
		# Crystals: hexagonal prisms, tilted, edges bright, faces faint.
		for k: Array in crystals:
			var base := Vector3(k[0], FLAT, k[1])
			var hh: float = k[2]
			var r: float = k[3]
			var tilt := Basis(Vector3(1, 0, 0.4).normalized(), float(k[4]))
			var corners: Array[Vector3] = []
			for j in 6:
				corners.append(Vector3(cos(TAU * j / 6.0), 0, sin(TAU * j / 6.0)) * r)
			for j in 6:
				var a := corners[j]
				var b := corners[(j + 1) % 6]
				for i in 60:
					var t := i / 59.0
					c.add(base + tilt * (a + Vector3(0, hh * t, 0)), Color(0.35, 0.55, 0.75, 0.55), 1.5)
					c.add(base + tilt * a.lerp(b, t), Color(0.35, 0.55, 0.75, 0.5), 1.4)
					c.add(base + tilt * (a.lerp(b, t) + Vector3(0, hh, 0)), Color(0.35, 0.55, 0.75, 0.5), 1.4)
				for i in 120:
					var t := rng.randf()
					var s := rng.randf()
					c.add(base + tilt * (a.lerp(b, t) + Vector3(0, hh * s, 0)), Color(0.45, 0.62, 0.8, 0.12), 1.3)
				for i in 30:
					var t := i / 29.0
					c.add(base + tilt * (a.lerp(Vector3.ZERO, t) + Vector3(0, hh + r * 0.9 * t, 0)), Color(0.35, 0.55, 0.75, 0.55), 1.4)
		# The tree of life: one trunk, three clades - producers, gatherers,
		# hunters - light running up it.
		var clade := [Color(0.25, 0.6, 0.35), Color(0.1, 0.55, 0.7), Color(0.72, 0.3, 0.52)]
		var branch := func(from: Vector3, dir: Vector3, len: float, depth: int, cl: int, self_ref: Callable) -> void:
			var to := from + dir * len
			var n := int(len / 0.012)
			for i in n:
				var p := from.lerp(to, float(i) / n)
				var col: Color = Color(0.3, 0.45, 0.55) if cl < 0 else clade[cl]
				h.add(p, Color(col, 0.7), 1.6 - depth * 0.1, 3.0, -p.y * 5.0)
			if depth >= 4:
				ball(h, to, 0.03, 18, Color((Color(0.3, 0.45, 0.55) if cl < 0 else clade[cl]), 0.8), 1.8)
				return
			var kids := 3 if depth == 0 else 2
			for k in kids:
				var a := TAU * k / kids + depth * 0.7
				var d := (dir + Vector3(cos(a), 0.0, sin(a)) * 0.75).normalized()
				self_ref.call(to, d, len * 0.68, depth + 1, k if depth == 0 else cl, self_ref)
		branch.call(Vector3(0, -1.05, 0), Vector3.UP, 0.85, 0, -1, branch)

	# Radiation: streaks falling through the scene.
	func animate(time: float, _delta: float) -> void:
		anim.clear_surfaces()
		anim.surface_begin(Mesh.PRIMITIVE_LINES)
		for k in 26:
			var h1 := fposmod(sin(k * 12.9898) * 43758.5, 1.0)
			var h2 := fposmod(sin(k * 78.233) * 12345.6, 1.0)
			var u := fposmod(time * 0.5 + h1, 1.0)
			var at := Vector3(lerpf(-3.8, 3.8, h2), lerpf(top, FLAT, u), lerpf(-2.4, 2.4, h1))
			anim.surface_set_color(Color(1, 1, 1, 0.8 * (1.0 - u)))
			anim.surface_add_vertex(at)
			anim.surface_set_color(Color(1, 1, 1, 0.0))
			anim.surface_add_vertex(at + Vector3(0.12, 0.5, 0.05))
		anim.surface_end()

	func spots(n: int) -> Array:
		# Up the crystals' field, near to far.
		var out := []
		for k in n:
			var t := (k + 0.5) / maxf(1.0, n)
			out.append(Vector3(lerpf(2.8, -0.6, t), FLAT + 0.3 + t * 1.6, lerpf(1.6, -1.2, t)))
		return out


# --- 10 · planet 5: the lightless abyss ----------------------------------------

class Ch10 extends "res://scripts/ui/campaign_scene.gd":
	const RIM := -1.2
	const DEEP := -6.2
	var arms: Array = [] # the apex colony's filaments: [direction, phase]

	func configure() -> void:
		place = "无光深渊"
		place_en = "LIGHTLESS ABYSS  ·  PLANET V"
		emblem = "星之霸主"
		emblem_en = "APEX COLONY  ·  THE STAR SOVEREIGN"
		emblem_col = Color(0.72, 0.25, 0.48)
		hot = Color(0.72, 0.25, 0.5)
		holo_c = Vector3(-2.3, -1.4, -0.6)
		holo_r = 1.1
		motes = Vector2(-0.4, 6.0)

	func floor_h(x: float, z: float) -> float:
		var cx := 0.55 + sin(z * 0.7) * 0.3
		var dx := absf(x - cx)
		var t := smoothstep(0.35, 1.9, dx)
		return lerpf(DEEP, RIM, pow(t, 0.7)) + _n(x * 1.1, z * 1.1, 101.0) * 0.12

	func bake(c, h) -> void:
		var rng: RandomNumberGenerator = c.rng
		ground(c, floor_h, 0.2, func(y: float) -> Color: return Color(0.22, 0.25, 0.42, 0.32), 0.03, 0.25)
		section(c, floor_h, HALF.y, bottom, Color(0.2, 0.22, 0.38))
		# The sovereign's mat over the trench floor: veins pulsing out.
		var x := -HALF.x
		while x < HALF.x:
			var z := -HALF.y
			while z < HALF.y:
				var y := floor_h(x, z)
				if y < DEEP + 1.6:
					var v := absf(_n(x * 2.6, z * 2.6, 102.0))
					if v < 0.06 or rng.randf() < 0.05:
						c.add(Vector3(x, y + 0.02, z), Color(0.72, 0.28, 0.5, 0.4 + (0.3 if v < 0.06 else 0.0)), 1.6, 3.0, -Vector2(x - 0.55, z).length() * 2.5)
				z += 0.025
			x += 0.025
		# Marine snow: thick, slow.
		drift(c, 11000, Color(0.3, 0.45, 0.65), Color(0.25, 0.25, 0.45))
		# The sovereign: a dense core, a crown of spines, long filaments.
		ball(h, Vector3.ZERO, 0.5, 2600, Color(0.72, 0.25, 0.48, 0.35), 1.4, true)
		ball(h, Vector3.ZERO, 0.32, 1400, Color(0.6, 0.2, 0.42, 0.5), 1.6)
		for k in 60:
			var d := dir3(h.rng as RandomNumberGenerator)
			for i in 20:
				h.add(d * (0.5 + i * 0.015), Color(0.72, 0.25, 0.48, 0.7), 1.4)
		for k in 9:
			var d := Vector3(cos(TAU * k / 9.0), -0.35 + 0.3 * sin(k * 1.7), sin(TAU * k / 9.0)).normalized()
			arms.append([d, k * 0.7])
		for k in 500:
			var d := dir3(h.rng as RandomNumberGenerator) * (h.rng as RandomNumberGenerator).randf_range(0.8, 1.3)
			h.add(d, Color(0.72, 0.3, 0.5, 0.55), 1.6, 3.0, d.length() * 4.0)

	# The filaments writhe.
	func animate(time: float, _delta: float) -> void:
		holo_lines.clear_surfaces()
		for arm: Array in arms:
			var d: Vector3 = arm[0]
			var ph: float = arm[1]
			var u := d.cross(Vector3.UP).normalized()
			var v := d.cross(u)
			holo_lines.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
			for i in 30:
				var t := i / 29.0
				var w := sin(t * 5.0 - time * 1.6 + ph) * 0.14 * t
				var w2 := cos(t * 4.0 - time * 1.2 + ph) * 0.1 * t
				holo_lines.surface_add_vertex(d * (0.5 + t * 1.0) + u * w + v * w2)
			holo_lines.surface_end()

	func spots(n: int) -> Array:
		var out := []
		for k in n:
			var t := (k + 0.5) / maxf(1.0, n)
			var y := lerpf(RIM - 0.4, DEEP + 0.4, t)
			out.append(Vector3(0.55 + sin(0.35 * 0.7) * 0.3, y, 0.35))
		return out
