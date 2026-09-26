extends CharacterBody3D
## First-person walker with a camera: raise it (right click / C), zoom through
## prime lenses (scroll), set aperture (Q/E), exposure (Z/X), film (F), shoot (left click).

signal photo_taken(meta: Dictionary)
signal camera_changed

const LENSES := [16, 24, 35, 50, 85, 135, 200]
const APERTURES := [1.4, 2.0, 2.8, 4.0, 5.6, 8.0, 11.0, 16.0]
const FILMS := [
	{"name": "Natural", "saturation": 1.05, "contrast": 1.0},
	{"name": "Portra", "saturation": 0.92, "contrast": 0.95, "lift": Vector3(0.035, 0.02, 0.0), "gain": Vector3(1.05, 1.0, 0.9), "grain": 0.03},
	{"name": "Cinestill", "saturation": 1.08, "contrast": 1.1, "lift": Vector3(0.0, 0.03, 0.06), "gain": Vector3(1.08, 0.97, 0.9), "grain": 0.04},
	{"name": "Velvia", "saturation": 1.35, "contrast": 1.12},
	{"name": "Faded", "saturation": 0.8, "contrast": 0.85, "lift": Vector3(0.08, 0.07, 0.09), "grain": 0.03},
	{"name": "Mono", "saturation": 0.0, "contrast": 1.2, "mono": 1.0, "grain": 0.05},
]
const WALK := 4.2
const RUN := 7.6
const RAISED_SPEED := 2.3
const JUMP := 4.8
const GRAVITY := 15.0
const EYE := 1.62
const WALK_HFOV := 88.0

var world                       # World.gd
var head: Node3D
var camera: Camera3D
var yaw := 0.0
var pitch := 0.0
var raised := false
var lens_idx := 2
var aperture_idx := 2
var film_idx := 0
var exposure := 0.0
var focus_dist := 10.0
var focus_locked := false
var input_locked := false
var sitting := false
var busy := false               # developing a photo

var _focal := 35.0
var _bob := 0.0
var _raise_t := 0.0


func _ready() -> void:
	var shape := CapsuleShape3D.new()
	shape.radius = 0.35
	shape.height = 1.75
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position.y = 0.875
	add_child(cs)
	collision_layer = 1
	collision_mask = 1
	floor_snap_length = 0.5
	floor_max_angle = deg_to_rad(50.0)
	head = Node3D.new()
	head.position.y = EYE
	add_child(head)
	camera = Camera3D.new()
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.near = 0.05
	camera.far = 1500.0
	camera.fov = WALK_HFOV
	head.add_child(camera)


func set_yaw(y: float) -> void:
	yaw = y
	rotation.y = yaw


func focal() -> int:
	return LENSES[lens_idx]


func aperture() -> float:
	return APERTURES[aperture_idx]


func film() -> Dictionary:
	return FILMS[film_idx]


func net_flags() -> int:
	var f := 0
	if raised:
		f |= 1
	if Vector2(velocity.x, velocity.z).length() > 0.5:
		f |= 2
	if Input.is_action_pressed("sprint"):
		f |= 4
	if sitting:
		f |= 8
	return f


func look() -> Dictionary:
	var d: Dictionary = film().duplicate()
	d["exposure"] = exposure
	return d


# ------------------------------------------------------------------ input

func handle_input(event: InputEvent) -> void:
	if input_locked:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens := 0.0022 * GameState.mouse_sensitivity * (camera.fov / WALK_HFOV)
		yaw -= event.relative.x * sens
		pitch = clampf(pitch - event.relative.y * sens, deg_to_rad(-85), deg_to_rad(85))
		rotation.y = yaw
		head.rotation.x = pitch
	elif event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			get_viewport().set_input_as_handled()
			return
		match event.button_index:
			MOUSE_BUTTON_RIGHT:
				toggle_raise()
			MOUSE_BUTTON_LEFT:
				if raised:
					shoot()
			MOUSE_BUTTON_WHEEL_UP:
				if raised:
					lens_idx = mini(lens_idx + 1, LENSES.size() - 1)
					camera_changed.emit()
			MOUSE_BUTTON_WHEEL_DOWN:
				if raised:
					lens_idx = maxi(lens_idx - 1, 0)
					camera_changed.emit()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.is_action("camera_toggle"):
			toggle_raise()
		elif event.is_action("aperture_open"):
			aperture_idx = maxi(aperture_idx - 1, 0)
			camera_changed.emit()
		elif event.is_action("aperture_close"):
			aperture_idx = mini(aperture_idx + 1, APERTURES.size() - 1)
			camera_changed.emit()
		elif event.is_action("film_next"):
			film_idx = (film_idx + 1) % FILMS.size()
			camera_changed.emit()
		elif event.is_action("exposure_up"):
			exposure = minf(exposure + 1.0 / 3.0, 2.0)
			camera_changed.emit()
		elif event.is_action("exposure_down"):
			exposure = maxf(exposure - 1.0 / 3.0, -2.0)
			camera_changed.emit()


