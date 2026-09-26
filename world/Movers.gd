extends RefCounted
## Things that move and make a place feel lived in: chimney smoke and kitchen
## steam, a commuter train (timed off the wall clock so both players see it pass
## together) with blinking, ringing crossings, and cats that wander the lanes.

const Geo := preload("res://world/Geo.gd")
const TextureForge := preload("res://world/TextureForge.gd")
const MAX_SMOKE := 16


static func populate(root: Node3D, biome, mats) -> void:
	_smoke(root, biome.smoke_spots)
	if "rail_x" in biome:
		var train := Train.new()
		train.setup(biome, mats)
		root.add_child(train)
		for i in 5:
			var cat := Cat.new()
			cat.setup(biome, mats, i)
			root.add_child(cat)


static func _smoke(root: Node3D, spots: Array) -> void:
	var dot := TextureForge.dot(4)
	var n := mini(spots.size(), MAX_SMOKE)
	for i in n:
		var s: Array = spots[i]
		var steam: bool = s[1] == "steam"
		var p := CPUParticles3D.new()
		p.amount = 10 if steam else 14
		p.lifetime = 2.5 if steam else 6.0
		p.preprocess = p.lifetime
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = 0.15
		p.direction = Vector3(0.15, 1, 0)
		p.spread = 12.0
		p.initial_velocity_min = 0.5 if not steam else 0.8
		p.initial_velocity_max = 0.9 if not steam else 1.4
		p.gravity = Vector3(0.25, 0.08, 0.05)
		var curve := Curve.new()
		curve.add_point(Vector2(0, 0.4))
		curve.add_point(Vector2(1, 1.8))
		p.scale_amount_curve = curve
		var q := QuadMesh.new()
		q.size = Vector2(0.45, 0.45) if not steam else Vector2(0.3, 0.3)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.vertex_color_use_as_albedo = true
		m.albedo_texture = dot
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		q.material = m
		p.mesh = q
		var g := Gradient.new()
		var c := Color(0.92, 0.92, 0.95) if steam else Color(0.75, 0.74, 0.76)
		g.set_color(0, Color(c, 0.0))
		g.add_point(0.15, Color(c, 0.55 if steam else 0.45))
		g.set_color(g.get_point_count() - 1, Color(c, 0.0))
		p.color_ramp = g
		p.position = s[0]
		p.name = "Smoke"
		root.add_child(p)




# ------------------------------------------------------------------ train

