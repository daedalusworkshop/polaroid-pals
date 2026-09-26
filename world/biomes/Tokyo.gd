extends "res://world/biomes/Biome.gd"
## Tokyo backstreets — inspired by Yanaka / Shimokitazawa. Narrow lanes of little
## two-storey houses and shops, vending machines glowing on every corner, paper
## lanterns, tangled power lines, a sakura-lined canal, a neighbourhood shrine,
## a railway crossing, and the city's towers on the horizon.

const C_ASPHALT := Color("5d606e")
const C_ASPHALT_L := Color("6a6d7a")
const C_PAVE := Color("a9a597")
const C_PLASTER := [Color("e9e0cc"), Color("d9d2c2"), Color("c8d3cf"), Color("e8d6c0"), Color("d6d0d8"), Color("c9c0ae"), Color("b8c4c8")]
const C_ROOF := [Color("3f4658"), Color("4a4f5c"), Color("5a4f4a"), Color("36404e")]
const C_WOODFRONT := Color("6b4a33")
const C_SIGN := [Color("c8413b"), Color("2f6f8f"), Color("e6b43c"), Color("3d8a5a"), Color("7a4aa0"), Color("e8e0cf")]
const C_VENDING := [Color("d9453c"), Color("f2f2f2"), Color("3b73c4"), Color("2f9a6a")]

var n1: FastNoiseLite
var xs: Array = []          # x of north-south streets
var zs: Array = []          # z of east-west streets
var widths_x: Array = []
var widths_z: Array = []
var canal_z := 0.0
var rail_x := 0.0
var shrine_block := Vector2i(-1, -1)
var poles: Array = []       # pole tops for wires


func _init(p_seed: int) -> void:
	super(p_seed)
	n1 = noise(0.02, 2, 21)
	grass_tint = Color("6a9a4a")
	flower_colors = [Color("ffffff"), Color("f7c6d4")]
	flower_amount = 0.1
	R = 112.0
	var x := -150.0
	while x < 150.0:
		xs.append(x)
		widths_x.append(4.2 if rng.randf() < 0.7 else 6.5)
		x += rng.randf_range(26.0, 34.0)
	var z := -150.0
	while z < 150.0:
		zs.append(z)
		widths_z.append(4.2 if rng.randf() < 0.65 else 6.5)
		z += rng.randf_range(24.0, 30.0)
	# the canal replaces one east-west street near the middle
	var ci := zs.size() / 2
	canal_z = zs[ci]
	widths_z[ci] = 12.0
	rail_x = xs[xs.size() - 2]
	widths_x[xs.size() - 2] = 9.0
	shrine_block = Vector2i(xs.size() / 2 - 1, ci - 2)
	var sx: float = xs[xs.size() / 2 - 1]
	spawn = Vector3(sx, 0, canal_z + 12.0)
	spawn_yaw = deg_to_rad(20.0)


func height(x: float, z: float) -> float:
	var r := sqrt(x * x + z * z)
	var h := n1.get_noise_2d(x, z) * 0.25
	if absf(z - canal_z) < 4.0 and r < 260.0:
		h -= 3.0
	return h


func _street_d(x: float, z: float) -> float:
	var best := 999.0
	for i in xs.size():
		best = minf(best, absf(x - xs[i]) - widths_x[i] * 0.5)
	for i in zs.size():
		best = minf(best, absf(z - zs[i]) - widths_z[i] * 0.5)
	return best


func ground_color(x: float, z: float, h: float, slope: float) -> Color:
	if absf(z - canal_z) < 4.0:
		return Color("7d8088")
	if absf(z - canal_z) < 6.0:
		return Color("9aa08a")
	if _street_d(x, z) < 0.0:
		return C_ASPHALT.lerp(C_ASPHALT_L, n1.get_noise_2d(x * 3.0, z * 3.0) * 0.5 + 0.5)
	return C_PAVE


func grass_density(x: float, z: float, _h: float, _s: float) -> float:
	# only the canal banks and the shrine grounds are green
	var dc := absf(z - canal_z)
	if dc > 4.3 and dc < 6.2:
		return 0.7
	return 0.0


func generate() -> void:
	build_terrain(520.0, 10.0)
	water_level = -2.4
	_canal()
	_railway()
	for i in xs.size() - 1:
		for j in zs.size() - 1:
			var bx0: float = xs[i] + widths_x[i] * 0.5
			var bx1: float = xs[i + 1] - widths_x[i + 1] * 0.5
			var bz0: float = zs[j] + widths_z[j] * 0.5
			var bz1: float = zs[j + 1] - widths_z[j + 1] * 0.5
			var cx := (bx0 + bx1) * 0.5
			var cz := (bz0 + bz1) * 0.5
			var r := Vector2(cx, cz).length()
			if r > 290.0:
				continue
			if r > R + 25.0:
				_skyline_block(bx0, bx1, bz0, bz1, r)
				continue
			if Vector2i(i, j) == shrine_block:
				_shrine(bx0, bx1, bz0, bz1)
				continue
			_city_block(bx0, bx1, bz0, bz1)
	_street_life()
	_wires()
	_tokyo_tower(Vector3(-260, 0, -330))
	scatter_grass(0.6)
	photo_spots.append([spawn, "canal"])


