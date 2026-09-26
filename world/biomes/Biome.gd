extends RefCounted
## Base for a procedurally generated world: terrain, grass/flower fields and a
## shared kit of natural props. Subclasses shape the land and place landmarks.

const Geo := preload("res://world/Geo.gd")

var geo := Geo.new()
var rng := RandomNumberGenerator.new()
var seed := 1
var R := 118.0                       # walkable radius
var spawn := Vector3(0, 0, 40)
var spawn_yaw := 0.0
var ray_spots: Array = []            # [top: Vector3, width, length]
var photo_spots: Array = []          # [Vector3, String]
var water_level := -1000.0
var grass_tint := Color("5f9a45")
var flower_colors: Array = [Color("ffffff"), Color("d8c8ff")]
var flower_amount := 0.1

# inner terrain cache
var _half := 140.0
var _cell := 2.5
var _n := 0
var _h := PackedFloat32Array()
var _cols := PackedColorArray()
var _occ := {}                       # Vector2i -> true (big props)
var _grass := {}                     # chunk -> [[Transform3D, Color], ...]
var _flowers := {}
var _grass_mesh: ArrayMesh
var _flower_mesh: ArrayMesh


func _init(p_seed: int) -> void:
	seed = p_seed
	rng.seed = p_seed


# ------------------------------------------------------------------ overridables

func height(_x: float, _z: float) -> float:
	return 0.0


## Colour of the ground; slope is 0 (flat) .. 1 (vertical).
func ground_color(_x: float, _z: float, _h: float, _slope: float) -> Color:
	return Color("5f9a45")


## 0..1 chance of a grass tuft here (flowers use flower_amount on top).
func grass_density(_x: float, _z: float, _h: float, _slope: float) -> float:
	return 0.8


func generate() -> void:
	pass


# ------------------------------------------------------------------ helpers

func noise(freq: float, octaves := 3, offset := 0) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed + offset
	n.frequency = freq
	n.fractal_octaves = octaves
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	return n


func jitter(c: Color, amt := 0.05) -> Color:
	var v := rng.randf_range(-amt, amt)
	return Color(clampf(c.r + v, 0, 1), clampf(c.g + v, 0, 1), clampf(c.b + v, 0, 1), c.a)


func pick(arr: Array):
	return arr[rng.randi() % arr.size()]


## Height of the built terrain surface (bilinear on the cached grid).
func ground_y(x: float, z: float) -> float:
	var fx := (x + _half) / _cell
	var fz := (z + _half) / _cell
	if fx < 0 or fz < 0 or fx >= _n or fz >= _n or _h.is_empty():
		return height(x, z)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var w := _n + 1
	var h00 := _h[iz * w + ix]
	var h10 := _h[iz * w + ix + 1]
	var h01 := _h[(iz + 1) * w + ix]
	var h11 := _h[(iz + 1) * w + ix + 1]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


func at(x: float, z: float) -> Vector3:
	return Vector3(x, ground_y(x, z), z)


func slope_at(x: float, z: float) -> float:
	var e := 1.0
	var dx := ground_y(x + e, z) - ground_y(x - e, z)
	var dz := ground_y(x, z + e) - ground_y(x, z - e)
	var n := Vector3(-dx, 2.0 * e, -dz).normalized()
	return 1.0 - n.y


## Reserve a circular footprint; returns false if something big is already there.
func claim(p: Vector3, radius: float, test_only := false) -> bool:
	var c := 2.0
	var r := int(ceil(radius / c))
	var cx := int(floor(p.x / c))
	var cz := int(floor(p.z / c))
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if _occ.has(Vector2i(cx + dx, cz + dz)):
				return false
	if not test_only:
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if dx * dx + dz * dz <= (r + 0.5) * (r + 0.5):
					_occ[Vector2i(cx + dx, cz + dz)] = true
	return true


func is_free(p: Vector3, radius: float) -> bool:
	return claim(p, radius, true)


func random_point(radius: float, min_r := 0.0) -> Vector3:
	var a := rng.randf() * TAU
	var d := sqrt(rng.randf_range((min_r / radius) ** 2, 1.0)) * radius
	return at(cos(a) * d, sin(a) * d)


