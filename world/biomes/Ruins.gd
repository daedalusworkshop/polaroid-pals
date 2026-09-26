extends "res://world/biomes/Biome.gd"
## Jungle temple ruins — inspired by Ta Prohm (Angkor). Mossy faceted boulders,
## a stepped temple swallowed by strangler figs, a stone-face gate, a lily pond,
## a sword in a stone, ferns everywhere and shafts of light through the canopy.

const C_GRASS_D := Color("3b7438")
const C_GRASS_M := Color("4f8f3d")
const C_GRASS_L := Color("6fab4a")
const C_DIRT := Color("8e7f5c")
const C_ROCK := Color("7a84a6")
const C_STONE := Color("a4a498")
const C_STONE_D := Color("878a86")
const C_LEAF := [Color("3e8039"), Color("4c9442"), Color("357234"), Color("5aa048")]
const C_TRUNK := Color("6e5c4a")
const C_FIG := Color("9a927c", 0.6)

var n1: FastNoiseLite
var n2: FastNoiseLite
var n3: FastNoiseLite
var temple := Vector2(0, -30)
var pond := Vector2(-56, -12)
var sword := Vector2(46, 14)
var paths: Array = []


func _init(p_seed: int) -> void:
	super(p_seed)
	n1 = noise(0.012, 3, 1)
	n2 = noise(0.05, 2, 2)
	n3 = noise(0.004, 2, 3)
	grass_tint = Color("5a9a46")
	flower_colors = [Color("f4f0ff"), Color("cbb8f0"), Color("fff6c8")]
	flower_amount = 0.05
	spawn = Vector3(0, 0, 62)
	spawn_yaw = 0.0
	paths = [
		[Vector2(0, 75), Vector2(3, 45), Vector2(0, 22), Vector2(-2, 5), Vector2(0, -12)],
		[Vector2(0, 32), Vector2(20, 26), Vector2(sword.x - 4, sword.y + 2)],
		[Vector2(-2, 8), Vector2(-28, 2), Vector2(pond.x + 8, pond.y + 5)],
		[Vector2(14, -40), Vector2(30, -62), Vector2(40, -80)],
	]


func height(x: float, z: float) -> float:
	var r := sqrt(x * x + z * z)
	var h := n1.get_noise_2d(x, z) * 4.0 + n2.get_noise_2d(x, z) * 0.9
	h += smoothstep(R - 20.0, R + 60.0, r) * (22.0 + n3.get_noise_2d(x, z) * 14.0)
	h += smoothstep(220.0, 520.0, r) * (50.0 + n1.get_noise_2d(x * 0.3, z * 0.3) * 40.0)
	var dt := Vector2(x, z).distance_to(temple)
	h = lerpf(h, 0.6, smoothstep(40.0, 24.0, dt))
	var dp := Vector2(x, z).distance_to(pond)
	h = lerpf(h, -1.6, smoothstep(13.0, 6.0, dp))
	var dpath := 99.0
	for p in paths:
		dpath = minf(dpath, dist_to_path(Vector2(x, z), p))
	h -= smoothstep(3.5, 0.0, dpath) * 0.25
	return h


func _path_d(x: float, z: float) -> float:
	var d := 99.0
	for p in paths:
		d = minf(d, dist_to_path(Vector2(x, z), p))
	return d


func ground_color(x: float, z: float, h: float, slope: float) -> Color:
	var n := n2.get_noise_2d(x * 0.8, z * 0.8)
	var c := C_GRASS_M.lerp(C_GRASS_L if n > 0.0 else C_GRASS_D, minf(absf(n) * 1.6, 1.0))
	var pd := _path_d(x, z)
	if pd < 1.6:
		c = C_DIRT.lerp(C_GRASS_M, clampf(pd / 1.6, 0, 1) * 0.5)
	var dt := Vector2(x, z).distance_to(temple)
	if dt < 26.0 and pd > 1.6:
		c = c.lerp(Color("7f8a5a"), 0.35)
	if slope > 0.35:
		c = c.lerp(Color("5d6a50"), clampf((slope - 0.35) * 3.0, 0, 1))
	if h < -0.9:
		c = Color("4d5a44")
	return c


