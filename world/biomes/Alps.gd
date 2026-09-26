extends "res://world/biomes/Biome.gd"
## Alpine valley — inspired by Lauterbrunnen, Switzerland. A U-shaped valley of
## wildflower meadows between sheer cliffs streaming with waterfalls, a river,
## chalets with geranium boxes, a white church, grazing cows, pine forests and
## snowy peaks all around.

const C_GRASS := Color("78b04e")
const C_GRASS_L := Color("93c35f")
const C_GRASS_D := Color("5d9d40")
const C_ROAD := Color("bfae8c")
const C_ROCK := Color("8a8f9e")
const C_ROCK_D := Color("6d7283")
const C_SNOW := Color("eef3fb")
const C_PINE := [Color("2f5f4a"), Color("355f44"), Color("2a5646"), Color("3b6a4c")]
const C_WOOD := [Color("9a5f38"), Color("7d4a2c"), Color("ad6d3d"), Color("8b5534")]
const C_ROOF := [Color("5b4a45"), Color("6b5a52"), Color("4d4a55"), Color("7a4a3c")]
const C_STONE := Color("ddd6c6")
const C_SHUTTER := [Color("3f7a52"), Color("b8483e"), Color("3d5f8a")]

var n1: FastNoiseLite
var n2: FastNoiseLite
var n3: FastNoiseLite
var road: Array = []
var falls: Array = []          # [top: Vector3, bottom: Vector3]


func _init(p_seed: int) -> void:
	super(p_seed)
	n1 = noise(0.01, 3, 11)
	n2 = noise(0.045, 2, 12)
	n3 = noise(0.0035, 4, 13)
	grass_tint = Color("86b85a")
	flower_colors = [Color("ffffff"), Color("ffe066"), Color("c9a8ff"), Color("ff8fa8"), Color("8fb8ff"), Color("ffffff")]
	flower_amount = 0.22
	R = 118.0
	spawn = Vector3(-40, 0, 20)
	spawn_yaw = deg_to_rad(-70.0)
	var pts := []
	for i in 13:
		var x := -150.0 + i * 25.0
		pts.append(Vector2(x, _zc(x) + 24.0 + sin(x * 0.03) * 4.0))
	road = pts


func _zc(x: float) -> float:
	return sin(x * 0.011) * 9.0


func _river_z(x: float) -> float:
	return _zc(x) - 6.0 + sin(x * 0.045) * 5.0


func height(x: float, z: float) -> float:
	var d := absf(z - _zc(x))
	var h := d * 0.035 + n1.get_noise_2d(x, z) * 1.6 + n2.get_noise_2d(x, z) * 0.35
	# sheer cliffs forming the U of the valley
	var jag := n2.get_noise_2d(x * 0.5, z * 0.5) * 6.0
	h += smoothstep(80.0 + jag, 96.0 + jag, d) * (62.0 + n1.get_noise_2d(x * 0.7, 0.0) * 10.0)
	# the benches above the cliffs and the peaks beyond
	h += maxf(d - 98.0, 0.0) * 0.35
	h += smoothstep(150.0, 300.0, d) * (70.0 + n3.get_noise_2d(x, z) * 90.0)
	# the great peak at the head of the valley
	var pk := Vector2(x + 430.0, z - 40.0).length()
	h += maxf(0.0, 260.0 - pk * 0.9) * (0.85 + n2.get_noise_2d(x * 0.2, z * 0.2) * 0.2)
	# the river bed
	var dr := absf(z - _river_z(x))
	h -= smoothstep(6.0, 2.2, dr) * 1.7
	return h


