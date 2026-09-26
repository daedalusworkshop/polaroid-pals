extends RefCounted
## Chunked mesh builder. Props are "painted" into per-layer, per-chunk vertex
## buffers (flat-shaded, vertex-coloured) and baked into a handful of meshes.

const CHUNK := 40.0
## Layers that share another layer's material.
const LAYER_MAT := {"bush": "leaf", "canopy": "leaf"}
const NO_SHADOW := ["glow", "sign", "water", "falls", "grass", "flower"]
## Small stuff fades out at distance (metres).
const VIS_RANGE := {"bush": 110.0, "fern": 70.0}


class Buf:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()


var layers := {}        # layer -> {Vector2i: Buf}
var colliders: Array = []   # [Shape3D, Transform3D]
var light_spots: Array = [] # [Vector3, Color, range]


func _buf(layer: String, p: Vector3) -> Buf:
	var key := Vector2i(floori(p.x / CHUNK), floori(p.z / CHUNK))
	if not layers.has(layer):
		layers[layer] = {}
	var L: Dictionary = layers[layer]
	if not L.has(key):
		L[key] = Buf.new()
	return L[key]


# ------------------------------------------------------------------ primitives

## Flat triangle. `out` = which way the face should point (auto-fixes winding).
func tri(layer: String, a: Vector3, b: Vector3, c: Vector3, col: Color, out := Vector3.ZERO,
		ua := Vector2(0, 0), ub := Vector2(1, 0), uc := Vector2(1, 1)) -> void:
	var n := (c - a).cross(b - a)
	if out != Vector3.ZERO and n.dot(out) < 0.0:
		var t := b; b = c; c = t
		var tu := ub; ub = uc; uc = tu
		n = -n
	n = n.normalized()
	var buf := _buf(layer, (a + b + c) / 3.0)
	buf.v.append(a); buf.v.append(b); buf.v.append(c)
	buf.n.append(n); buf.n.append(n); buf.n.append(n)
	buf.c.append(col); buf.c.append(col); buf.c.append(col)
	buf.uv.append(ua); buf.uv.append(ub); buf.uv.append(uc)


## Triangle with per-vertex normals (smooth terrain). Winding follows `out`.
func tri_n(layer: String, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3,
		ca: Color, cb: Color, cc: Color, out := Vector3.UP) -> void:
	if (c - a).cross(b - a).dot(out) < 0.0:
		var t := b; b = c; c = t
		var tn := nb; nb = nc; nc = tn
		var tc := cb; cb = cc; cc = tc
	var buf := _buf(layer, (a + b + c) / 3.0)
	buf.v.append(a); buf.v.append(b); buf.v.append(c)
	buf.n.append(na); buf.n.append(nb); buf.n.append(nc)
	buf.c.append(ca); buf.c.append(cb); buf.c.append(cc)
	buf.uv.append(Vector2.ZERO); buf.uv.append(Vector2.ZERO); buf.uv.append(Vector2.ZERO)


func quad(layer: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, out := Vector3.ZERO,
		uv0 := Vector2(0, 1), uv1 := Vector2(1, 1), uv2 := Vector2(1, 0), uv3 := Vector2(0, 0)) -> void:
	if out == Vector3.ZERO:
		out = (c - a).cross(b - a)
	tri(layer, a, b, c, col, out, uv0, uv1, uv2)
	tri(layer, a, c, d, col, out, uv0, uv2, uv3)


## Quad with explicit per-vertex normals (foliage cards). No winding needed.
func card(layer: String, p: Array, normals: Array, col: Color, cols := []) -> void:
	var buf := _buf(layer, (p[0] + p[2]) * 0.5)
	var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
	for idx in [0, 1, 2, 0, 2, 3]:
		buf.v.append(p[idx])
		buf.n.append(normals[idx])
		buf.c.append(cols[idx] if cols.size() == 4 else col)
		buf.uv.append(uvs[idx])