class Train extends Node3D:
	const PERIOD := 110.0          # a train every ~2 minutes
	const SPEED := 22.0
	const CARS := 4
	const CAR_LEN := 19.0
	var biome
	var rail_x := 0.0
	var crossings: Array = []      # z positions
	var blinkers: Array = []       # [MeshInstance3D, MeshInstance3D] per crossing
	var bell: AudioStreamPlayer
	var rumble: AudioStreamPlayer3D
	var body: Node3D

	func setup(p_biome, mats) -> void:
		biome = p_biome
		rail_x = biome.rail_x
		for j in biome.zs.size():
			var z: float = biome.zs[j]
			if absf(z) < biome.R + 15.0 and absf(z - biome.canal_z) > 1.0:
				crossings.append(z)
		body = Node3D.new()
		add_child(body)
		var g := Geo.new()
		var silver := Color("d8dce4", 0.0)
		for c in CARS:
			var z0 := -c * (CAR_LEN + 0.6)
			g.block("solid", Vector3(0, 0.55, z0), Vector3(2.9, 3.3, CAR_LEN), silver, 0.0, Color("b8bcc4", 0.0))
			g.box("solid", Transform3D(Basis(), Vector3(0, 1.35, z0)), Vector3(2.94, 0.28, CAR_LEN - 0.4), Color("3aa05a", 0.0))
			g.block("solid", Vector3(0, 0.1, z0), Vector3(2.6, 0.5, CAR_LEN - 2.0), Color("3a3c44", 0.0))
			for k in 6:
				var wz := z0 - CAR_LEN * 0.5 + 1.8 + k * 3.1
				for sx: float in [-1.47, 1.47]:
					g.box("glow", Transform3D(Basis(), Vector3(sx, 2.35, wz)), Vector3(0.04, 0.9, 1.9), Color("f2e8c8", 0.35))
			for sx: float in [-1.48, 1.48]:
				for k in 3:
					g.box("solid", Transform3D(Basis(), Vector3(sx, 1.9, z0 - CAR_LEN * 0.33 + k * CAR_LEN * 0.33)), Vector3(0.03, 2.1, 1.2), Color("9aa0aa", 0.0))
		# headlights on both ends
		for z: float in [CAR_LEN * 0.5 + 0.02, -(CARS - 1) * (CAR_LEN + 0.6) - CAR_LEN * 0.5 - 0.02]:
			for sx: float in [-0.9, 0.9]:
				g.box("glow", Transform3D(Basis(), Vector3(sx, 1.2, z)), Vector3(0.4, 0.25, 0.05), Color("fff6d8", 0.7))
		for layer in ["solid", "glow"]:
			var mi := MeshInstance3D.new()
			mi.mesh = g.to_mesh(layer)
			mi.material_override = mats.get_mat(layer)
			mi.extra_cull_margin = 40.0
			body.add_child(mi)
		# blinking crossing lamps
		var red := StandardMaterial3D.new()
		red.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		red.albedo_color = Color(1.0, 0.2, 0.15)
		for z in crossings:
			var pair := []
			for side: float in [-1.0, 1.0]:
				for lx: float in [-0.3, 0.3]:
					var s := MeshInstance3D.new()
					var sm := SphereMesh.new()
					sm.radius = 0.16
					sm.height = 0.32
					sm.radial_segments = 6
					sm.rings = 3
					s.mesh = sm
					s.material_override = red
					s.position = Vector3(rail_x + side * 3.2 + lx, 2.4, z + side * 3.0 + 0.15)
					s.visible = false
					add_child(s)
					pair.append([s, lx])
			blinkers.append(pair)
		bell = AudioStreamPlayer.new()
		bell.stream = _bell_wav()
		bell.volume_db = -80.0
		add_child(bell)
		rumble = AudioStreamPlayer3D.new()
		rumble.stream = _rumble_wav()
		rumble.unit_size = 25.0
		rumble.volume_db = -6.0
		body.add_child(rumble)

	func _process(_delta: float) -> void:
		var now := Time.get_unix_time_from_system()
		var cycle := floorf(now / PERIOD)
		var t := fmod(now, PERIOD)
		var dir := 1.0 if int(cycle) % 2 == 0 else -1.0
		var travel := SPEED * t - 320.0
		var head := travel * dir
		var running := travel < 320.0 + CARS * CAR_LEN
		body.visible = running
		body.position = Vector3(rail_x, 0.0, head)
		body.rotation.y = 0.0 if dir > 0.0 else PI
		if running and not rumble.playing:
			rumble.play()
		elif not running and rumble.playing:
			rumble.stop()
		var cam := get_viewport().get_camera_3d()
		var bell_vol := -80.0
		var blink := int(now * 2.4) % 2
		var tail := head - dir * CARS * (CAR_LEN + 0.6)
		for i in crossings.size():
			var z: float = crossings[i]
			var near := running and ((z - head) * dir > -70.0) and ((z - tail) * dir < 5.0)
			for b in blinkers[i]:
				b[0].visible = near and ((b[1] < 0.0) == (blink == 0))
			if near and cam:
				var d := cam.global_position.distance_to(Vector3(rail_x, 2.0, z))
				bell_vol = maxf(bell_vol, -8.0 - d * 0.35)
		bell.volume_db = lerpf(bell.volume_db, bell_vol, 0.2)
		if bell_vol > -60.0 and not bell.playing:
			bell.play()
		elif bell_vol <= -60.0 and bell.playing and bell.volume_db < -55.0:
			bell.stop()

	static func _to_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
		var data := PackedByteArray()
		data.resize(samples.size() * 2)
		for i in samples.size():
			data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 30000.0))
		var w := AudioStreamWAV.new()
		w.format = AudioStreamWAV.FORMAT_16_BITS
		w.mix_rate = 22050
		w.data = data
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_end = samples.size()
		return w

	func _bell_wav() -> AudioStreamWAV:
		var n := int(22050 * 0.84)
		var s := PackedFloat32Array()
		s.resize(n)
		for i in n:
			var t := float(i) / 22050.0
			var lt := fmod(t, 0.42)
			var env := exp(-lt * 9.0)
			s[i] = (sin(t * TAU * 1180.0) * 0.6 + sin(t * TAU * 1770.0) * 0.3) * env * 0.35
		return _to_wav(s)

	func _rumble_wav() -> AudioStreamWAV:
		var n := int(22050 * 2.0)
		var s := PackedFloat32Array()
		s.resize(n)
		var lp := 0.0
		var rng := RandomNumberGenerator.new()
		rng.seed = 3
		for i in n:
			var t := float(i) / 22050.0
			lp = lerpf(rng.randf_range(-1, 1), lp, 0.96)
			var clack := exp(-fmod(t, 0.5) * 30.0) * 0.5 + exp(-fmod(t + 0.12, 0.5) * 30.0) * 0.4
			s[i] = lp * 3.0 * (0.6 + clack)
		return _to_wav(s)