func ground_color(x: float, z: float, h: float, slope: float) -> Color:
	var n := n2.get_noise_2d(x * 1.3, z * 1.3)
	var c := C_GRASS.lerp(C_GRASS_L if n > 0.0 else C_GRASS_D, minf(absf(n) * 1.5, 1.0))
	if dist_to_path(Vector2(x, z), road) < 2.0:
		c = C_ROAD
	var dr := absf(z - _river_z(x))
	if dr < 3.2:
		c = Color("a79f86")
	if slope > 0.42:
		c = C_ROCK.lerp(C_ROCK_D, clampf((slope - 0.42) * 2.0, 0.0, 1.0) * 0.6 + n * 0.2)
		# horizontal strata on the cliff faces
		if int(floor(h / 3.5)) % 2 == 0:
			c = c.darkened(0.06)
	elif h > 75.0:
		c = C_GRASS_D.lerp(Color("6f8a58"), 0.5)
	if h > 125.0 + n * 20.0 and slope < 0.7:
		c = C_SNOW
	elif h > 170.0:
		c = C_SNOW.lerp(C_ROCK, 0.25)
	return c


func grass_density(x: float, z: float, h: float, slope: float) -> float:
	if slope > 0.4 or h > 60.0:
		return 0.0
	if dist_to_path(Vector2(x, z), road) < 2.2 or absf(z - _river_z(x)) < 3.5:
		return 0.0
	return 0.95


func generate() -> void:
	build_terrain(620.0, 10.0)
	water_level = -1.05
	_river()
	_village()
	_church(Vector2(20.0, 0.0))
	_waterfalls()
	_forest()
	_meadow_life()
	scatter_grass(0.7)
	for f in falls:
		ray_spots.append([f[1] + Vector3(0, 40, 0), 4.0, 50.0])
	for i in 12:
		var p := random_point(90.0)
		ray_spots.append([p + Vector3(0, 30, 0), rng.randf_range(3.0, 6.0), 45.0])


# ------------------------------------------------------------------ water

func _river() -> void:
	var x := -180.0
	var step := 4.0
	while x < 180.0:
		var z0 := _river_z(x)
		var z1 := _river_z(x + step)
		var w := 3.6
		var a := Vector3(x, water_level, z0 - w)
		var b := Vector3(x + step, water_level, z1 - w)
		var c := Vector3(x + step, water_level, z1 + w)
		var d := Vector3(x, water_level, z0 + w)
		geo.quad("water", a, b, c, d, Color.WHITE, Vector3.UP)
		# pebbles along the banks
		if rng.randf() < 0.5:
			var side := -1.0 if rng.randf() < 0.5 else 1.0
			var p := at(x, z0 + side * rng.randf_range(3.2, 4.5))
			geo.rock("solid", p, Vector3(0.35, 0.2, 0.3), rng, jitter(Color("b8b2a4"), 0.04), 0.0)
		x += step
	# wooden bridges where the road meets the river
	for bx: float in [-60.0, 55.0]:
		var zc := _river_z(bx)
		var y := water_level + 0.9
		var deck := Transform3D(Basis(Vector3.UP, 0.0), Vector3(bx, y, zc))
		geo.box("solid", deck, Vector3(3.2, 0.25, 10.0), Color("8a5a36"))
		geo.col_box(deck, Vector3(3.2, 0.25, 10.0))
		for sx: float in [-1.5, 1.5]:
			for k in 5:
				geo.block("solid", Vector3(bx + sx, y, zc - 4.5 + k * 2.25), Vector3(0.14, 0.9, 0.14), Color("6e4527"))
			geo.box("solid", Transform3D(Basis(), Vector3(bx + sx, y + 0.95, zc)), Vector3(0.12, 0.1, 10.0), Color("7a4c2c"))
		# ramps from the banks
		for sz: float in [-1.0, 1.0]:
			var bank := at(bx, zc + sz * 7.5)
			var mid := (Vector3(bx, y, zc + sz * 5.0) + bank) * 0.5
			var ang := atan2(y - bank.y, 2.5)
			var rx := Transform3D(Basis(Vector3.RIGHT, ang * sz), mid)
			geo.box("solid", rx, Vector3(3.2, 0.2, 2.8), Color("8a5a36"))
			geo.col_box(rx, Vector3(3.2, 0.2, 2.8))
		photo_spots.append([Vector3(bx, y, zc), "bridge"])