## Box centred on xf.origin. `top` overrides the top face colour.
func box(layer: String, xf: Transform3D, size: Vector3, col: Color, top = null, bottom := false) -> void:
	var h := size * 0.5
	var bs := xf.basis
	var o := xf.origin
	var X := bs.x * h.x
	var Y := bs.y * h.y
	var Z := bs.z * h.z
	var p000 := o - X - Y - Z
	var p100 := o + X - Y - Z
	var p010 := o - X + Y - Z
	var p110 := o + X + Y - Z
	var p001 := o - X - Y + Z
	var p101 := o + X - Y + Z
	var p011 := o - X + Y + Z
	var p111 := o + X + Y + Z
	var top_col: Color = top if top != null else col
	quad(layer, p010, p110, p111, p011, top_col, bs.y)
	quad(layer, p001, p101, p111, p011, col, bs.z)
	quad(layer, p000, p100, p110, p010, col, -bs.z)
	quad(layer, p100, p101, p111, p110, col, bs.x)
	quad(layer, p000, p001, p011, p010, col, -bs.x)
	if bottom:
		quad(layer, p000, p100, p101, p001, col, -bs.y)


## Axis-aligned convenience: box from its bottom-centre.
func block(layer: String, base: Vector3, size: Vector3, col: Color, yaw := 0.0, top = null) -> void:
	var xf := Transform3D(Basis(Vector3.UP, yaw), base + Vector3(0, size.y * 0.5, 0))
	box(layer, xf, size, col, top)


## Faceted (tapered) cylinder from a to b.
func cyl(layer: String, a: Vector3, b: Vector3, r0: float, r1: float, sides: int, col: Color,
		cap := true, twist := 0.0, cap_col = null) -> void:
	var axis := (b - a).normalized()
	var ref := Vector3.UP if absf(axis.y) < 0.95 else Vector3.RIGHT
	var u := axis.cross(ref).normalized()
	var w := axis.cross(u).normalized()
	var ring0: Array = []
	var ring1: Array = []
	for i in sides:
		var ang := TAU * i / sides + twist
		var d := u * cos(ang) + w * sin(ang)
		ring0.append(a + d * r0)
		ring1.append(b + d * r1)
	for i in sides:
		var j := (i + 1) % sides
		var mid_dir: Vector3 = ((ring0[i] + ring0[j]) * 0.5 - a).normalized()
		if r1 < 0.001:
			tri(layer, ring0[i], ring0[j], b, col, mid_dir + axis * 0.3)
		else:
			quad(layer, ring0[i], ring0[j], ring1[j], ring1[i], col, mid_dir)
	if cap and r1 > 0.001:
		var cc: Color = cap_col if cap_col != null else col
		for i in sides:
			tri(layer, b, ring1[i], ring1[(i + 1) % sides], cc, axis)


## Gable roof over a rectangle (ridge along local X). base = centre at eave height.
func roof(layer: String, base: Vector3, width: float, depth: float, height: float, yaw: float,
		col: Color, gable_col: Color, overhang := 0.4) -> void:
	var bs := Basis(Vector3.UP, yaw)
	var hw := width * 0.5 + overhang
	var hd := depth * 0.5 + overhang
	var r0 := base + bs * Vector3(-hw, height, 0)
	var r1 := base + bs * Vector3(hw, height, 0)
	var f0 := base + bs * Vector3(-hw, -overhang * 0.4, hd)
	var f1 := base + bs * Vector3(hw, -overhang * 0.4, hd)
	var b0 := base + bs * Vector3(-hw, -overhang * 0.4, -hd)
	var b1 := base + bs * Vector3(hw, -overhang * 0.4, -hd)
	var nf := (bs * Vector3(0, hd, height)).normalized()
	var nb := (bs * Vector3(0, hd, -height)).normalized()
	quad(layer, f0, f1, r1, r0, col, nf)
	quad(layer, b0, b1, r1, r0, col, nb)
	# undersides so overhangs aren't see-through
	quad(layer, f0, f1, r1, r0, col.darkened(0.35), -nf)
	quad(layer, b0, b1, r1, r0, col.darkened(0.35), -nb)
	# gable ends (inside the wall line)
	var gw := width * 0.5
	var gd := depth * 0.5
	var ex := bs * Vector3(1, 0, 0)
	for s in [-1.0, 1.0]:
		var g0 := base + bs * Vector3(s * gw, 0, gd)
		var g1 := base + bs * Vector3(s * gw, 0, -gd)
		var gt := base + bs * Vector3(s * gw, height - overhang * height / hd, 0)
		tri(layer, g0, g1, gt, gable_col, ex * s)