# ------------------------------------------------------------------ cats

class Cat extends Node3D:
	var biome
	var rng := RandomNumberGenerator.new()
	var target := Vector3.ZERO
	var wait := 0.0
	var tail: Node3D
	var body: Node3D
	var sitting := false

	func setup(p_biome, mats, i: int) -> void:
		biome = p_biome
		rng.seed = 900 + i * 17 + int(Time.get_unix_time_from_system()) % 1000
		var col: Color = [Color("f2a65a"), Color("2a2a2e"), Color("e8e4dc"), Color("8a8a8e"), Color("c8a07a")][i % 5]
		col.a = 0.0
		var g := Geo.new()
		g.box("solid", Transform3D(Basis(), Vector3(0, 0.16, 0)), Vector3(0.2, 0.18, 0.4), col)
		g.box("solid", Transform3D(Basis(), Vector3(0, 0.3, -0.2)), Vector3(0.19, 0.17, 0.16), col)
		for sx: float in [-0.06, 0.06]:
			g.box("solid", Transform3D(Basis(), Vector3(sx, 0.41, -0.2)), Vector3(0.05, 0.07, 0.04), col)
			g.box("solid", Transform3D(Basis(), Vector3(sx * 0.7, 0.32, -0.285)), Vector3(0.025, 0.025, 0.01), Color("2a3a20", 0.0))
		for lx: float in [-0.07, 0.07]:
			for lz: float in [-0.14, 0.14]:
				g.block("solid", Vector3(lx, 0.0, lz), Vector3(0.05, 0.08, 0.05), col)
		body = Node3D.new()
		add_child(body)
		var mi := MeshInstance3D.new()
		mi.mesh = g.to_mesh("solid")
		mi.material_override = mats.get_mat("solid")
		body.add_child(mi)
		var tg := Geo.new()
		tg.cyl("solid", Vector3.ZERO, Vector3(0, 0.25, 0.08), 0.025, 0.02, 4, col)
		tail = Node3D.new()
		tail.position = Vector3(0, 0.2, 0.2)
		var tmi := MeshInstance3D.new()
		tmi.mesh = tg.to_mesh("solid")
		tmi.material_override = mats.get_mat("solid")
		tail.add_child(tmi)
		body.add_child(tail)
		var start: Vector3 = biome.random_point(biome.R - 10.0)
		for attempt in 40:
			if biome._street_d(start.x, start.z) < 0.3 and absf(start.z - biome.canal_z) > 6.0:
				break
			start = biome.random_point(biome.R - 10.0)
		position = start
		target = start
		wait = rng.randf_range(0.0, 4.0)

	func _process(delta: float) -> void:
		tail.rotation.z = sin(Time.get_ticks_msec() * 0.004 + rng.seed) * 0.5
		if wait > 0.0:
			wait -= delta
			body.position.y = lerpf(body.position.y, -0.06 if sitting else 0.0, 0.1)
			if wait <= 0.0:
				_pick_target()
			return
		var to := target - position
		to.y = 0.0
		if to.length() < 0.15:
			sitting = rng.randf() < 0.6
			wait = rng.randf_range(3.0, 12.0)
			return
		var step := to.normalized() * minf(0.7 * delta, to.length())
		position += step
		position.y = biome.ground_y(position.x, position.z)
		rotation.y = lerp_angle(rotation.y, atan2(-to.x, -to.z), 0.15)
		body.position.y = absf(sin(Time.get_ticks_msec() * 0.018)) * 0.02

	func _pick_target() -> void:
		sitting = false
		for attempt in 10:
			var a := rng.randf() * TAU
			var d := rng.randf_range(3.0, 10.0)
			var p := position + Vector3(cos(a) * d, 0, sin(a) * d)
			if Vector2(p.x, p.z).length() > biome.R - 5.0:
				continue
			if biome._street_d(p.x, p.z) < 0.5 and absf(p.z - biome.canal_z) > 6.0:
				target = Vector3(p.x, 0, p.z)
				return
		target = position