# ------------------------------------------------------------------ blocks

func _city_block(x0: float, x1: float, z0: float, z1: float) -> void:
	var inset := 0.6
	var depth_z := minf(11.0, (z1 - z0) * 0.5)
	var depth_x := minf(9.0, (x1 - x0) * 0.5)
	# south and north faces
	for face: int in [-1, 1]:
		var x := x0 + inset
		while x < x1 - inset - 3.0:
			var w := minf(rng.randf_range(5.0, 9.0), x1 - inset - x)
			if w < 3.5:
				break
			var cz := z0 + inset + depth_z * 0.5 if face < 0 else z1 - inset - depth_z * 0.5
			var c := Vector3(x + w * 0.5, 0, cz)
			if Vector2(c.x, c.z).length() < R + 18.0:
				_building(c, w - 0.4, depth_z - 0.4, PI if face < 0 else 0.0)
			x += w
	# east and west faces (the middle stretch)
	for face: int in [-1, 1]:
		var z := z0 + inset + depth_z
		while z < z1 - inset - depth_z - 3.0:
			var w := minf(rng.randf_range(5.0, 8.0), z1 - inset - depth_z - z)
			if w < 3.5:
				break
			var cx := x0 + inset + depth_x * 0.5 if face < 0 else x1 - inset - depth_x * 0.5
			var c := Vector3(cx, 0, z + w * 0.5)
			if Vector2(c.x, c.z).length() < R + 18.0:
				_building(c, depth_x - 0.4, w - 0.4, -PI * 0.5 if face < 0 else PI * 0.5)
			z += w


