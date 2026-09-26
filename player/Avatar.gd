extends Node3D
## Your partner, as seen in the world: a little bundled-up photographer with a
## beanie, scarf and camera. Smoothly follows network updates and does emotes.

const Geo := preload("res://world/Geo.gd")
const TextureForge := preload("res://world/TextureForge.gd")

var mats
var color := Color.WHITE
var body: MeshInstance3D
var arm_l: Node3D
var arm_r: Node3D
var leg_l: Node3D
var leg_r: Node3D
var cam_node: Node3D
var torso: Node3D
var flash: OmniLight3D
var chat_text := ""
var chat_timer := 0.0

var _target_pos := Vector3.ZERO
var _target_yaw := 0.0
var _pitch := 0.0
var _flags := 0
var _has_target := false
var _walk := 0.0
var _emote := ""
var _emote_t := 0.0
var _hearts: Array = []


func setup(c: Color, p_mats) -> void:
	mats = p_mats
	color = c
	torso = Node3D.new()
	add_child(torso)
	_rebuild()
	var sb := StaticBody3D.new()
	sb.collision_layer = 2
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	sb.add_child(cs)
	add_child(sb)
	flash = OmniLight3D.new()
	flash.light_color = Color(1, 0.97, 0.9)
	flash.omni_range = 6.0
	flash.light_energy = 0.0
	flash.position = Vector3(0, 1.4, -0.4)
	add_child(flash)


func set_color(c: Color) -> void:
	color = c
	_rebuild()


func _mesh_node(parent: Node3D, build: Callable, pos := Vector3.ZERO) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = pos
	parent.add_child(pivot)
	var g := Geo.new()
	build.call(g)
	var mi := MeshInstance3D.new()
	mi.mesh = g.to_mesh("solid")
	mi.material_override = mats.get_mat("solid")
	pivot.add_child(mi)
	return pivot