func _waterfalls() -> void:
	var spots := [[-70.0, -1.0], [15.0, -1.0], [85.0, -1.0], [-25.0, 1.0], [60.0, 1.0]]
	for s in spots:
		var fx: float = s[0] + rng.randf_range(-8, 8)
		var side: float = s[1]
		# walk outwards to the top of the cliff
		var zc := _zc(fx)
		var d_top := 96.0
		var d_bot := 80.0
		var top := Vector3(fx, height(fx, zc + side * d_top), zc + side * d_top)
		var bot := Vector3(fx, height(fx, zc + side * d_bot) - 0.3, zc + side * d_bot)
		falls.append([top, bot])
		var segs := 14
		var width := rng.randf_range(2.0, 3.6)
		for i in segs:
			var t0 := float(i) / segs
			var t1 := float(i + 1) / segs
			var p0 := _fall_point(top, bot, t0, side)
			var p1 := _fall_point(top, bot, t1, side)
			var w0 := width * (1.0 + t0 * 0.8)
			var w1 := width * (1.0 + t1 * 0.8)
			geo.quad("falls", p0 - Vector3(w0 * 0.5, 0, 0), p0 + Vector3(w0 * 0.5, 0, 0),
				p1 + Vector3(w1 * 0.5, 0, 0), p1 - Vector3(w1 * 0.5, 0, 0), Color.WHITE, Vector3(0, 0, -side),
				Vector2(0, t0), Vector2(1, t0), Vector2(1, t1), Vector2(0, t1))
		# plunge pool
		var pc := bot + Vector3(0, 0.1, -side * 3.0)
		for k in 16:
			var a0 := TAU * k / 16.0
			var a1 := TAU * (k + 1) / 16.0
			geo.tri("water", pc, pc + Vector3(cos(a0), 0, sin(a0)) * 5.0, pc + Vector3(cos(a1), 0, sin(a1)) * 5.0, Color.WHITE, Vector3.UP)
		for k in 7:
			var a := rng.randf() * TAU
			boulder(pc + Vector3(cos(a) * 5.5, -0.2, sin(a) * 5.5), rng.randf_range(0.6, 1.4), C_ROCK, 0.0)
		photo_spots.append([pc + Vector3(0, 0, -side * 12.0), "waterfall"])


func _fall_point(top: Vector3, bot: Vector3, t: float, side: float) -> Vector3:
	# a free-falling arc that leaves the lip and drifts a little outward
	var p := top.lerp(bot, t)
	p.y = lerpf(top.y, bot.y, t * t * 0.4 + t * 0.6)
	p.z += -side * (2.5 + sin(t * PI) * 2.0)
	return p


# ------------------------------------------------------------------ village

func _village() -> void:
	var placed := 0
	var tries := 0
	while placed < 18 and tries < 400:
		tries += 1
		var i := rng.randi_range(0, road.size() - 2)
		var t := rng.randf()
		var rp: Vector2 = road[i].lerp(road[i + 1], t)
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var off := rng.randf_range(9.0, 16.0)
		var p2 := rp + Vector2(0, side * off)
		if p2.length() > R - 6.0:
			continue
		if absf(p2.y - _river_z(p2.x)) < 9.0:
			continue
		var p := at(p2.x, p2.y)
		if not claim(p, 8.0):
			continue
		var yaw := (0.0 if side < 0 else PI) + rng.randf_range(-0.15, 0.15)
		if rng.randf() < 0.18:
			_barn(p, yaw)
		else:
			_chalet(p, yaw)
		placed += 1
	# fences along the road
	for i in road.size() - 1:
		var a: Vector2 = road[i]
		var b: Vector2 = road[i + 1]
		for side: float in [-3.2, 3.2]:
			var n := int(a.distance_to(b) / 2.5)
			for k in n:
				var q := a.lerp(b, float(k) / n) + Vector2(0, side)
				if q.length() > R or not is_free(at(q.x, q.y), 0.5):
					continue
				if absf(q.y - _river_z(q.x)) < 5.0:
					continue
				var gp := at(q.x, q.y)
				geo.block("solid", gp - Vector3(0, 0.2, 0), Vector3(0.12, 1.2, 0.12), Color("7a5334"))
				var nq := a.lerp(b, float(k + 1) / n) + Vector2(0, side)
				var gp2 := at(nq.x, nq.y)
				for hgt: float in [0.55, 0.9]:
					geo.cyl("solid", gp + Vector3(0, hgt, 0), gp2 + Vector3(0, hgt, 0), 0.05, 0.05, 4, Color("8a6040"), false)
	# benches with a view
	for i in 5:
		var p := random_point(80.0, 20.0)
		if not claim(p, 2.0) or p.y > 20.0:
			continue
		bench(p, rng.randf() * TAU, Color("9a6a44"), Color("5a5048"))