# ------------------------------------------------------------------ terrain

func build_terrain(outer_half := 560.0, outer_cell := 10.0) -> void:
	_n = int(_half * 2.0 / _cell)
	var w := _n + 1
	_h.resize(w * w)
	for iz in w:
		for ix in w:
			_h[iz * w + ix] = height(-_half + ix * _cell, -_half + iz * _cell)
	_grid_mesh(_h, w, _cell, -_half, false, R + 14.0)
	# skirt around the detailed area so seams with the far terrain never show sky
	for i in _n:
		for side in 4:
			var p0: Vector3
			var p1: Vector3
			var out: Vector3
			match side:
				0:
					p0 = Vector3(-_half + i * _cell, _h[i], -_half); p1 = Vector3(-_half + (i + 1) * _cell, _h[i + 1], -_half); out = Vector3.BACK
				1:
					p0 = Vector3(-_half + i * _cell, _h[_n * w + i], _half); p1 = Vector3(-_half + (i + 1) * _cell, _h[_n * w + i + 1], _half); out = Vector3.FORWARD
				2:
					p0 = Vector3(-_half, _h[i * w], -_half + i * _cell); p1 = Vector3(-_half, _h[(i + 1) * w], -_half + (i + 1) * _cell); out = Vector3.RIGHT
				_:
					p0 = Vector3(_half, _h[i * w + _n], -_half + i * _cell); p1 = Vector3(_half, _h[(i + 1) * w + _n], -_half + (i + 1) * _cell); out = Vector3.LEFT
			var col := ground_color(p0.x, p0.z, p0.y, 0.8).darkened(0.1)
			geo.quad("terrain", p0, p1, p1 - Vector3(0, 6, 0), p0 - Vector3(0, 6, 0), col, out)
			geo.quad("terrain", p0, p1, p1 - Vector3(0, 6, 0), p0 - Vector3(0, 6, 0), col, -out)
	# far terrain, coarser
	var m := int(outer_half * 2.0 / outer_cell)
	var ow := m + 1
	var oh := PackedFloat32Array()
	oh.resize(ow * ow)
	for iz in ow:
		for ix in ow:
			oh[iz * ow + ix] = height(-outer_half + ix * outer_cell, -outer_half + iz * outer_cell)
	_grid_mesh(oh, ow, outer_cell, -outer_half, true, 0.0)


## Emit a height grid as smooth-shaded, vertex-coloured triangles.
## Steep triangles become crisp rock facets. Optionally adds collision near the centre.
func _grid_mesh(hh: PackedFloat32Array, w: int, cell: float, origin: float, skip_inner: bool, collide_r: float) -> void:
	var nrm := PackedVector3Array()
	var cols := PackedColorArray()
	nrm.resize(w * w)
	cols.resize(w * w)
	for iz in w:
		for ix in w:
			var n := _gn(hh, w, cell, ix, iz)
			nrm[iz * w + ix] = n
			var x := origin + ix * cell
			var z := origin + iz * cell
			if skip_inner and absf(x) < _half - cell and absf(z) < _half - cell:
				continue
			cols[iz * w + ix] = ground_color(x, z, hh[iz * w + ix], 1.0 - n.y)
	if not skip_inner:
		_cols = cols
	var faces := PackedVector3Array()
	var cr2 := collide_r * collide_r
	for iz in w - 1:
		for ix in w - 1:
			var x0 := origin + ix * cell
			var z0 := origin + iz * cell
			if skip_inner and absf(x0 + cell * 0.5) < _half and absf(z0 + cell * 0.5) < _half:
				continue
			var ia := iz * w + ix
			var ib := ia + 1
			var ic := ia + w
			var id := ic + 1
			var a := Vector3(x0, hh[ia], z0)
			var b := Vector3(x0 + cell, hh[ib], z0)
			var c := Vector3(x0, hh[ic], z0 + cell)
			var d := Vector3(x0 + cell, hh[id], z0 + cell)
			var tris: Array
			if (ix + iz) % 2 == 0:
				tris = [[a, b, d, ia, ib, id], [a, d, c, ia, id, ic]]
			else:
				tris = [[a, b, c, ia, ib, ic], [b, d, c, ib, id, ic]]
			var near := collide_r > 0.0 and (x0 * x0 + z0 * z0) < cr2
			for t in tris:
				var p0: Vector3 = t[0]
				var p1: Vector3 = t[1]
				var p2: Vector3 = t[2]
				var fn := (p2 - p0).cross(p1 - p0).normalized()
				if fn.y < 0:
					fn = -fn
				if fn.y < 0.72:
					var cen := (p0 + p1 + p2) / 3.0
					var rc := ground_color(cen.x, cen.z, cen.y, 1.0 - fn.y)
					geo.tri_n("terrain", p0, p1, p2, fn, fn, fn, rc, rc, rc)
				else:
					geo.tri_n("terrain", p0, p1, p2, nrm[t[3]], nrm[t[4]], nrm[t[5]], cols[t[3]], cols[t[4]], cols[t[5]])
				if near:
					faces.append(p0); faces.append(p1); faces.append(p2)
	if not faces.is_empty():
		geo.col_faces(faces)