func toggle_raise() -> void:
	raised = not raised
	sitting = false
	camera_changed.emit()


# ------------------------------------------------------------------ movement

func _physics_process(delta: float) -> void:
	var input := Vector2.ZERO
	if not input_locked:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if input.length() > 0.1:
		sitting = false
	var speed := WALK
	if raised:
		speed = RAISED_SPEED * (1.0 if focal() < 85 else 0.7)
	elif Input.is_action_pressed("sprint") and not input_locked:
		speed = RUN
	var dir := (transform.basis * Vector3(input.x, 0, input.y))
	dir.y = 0
	dir = dir.normalized() * minf(input.length(), 1.0)
	var target := dir * speed
	var accel := 12.0 if is_on_floor() else 4.0
	velocity.x = move_toward(velocity.x, target.x, accel * speed * delta)
	velocity.z = move_toward(velocity.z, target.z, accel * speed * delta)
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	elif not input_locked and Input.is_action_just_pressed("jump"):
		velocity.y = JUMP
	move_and_slide()
	# stay inside the world, gently
	var flat := Vector2(global_position.x, global_position.z)
	var R: float = world.biome.R if world and world.biome else 120.0
	if flat.length() > R:
		var back := flat.normalized() * R
		global_position.x = back.x
		global_position.z = back.y
	if global_position.y < -60.0:
		var sp: Vector3 = world.biome.spawn
		global_position = world.biome.at(sp.x, sp.z) + Vector3(0, 2, 0)
		velocity = Vector3.ZERO


func _process(delta: float) -> void:
	# head bob + sit
	var moving := Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and moving > 0.5:
		_bob += delta * moving * 1.9
	var bob_amt := 0.035 if not raised else 0.012
	var eye := EYE - (0.75 if sitting else 0.0)
	head.position.y = lerpf(head.position.y, eye + sin(_bob) * bob_amt, 1.0 - exp(-delta * 14.0))
	head.position.x = cos(_bob * 0.5) * bob_amt * 0.5
	# lens / fov
	_raise_t = move_toward(_raise_t, 1.0 if raised else 0.0, delta * 5.0)
	var target_focal := float(focal()) if raised else 20.0
	_focal = lerpf(_focal, target_focal, 1.0 - exp(-delta * 10.0))
	var hfov := rad_to_deg(2.0 * atan(18.0 / _focal))
	camera.fov = clampf(lerpf(WALK_HFOV, hfov, _raise_t), 5.0, 110.0)
	if raised and not focus_locked:
		_autofocus(delta)


func _autofocus(delta: float) -> void:
	var space := get_world_3d().direct_space_state
	var from := camera.global_position
	var to := from - camera.global_transform.basis.z * 400.0
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 2, [get_rid()])
	var hit := space.intersect_ray(q)
	var d := 400.0
	if not hit.is_empty():
		d = from.distance_to(hit["position"])
	focus_dist = lerpf(focus_dist, d, 1.0 - exp(-delta * 8.0))


# ------------------------------------------------------------------ photography

func dof_settings() -> Dictionary:
	var f := float(focal())
	var n := aperture()
	var blur := clampf(pow(f / 50.0, 1.1) * (2.8 / n) * 2.4, 0.0, 7.0)
	if f <= 24:
		blur *= 0.5
	var scale := 2.5 + 14.0 / (1.0 + focus_dist * 0.25)
	return {"blur": blur, "focus_dist": focus_dist, "dof_scale": scale}


func shoot() -> void:
	if busy or world == null:
		return
	busy = true
	var settings := look()
	settings.merge(dof_settings())
	var img: Image = await world.develop_photo(settings)
	busy = false
	var meta := {
		"id": PhotoStore.new_id(),
		"by": GameState.player_name,
		"color": GameState.player_color.to_html(false),
		"world": GameState.world_id,
		"world_name": GameState.world_name(),
		"clock": GameState.clock_string(),
		"weather": GameState.weather,
		"lens": "%dmm f/%s" % [focal(), str(aperture()).trim_suffix(".0")],
		"film": film()["name"],
		"ts": Time.get_unix_time_from_system(),
	}
	var stored := PhotoStore.add_photo(img, meta)
	Net.send_photo(stored, img.save_png_to_buffer())
	Net.send_event("shutter", {})
	photo_taken.emit(stored)