func _chalet(base: Vector3, yaw: float) -> void:
	var bs := Basis(Vector3.UP, yaw)
	var w := rng.randf_range(7.0, 10.0)
	var dpt := rng.randf_range(6.5, 8.5)
	var floors := rng.randi_range(2, 3)
	var fh := 2.7
	var wood: Color = pick(C_WOOD)
	var roof: Color = pick(C_ROOF)
	var shutter: Color = pick(C_SHUTTER)
	var ground := base.y - 0.6
	for c in [Vector3(-w, 0, -dpt), Vector3(w, 0, -dpt), Vector3(w, 0, dpt), Vector3(-w, 0, dpt)]:
		var q: Vector3 = base + bs * (c * 0.5)
		ground = minf(ground, ground_y(q.x, q.z) - 0.3)
	var b0 := Vector3(base.x, ground, base.z)
	var stone_h := base.y - ground + 1.1
	geo.box("solid", Transform3D(bs, b0 + Vector3(0, stone_h * 0.5, 0)), Vector3(w, stone_h, dpt), C_STONE)
	var wood_h := floors * fh - 1.1
	var wb := b0 + Vector3(0, stone_h, 0)
	geo.box("solid", Transform3D(bs, wb + Vector3(0, wood_h * 0.5, 0)), Vector3(w + 0.1, wood_h, dpt + 0.1), wood)
	# log bands
	for k in int(wood_h / 0.55):
		geo.box("solid", Transform3D(bs, wb + Vector3(0, 0.3 + k * 0.55, 0)), Vector3(w + 0.22, 0.08, dpt + 0.22), wood.darkened(0.18))
	var eave := wb + Vector3(0, wood_h, 0)
	# wide, low gable roof with the ridge running front-to-back (gable faces the road)
	geo.roof("solid", eave, dpt, w, w * 0.32, yaw + PI * 0.5, roof, wood.darkened(0.1), 1.3)
	# windows + shutters + geranium boxes on the front
	var front := dpt * 0.5 + 0.06
	for fl in floors:
		var y := stone_h + (fl - 1) * fh + 0.95
		if fl == 0:
			y = maxf(stone_h * 0.5 - 0.35, 0.25)
		var nwin := 2 if w < 8.5 else 3
		for k in nwin:
			var x := -w * 0.5 + (k + 0.5) * (w / nwin)
			var wp: Vector3 = b0 + bs * Vector3(x, y, front)
			var win := Color("f6d68a", 0.3) if fl > 0 else Color("e8c47a", 0.3)
			geo.box("glow", Transform3D(bs, wp + bs * Vector3(0, 0.55, 0)), Vector3(0.9, 1.0, 0.05), win)
			geo.box("solid", Transform3D(bs, wp + bs * Vector3(0, 0.55, 0.02)), Vector3(1.05, 0.1, 0.08), Color("f2ede2"))
			geo.box("solid", Transform3D(bs, wp + bs * Vector3(0, 0.55, 0.02)), Vector3(0.08, 1.1, 0.08), Color("f2ede2"))
			for sx: float in [-0.72, 0.72]:
				geo.box("solid", Transform3D(bs, wp + bs * Vector3(sx, 0.55, 0.04)), Vector3(0.45, 1.1, 0.06), shutter)
			if fl > 0 or rng.randf() < 0.5:
				var box_p: Vector3 = wp + bs * Vector3(0, 0.0, 0.25)
				geo.box("solid", Transform3D(bs, box_p), Vector3(1.1, 0.25, 0.3), wood.darkened(0.25))
				geo.leaf_ball("bush", box_p + Vector3(0, 0.28, 0), Vector3(0.6, 0.22, 0.22), 7, pick([Color("e8484f"), Color("f06d8a"), Color("e84a3a")]), rng, 0.7, 0.4)
				geo.light(wp + bs * Vector3(0, 0.6, 0.8), Color(1.0, 0.8, 0.5), 5.0)
	# wrap-around balcony on the upper floor
	if floors >= 2:
		var by := stone_h - 0.05
		var bp: Vector3 = b0 + bs * Vector3(0, by, front + 0.7)
		geo.box("solid", Transform3D(bs, bp), Vector3(w + 0.6, 0.15, 1.4), wood.darkened(0.15))
		geo.box("solid", Transform3D(bs, bp + bs * Vector3(0, 0.55, 0.65)), Vector3(w + 0.6, 0.8, 0.08), wood.lightened(0.08))
		for k in int(w / 0.5):
			geo.box("solid", Transform3D(bs, bp + bs * Vector3(-w * 0.5 + k * 0.5 + 0.2, 0.55, 0.7)), Vector3(0.18, 0.7, 0.05), wood.darkened(0.3))
	# door + chimney + woodpile
	geo.box("solid", Transform3D(bs, b0 + bs * Vector3(w * 0.3, stone_h * 0.5 - 0.1, front)), Vector3(1.1, 2.0, 0.08), wood.darkened(0.35))
	var ch: Vector3 = eave + bs * Vector3(-w * 0.25, w * 0.2, -dpt * 0.2)
	geo.block("solid", ch, Vector3(0.7, 1.6, 0.7), C_STONE.darkened(0.1))
	if rng.randf() < 0.6:
		for k in 6:
			geo.cyl("solid", b0 + bs * Vector3(-w * 0.5 - 0.5, stone_h * 0.3 + (k % 3) * 0.3, -dpt * 0.3 + (k / 3) * 0.3 - 0.3),
				b0 + bs * Vector3(-w * 0.5 - 0.5, stone_h * 0.3 + (k % 3) * 0.3, -dpt * 0.3 + (k / 3) * 0.3 + 0.8), 0.15, 0.15, 5, Color("a7794e"))
	geo.col_box(Transform3D(bs, b0 + Vector3(0, (stone_h + wood_h) * 0.5, 0)), Vector3(w, stone_h + wood_h, dpt))