## Smooth normal of a height-grid vertex.
func _gn(hh: PackedFloat32Array, w: int, cell: float, ix: int, iz: int) -> Vector3:
	var x0 := clampi(ix - 1, 0, w - 1)
	var x1 := clampi(ix + 1, 0, w - 1)
	var z0 := clampi(iz - 1, 0, w - 1)
	var z1 := clampi(iz + 1, 0, w - 1)
	var dx := (hh[iz * w + x1] - hh[iz * w + x0]) / (cell * (x1 - x0))
	var dz := (hh[z1 * w + ix] - hh[z0 * w + ix]) / (cell * (z1 - z0))
	return Vector3(-dx, 1.0, -dz).normalized()


# ------------------------------------------------------------------ grass & flowers

func scatter_grass(step := 0.75, max_r := -1.0) -> void:
	if max_r < 0:
		max_r = R + 12.0
	var g := 0.0
	var z := -max_r
	while z < max_r:
		var x := -max_r
		while x < max_r:
			var px := x + rng.randf_range(0, step)
			var pz := z + rng.randf_range(0, step)
			x += step
			if px * px + pz * pz > max_r * max_r:
				continue
			var h := ground_y(px, pz)
			if h < water_level + 0.15:
				continue
			var sl := slope_at(px, pz)
			var dens := grass_density(px, pz, h, sl)
			if dens <= 0.0 or rng.randf() > dens:
				continue
			var s := rng.randf_range(0.7, 1.25) * clampf(dens * 1.3, 0.6, 1.2)
			var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.3), s)), Vector3(px, h - 0.05, pz))
			var base := cached_color(px, pz)
			var tint := base.lerp(grass_tint, 0.35).lightened(rng.randf_range(0.0, 0.08))
			_add_inst(_grass, xf, tint)
			if rng.randf() < flower_amount * dens:
				var fs := rng.randf_range(0.8, 1.2)
				var fxf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(fs, fs, fs)), Vector3(px + 0.1, h, pz))
				_add_inst(_flowers, fxf, pick(flower_colors))
		z += step


func _add_inst(dict: Dictionary, xf: Transform3D, col: Color) -> void:
	var key := Vector2i(floori(xf.origin.x / 32.0), floori(xf.origin.z / 32.0))
	if not dict.has(key):
		dict[key] = []
	dict[key].append([xf, col])