func grass_density(x: float, z: float, h: float, slope: float) -> float:
	var pd := _path_d(x, z)
	if pd < 1.2 or slope > 0.5:
		return 0.0
	var d := 0.9 * smoothstep(1.2, 2.6, pd)
	var dt := Vector2(x, z).distance_to(temple)
	if absf(x - temple.x) < 17.0 and absf(z - temple.y) < 15.0:
		return 0.0
	if dt < 26.0:
		d *= 0.5
	if Vector2(x, z).distance_to(pond) < 9.5:
		return 0.0
	return d


func generate() -> void:
	build_terrain()
	water_level = -1.1
	_temple()
	_face_gate(Vector2(0, 22))
	_pond()
	_sword_stone()
	_fallen_walls()
	_forest()
	_undergrowth()
	_lanterns()
	scatter_grass(0.72)
	for i in 34:
		var p := random_point(75.0)
		ray_spots.append([p + Vector3(0, 30, 0), rng.randf_range(2.0, 5.5), rng.randf_range(34.0, 48.0)])
	photo_spots.append([at(temple.x, temple.y + 16), "temple steps"])


# ------------------------------------------------------------------ landmarks

func _stack(base: Vector3, sizes: Array, col: Color, yaw := 0.0) -> float:
	var y := base.y
	for s in sizes:
		var c := jitter(col, 0.025)
		geo.block("solid", Vector3(base.x, y, base.z), s, c, yaw)
		y += s.y
	return y


func _tower(base: Vector3, scale: float, col: Color) -> void:
	var sizes := []
	for i in 6:
		var w := (3.2 - i * 0.45) * scale
		sizes.append(Vector3(w, (1.1 - i * 0.08) * scale, w))
	var top := _stack(base, sizes, col)
	geo.cyl("solid", Vector3(base.x, top, base.z), Vector3(base.x, top + 1.4 * scale, base.z), 0.6 * scale, 0.0, 8, col)
	geo.col_block(base, Vector3(3.2 * scale, top - base.y, 3.2 * scale))