func _barn(base: Vector3, yaw: float) -> void:
	var bs := Basis(Vector3.UP, yaw)
	var w := 12.0
	var dpt := 9.0
	var h := 5.0
	var b0 := Vector3(base.x, base.y - 0.8, base.z)
	var wood: Color = C_WOOD[1].darkened(0.1)
	geo.box("solid", Transform3D(bs, b0 + Vector3(0, h * 0.5, 0)), Vector3(w, h, dpt), wood)
	for k in int(w / 0.6):
		geo.box("solid", Transform3D(bs, b0 + bs * Vector3(-w * 0.5 + k * 0.6, h * 0.5, dpt * 0.5 + 0.03)), Vector3(0.06, h, 0.05), wood.darkened(0.2))
	geo.roof("solid", b0 + Vector3(0, h, 0), w, dpt, 3.2, yaw, Color("6b6663"), wood, 0.8)
	geo.box("solid", Transform3D(bs, b0 + bs * Vector3(0, 1.6, dpt * 0.5 + 0.06)), Vector3(3.2, 3.2, 0.06), wood.darkened(0.35))
	for k in 5:
		var hp: Vector3 = b0 + bs * Vector3(w * 0.5 + 2.0, 0.6, -3.0 + k * 1.5)
		geo.cyl("solid", hp + bs * Vector3(-0.5, 0, 0), hp + bs * Vector3(0.5, 0, 0), 0.6, 0.6, 8, Color("e0c46c"), true)
	geo.col_box(Transform3D(bs, b0 + Vector3(0, h * 0.5, 0)), Vector3(w, h, dpt))