func _tuft_mesh(width: float, height: float, lift: float, blades: int) -> ArrayMesh:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()
	for i in blades:
		var ang := PI * i / blades
		var d := Vector3(cos(ang), 0, sin(ang)) * width * 0.5
		var p := [-d + Vector3(0, lift, 0), d + Vector3(0, lift, 0), d + Vector3(0, lift + height, 0), -d + Vector3(0, lift + height, 0)]
		var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		var alphas := [0.0, 0.0, 1.0, 1.0]
		for idx: int in [0, 1, 2, 0, 2, 3]:
			v.append(p[idx])
			n.append(Vector3.UP)
			c.append(Color(1, 1, 1, alphas[idx]))
			uv.append(uvs[idx])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = n
	arrays[Mesh.ARRAY_COLOR] = c
	arrays[Mesh.ARRAY_TEX_UV] = uv
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func build_instances(parent: Node3D, mats) -> void:
	_grass_mesh = _tuft_mesh(0.55, 0.36, 0.0, 3)
	_flower_mesh = _tuft_mesh(0.18, 0.18, 0.16, 2)
	_build_mm(parent, _grass, _grass_mesh, mats.get_mat("grass"), 58.0)
	_build_mm(parent, _flowers, _flower_mesh, mats.get_mat("flower"), 48.0)
	_grass.clear()
	_flowers.clear()


func _build_mm(parent: Node3D, dict: Dictionary, mesh: Mesh, mat: Material, vis: float) -> void:
	for key in dict:
		var list: Array = dict[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = mesh
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i][0])
			mm.set_instance_color(i, list[i][1])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = vis
		mmi.visibility_range_end_margin = 8.0
		parent.add_child(mmi)


# ------------------------------------------------------------------ natural prop kit

func tree_broadleaf(base: Vector3, height: float, canopy: float, trunk_col: Color, leaf_col: Color,
		collide := true, lean := 0.0) -> void:
	trunk_col.a = 0.6
	var dir := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized() * lean
	var top := base + Vector3(0, height, 0) + dir * height * 0.2
	var r := clampf(height * 0.045, 0.18, 1.2)
	var mid := base.lerp(top, 0.55) + Vector3(rng.randf_range(-0.4, 0.4), 0, rng.randf_range(-0.4, 0.4))
	geo.cyl("solid", base - Vector3(0, 0.4, 0), mid, r * 1.25, r, 6, trunk_col)
	geo.cyl("solid", mid, top, r, r * 0.55, 6, trunk_col)
	# a couple of branches reaching into the canopy
	for i in rng.randi_range(2, 4):
		var ang := rng.randf() * TAU
		var bstart := base.lerp(top, rng.randf_range(0.5, 0.8))
		var bend := bstart + Vector3(cos(ang) * canopy * 0.6, canopy * 0.35, sin(ang) * canopy * 0.6)
		geo.cyl("solid", bstart, bend, r * 0.45, r * 0.2, 5, trunk_col)
	var blobs := rng.randi_range(4, 7)
	for i in blobs:
		var o := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.3, 0.6), rng.randf_range(-1, 1)) * canopy * 0.65
		var br := canopy * rng.randf_range(0.5, 0.75)
		geo.leaf_ball("canopy", top + o, Vector3(br, br * 0.75, br), int(br * br * 6.0) + 8, jitter(leaf_col, 0.04), rng, 0.8, 0.35)
	if collide:
		geo.col_cyl(base, r * 1.1, height * 0.6)


func tree_pine(base: Vector3, height: float, col: Color, trunk_col := Color("5a4030"), collide := true) -> void:
	var r := height * 0.24
	geo.cyl("solid", base - Vector3(0, 0.3, 0), base + Vector3(0, height * 0.35, 0), height * 0.035, height * 0.025, 5, trunk_col)
	var tiers := int(clampf(height / 3.0, 3, 6))
	for i in tiers:
		var t := float(i) / tiers
		var y0 := height * (0.18 + t * 0.66)
		var tr := r * (1.0 - t * 0.72) * rng.randf_range(0.9, 1.1)
		var th := height * 0.34
		var c := col.lightened(t * 0.08)
		c.a = 0.0
		geo.cyl("solid", base + Vector3(0, y0, 0), base + Vector3(0, y0 + th, 0), tr, 0.0, 7, c, false, rng.randf() * TAU)
		# underside so tiers look solid from below
		var under := col.darkened(0.3)
		for k in 7:
			var a0 := TAU * k / 7.0
			var a1 := TAU * (k + 1) / 7.0
			geo.tri("solid", base + Vector3(0, y0, 0), base + Vector3(cos(a0) * tr, y0, sin(a0) * tr),
				base + Vector3(cos(a1) * tr, y0, sin(a1) * tr), under, Vector3.DOWN)
	if collide:
		geo.col_cyl(base, 0.35, height * 0.5)