func _temple() -> void:
	var tb := Vector3(temple.x, 0.0, temple.y)
	var tiers: Array[Vector3] = [Vector3(32, 1.5, 28), Vector3(24, 1.5, 21), Vector3(16, 1.5, 14)]
	var y := 0.0
	for t: Vector3 in tiers:
		# walls built from rows of blocks so the edges look hand-laid and broken
		var c := jitter(C_STONE, 0.02)
		c.a = 1.0
		geo.block("solid", Vector3(tb.x, y - 0.8, tb.z), Vector3(t.x, t.y + 0.8, t.z), c, 0.0, C_STONE.lightened(0.05))
		for k in int(t.x / 2.0):
			if rng.randf() < 0.35:
				var px := tb.x - t.x * 0.5 + k * 2.0 + 1.0
				var bc := jitter(C_STONE_D, 0.03)
				geo.block("solid", Vector3(px, y + t.y, tb.z + t.z * 0.5 - 0.5), Vector3(1.8, 0.35, 0.9), bc)
		geo.col_block(Vector3(tb.x, y - 0.8, tb.z), Vector3(t.x, t.y + 0.8, t.z))
		y += t.y
	var top_y := y
	# grand stairs on the south face, with a smooth ramp collider underneath
	var steps := 12
	var run := 0.55
	var rise := top_y / steps
	var front := tb.z + tiers[0].z * 0.5
	for i in steps:
		var sz := front + (steps - i) * run - run * 0.5
		geo.block("solid", Vector3(tb.x, 0.0, sz - (steps - i) * 0.0), Vector3(4.6, rise * (i + 1), run), jitter(C_STONE, 0.02))
	var ramp_len := sqrt(pow(steps * run, 2) + top_y * top_y)
	var ang := atan2(top_y, steps * run)
	var ramp_xf := Transform3D(Basis(Vector3.RIGHT, ang), Vector3(tb.x, top_y * 0.5 - 0.1, front + steps * run * 0.5))
	geo.col_box(ramp_xf, Vector3(4.6, 0.2, ramp_len))
	# balustrades beside the stairs
	for sx: float in [-2.6, 2.6]:
		geo.cyl("solid", Vector3(tb.x + sx, 0.0, front + steps * run), Vector3(tb.x + sx, 1.0, front + steps * run), 0.3, 0.25, 6, C_STONE_D)
	# central prasat + corner towers
	_tower(Vector3(tb.x, top_y, tb.z), 1.45, C_STONE)
	for cx: int in [-1, 1]:
		for cz: int in [-1, 1]:
			var p := Vector3(tb.x + cx * (tiers[1].x * 0.5 - 1.8), tiers[0].y, tb.z + cz * (tiers[1].z * 0.5 - 1.8))
			if rng.randf() < 0.8:
				_tower(p, 0.75, C_STONE.darkened(0.04))
			else:
				_stack(p, [Vector3(2.4, 0.9, 2.4), Vector3(2.0, 0.6, 2.0)], C_STONE_D)
	# pillar galleries around the base, some fallen
	for side in 4:
		var horizontal := side < 2
		var length: float = tiers[0].x + 6.0 if horizontal else tiers[0].z + 6.0
		var count := int(length / 3.0)
		for i in count + 1:
			var along := -length * 0.5 + i * (length / count)
			var p: Vector3
			if side == 0:
				p = Vector3(tb.x + along, 0, tb.z - tiers[0].z * 0.5 - 3.0)
			elif side == 1:
				p = Vector3(tb.x + along, 0, tb.z + tiers[0].z * 0.5 + 3.0)
			elif side == 2:
				p = Vector3(tb.x - tiers[0].x * 0.5 - 3.0, 0, tb.z + along * (tiers[0].z + 6.0) / length)
			else:
				p = Vector3(tb.x + tiers[0].x * 0.5 + 3.0, 0, tb.z + along * (tiers[0].z + 6.0) / length)
			if side == 1 and absf(p.x - tb.x) < 4.0:
				continue
			p.y = ground_y(p.x, p.z) - 0.2
			var roll := rng.randf()
			if roll < 0.12:
				# toppled pillar lying in the grass
				var yaw := rng.randf() * TAU
				geo.box("solid", Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, PI * 0.5), p + Vector3(0, 0.35, 0)),
					Vector3(0.7, 3.0, 0.7), jitter(C_STONE, 0.03))
				continue
			var hgt := 3.2 if roll > 0.35 else rng.randf_range(1.0, 2.4)
			_pillar(p, hgt)
			if hgt > 3.0 and i < count and rng.randf() < 0.55:
				var nxt := along + length / count
				var q: Vector3
				if side < 2:
					q = Vector3(tb.x + (along + nxt) * 0.5, p.y + hgt + 0.2, p.z)
					geo.block("solid", q, Vector3(length / count + 0.6, 0.45, 0.8), jitter(C_STONE, 0.02))
				else:
					q = Vector3(p.x, p.y + hgt + 0.2, p.z + (length / count) * 0.5 * (tiers[0].z + 6.0) / length)
					geo.block("solid", q, Vector3(0.8, 0.45, length / count + 0.6), jitter(C_STONE, 0.02))
	# strangler figs devouring the temple
	_fig(Vector3(tb.x + tiers[1].x * 0.5 - 1.0, tiers[0].y + tiers[1].y, tb.z - tiers[1].z * 0.5 + 1.5), 20.0, tiers[1].x * 0.5)
	_fig(Vector3(tb.x - tiers[0].x * 0.5 + 1.5, tiers[0].y, tb.z + tiers[0].z * 0.5 - 2.0), 17.0, 6.0)
	# scattered fallen blocks
	for i in 45:
		var a := rng.randf() * TAU
		var d := rng.randf_range(17.0, 30.0)
		var p := at(tb.x + cos(a) * d, tb.z + sin(a) * d * 0.9)
		if _path_d(p.x, p.z) < 2.0:
			continue
		var s := Vector3(rng.randf_range(0.6, 1.4), rng.randf_range(0.4, 0.7), rng.randf_range(0.6, 1.0))
		geo.box("solid", Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.3, 0.3)),
			p + Vector3(0, s.y * 0.3, 0)), s, jitter(C_STONE, 0.04))