func _church(pos: Vector2) -> void:
	var zc := _zc(pos.x) + 42.0
	var p := at(pos.x, zc)
	claim(p, 14.0)
	var b0 := p - Vector3(0, 0.8, 0)
	var white := Color("f3efe6")
	var yaw := PI * 0.5
	var bs := Basis(Vector3.UP, yaw)
	# nave
	geo.box("solid", Transform3D(bs, b0 + Vector3(0, 3.5, 0)), Vector3(8.0, 7.0, 16.0), white)
	geo.roof("solid", b0 + Vector3(0, 7.0, 0), 16.0, 8.0, 4.0, yaw + PI * 0.5, Color("6b4a3e"), white, 0.5)
	geo.col_box(Transform3D(bs, b0 + Vector3(0, 3.5, 0)), Vector3(8.0, 7.0, 16.0))
	# tall arched windows
	for k in 4:
		for sx: float in [-4.02, 4.02]:
			geo.box("glow", Transform3D(bs, b0 + bs * Vector3(sx, 3.8, -5.0 + k * 3.3)), Vector3(0.06, 2.4, 0.9), Color("f7cf8a", 0.25))
	# steeple (the famous one)
	var st: Vector3 = b0 + bs * Vector3(0, 0, 9.2)
	geo.block("solid", st, Vector3(3.6, 13.0, 3.6), white)
	geo.block("solid", st + Vector3(0, 13.0, 0), Vector3(3.9, 0.4, 3.9), Color("8a8078"))
	geo.cyl("solid", st + Vector3(0, 13.4, 0), st + Vector3(0, 22.0, 0), 2.1, 0.0, 8, Color("5a4a44"), false, PI / 8.0)
	for fz: float in [1.81, -1.81]:
		geo.box("solid", Transform3D(bs, st + bs * Vector3(0, 11.0, fz)), Vector3(1.4, 1.4, 0.06), Color("2c2a33"))
		geo.box("solid", Transform3D(bs, st + bs * Vector3(0, 11.0, fz * 1.01)), Vector3(1.1, 1.1, 0.04), Color("e8d9a0"))
	geo.cyl("solid", st + Vector3(0, 22.0, 0), st + Vector3(0, 23.2, 0), 0.06, 0.06, 4, Color("c9a44a"))
	geo.col_block(st, Vector3(3.6, 13.0, 3.6))
	# little graveyard wall + path
	for k in 12:
		var a := TAU * k / 12.0
		geo.block("solid", at(p.x + cos(a) * 13.0, p.z + sin(a) * 13.0) - Vector3(0, 0.3, 0), Vector3(3.2, 0.9, 0.5), C_STONE, -a + PI * 0.5)
	geo.light(st + Vector3(0, 11.0, 2.5), Color(1.0, 0.85, 0.6), 9.0)
	photo_spots.append([at(p.x - 30.0, p.z - 20.0), "church and falls"])


# ------------------------------------------------------------------ nature