# ------------------------------------------------------------------ organic bits

static var _ico_v: Array = []
static var _ico_f: Array = []


static func _ico() -> void:
	if not _ico_v.is_empty():
		return
	var t := (1.0 + sqrt(5.0)) / 2.0
	var verts := [
		Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	var faces := [
		[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2],
		[10, 7, 6], [7, 1, 8], [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5],
		[2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]
	for i in verts.size():
		verts[i] = verts[i].normalized()
	# one subdivision
	var cache := {}
	var nf: Array = []
	for f in faces:
		var m: Array = []
		for k in 3:
			var a: int = f[k]
			var b: int = f[(k + 1) % 3]
			var key := Vector2i(mini(a, b), maxi(a, b))
			if not cache.has(key):
				verts.append(((verts[a] + verts[b]) * 0.5).normalized())
				cache[key] = verts.size() - 1
			m.append(cache[key])
		nf.append([f[0], m[0], m[2]])
		nf.append([f[1], m[1], m[0]])
		nf.append([f[2], m[2], m[1]])
		nf.append([m[0], m[1], m[2]])
	_ico_v = verts
	_ico_f = nf


## Faceted boulder like the reference art. Returns hull points (for collision).
func rock(layer: String, center: Vector3, size: Vector3, rng: RandomNumberGenerator, col: Color,
		moss := 1.0, jag := 0.22, low := false) -> PackedVector3Array:
	_ico()
	var bs := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.2, 0.2))
	var pts := PackedVector3Array()
	var offs := rng.randf() * 100.0
	for v in _ico_v:
		var j := 1.0 + (rng.randf() - 0.5) * 2.0 * jag
		var p: Vector3 = v * j
		# flatten: planes cut through the top and bottom for chunky facets
		p.y = clampf(p.y, -0.55, 0.8 + sin(offs + p.x * 2.0) * 0.15)
		pts.append(center + bs * (p * size))
	var faces: Array = _ico_f
	var step := 1
	if low:
		step = 1
	for fi in range(0, faces.size(), step):
		var f: Array = faces[fi]
		var a := pts[f[0]]
		var b := pts[f[1]]
		var c := pts[f[2]]
		var fc := col
		var vshift := rng.randf_range(-0.05, 0.05)
		fc = Color(fc.r + vshift, fc.g + vshift, fc.b + vshift * 1.2, minf(moss, 0.9))
		tri(layer, a, b, c, fc, (a + b + c) / 3.0 - center)
	return pts


## Sphere-ish cloud of leaf cards with volumetric normals.
func leaf_ball(layer: String, center: Vector3, radius: Vector3, count: int, col: Color,
		rng: RandomNumberGenerator, card := 1.0, wind := 0.6, col_var := 0.07) -> void:
	for i in count:
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.6, 1), rng.randf_range(-1, 1)).normalized()
		var p := center + dir * radius * rng.randf_range(0.45, 1.0)
		var s := (radius.x + radius.y) * 0.5 * 0.95 * card * rng.randf_range(0.75, 1.15)
		var r := dir.cross(Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))).normalized()
		if r.length_squared() < 0.01:
			r = Vector3.RIGHT
		var u := dir.cross(r).normalized()
		var corners := [p - r * s * 0.5 - u * s * 0.5, p + r * s * 0.5 - u * s * 0.5,
			p + r * s * 0.5 + u * s * 0.5, p - r * s * 0.5 + u * s * 0.5]
		var normals := []
		for cpos in corners:
			normals.append(((cpos - center) / radius + dir * 0.6).normalized())
		var v := rng.randf_range(-col_var, col_var)
		var cc := Color(clampf(col.r + v, 0, 1), clampf(col.g + v * 1.1, 0, 1), clampf(col.b + v * 0.6, 0, 1), wind)
		card(layer, corners, normals, cc)