## A building centred at c. `yaw` turns its front (+Z local) to face the street.
func _building(c: Vector3, w: float, d: float, yaw: float) -> void:
	# local frame: front faces +Z after rotation
	var bs := Basis(Vector3.UP, yaw)
	var fw := w
	var fd := d
	if absf(sin(yaw)) > 0.5:
		fw = d
		fd = w
	var roll := rng.randf()
	var kind := "house"
	if roll < 0.32:
		kind = "shop"
	elif roll < 0.5:
		kind = "apartment"
	elif roll < 0.58:
		kind = "izakaya"
	var floors := 2
	if kind == "apartment":
		floors = rng.randi_range(3, 5)
	elif kind == "shop" and rng.randf() < 0.4:
		floors = 3
	var fh := 3.0
	var h := floors * fh
	var wall: Color = pick(C_PLASTER)
	var base := Vector3(c.x, -0.3, c.z)
	geo.box("solid", Transform3D(bs, base + Vector3(0, h * 0.5, 0)), Vector3(fw, h, fd), wall)
	geo.col_box(Transform3D(bs, base + Vector3(0, h * 0.5, 0)), Vector3(fw, h, fd))
	var front := fd * 0.5
	var F := func(x: float, y: float, zoff: float) -> Vector3:
		return base + bs * Vector3(x, y, front + zoff)
	# ground floor
	match kind:
		"shop", "izakaya":
			var sf: Color = Color("f7dca0", 0.55) if kind == "shop" else Color("ffb870", 0.5)
			geo.box("glow", Transform3D(bs, F.call(0, 1.3, 0.02)), Vector3(fw * 0.8, 2.2, 0.05), sf)
			geo.box("solid", Transform3D(bs, F.call(0, 2.6, 0.05)), Vector3(fw * 0.86, 0.35, 0.12), C_WOODFRONT)
			# striped awning
			var aw: Color = pick([Color("3d6e8f"), Color("b8483e"), Color("3d7a55"), Color("d8a33a")])
			geo.box("solid", Transform3D(bs * Basis(Vector3.RIGHT, 0.35), F.call(0, 2.75, 0.55)), Vector3(fw * 0.9, 0.06, 1.2), aw)
			if kind == "izakaya":
				# noren curtain + red lanterns
				for k in 3:
					geo.box("solid", Transform3D(bs, F.call(-0.6 + k * 0.6, 2.2, 0.15)), Vector3(0.55, 0.7, 0.02), Color("2b3350"))
				for sx in [-fw * 0.4, fw * 0.4]:
					var lp: Vector3 = F.call(sx, 2.3, 0.45)
					geo.cyl("glow", lp - Vector3(0, 0.35, 0), lp + Vector3(0, 0.35, 0), 0.28, 0.28, 8, Color("e8453c", 0.85))
					geo.cyl("solid", lp + Vector3(0, 0.35, 0), lp + Vector3(0, 0.42, 0), 0.2, 0.2, 6, Color("222222"))
					geo.light(lp, Color(1.0, 0.45, 0.3), 6.0)
			else:
				# shelves of goods visible through the window
				for k in 3:
					geo.box("solid", Transform3D(bs, F.call(0, 0.5 + k * 0.6, -0.4)), Vector3(fw * 0.7, 0.08, 0.5), Color("8a6a4a"))
				geo.light(F.call(0, 1.6, 1.0), Color(1.0, 0.85, 0.6), 6.0)
			# a vertical sign on the corner with glyphs
			if rng.randf() < 0.75:
				var sc: Color = pick(C_SIGN)
				sc.a = 0.85
				var sp: Vector3 = F.call(fw * 0.5 - 0.2, 3.6 + rng.randf() * 1.5, 0.5)
				var rows := rng.randi_range(3, 5)
				_sign(sp, bs, rows, sc)
		_:
			# house: sliding door, small window, potted plants
			geo.box("solid", Transform3D(bs, F.call(-fw * 0.2, 1.1, 0.03)), Vector3(1.6, 2.1, 0.06), C_WOODFRONT)
			geo.box("glow", Transform3D(bs, F.call(-fw * 0.2, 1.5, 0.07)), Vector3(1.3, 0.8, 0.02), Color("f2d49a", 0.35))
			geo.box("glow", Transform3D(bs, F.call(fw * 0.22, 1.5, 0.03)), Vector3(1.2, 0.9, 0.05), Color("e8c88a", 0.25))
			geo.box("solid", Transform3D(bs, F.call(fw * 0.22, 1.05, 0.1)), Vector3(1.3, 0.08, 0.18), Color("d8d2c4"))
			for k in rng.randi_range(2, 5):
				var pp: Vector3 = F.call(-fw * 0.45 + k * 0.45, 0.0, 0.45)
				var pr := rng.randf_range(0.15, 0.25)
				geo.cyl("solid", pp, pp + Vector3(0, pr * 1.6, 0), pr * 0.8, pr, 6, pick([Color("b86a45"), Color("6e7280"), Color("d8d0c0")]))
				geo.leaf_ball("bush", pp + Vector3(0, pr * 2.2, 0), Vector3(pr * 1.6, pr * 1.8, pr * 1.6), 6, pick([Color("4f8a45"), Color("3f7a44"), Color("6a9a4a")]), rng, 0.8, 0.5)
			geo.light(F.call(-fw * 0.2, 2.4, 0.6), Color(1.0, 0.85, 0.6), 4.5)
	# upper floors
	for fl in range(1, floors):
		var y := fl * fh + 1.4
		var nwin := maxi(1, int(fw / 2.4))
		for k in nwin:
			var x := -fw * 0.5 + (k + 0.5) * fw / nwin
			var lit := rng.randf() < 0.6
			geo.box("glow", Transform3D(bs, F.call(x, y, 0.03)), Vector3(1.2, 1.1, 0.05), Color("f2cf8a", 0.25) if lit else Color("7a8aa8", 0.35))
			geo.box("solid", Transform3D(bs, F.call(x, y - 0.62, 0.08)), Vector3(1.35, 0.1, 0.16), wall.darkened(0.2))
		if kind == "apartment":
			geo.box("solid", Transform3D(bs, F.call(0, fl * fh + 0.1, 0.6)), Vector3(fw, 0.15, 1.2), wall.darkened(0.1))
			geo.box("solid", Transform3D(bs, F.call(0, fl * fh + 0.65, 1.15)), Vector3(fw, 1.0, 0.08), wall.darkened(0.15))
			if rng.randf() < 0.5:
				# laundry pole with a towel or two
				geo.cyl("solid", F.call(-fw * 0.45, fl * fh + 1.9, 0.9), F.call(fw * 0.45, fl * fh + 1.9, 0.9), 0.03, 0.03, 4, Color("c0c0c8"), false)
				for t in rng.randi_range(1, 3):
					geo.box("solid", Transform3D(bs, F.call(-fw * 0.3 + t * 0.9, fl * fh + 1.55, 0.9)), Vector3(0.6, 0.65, 0.02), pick([Color("f4f1ea"), Color("9ac0e0"), Color("f0b8c0"), Color("f2d57a")]))
		if rng.randf() < 0.45:
			geo.box("solid", Transform3D(bs, F.call(fw * 0.5 - 0.6, fl * fh + 0.5, 0.25)), Vector3(0.8, 0.55, 0.4), Color("e4e4e0"))
	# roof
	if kind == "house" or (kind == "izakaya" and rng.randf() < 0.7):
		geo.roof("solid", base + Vector3(0, h, 0), fw, fd, fd * 0.3, yaw, pick(C_ROOF), wall.darkened(0.08), 0.5)
	else:
		geo.box("solid", Transform3D(bs, base + Vector3(0, h + 0.3, 0)), Vector3(fw + 0.1, 0.6, fd + 0.1), wall.darkened(0.12))
		if rng.randf() < 0.35:
			geo.cyl("solid", base + bs * Vector3(fw * 0.25, h + 0.6, -fd * 0.2), base + bs * Vector3(fw * 0.25, h + 2.2, -fd * 0.2), 0.7, 0.7, 8, Color("c8ccd4"))
	claim(c, maxf(fw, fd) * 0.45)