func _forest() -> void:
	# pine groves on the talus below the cliffs and the benches above
	var placed := 0
	var tries := 0
	while placed < 420 and tries < 5000:
		tries += 1
		var x := rng.randf_range(-260.0, 260.0)
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var d := rng.randf_range(50.0, 170.0)
		var z := _zc(x) + side * d
		var h := ground_y(x, z) if absf(x) < _half and absf(z) < _half else height(x, z)
		var sl := slope_at(x, z) if absf(x) < _half and absf(z) < _half else 0.2
		if sl > 0.45 or h > 115.0:
			continue
		# clustered groves
		if n1.get_noise_2d(x * 2.0, z * 2.0) < -0.05 and d < 90.0:
			continue
		var p := Vector3(x, h, z)
		if Vector2(x, z).length() < R + 5.0 and not claim(p, 1.6):
			continue
		tree_pine(p, rng.randf_range(7.0, 15.0), pick(C_PINE), Color("5a4030"), Vector2(x, z).length() < R + 5.0)
		placed += 1
	# a few broad trees in the village
	for i in 18:
		var p := random_point(R - 10.0, 10.0)
		if absf(p.z - _zc(p.x)) > 60.0 or not claim(p, 3.0):
			continue
		if dist_to_path(Vector2(p.x, p.z), road) < 4.0 or absf(p.z - _river_z(p.x)) < 6.0:
			continue
		tree_broadleaf(p, rng.randf_range(7.0, 11.0), rng.randf_range(3.0, 4.2), Color("6e5a48"), Color("5f9a3e"))
	# boulders tumbled from the cliffs
	for i in 40:
		var x := rng.randf_range(-R, R)
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var z := _zc(x) + side * rng.randf_range(60.0, 82.0)
		var p := at(x, z)
		if Vector2(x, z).length() > R or not claim(p, 2.0):
			continue
		boulder(p, rng.randf_range(0.8, 2.6), C_ROCK, 0.0)


func _meadow_life() -> void:
	# cows
	for i in 9:
		var p := random_point(R - 15.0, 10.0)
		if absf(p.z - _zc(p.x)) > 55.0 or p.y > 8.0 or not claim(p, 2.5):
			continue
		if dist_to_path(Vector2(p.x, p.z), road) < 4.0 or absf(p.z - _river_z(p.x)) < 5.0:
			continue
		_cow(p, rng.randf() * TAU)
	# hay bales and flower bushes
	for i in 30:
		var p := random_point(R - 8.0)
		if absf(p.z - _zc(p.x)) > 60.0 or not is_free(p, 1.5) or absf(p.z - _river_z(p.x)) < 5.0:
			continue
		if dist_to_path(Vector2(p.x, p.z), road) < 3.0:
			continue
		if rng.randf() < 0.3:
			geo.cyl("solid", p + Vector3(-0.6, 0.6, 0), p + Vector3(0.6, 0.6, 0), 0.65, 0.65, 8, Color("dcc06a"))
			geo.col_block(p, Vector3(1.2, 1.2, 1.3))
		else:
			bush(p, rng.randf_range(0.5, 1.0), Color("5e9a44"))
	for i in 25:
		var p := random_point(R)
		if absf(p.z - _zc(p.x)) > 75.0 or not is_free(p, 1.0):
			continue
		boulder(p, rng.randf_range(0.3, 0.9), C_ROCK.lightened(0.05), 0.0, false)


func _cow(base: Vector3, yaw: float) -> void:
	var bs := Basis(Vector3.UP, yaw)
	var body := Color("f2ede6") if rng.randf() < 0.5 else Color("8a5a3a")
	var spot := Color("6a4a36") if body.r > 0.8 else Color("f2ede6")
	var b := base + Vector3(0, 0.05, 0)
	geo.box("solid", Transform3D(bs, b + Vector3(0, 1.0, 0)), Vector3(0.8, 0.75, 1.7), body)
	geo.box("solid", Transform3D(bs, b + bs * Vector3(0.41, 1.1, 0.2)), Vector3(0.02, 0.4, 0.6), spot)
	geo.box("solid", Transform3D(bs, b + bs * Vector3(-0.41, 0.95, -0.3)), Vector3(0.02, 0.35, 0.5), spot)
	var head: Vector3 = b + bs * Vector3(0, 1.15, 1.05)
	geo.box("solid", Transform3D(bs * Basis(Vector3.RIGHT, 0.3), head), Vector3(0.5, 0.5, 0.6), body)
	geo.box("solid", Transform3D(bs, head + bs * Vector3(0, -0.12, 0.33)), Vector3(0.42, 0.26, 0.12), Color("e8b0a8"))
	for sx: float in [-0.3, 0.3]:
		geo.box("solid", Transform3D(bs, head + bs * Vector3(sx, 0.25, 0)), Vector3(0.12, 0.08, 0.08), Color("e8e2cf"))
	geo.cyl("solid", head + bs * Vector3(0, -0.35, -0.05), head + bs * Vector3(0, -0.6, -0.05), 0.1, 0.13, 6, Color("c9a44a"))
	for lx: float in [-0.3, 0.3]:
		for lz: float in [-0.6, 0.6]:
			geo.block("solid", b + bs * Vector3(lx, 0.0, lz), Vector3(0.16, 0.65, 0.16), body.darkened(0.1))
	geo.col_box(Transform3D(bs, b + Vector3(0, 0.8, 0)), Vector3(0.8, 1.4, 2.0))