func _rebuild() -> void:
	for c in torso.get_children():
		c.queue_free()
	var coat := color
	coat.a = 0.0
	var accent := color.lightened(0.35)
	accent.a = 0.0
	var skin := Color("f2c9a0", 0.0)
	var pants := Color("3e4058", 0.0)
	var dark := Color("2a2a33", 0.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var body_build := func(g):
		g.cyl("solid", Vector3(0, 0.55, 0), Vector3(0, 1.32, 0), 0.3, 0.23, 8, coat)
		g.cyl("solid", Vector3(0, 1.26, 0), Vector3(0, 1.38, 0), 0.25, 0.25, 8, accent)       # scarf
		g.block("solid", Vector3(0.12, 1.1, -0.22), Vector3(0.14, 0.3, 0.06), accent)          # scarf tail
		g.rock("solid", Vector3(0, 1.6, 0), Vector3(0.24, 0.25, 0.24), rng, skin, 0.0, 0.02)  # head
		g.cyl("solid", Vector3(0, 1.66, 0), Vector3(0, 1.86, 0), 0.265, 0.14, 8, accent)       # beanie
		g.cyl("solid", Vector3(0, 1.64, 0), Vector3(0, 1.7, 0), 0.27, 0.27, 8, coat)           # cuff
		g.rock("solid", Vector3(0, 1.9, 0), Vector3(0.07, 0.07, 0.07), rng, Color(1, 1, 1, 0), 0.0, 0.05)
		g.block("solid", Vector3(-0.08, 1.58, -0.225), Vector3(0.045, 0.06, 0.02), dark)       # eyes
		g.block("solid", Vector3(0.08, 1.58, -0.225), Vector3(0.045, 0.06, 0.02), dark)
		g.block("solid", Vector3(-0.14, 1.53, -0.2), Vector3(0.05, 0.03, 0.02), Color("f29a9a", 0.0))  # blush
		g.block("solid", Vector3(0.14, 1.53, -0.2), Vector3(0.05, 0.03, 0.02), Color("f29a9a", 0.0))
	_mesh_node(torso, body_build)
	leg_l = _mesh_node(torso, func(g): g.block("solid", Vector3(0, -0.55, 0), Vector3(0.15, 0.55, 0.17), pants), Vector3(-0.12, 0.58, 0))
	leg_r = _mesh_node(torso, func(g): g.block("solid", Vector3(0, -0.55, 0), Vector3(0.15, 0.55, 0.17), pants), Vector3(0.12, 0.58, 0))
	arm_l = _mesh_node(torso, func(g): g.block("solid", Vector3(0, -0.5, 0), Vector3(0.12, 0.5, 0.12), coat), Vector3(-0.33, 1.28, 0))
	arm_r = _mesh_node(torso, func(g): g.block("solid", Vector3(0, -0.5, 0), Vector3(0.12, 0.5, 0.12), coat), Vector3(0.33, 1.28, 0))
	var cam_build := func(g):
		g.block("solid", Vector3(0, -0.07, 0), Vector3(0.24, 0.15, 0.1), dark)
		g.cyl("solid", Vector3(0, 0, -0.05), Vector3(0, 0, -0.14), 0.05, 0.045, 7, Color("45454f", 0.0))
		g.block("solid", Vector3(0.07, 0.06, 0), Vector3(0.05, 0.03, 0.05), Color("c9c9d0", 0.0))
	cam_node = _mesh_node(torso, cam_build, Vector3(0, 1.0, -0.3))


func set_target(pos: Vector3, yaw: float, pitch: float, flags: int) -> void:
	_target_pos = pos
	_target_yaw = yaw
	_pitch = pitch
	_flags = flags
	if not _has_target:
		_has_target = true
		global_position = pos
		rotation.y = yaw


func head_pos() -> Vector3:
	return global_position + Vector3(0, 2.15, 0)


func is_raised() -> bool:
	return _flags & 1 != 0


func play_emote(kind: String) -> void:
	_emote = kind
	_emote_t = 0.0
	if kind == "heart":
		for i in 5:
			var s := Sprite3D.new()
			s.texture = TextureForge.heart()
			s.pixel_size = 0.03
			s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			s.shaded = false
			s.position = Vector3(randf_range(-0.3, 0.3), 2.0 + i * 0.15, randf_range(-0.3, 0.3))
			add_child(s)
			_hearts.append([s, -i * 0.2])


func do_flash() -> void:
	flash.light_energy = 3.0


func say(text: String) -> void:
	chat_text = text
	chat_timer = 6.0


func set_depth_mode(on: bool) -> void:
	for h in _hearts:
		h[0].visible = not on


func _process(delta: float) -> void:
	if _has_target:
		global_position = global_position.lerp(_target_pos, 1.0 - exp(-delta * 12.0))
		rotation.y = lerp_angle(rotation.y, _target_yaw, 1.0 - exp(-delta * 12.0))
	var moving := _flags & 2 != 0
	var sitting := _flags & 8 != 0
	var raised := _flags & 1 != 0
	_walk += delta * (9.0 if _flags & 4 else 6.0) * (1.0 if moving else 0.0)
	var swing := sin(_walk) * 0.6 if moving else 0.0
	leg_l.rotation.x = lerpf(leg_l.rotation.x, -1.4 if sitting else swing, 0.3)
	leg_r.rotation.x = lerpf(leg_r.rotation.x, -1.4 if sitting else -swing, 0.3)
	torso.position.y = lerpf(torso.position.y, -0.5 if sitting else absf(sin(_walk)) * 0.05, 0.3)
	# camera up to the eye when shooting, otherwise hanging at the chest
	var cam_target := Vector3(0, 1.58, -0.33) if raised else Vector3(0, 1.0, -0.3)
	cam_node.position = cam_node.position.lerp(cam_target, 1.0 - exp(-delta * 10.0))
	cam_node.rotation.x = lerpf(cam_node.rotation.x, _pitch if raised else 0.0, 0.2)
	var arm_target := -1.35 if raised else -swing * 0.6
	arm_l.rotation.x = lerpf(arm_l.rotation.x, arm_target, 0.25)
	var r_target := -1.35 if raised else swing * 0.6
	var r_roll := 0.0
	_emote_t += delta
	match _emote:
		"wave":
			r_target = 0.0
			r_roll = 2.6 + sin(_emote_t * 12.0) * 0.4
			if _emote_t > 2.0:
				_emote = ""
		"hop":
			torso.position.y = absf(sin(_emote_t * 9.0)) * 0.35
			if _emote_t > 1.4:
				_emote = ""
		"heart":
			if _emote_t > 2.5:
				_emote = ""
	arm_r.rotation.x = lerpf(arm_r.rotation.x, r_target, 0.25)
	arm_r.rotation.z = lerpf(arm_r.rotation.z, r_roll, 0.25)
	for h in _hearts.duplicate():
		h[1] += delta
		var s: Sprite3D = h[0]
		if h[1] > 0.0:
			s.position.y += delta * 0.8
			s.modulate.a = clampf(2.0 - h[1], 0.0, 1.0)
		if h[1] > 2.0:
			s.queue_free()
			_hearts.erase(h)
	flash.light_energy = move_toward(flash.light_energy, 0.0, delta * 20.0)
	if chat_timer > 0.0:
		chat_timer -= delta