func _sign(top: Vector3, bs: Basis, rows: int, col: Color) -> void:
	# a vertical panel whose UVs pick a random column of the glyph atlas
	var gx := rng.randi_range(0, 7)
	var gy := rng.randi_range(0, 8 - rows)
	var w := 0.55
	var h := rows * 0.55
	var r := bs.x
	var n := bs.z
	var p0 := top - Vector3(0, h, 0)
	var u0 := gx / 8.0
	var u1 := (gx + 1) / 8.0
	var v0 := gy / 8.0
	var v1 := (gy + rows) / 8.0
	for side: float in [1.0, -1.0]:
		var o := n * 0.001 * side
		# the panel sticks out from the wall, so it faces sideways along the street

		geo.quad("sign", p0 + o, p0 + n * w + o, top + n * w + o, top + o, col, r * side,
			Vector2(u0, v1), Vector2(u1, v1), Vector2(u1, v0), Vector2(u0, v0))
	geo.box("solid", Transform3D(bs, top - Vector3(0, h * 0.5, 0) + n * w * 0.5 + r * 0.04), Vector3(0.02, h + 0.1, w + 0.1), Color("303038"))


func _skyline_block(x0: float, x1: float, z0: float, z1: float, r: float) -> void:
	var c := Vector3((x0 + x1) * 0.5, 0, (z0 + z1) * 0.5)
	var tall := clampf((r - 120.0) / 150.0, 0.0, 1.0)
	var n := rng.randi_range(1, 3)
	for i in n:
		var w := rng.randf_range(8.0, (x1 - x0) * 0.8)
		var d := rng.randf_range(8.0, (z1 - z0) * 0.8)
		var h := rng.randf_range(8.0, 16.0) + tall * rng.randf_range(10.0, 70.0)
		var p := c + Vector3(rng.randf_range(-4, 4), -0.5, rng.randf_range(-4, 4))
		var col: Color = pick([Color("b8bcc8"), Color("a9b0c0"), Color("c8c4bc"), Color("9aa4b4"), Color("d0ccc4")])
		geo.block("solid", p, Vector3(w, h, d), col)
		# window bands
		var bands := int(h / 3.5)
		for k in bands:
			if rng.randf() < 0.75:
				geo.block("glow", p + Vector3(0, 1.4 + k * 3.5, 0), Vector3(w + 0.1, 1.0, d + 0.1), Color("f0d08a", 0.3) if rng.randf() < 0.6 else Color("8a98b8", 0.3))
		if h > 50.0 and rng.randf() < 0.5:
			geo.block("glow", p + Vector3(0, h, 0), Vector3(0.6, 0.6, 0.6), Color("ff4040", 0.6))


# ------------------------------------------------------------------ canal, rail, shrine

func _canal() -> void:
	var x := -R - 30.0
	while x < R + 30.0:
		var a := Vector3(x, water_level, canal_z - 3.8)
		var b := Vector3(x + 6.0, water_level, canal_z - 3.8)
		geo.quad("water", a, b, b + Vector3(0, 0, 7.6), a + Vector3(0, 0, 7.6), Color.WHITE, Vector3.UP)
		for side: float in [-1.0, 1.0]:
			# stone embankment walls
			var wz := canal_z + side * 4.0
			geo.block("solid", Vector3(x + 3.0, -3.3, wz), Vector3(6.0, 3.3, 0.5), Color("8e9098").lerp(Color("a39c88"), rng.randf() * 0.4))
			geo.col_block(Vector3(x + 3.0, -3.3, wz), Vector3(6.0, 4.4, 0.5))
			# railing
			geo.block("solid", Vector3(x + 3.0, 0.0, canal_z + side * 4.35), Vector3(6.0, 0.9, 0.08), Color("5a5e66"))
		x += 6.0
	# sakura along both banks
	var t := -R
	while t < R:
		for side: float in [-1.0, 1.0]:
			if rng.randf() < 0.8:
				var p := at(t + rng.randf_range(-1.5, 1.5), canal_z + side * 5.3)
				if _street_d(p.x, p.z) > 1.0 or absf(p.z - canal_z) < 6.0:
					tree_sakura(p, rng.randf_range(5.0, 7.0))
		t += rng.randf_range(7.0, 10.0)
	# little bridges where streets cross
	for i in xs.size():
		var bx: float = xs[i]
		if absf(bx) > R + 20.0:
			continue
		var bw: float = widths_x[i]
		var deck := Transform3D(Basis(), Vector3(bx, -0.15, canal_z))
		geo.box("solid", deck, Vector3(bw + 1.0, 0.3, 9.0), Color("8a8c94"))
		geo.col_box(deck, Vector3(bw + 1.0, 0.3, 9.0))
		for sx: float in [-0.5, 0.5]:
			geo.block("solid", Vector3(bx + sx * (bw + 1.0), 0.0, canal_z), Vector3(0.25, 1.0, 9.0), Color("c8413b") if i % 2 == 0 else Color("7a7e88"))