func _pillar(base: Vector3, hgt: float) -> void:
	var c := jitter(C_STONE, 0.03)
	geo.block("solid", base, Vector3(0.9, 0.35, 0.9), C_STONE_D)
	geo.block("solid", base + Vector3(0, 0.35, 0), Vector3(0.62, hgt - 0.6, 0.62), c)
	# carved bands
	geo.block("solid", base + Vector3(0, hgt * 0.45, 0), Vector3(0.7, 0.15, 0.7), c.darkened(0.08))
	if hgt > 3.0:
		geo.block("solid", base + Vector3(0, hgt - 0.25, 0), Vector3(0.95, 0.3, 0.95), C_STONE_D)
	geo.col_block(base, Vector3(0.7, hgt, 0.7))


func _fig(base: Vector3, height: float, reach: float) -> void:
	var trunk := base + Vector3(0, height * 0.55, 0)
	geo.cyl("solid", base, trunk, 1.3, 0.9, 7, C_FIG)
	geo.cyl("solid", trunk, trunk + Vector3(0.5, height * 0.45, -0.3), 0.9, 0.5, 7, C_FIG)
	# roots pouring over the stones down to the ground
	for i in 9:
		var ang := TAU * i / 9.0 + rng.randf_range(-0.2, 0.2)
		var dir := Vector3(cos(ang), 0, sin(ang))
		var pts: Array = [base + dir * 0.8 + Vector3(0, 1.5, 0)]
		var p: Vector3 = pts[0]
		var rlen := reach * rng.randf_range(0.6, 1.1) + 3.0
		var segs := 7
		for s in segs:
			var t := float(s + 1) / segs
			var q := base + dir * (0.8 + rlen * t) + Vector3(0, 1.5 - t * 1.8, 0)
			var gy := ground_y(q.x, q.z)
			q.y = maxf(q.y, gy + 0.1) if t < 0.5 else lerpf(q.y, gy + 0.05, t)
			q += dir.cross(Vector3.UP) * sin(t * 5.0 + ang) * 0.4
			pts.append(q)
		for s in pts.size() - 1:
			var r0 := lerpf(0.42, 0.1, float(s) / segs)
			geo.cyl("solid", pts[s], pts[s + 1], r0, r0 * 0.8, 5, C_FIG.darkened(rng.randf() * 0.08))
	var top := trunk + Vector3(0.5, height * 0.45, -0.3)
	for i in 8:
		var o := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.2, 0.5), rng.randf_range(-1, 1)) * 7.0
		var br := rng.randf_range(4.0, 6.0)
		geo.leaf_ball("canopy", top + o, Vector3(br, br * 0.65, br), 40, pick(C_LEAF), rng, 0.8, 0.3)
	geo.col_cyl(base - Vector3(0, 1, 0), 1.3, height * 0.6)