func tree_sakura(base: Vector3, height: float) -> void:
	var trunk := Color("5b4040", 0.6)
	var top := base + Vector3(rng.randf_range(-0.8, 0.8), height * 0.55, rng.randf_range(-0.8, 0.8))
	geo.cyl("solid", base - Vector3(0, 0.3, 0), top, 0.32, 0.2, 6, trunk)
	for i in 4:
		var ang := TAU * i / 4.0 + rng.randf() * 0.8
		var end := top + Vector3(cos(ang) * height * 0.35, height * rng.randf_range(0.1, 0.3), sin(ang) * height * 0.35)
		geo.cyl("solid", top, end, 0.18, 0.08, 5, trunk)
		var br := height * rng.randf_range(0.2, 0.28)
		geo.leaf_ball("canopy", end + Vector3(0, br * 0.3, 0), Vector3(br * 1.2, br * 0.8, br * 1.2), 22,
			jitter(Color("f6c1cf"), 0.04), rng, 0.8, 0.3)
	geo.leaf_ball("canopy", top + Vector3(0, height * 0.35, 0), Vector3(height * 0.3, height * 0.22, height * 0.3), 26,
		Color("f9d0da"), rng, 0.8, 0.3)
	geo.col_cyl(base, 0.35, 3.0)


func bush(base: Vector3, radius: float, col: Color, squash := 0.75) -> void:
	geo.leaf_ball("bush", base + Vector3(0, radius * squash * 0.7, 0), Vector3(radius, radius * squash, radius),
		int(radius * radius * 7.0) + 5, jitter(col, 0.03), rng, 0.9, 0.8)


func boulder(base: Vector3, size: float, col: Color, moss := 1.0, collide := true) -> void:
	var sz := Vector3(size * rng.randf_range(0.9, 1.4), size * rng.randf_range(0.6, 1.0), size * rng.randf_range(0.9, 1.3))
	var pts := geo.rock("solid", base + Vector3(0, sz.y * 0.35, 0), sz, rng, jitter(col, 0.03), moss)
	if collide and size > 0.6:
		geo.col_hull(pts)


func rock_cluster(center: Vector3, count: int, size: float, col: Color, moss := 1.0) -> void:
	for i in count:
		var o := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)) * size * 1.4
		var p := at(center.x + o.x, center.z + o.z)
		boulder(p, size * rng.randf_range(0.4, 1.0), col, moss)


func bench(base: Vector3, yaw: float, wood := Color("9a6a44"), metal := Color("3c3c44")) -> void:
	var bs := Basis(Vector3.UP, yaw)
	for sx: float in [-0.7, 0.7]:
		geo.box("solid", Transform3D(bs, base + bs * Vector3(sx, 0.22, 0)), Vector3(0.08, 0.44, 0.45), metal)
	geo.box("solid", Transform3D(bs, base + bs * Vector3(0, 0.46, 0)), Vector3(1.7, 0.07, 0.45), wood)
	geo.box("solid", Transform3D(bs * Basis(Vector3.RIGHT, -0.2), base + bs * Vector3(0, 0.75, -0.22)), Vector3(1.7, 0.3, 0.06), wood)
	geo.col_box(Transform3D(bs, base + bs * Vector3(0, 0.3, 0)), Vector3(1.7, 0.6, 0.5))
	photo_spots.append([base, "bench"])


## Path helper: distance from p to the polyline.
func dist_to_path(p: Vector2, path: Array) -> float:
	var best := 1e9
	for i in path.size() - 1:
		var a: Vector2 = path[i]
		var b: Vector2 = path[i + 1]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t))
	return best


## Ground colour from the terrain cache (cheap; used when scattering).
func cached_color(x: float, z: float) -> Color:
	if _cols.is_empty():
		return ground_color(x, z, ground_y(x, z), 0.0)
	var w := _n + 1
	var ix := clampi(int(round((x + _half) / _cell)), 0, _n)
	var iz := clampi(int(round((z + _half) / _cell)), 0, _n)
	return _cols[iz * w + ix]