func _railway() -> void:
	var z := -300.0
	while z < 300.0:
		geo.block("solid", Vector3(rail_x, -0.28, z + 5.0), Vector3(4.2, 0.2, 10.0), Color("7a7066"))
		for k in 10:
			geo.block("solid", Vector3(rail_x, -0.1, z + k + 0.5), Vector3(3.0, 0.1, 0.3), Color("5a4a3c"))
		for sx: float in [-0.75, 0.75]:
			geo.block("solid", Vector3(rail_x + sx, 0.0, z + 5.0), Vector3(0.1, 0.14, 10.0), Color("b8bcc4"))
		z += 10.0
	# fences along the tracks except at crossings, with crossing signals
	for j in zs.size():
		var cz: float = zs[j]
		if absf(cz) > R + 15.0 or absf(cz - canal_z) < 1.0:
			continue
		for sx: float in [-1.0, 1.0]:
			var pp := Vector3(rail_x + sx * 3.2, 0, cz + sx * (widths_z[j] * 0.5 + 0.3))
			geo.cyl("solid", pp, pp + Vector3(0, 3.2, 0), 0.08, 0.08, 6, Color("f0f0f0"))
			geo.block("solid", pp + Vector3(0, 2.6, 0), Vector3(0.9, 0.15, 0.15), Color("2a2a2a"))
			for lx: float in [-0.3, 0.3]:
				geo.cyl("glow", pp + Vector3(lx, 2.4, 0.1), pp + Vector3(lx, 2.4, 0.2), 0.12, 0.12, 8, Color("ff3b30", 0.6))
			# striped barrier arm
			for k in 6:
				geo.block("solid", pp + Vector3(0.1, 1.0, -sx * (0.4 + k * 0.5)), Vector3(0.08, 0.1, 0.5), Color("f2c230") if k % 2 == 0 else Color("222222"))
			geo.light(pp + Vector3(0, 2.4, 0), Color(1.0, 0.3, 0.25), 5.0)
	var zz := -R - 20.0
	while zz < R + 20.0:
		if _street_d(rail_x + 4.0, zz) > 0.5:
			for sx: float in [-4.2, 4.2]:
				geo.block("solid", Vector3(rail_x + sx, 0.0, zz), Vector3(0.08, 1.4, 2.0), Color("7a8a7a"))
			geo.col_block(Vector3(rail_x, 0.0, zz), Vector3(9.0, 1.5, 2.0))
		zz += 2.0


func _shrine(x0: float, x1: float, z0: float, z1: float) -> void:
	var c := Vector3((x0 + x1) * 0.5, 0, (z0 + z1) * 0.5)
	claim(c, 14.0)
	var verm := Color("d8452e")
	# gravel grounds + stone path
	geo.block("solid", Vector3(c.x, -0.28, c.z), Vector3(x1 - x0, 0.3, z1 - z0), Color("c8c0ae"))
	var gate_z := z1 - 1.5
	var hall_z := z0 + 6.0
	var z := gate_z
	while z > hall_z + 2.0:
		geo.block("solid", Vector3(c.x, -0.2, z), Vector3(2.2, 0.25, 1.1), Color("a8a39a").lerp(Color("9a948a"), rng.randf()))
		z -= 1.3
	# torii
	var tp := Vector3(c.x, 0, gate_z)
	for sx: float in [-1.9, 1.9]:
		geo.cyl("solid", tp + Vector3(sx, 0, 0), tp + Vector3(sx, 4.6, 0), 0.26, 0.22, 8, verm)
		geo.cyl("solid", tp + Vector3(sx, 0, 0), tp + Vector3(sx, 0.5, 0), 0.32, 0.32, 8, Color("222222"))
		geo.col_cyl(tp + Vector3(sx, 0, 0), 0.26, 4.6)
	geo.box("solid", Transform3D(Basis(), tp + Vector3(0, 3.9, 0)), Vector3(4.8, 0.28, 0.35), verm)
	geo.box("solid", Transform3D(Basis(), tp + Vector3(0, 4.7, 0)), Vector3(5.8, 0.3, 0.5), Color("262626"))
	geo.box("solid", Transform3D(Basis(Vector3.FORWARD, 0.04), tp + Vector3(-1.5, 4.85, 0)), Vector3(3.2, 0.12, 0.55), Color("262626"))
	geo.box("solid", Transform3D(Basis(Vector3.FORWARD, -0.04), tp + Vector3(1.5, 4.85, 0)), Vector3(3.2, 0.12, 0.55), Color("262626"))
	geo.box("solid", Transform3D(Basis(), tp + Vector3(0, 4.3, 0)), Vector3(0.3, 0.6, 0.3), verm)
	# stone lanterns + komainu
	for sx: float in [-3.0, 3.0]:
		var lp := Vector3(c.x + sx, 0, gate_z - 4.0)
		geo.block("solid", lp, Vector3(0.7, 0.3, 0.7), Color("9a968c"))
		geo.cyl("solid", lp + Vector3(0, 0.3, 0), lp + Vector3(0, 1.1, 0), 0.14, 0.14, 6, Color("9a968c"))
		geo.block("glow", lp + Vector3(0, 1.1, 0), Vector3(0.5, 0.45, 0.5), Color("f6c46a", 0.45))
		geo.cyl("solid", lp + Vector3(0, 1.55, 0), lp + Vector3(0, 1.95, 0), 0.5, 0.05, 6, Color("8e8a80"))
		geo.light(lp + Vector3(0, 1.3, 0), Color(1.0, 0.75, 0.45), 6.0)
		geo.col_block(lp, Vector3(0.7, 1.9, 0.7))
		var kp := Vector3(c.x + sx * 0.7, 0, hall_z + 5.0)
		geo.block("solid", kp, Vector3(0.8, 0.6, 0.8), Color("8e8a80"))
		geo.block("solid", kp + Vector3(0, 0.6, 0), Vector3(0.5, 0.7, 0.6), Color("a8a49a"))
		geo.block("solid", kp + Vector3(0, 1.3, 0.1), Vector3(0.45, 0.4, 0.45), Color("a8a49a"))
	# the hall
	var hp := Vector3(c.x, 0, hall_z)
	geo.block("solid", hp, Vector3(8.0, 0.8, 6.0), Color("8e8a80"))
	geo.box("solid", Transform3D(Basis(), hp + Vector3(0, 2.3, 0)), Vector3(6.4, 3.0, 4.6), Color("8a5a3a"))
	geo.box("glow", Transform3D(Basis(), hp + Vector3(0, 2.2, 2.32)), Vector3(3.0, 2.0, 0.04), Color("f2c070", 0.35))
	for sx: float in [-3.0, -1.5, 1.5, 3.0]:
		geo.cyl("solid", hp + Vector3(sx, 0.8, 2.6), hp + Vector3(sx, 3.8, 2.6), 0.14, 0.14, 6, verm)
	geo.roof("solid", hp + Vector3(0, 3.8, 0), 6.4, 4.6, 2.6, 0.0, Color("3c4454"), Color("8a5a3a"), 1.6)
	geo.box("solid", Transform3D(Basis(), hp + Vector3(0, 6.45, 0)), Vector3(8.4, 0.25, 0.3), Color("c9a44a"))
	# rope + bell + offering box
	geo.cyl("solid", hp + Vector3(0, 3.6, 2.9), hp + Vector3(0, 1.3, 2.9), 0.06, 0.06, 4, Color("e8dcc0"))
	geo.block("solid", hp + Vector3(0, 0.8, 3.3), Vector3(1.4, 0.7, 0.7), Color("6b4a33"))
	geo.col_box(Transform3D(Basis(), hp + Vector3(0, 2.3, 0)), Vector3(8.0, 4.6, 6.0))
	# ema board
	var ep := Vector3(c.x + 4.5, 0, hall_z + 6.5)
	for sx: float in [-0.9, 0.9]:
		geo.block("solid", ep + Vector3(sx, 0, 0), Vector3(0.12, 1.8, 0.12), Color("6b4a33"))
	geo.box("solid", Transform3D(Basis(), ep + Vector3(0, 1.3, 0)), Vector3(2.0, 0.8, 0.08), Color("8a5a3a"))
	for k in 8:
		geo.box("solid", Transform3D(Basis(Vector3.FORWARD, rng.randf_range(-0.2, 0.2)), ep + Vector3(-0.8 + (k % 4) * 0.52, 1.1 + (k / 4) * 0.35, 0.06)), Vector3(0.3, 0.22, 0.02), Color("e8d6ac"))
	# great camphor tree + sakura
	tree_broadleaf(Vector3(c.x - (x1 - x0) * 0.32, 0, c.z - 2.0), 13.0, 5.5, Color("5a4a40"), Color("3f7a3e"))
	for i in 3:
		tree_sakura(Vector3(c.x + (x1 - x0) * 0.3, 0, c.z - 6.0 + i * 5.0), rng.randf_range(5.0, 6.5))
	# a low wall around it
	for side: float in [-1.0, 1.0]:
		geo.block("solid", Vector3(c.x + side * (x1 - x0) * 0.5, 0, c.z), Vector3(0.4, 1.1, z1 - z0), Color("b8b2a4"))
		geo.col_block(Vector3(c.x + side * (x1 - x0) * 0.5, 0, c.z), Vector3(0.4, 1.1, z1 - z0))
	photo_spots.append([tp + Vector3(0, 0, 6), "shrine gate"])