func _face_gate(pos: Vector2) -> void:
	var g := at(pos.x, pos.y)
	g.y -= 0.3
	var c := C_STONE
	# walls either side of the doorway
	for sx: int in [-1, 1]:
		var wc := Vector3(g.x + sx * 6.5, g.y, g.z)
		geo.block("solid", wc, Vector3(9.0, 3.6, 1.6), jitter(c, 0.02))
		geo.col_block(wc, Vector3(9.0, 3.6, 1.6))
		for k in 4:
			if rng.randf() < 0.6:
				geo.block("solid", wc + Vector3(-3.5 + k * 2.3, 3.6, 0), Vector3(1.6, 0.4, 1.8), jitter(C_STONE_D, 0.03))
	# doorway frame
	for sx: float in [-1.9, 1.9]:
		geo.block("solid", Vector3(g.x + sx, g.y, g.z), Vector3(1.4, 4.2, 2.4), jitter(c, 0.02))
		geo.col_block(Vector3(g.x + sx, g.y, g.z), Vector3(1.4, 4.2, 2.4))
	geo.block("solid", Vector3(g.x, g.y + 4.2, g.z), Vector3(5.4, 1.0, 2.6), jitter(c, 0.02))
	# face tower
	var fy := g.y + 5.2
	geo.block("solid", Vector3(g.x, fy, g.z), Vector3(4.2, 4.6, 3.8), C_STONE.lightened(0.03))
	for face_z: float in [1.0, -1.0]:
		var fz: float = g.z + face_z * 1.92
		var fb := Basis(Vector3.UP, 0.0 if face_z > 0 else PI)
		var off := func(x: float, y: float, d: float) -> Vector3:
			return Vector3(g.x, fy, fz) + fb * Vector3(x, y, d)
		var dark := C_STONE.darkened(0.3)
		geo.box("solid", Transform3D(fb, off.call(0, 3.1, 0.12)), Vector3(3.2, 0.35, 0.3), C_STONE_D)        # brow
		geo.box("solid", Transform3D(fb, off.call(-0.8, 2.6, 0.05)), Vector3(0.9, 0.25, 0.14), dark)           # eyes
		geo.box("solid", Transform3D(fb, off.call(0.8, 2.6, 0.05)), Vector3(0.9, 0.25, 0.14), dark)
		geo.box("solid", Transform3D(fb, off.call(0, 2.0, 0.2)), Vector3(0.55, 1.0, 0.4), C_STONE)             # nose
		geo.box("solid", Transform3D(fb, off.call(0, 1.05, 0.12)), Vector3(1.5, 0.3, 0.25), C_STONE.darkened(0.12)) # lips
		geo.box("solid", Transform3D(fb, off.call(0, 0.8, 0.08)), Vector3(1.1, 0.12, 0.2), dark)
	_stack(Vector3(g.x, fy + 4.6, g.z), [Vector3(3.6, 0.8, 3.3), Vector3(2.8, 0.7, 2.6), Vector3(2.0, 0.6, 1.9)], C_STONE)
	geo.cyl("solid", Vector3(g.x, fy + 6.7, g.z), Vector3(g.x, fy + 8.2, g.z), 0.8, 0.0, 8, C_STONE)
	geo.col_block(Vector3(g.x, g.y + 4.2, g.z), Vector3(5.4, 7.0, 3.8))
	claim(g, 12.0)
	photo_spots.append([g + Vector3(0, 0, 10), "face gate"])
	# a guardian lion either side of the path
	for sx: float in [-3.2, 3.2]:
		_lion(at(g.x + sx, g.z + 4.0), 0.0 if sx < 0 else 0.0)


func _lion(base: Vector3, yaw: float) -> void:
	var c := C_STONE.darkened(0.05)
	var bs := Basis(Vector3.UP, yaw)
	geo.box("solid", Transform3D(bs, base + Vector3(0, 0.3, 0)), Vector3(0.9, 0.6, 0.9), C_STONE_D)
	geo.box("solid", Transform3D(bs, base + bs * Vector3(0, 0.9, -0.1)), Vector3(0.6, 0.7, 0.8), c)
	geo.box("solid", Transform3D(bs, base + bs * Vector3(0, 1.45, 0.15)), Vector3(0.55, 0.5, 0.5), c)
	geo.box("solid", Transform3D(bs, base + bs * Vector3(0, 1.35, 0.42)), Vector3(0.35, 0.22, 0.15), c.darkened(0.1))
	geo.col_block(base, Vector3(0.9, 1.6, 0.9))