## Paragliders drifting in lazy circles high above the valley.
func build_extras(root: Node3D, mats) -> void:
	var cols := [Color("f07a5a"), Color("f2c14e"), Color("6fb3e0")]
	for i in 3:
		var pivot := Node3D.new()
		pivot.position = Vector3(rng.randf_range(-60, 60), rng.randf_range(70, 110), _zc(0) + rng.randf_range(-40, 40))
		root.add_child(pivot)
		var g := Geo.new()
		var c: Color = cols[i]
		c.a = 0.0
		for k in 7:
			var a0 := -0.9 + k * 0.3
			var a1 := a0 + 0.3
			var r := 3.5
			var p0 := Vector3(sin(a0) * r, cos(a0) * r * 0.35, 0)
			var p1 := Vector3(sin(a1) * r, cos(a1) * r * 0.35, 0)
			var cc := c if k % 2 == 0 else c.lightened(0.35)
			g.quad("solid", p0 + Vector3(0, 0, -0.8), p1 + Vector3(0, 0, -0.8), p1 + Vector3(0, 0, 0.8), p0 + Vector3(0, 0, 0.8), cc, Vector3.UP)
			g.quad("solid", p0 + Vector3(0, 0, -0.8), p1 + Vector3(0, 0, -0.8), p1 + Vector3(0, 0, 0.8), p0 + Vector3(0, 0, 0.8), cc.darkened(0.2), Vector3.DOWN)
		g.block("solid", Vector3(0, -3.2, 0), Vector3(0.35, 0.6, 0.35), Color("3a3a48", 0.0))
		for sx: float in [-2.5, 2.5]:
			g.cyl("solid", Vector3(0, -2.6, 0), Vector3(sx, 0.4, 0), 0.02, 0.02, 3, Color("ffffff", 0.0), false)
		var mi := MeshInstance3D.new()
		mi.mesh = g.to_mesh("solid")
		mi.material_override = mats.get_mat("solid")
		mi.position = Vector3(rng.randf_range(25.0, 45.0), 0, 0)
		mi.rotation.y = PI * 0.5
		mi.rotation.z = -0.2
		pivot.add_child(mi)
		var tw := pivot.create_tween().set_loops()
		var dur := rng.randf_range(50.0, 80.0)
		tw.tween_property(pivot, "rotation:y", TAU, dur).from(0.0)
	# spray at the foot of each fall
	for f in falls:
		var mist := CPUParticles3D.new()
		mist.amount = 40
		mist.lifetime = 2.5
		mist.preprocess = 2.5
		mist.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		mist.emission_sphere_radius = 2.0
		mist.direction = Vector3(0, 1, 0)
		mist.spread = 60.0
		mist.initial_velocity_min = 1.0
		mist.initial_velocity_max = 2.5
		mist.gravity = Vector3(0, -0.5, 0)
		var q := QuadMesh.new()
		q.size = Vector2(0.5, 0.5)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.albedo_color = Color(1, 1, 1, 0.35)
		q.material = m
		mist.mesh = q
		mist.position = f[1] + Vector3(0, 1.0, 0)
		root.add_child(mist)