# ------------------------------------------------------------------ street furniture

func _street_life() -> void:
	# utility poles + street lamps along every street
	for i in xs.size():
		var x: float = xs[i] + widths_x[i] * 0.5 - 0.35
		if absf(x - rail_x) < 6.0:
			continue
		var z := -R - 10.0
		while z < R + 10.0:
			if Vector2(x, z).length() < R + 12.0 and _street_d(x - 1.0, z) > -widths_x[i] and absf(z - canal_z) > 6.0:
				_pole(Vector3(x, 0, z))
			z += rng.randf_range(13.0, 17.0)
	for j in zs.size():
		var z: float = zs[j] - widths_z[j] * 0.5 + 0.35
		if absf(zs[j] - canal_z) < 1.0:
			continue
		var x := -R - 10.0
		while x < R + 10.0:
			if Vector2(x, z).length() < R + 12.0 and absf(x - rail_x) > 6.0:
				_pole(Vector3(x, 0, z))
			x += rng.randf_range(13.0, 17.0)
	# vending machines, bicycles, mirrors, cats
	for i in 70:
		var p := _random_street_edge()
		if p == Vector3.INF:
			continue
		var r := rng.randf()
		if r < 0.45:
			_vending(p)
		elif r < 0.7:
			_bicycle(p)
		elif r < 0.82:
			_mirror(p)
		else:
			_planters(p)
	for i in 10:
		var p := _random_street_edge()
		if p != Vector3.INF:
			_cat(p + Vector3(0, 0, 0))