func _pond() -> void:
	var c := Vector3(pond.x, water_level, pond.y)
	var sides := 24
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		geo.tri("water", c, c + Vector3(cos(a0), 0, sin(a0)) * 11.5, c + Vector3(cos(a1), 0, sin(a1)) * 11.5, Color.WHITE, Vector3.UP)
	# lily pads and lotus
	for i in 40:
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * 8.5
		var p := c + Vector3(cos(a) * d, 0.03, sin(a) * d)
		var r := rng.randf_range(0.3, 0.6)
		geo.cyl("solid", p, p + Vector3(0, 0.04, 0), r, r, 7, jitter(Color("4f9a44"), 0.05), true, rng.randf() * TAU)
		if rng.randf() < 0.3:
			var fp := p + Vector3(0, 0.05, 0)
			geo.leaf_ball("bush", fp + Vector3(0, 0.12, 0), Vector3(0.18, 0.14, 0.18), 5, Color("f7b8cf"), rng, 1.2, 0.2)
	# stone rim steps on one side
	for i in 9:
		var a := -0.6 + i * 0.16
		var p := at(pond.x + cos(a) * 12.2, pond.y + sin(a) * 12.2)
		geo.box("solid", Transform3D(Basis(Vector3.UP, -a), p + Vector3(0, 0.1, 0)), Vector3(0.9, 0.5, 2.2), jitter(C_STONE, 0.03))
	# reeds
	for i in 30:
		var a := rng.randf() * TAU
		var p := at(pond.x + cos(a) * rng.randf_range(10.0, 12.5), pond.y + sin(a) * rng.randf_range(10.0, 12.5))
		geo.fern(p, rng.randf_range(0.9, 1.4), Color("6aa04a"), rng)
	claim(Vector3(pond.x, 0, pond.y), 12.0)
	photo_spots.append([at(pond.x + 12, pond.y + 6), "lotus pond"])


func _sword_stone() -> void:
	var p := at(sword.x, sword.y)
	var sz := Vector3(2.4, 1.8, 2.0)
	var pts := geo.rock("solid", p + Vector3(0, 0.7, 0), sz, rng, C_ROCK.lightened(0.05), 0.4, 0.12)
	geo.col_hull(pts)
	# the sword: tilted blade, crossguard, wrapped grip, pommel
	var tip := p + Vector3(-0.2, 1.3, 0.1)
	var dir := Vector3(0.35, 1.0, -0.15).normalized()
	var hilt := tip + dir * 1.25
	geo.cyl("solid", tip, hilt, 0.1, 0.12, 4, Color("d9dde6"), false)
	var side := dir.cross(Vector3.FORWARD).normalized()
	geo.cyl("solid", hilt - side * 0.35, hilt + side * 0.35, 0.06, 0.06, 4, Color("5a4a3a"))
	geo.cyl("solid", hilt, hilt + dir * 0.4, 0.05, 0.05, 5, Color("c46a3a"))
	geo.cyl("solid", hilt + dir * 0.4, hilt + dir * 0.5, 0.08, 0.04, 5, Color("403838"))
	claim(p, 9.0)
	for i in 14:
		var a := rng.randf() * TAU
		bush(at(sword.x + cos(a) * rng.randf_range(4.5, 8.0), sword.y + sin(a) * rng.randf_range(4.5, 8.0)), rng.randf_range(0.8, 1.6), pick(C_LEAF))
	ray_spots.append([p + Vector3(-6, 30, 4), 4.0, 42.0])
	photo_spots.append([at(sword.x - 6, sword.y + 4), "the sword in the stone"])


func _fallen_walls() -> void:
	for w in 7:
		var p := random_point(R - 10.0, 42.0)
		if _path_d(p.x, p.z) < 4.0 or not is_free(p, 6.0):
			continue
		claim(p, 5.0)
		var yaw := rng.randf() * TAU
		var bs := Basis(Vector3.UP, yaw)
		var length := rng.randi_range(4, 8)
		for i in length:
			var q := p + bs * Vector3(i * 1.25 - length * 0.6, 0, 0)
			q.y = ground_y(q.x, q.z) - 0.2
			var rows := rng.randi_range(1, 4)
			for r in rows:
				var off := Vector3(rng.randf_range(-0.05, 0.05), 0, rng.randf_range(-0.1, 0.1))
				geo.box("solid", Transform3D(bs * Basis(Vector3.UP, rng.randf_range(-0.06, 0.06)), q + Vector3(0, 0.3 + r * 0.6, 0) + off),
					Vector3(1.2, 0.58, 0.8), jitter(C_STONE, 0.035))
			geo.col_block(q, Vector3(1.25, rows * 0.6 + 0.2, 0.8), yaw)