## Fern: arching fronds in a rosette.
func fern(center: Vector3, size: float, col: Color, rng: RandomNumberGenerator) -> void:
	var n := rng.randi_range(5, 8)
	for i in n:
		var ang := TAU * i / n + rng.randf_range(-0.3, 0.3)
		var dir := Vector3(cos(ang), 0, sin(ang))
		var side := dir.cross(Vector3.UP)
		var tilt := rng.randf_range(0.45, 0.8)
		var tip := center + (dir * cos(tilt) + Vector3.UP * sin(tilt)) * size
		var w := size * 0.28
		var corners := [center - side * w * 0.3, center + side * w * 0.3, tip + side * w, tip - side * w]
		var up := (Vector3.UP + dir * 0.4).normalized()
		var v := rng.randf_range(-0.05, 0.05)
		var cc := Color(col.r + v, col.g + v, col.b + v * 0.5, 1.0)
		# vertex alpha: base still, tip sways
		var cols := [Color(cc, 0.0), Color(cc, 0.0), Color(cc, 1.0), Color(cc, 1.0)]
		# UV: texture tip at top (v=0) — card() maps p[2],p[3] to v=0
		card("fern", corners, [up, up, up, up], cc, cols)


# ------------------------------------------------------------------ collision + lights

func col_box(xf: Transform3D, size: Vector3) -> void:
	var s := BoxShape3D.new()
	s.size = size
	colliders.append([s, xf])


func col_block(base: Vector3, size: Vector3, yaw := 0.0) -> void:
	col_box(Transform3D(Basis(Vector3.UP, yaw), base + Vector3(0, size.y * 0.5, 0)), size)


func col_cyl(base: Vector3, radius: float, height: float) -> void:
	var s := CylinderShape3D.new()
	s.radius = radius
	s.height = height
	colliders.append([s, Transform3D(Basis(), base + Vector3(0, height * 0.5, 0))])


func col_hull(points: PackedVector3Array) -> void:
	var s := ConvexPolygonShape3D.new()
	s.points = points
	colliders.append([s, Transform3D()])


func col_faces(faces: PackedVector3Array) -> void:
	var s := ConcavePolygonShape3D.new()
	s.set_faces(faces)
	s.backface_collision = true
	colliders.append([s, Transform3D()])


func light(pos: Vector3, col: Color, rng_m := 7.0) -> void:
	light_spots.append([pos, col, rng_m])


# ------------------------------------------------------------------ bake

func build(parent: Node3D, mats) -> void:
	for layer in layers:
		var mat_name: String = LAYER_MAT.get(layer, layer)
		var mat: Material = mats.get_mat(mat_name)
		for key in layers[layer]:
			var b: Buf = layers[layer][key]
			if b.v.is_empty():
				continue
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = b.v
			arrays[Mesh.ARRAY_NORMAL] = b.n
			arrays[Mesh.ARRAY_COLOR] = b.c
			arrays[Mesh.ARRAY_TEX_UV] = b.uv
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.material_override = mat
			mi.name = "%s_%d_%d" % [layer, key.x, key.y]
			if layer in NO_SHADOW:
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if VIS_RANGE.has(layer):
				mi.visibility_range_end = VIS_RANGE[layer]
				mi.visibility_range_end_margin = 10.0
				mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
			parent.add_child(mi)
	layers.clear()
	if not colliders.is_empty():
		var body := StaticBody3D.new()
		body.name = "Colliders"
		parent.add_child(body)
		for c in colliders:
			var cs := CollisionShape3D.new()
			cs.shape = c[0]
			cs.transform = c[1]
			body.add_child(cs)
	colliders.clear()


## Standalone mesh from one layer (used for avatars and small movable props).
func to_mesh(layer: String) -> ArrayMesh:
	var all := Buf.new()
	if layers.has(layer):
		for key in layers[layer]:
			var b: Buf = layers[layer][key]
			all.v.append_array(b.v)
			all.n.append_array(b.n)
			all.c.append_array(b.c)
			all.uv.append_array(b.uv)
	var mesh := ArrayMesh.new()
	if all.v.is_empty():
		return mesh
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = all.v
	arrays[Mesh.ARRAY_NORMAL] = all.n
	arrays[Mesh.ARRAY_COLOR] = all.c
	arrays[Mesh.ARRAY_TEX_UV] = all.uv
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