func _random_street_edge() -> Vector3:
	for attempt in 20:
		var p := random_point(R - 2.0)
		var sd := _street_d(p.x, p.z)
		if sd < -0.2 and sd > -1.1 and absf(p.z - canal_z) > 6.0 and absf(p.x - rail_x) > 6.0 and is_free(p, 0.8):
			claim(p, 0.8)
			return Vector3(p.x, 0.0, p.z)
	return Vector3.INF


func _street_yaw(p: Vector3) -> float:
	# which way does the nearest street run? face across it
	var bx := 999.0
	var bz := 999.0
	for i in xs.size():
		bx = minf(bx, absf(p.x - xs[i]))
	for j in zs.size():
		bz = minf(bz, absf(p.z - zs[j]))
	return PI * 0.5 if bx < bz else 0.0


func _pole(p: Vector3) -> void:
	var top := p + Vector3(0, 8.0, 0)
	geo.cyl("solid", p - Vector3(0, 0.3, 0), top, 0.17, 0.13, 6, Color("9a9a96"))
	geo.box("solid", Transform3D(Basis(), top - Vector3(0, 0.5, 0)), Vector3(1.4, 0.12, 0.12), Color("8a8a86"))
	if rng.randf() < 0.4:
		geo.cyl("solid", top - Vector3(0.35, 1.8, 0), top - Vector3(0.35, 1.0, 0), 0.25, 0.25, 7, Color("8f9398"))
	# street lamp arm
	var lamp := p + Vector3(0.9, 5.0, 0)
	geo.cyl("solid", p + Vector3(0, 5.2, 0), lamp + Vector3(0, 0.1, 0), 0.04, 0.04, 4, Color("6a6a6a"), false)
	geo.block("glow", lamp - Vector3(0, 0.15, 0), Vector3(0.45, 0.12, 0.25), Color("fff0c8", 0.5))
	geo.light(lamp - Vector3(0, 0.5, 0), Color(1.0, 0.9, 0.7), 9.0)
	geo.col_cyl(p, 0.18, 4.0)
	poles.append(top - Vector3(0, 0.5, 0))


func _wires() -> void:
	# connect poles to near neighbours with gently sagging cables
	for i in poles.size():
		var a: Vector3 = poles[i]
		for j in range(i + 1, poles.size()):
			var b: Vector3 = poles[j]
			var d := a.distance_to(b)
			if d < 19.0 and d > 5.0 and (absf(a.x - b.x) < 0.5 or absf(a.z - b.z) < 0.5):
				for k: float in [-0.6, 0.0, 0.6]:
					var off := Vector3(k, 0, 0) if absf(a.x - b.x) < 0.5 else Vector3(0, 0, k)
					var mid := (a + b) * 0.5 + off + Vector3(0, -0.7, 0)
					geo.cyl("solid", a + off, mid, 0.022, 0.022, 3, Color("25252b"), false)
					geo.cyl("solid", mid, b + off, 0.022, 0.022, 3, Color("25252b"), false)


func _vending(p: Vector3) -> void:
	var yaw := _street_yaw(p) + (PI if rng.randf() < 0.5 else 0.0)
	var bs := Basis(Vector3.UP, yaw)
	var n := rng.randi_range(1, 3)
	for i in n:
		var q := p + bs * Vector3((i - (n - 1) * 0.5) * 1.05, 0, 0)
		var body: Color = pick(C_VENDING)
		geo.box("solid", Transform3D(bs, q + Vector3(0, 0.9, 0)), Vector3(1.0, 1.8, 0.75), body)
		geo.box("glow", Transform3D(bs, q + bs * Vector3(0, 1.15, 0.38)), Vector3(0.82, 0.95, 0.02), Color("f4f6f8", 0.8))
		for row in 3:
			for k in 5:
				var bc: Color = pick([Color("e84a3a"), Color("3a8ae8"), Color("f2c230"), Color("4ac27a"), Color("f07aa8"), Color("8a5a3a")])
				bc.a = 0.9
				geo.box("glow", Transform3D(bs, q + bs * Vector3(-0.32 + k * 0.16, 0.82 + row * 0.3, 0.4)), Vector3(0.09, 0.2, 0.02), bc)
		geo.box("solid", Transform3D(bs, q + bs * Vector3(0, 0.35, 0.39)), Vector3(0.7, 0.25, 0.04), Color("2a2a30"))
		geo.col_box(Transform3D(bs, q + Vector3(0, 0.9, 0)), Vector3(1.0, 1.8, 0.75))
	geo.light(p + bs * Vector3(0, 1.2, 1.0), Color(0.85, 0.92, 1.0), 5.0)