func _forest() -> void:
	# big canopy trees in a ring, leaving the temple and clearings open to the sky
	var placed := 0
	var tries := 0
	while placed < 95 and tries < 2000:
		tries += 1
		var p := random_point(R + 40.0, 30.0)
		if _path_d(p.x, p.z) < 4.5:
			continue
		if Vector2(p.x, p.z).distance_to(temple) < 26.0 or Vector2(p.x, p.z).distance_to(pond) < 14.0:
			continue
		if not claim(p, 3.5):
			continue
		var r := Vector2(p.x, p.z).length()
		var h := rng.randf_range(13.0, 22.0) * (1.1 if r > R else 1.0)
		tree_broadleaf(p, h, rng.randf_range(4.5, 7.0), C_TRUNK.lerp(C_FIG, rng.randf() * 0.5), pick(C_LEAF), r < R + 5.0)
		placed += 1
	# young trees
	for i in 45:
		var p := random_point(R, 20.0)
		if _path_d(p.x, p.z) < 3.0 or not claim(p, 2.0):
			continue
		tree_broadleaf(p, rng.randf_range(5.0, 8.0), rng.randf_range(2.0, 3.0), C_TRUNK, pick(C_LEAF))
	# boulder groups like the reference art
	for i in 26:
		var p := random_point(R, 12.0)
		if _path_d(p.x, p.z) < 3.5 or not claim(p, 3.0):
			continue
		rock_cluster(p, rng.randi_range(1, 4), rng.randf_range(0.8, 2.2), C_ROCK)
	# a few tall standing crystal-ish stones
	for i in 10:
		var p := random_point(R - 5.0, 25.0)
		if _path_d(p.x, p.z) < 3.5 or not claim(p, 2.0):
			continue
		var pts := geo.rock("solid", p + Vector3(0, 1.4, 0), Vector3(1.0, 2.6, 1.1), rng, jitter(C_ROCK, 0.03), 1.0, 0.15)
		geo.col_hull(pts)


func _undergrowth() -> void:
	for i in 520:
		var p := random_point(R + 20.0)
		var pd := _path_d(p.x, p.z)
		if pd < 1.8 or Vector2(p.x, p.z).distance_to(pond) < 11.0:
			continue
		if absf(p.x - temple.x) < 18.0 and absf(p.z - temple.y) < 16.0:
			continue
		if not is_free(p, 1.0):
			continue
		# bushes hug path edges and rocks like the reference
		var r := rng.randf_range(0.6, 1.9) * (1.2 if pd < 5.0 else 1.0)
		bush(p, r, pick(C_LEAF).lightened(rng.randf_range(0.0, 0.12)))
	for i in 420:
		var p := random_point(R + 10.0)
		if _path_d(p.x, p.z) < 1.5 or Vector2(p.x, p.z).distance_to(pond) < 10.0:
			continue
		if absf(p.x - temple.x) < 17.0 and absf(p.z - temple.y) < 15.0:
			continue
		geo.fern(p, rng.randf_range(0.7, 1.5), Color("5da24c").lerp(Color("3f7a3c"), rng.randf()), rng)


func _lanterns() -> void:
	# little oil lamps along the causeway so the temple glows at night
	for p in paths[0]:
		var q := at(p.x + 2.2, p.y)
		geo.block("solid", q, Vector3(0.45, 0.8, 0.45), C_STONE_D)
		geo.block("glow", q + Vector3(0, 0.8, 0), Vector3(0.3, 0.3, 0.3), Color(1.0, 0.72, 0.35, 0.5))
		geo.block("solid", q + Vector3(0, 1.1, 0), Vector3(0.55, 0.12, 0.55), C_STONE_D)
		geo.light(q + Vector3(0, 1.0, 0), Color(1.0, 0.7, 0.4), 7.0)
	var front := temple.y + 14.0 + 6.6
	for sx: float in [-3.2, 3.2]:
		var q := at(temple.x + sx, front + 1.0)
		geo.block("glow", q + Vector3(0, 0.9, 0), Vector3(0.3, 0.3, 0.3), Color(1.0, 0.72, 0.35, 0.5))
		geo.light(q + Vector3(0, 1.0, 0), Color(1.0, 0.7, 0.4), 8.0)