func _bicycle(p: Vector3) -> void:
	var yaw := _street_yaw(p) + PI * 0.5 + rng.randf_range(-0.3, 0.3)
	var bs := Basis(Vector3.UP, yaw)
	var frame: Color = pick([Color("3a6ea8"), Color("d8d8d8"), Color("b83a3a"), Color("2a2a2a"), Color("7aa84a")])
	for wz: float in [-0.5, 0.5]:
		var c := p + bs * Vector3(0, 0.33, wz)
		geo.cyl("solid", c - bs.x * 0.02, c + bs.x * 0.02, 0.33, 0.33, 10, Color("2a2a2e"), true)
	geo.cyl("solid", p + bs * Vector3(0, 0.33, -0.5), p + bs * Vector3(0, 0.75, 0.1), 0.03, 0.03, 4, frame)
	geo.cyl("solid", p + bs * Vector3(0, 0.33, 0.5), p + bs * Vector3(0, 0.75, 0.1), 0.03, 0.03, 4, frame)
	geo.cyl("solid", p + bs * Vector3(0, 0.75, 0.1), p + bs * Vector3(0, 0.95, 0.45), 0.03, 0.03, 4, frame)
	geo.block("solid", p + bs * Vector3(0, 0.8, -0.2), Vector3(0.12, 0.06, 0.25), Color("2a2a2e"), yaw)
	geo.box("solid", Transform3D(bs, p + bs * Vector3(0, 0.95, 0.5)), Vector3(0.55, 0.04, 0.04), Color("303030"))
	if rng.randf() < 0.6:
		geo.box("solid", Transform3D(bs, p + bs * Vector3(0, 0.75, 0.65)), Vector3(0.35, 0.22, 0.3), Color("c0c4c8"))


func _mirror(p: Vector3) -> void:
	geo.cyl("solid", p, p + Vector3(0, 2.8, 0), 0.05, 0.05, 5, Color("e87a2a"))
	var yaw := _street_yaw(p) + PI * 0.25
	var m := p + Vector3(0, 2.9, 0)
	var dir := Vector3(sin(yaw), 0, cos(yaw))
	geo.cyl("solid", m, m + dir * 0.1, 0.34, 0.34, 10, Color("e87a2a"))
	geo.cyl("glow", m + dir * 0.1, m + dir * 0.12, 0.29, 0.29, 10, Color("b8c8e0", 0.7))
	geo.col_cyl(p, 0.08, 2.6)


func _planters(p: Vector3) -> void:
	for k in rng.randi_range(3, 6):
		var q := p + Vector3(rng.randf_range(-0.8, 0.8), 0, rng.randf_range(-0.8, 0.8))
		var r := rng.randf_range(0.15, 0.3)
		geo.cyl("solid", q, q + Vector3(0, r * 1.5, 0), r * 0.8, r, 7, pick([Color("b86a45"), Color("6e7280"), Color("e8e4dc"), Color("4a5a7a")]))
		geo.leaf_ball("bush", q + Vector3(0, r * 2.3, 0), Vector3(r * 1.8, r * 2.2, r * 1.8), 7, pick([Color("4f8a45"), Color("5a9a4a"), Color("3f7a44")]), rng, 0.8, 0.6)


func _cat(p: Vector3) -> void:
	var col: Color = pick([Color("f2a65a"), Color("2a2a2e"), Color("e8e4dc"), Color("8a8a8e")])
	var yaw := rng.randf() * TAU
	var bs := Basis(Vector3.UP, yaw)
	geo.box("solid", Transform3D(bs, p + Vector3(0, 0.14, 0)), Vector3(0.22, 0.2, 0.36), col)
	geo.box("solid", Transform3D(bs, p + bs * Vector3(0, 0.3, 0.15)), Vector3(0.2, 0.18, 0.16), col)
	for sx: float in [-0.06, 0.06]:
		geo.box("solid", Transform3D(bs, p + bs * Vector3(sx, 0.42, 0.15)), Vector3(0.05, 0.07, 0.04), col)
	geo.cyl("solid", p + bs * Vector3(0, 0.12, -0.18), p + bs * Vector3(0.1, 0.35, -0.3), 0.025, 0.02, 4, col)


func _tokyo_tower(p: Vector3) -> void:
	var red := Color("e8553a")
	var white := Color("f2f0ea")
	var levels := 14
	for i in levels:
		var t0 := float(i) / levels
		var t1 := float(i + 1) / levels
		var w0 := lerpf(40.0, 3.0, pow(t0, 0.7))
		var w1 := lerpf(40.0, 3.0, pow(t1, 0.7))
		var y0 := t0 * 190.0
		var y1 := t1 * 190.0
		var c := red if i % 2 == 0 else white
		for cx: int in [-1, 1]:
			for cz: int in [-1, 1]:
				geo.cyl("solid", p + Vector3(cx * w0 * 0.5, y0, cz * w0 * 0.5), p + Vector3(cx * w1 * 0.5, y1, cz * w1 * 0.5), 1.2, 1.0, 4, c, false)
		if i % 3 == 1:
			geo.block("solid", p + Vector3(0, y1 - 1.0, 0), Vector3(w1, 2.0, w1), c)
			geo.block("glow", p + Vector3(0, y1 - 1.5, 0), Vector3(w1 + 0.2, 0.6, w1 + 0.2), Color("ffd080", 0.2))
	geo.block("solid", p + Vector3(0, 60.0, 0), Vector3(22.0, 5.0, 22.0), white)
	geo.block("glow", p + Vector3(0, 61.5, 0), Vector3(22.3, 2.0, 22.3), Color("ffd49a", 0.3))
	geo.cyl("solid", p + Vector3(0, 190.0, 0), p + Vector3(0, 230.0, 0), 1.2, 0.3, 6, red)
	geo.block("glow", p + Vector3(0, 230.0, 0), Vector3(1.5, 1.5, 1.5), Color("ff4040", 0.8))
