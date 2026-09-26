extends Node3D
## Time of day, per-world palettes, sky, fog, sun/moon, god rays, weather particles
## and a small pool of lantern lights that follow you around at night.

const TextureForge := preload("res://world/TextureForge.gd")
const SKY_SHADER := preload("res://shaders/sky.gdshader")

## Keyframes: hour, sky top, horizon, sun colour, sun energy, ambient colour,
## ambient energy, fog colour, fog density, god-ray strength, night amount.
const PALETTES := {
	"ruins": [
		[0.0, "0b1330", "20315a", "9ab0ea", 0.42, "3a4c84", 0.62, "1c2a48", 0.011, 0.0, 1.0],
		[5.4, "34457e", "e8a58a", "ffb58a", 0.55, "4c5e86", 0.62, "8f98a6", 0.014, 0.35, 0.35],
		[8.0, "5a98d8", "cfe8dc", "fff0c8", 1.05, "6a78b0", 0.86, "a8c6cc", 0.009, 0.6, 0.0],
		[12.5, "4a90e0", "c6e6ee", "fffaf0", 1.15, "7288bc", 0.9, "b4d4da", 0.006, 0.35, 0.0],
		[17.3, "5a84c4", "ffd49a", "ffc070", 1.05, "6e6aa8", 0.84, "e2c496", 0.008, 0.65, 0.0],
		[19.2, "3a3f7e", "ff8f70", "ff7850", 0.5, "5a4d82", 0.62, "a97c86", 0.01, 0.25, 0.45],
		[20.8, "0b1330", "20315a", "9ab0ea", 0.42, "3a4c84", 0.62, "1c2a48", 0.011, 0.0, 1.0],
	],
	"alps": [
		[0.0, "0a1230", "243766", "a8bcf2", 0.45, "3c5088", 0.64, "22304f", 0.004, 0.0, 1.0],
		[5.4, "3a4e8e", "f2b09a", "ffbf98", 0.6, "5a6a96", 0.64, "c9a8aa", 0.006, 0.2, 0.3],
		[8.0, "4f96e6", "d6ecf6", "fff4dc", 1.1, "6f8fba", 0.72, "c8e0ee", 0.0035, 0.3, 0.0],
		[12.5, "3f8ae6", "cfe8f8", "fffdf4", 1.2, "7898c2", 0.78, "cfe6f4", 0.003, 0.15, 0.0],
		[17.2, "4c7fcc", "ffd9a8", "ffc47a", 1.1, "6f76a8", 0.72, "efd0a8", 0.004, 0.45, 0.0],
		[19.3, "2f3b80", "ff9a86", "ff8a6a", 0.55, "5c5190", 0.62, "c08a98", 0.005, 0.2, 0.45],
		[20.9, "0a1230", "243766", "a8bcf2", 0.45, "3c5088", 0.64, "22304f", 0.004, 0.0, 1.0],
	],
	"tokyo": [
		[0.0, "0c0f2a", "2a2a5a", "a4aee8", 0.32, "40447a", 0.66, "24264a", 0.012, 0.0, 1.0],
		[5.4, "404880", "f0a890", "ffb89a", 0.55, "5a5c88", 0.64, "a898a8", 0.014, 0.2, 0.35],
		[8.0, "5a94d4", "dceaf0", "fff2d8", 1.0, "6c86aa", 0.72, "c2d6e2", 0.009, 0.3, 0.0],
		[12.5, "4a8ada", "d2e6f4", "fffaf0", 1.1, "7690b8", 0.78, "c8dcea", 0.007, 0.15, 0.0],
		[17.0, "6a7cc0", "ffc89a", "ffb870", 1.0, "7a6fa0", 0.72, "f0c4a0", 0.01, 0.4, 0.0],
		[18.8, "3c3a82", "ff8a7a", "ff7058", 0.45, "665090", 0.66, "c07890", 0.012, 0.15, 0.55],
		[20.3, "0c0f2a", "2a2a5a", "a4aee8", 0.32, "40447a", 0.66, "24264a", 0.012, 0.0, 1.0],
	],
}
const WEATHER_FX := {
	#            clouds, sun mult, fog mult, ray mult, sat
	"clear":     [0.35, 1.0, 1.0, 1.0, 1.0],
	"mist":      [0.5, 0.85, 3.2, 1.7, 0.9],
	"rain":      [0.97, 0.35, 1.8, 0.1, 0.65],
	"snow":      [0.85, 0.55, 1.9, 0.3, 0.7],
	"petals":    [0.35, 1.0, 1.0, 1.0, 1.0],
	"fireflies": [0.25, 1.0, 1.0, 1.0, 1.0],
}
const POOL_SIZE := 12

var biome := "ruins"
var mats
var sun: DirectionalLight3D
var env: Environment
var depth_env: Environment
var world_env: WorldEnvironment
var sky_mat: ShaderMaterial
var camera: Camera3D
var rays_root: Node3D
var light_spots: Array = []
var night := 0.0
var sun_dir := Vector3.UP

var _pool: Array = []
var _pool_timer := 0.0
var _particles := {}
var _cloud_time := 0.0
var _snow_cover := 0.0
var _wet := 0.0
var _last_weather := ""


func setup(p_biome: String, p_mats, spots: Array) -> void:
	biome = p_biome
	mats = p_mats
	light_spots = spots
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 90.0
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.light_angular_distance = 0.0
	add_child(sun)

	sky_mat = ShaderMaterial.new()
	sky_mat.shader = SKY_SHADER
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	sky.process_mode = Sky.PROCESS_MODE_REALTIME

	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_sky_affect = 0.0
	world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	depth_env = Environment.new()
	depth_env.background_mode = Environment.BG_COLOR
	depth_env.background_color = Color(1, 1, 1)
	depth_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	depth_env.ambient_light_color = Color(0, 0, 0)
	depth_env.tonemap_mode = Environment.TONE_MAPPER_LINEAR

	rays_root = Node3D.new()
	rays_root.name = "GodRays"
	add_child(rays_root)

	for i in POOL_SIZE:
		var l := OmniLight3D.new()
		l.omni_range = 7.0
		l.light_energy = 0.0
		l.shadow_enabled = false
		l.visible = false
		add_child(l)
		_pool.append(l)
	_make_particles()


func set_camera(cam: Camera3D) -> void:
	camera = cam


## Add a light shaft whose top sits at `top` (it extends along the sun direction).
func add_ray(top: Vector3, width: float, length: float) -> void:
	var mi := MeshInstance3D.new()
	var st := PackedVector3Array([Vector3(-0.5, 0, 0), Vector3(0.5, 0, 0), Vector3(0.5, -1, 0), Vector3(-0.5, -1, 0)])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([st[0], st[1], st[2], st[0], st[2], st[3]])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mi.mesh = mesh
	mi.material_override = mats.godray
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = length
	mi.position = top
	mi.scale = Vector3(width, length, 1)
	rays_root.add_child(mi)


# ------------------------------------------------------------------ per frame

func _process(delta: float) -> void:
	_cloud_time += delta
	apply(GameState.time_of_day, GameState.weather, delta)
	if camera:
		var cp := camera.global_position
		for key in _particles:
			var p: CPUParticles3D = _particles[key]
			p.global_position = cp + p.get_meta("offset", Vector3.ZERO)
		_pool_timer -= delta
		if _pool_timer <= 0.0:
			_pool_timer = 0.35
			_update_pool(cp)


func _sample(t: float) -> Array:
	var keys: Array = PALETTES.get(biome, PALETTES["ruins"])
	t = fmod(t + 24.0, 24.0)
	var a: Array = keys[keys.size() - 1]
	var b: Array = keys[0]
	var span := 0.0
	var f := 0.0
	var found := false
	for i in keys.size() - 1:
		if t >= keys[i][0] and t < keys[i + 1][0]:
			a = keys[i]
			b = keys[i + 1]
			found = true
			break
	if found:
		span = b[0] - a[0]
		f = (t - a[0]) / span
	else:
		# wrap from the last key through midnight to the first
		var t0: float = a[0]
		var t1: float = 24.0 + b[0]
		var tt := t if t >= t0 else t + 24.0
		f = (tt - t0) / (t1 - t0)
	f = smoothstep(0.0, 1.0, f)
	var out: Array = [t]
	for i in range(1, a.size()):
		if a[i] is String:
			out.append(Color(a[i]).lerp(Color(b[i]), f))
		else:
			out.append(lerpf(a[i], b[i], f))
	return out


func apply(t: float, weather: String, delta := 0.0) -> void:
	var p := _sample(t)
	var fx: Array = WEATHER_FX.get(weather, WEATHER_FX["clear"])
	night = p[10]
	var sat: float = fx[4]

	# Sun path: rises ~5.5h in the east, sets ~19.5h in the west.
	var day_f := (t - 5.5) / 14.0
	var is_day := day_f > 0.0 and day_f < 1.0
	var elev: float
	var az: float
	if is_day:
		elev = sin(day_f * PI) * deg_to_rad(58.0)
		az = lerpf(deg_to_rad(-105.0), deg_to_rad(105.0), day_f)
	else:
		var nf := fmod(t - 19.5 + 24.0, 24.0) / 10.0
		elev = sin(clampf(nf, 0.0, 1.0) * PI) * deg_to_rad(42.0)
		az = lerpf(deg_to_rad(-100.0), deg_to_rad(100.0), nf)
	var true_dir := Vector3(sin(az) * cos(elev), sin(elev), -cos(az) * cos(elev) * 0.6 - 0.4).normalized()
	var light_elev := maxf(elev, deg_to_rad(9.0))
	sun_dir = Vector3(sin(az) * cos(light_elev), sin(light_elev), -cos(az) * cos(light_elev) * 0.6 - 0.4).normalized()
	var up := Vector3.UP if absf(sun_dir.y) < 0.98 else Vector3.FORWARD
	sun.basis = Basis.looking_at(-sun_dir, up)

	var sun_col: Color = _desat(p[3], sat)
	sun.light_color = sun_col
	sun.light_energy = p[4] * fx[1]
	var amb: Color = _desat(p[5], sat)
	env.ambient_light_color = amb
	env.ambient_light_energy = p[6] * 1.55
	var fog_col: Color = _desat(p[7], sat)
	env.fog_light_color = fog_col
	env.fog_density = p[8] * fx[2]

	var top: Color = _desat(p[1], sat)
	var hor: Color = _desat(p[2], sat)
	if weather == "rain" or weather == "snow":
		top = top.lerp(Color(0.55, 0.6, 0.68) * (1.0 - night * 0.7), 0.6)
		hor = hor.lerp(Color(0.72, 0.75, 0.8) * (1.0 - night * 0.7), 0.6)
	sky_mat.set_shader_parameter("top", top)
	sky_mat.set_shader_parameter("horizon", hor)
	sky_mat.set_shader_parameter("ground", fog_col.darkened(0.2))
	sky_mat.set_shader_parameter("sun_color", sun_col.lerp(Color.WHITE, 0.2))
	sky_mat.set_shader_parameter("sun_dir", true_dir)
	sky_mat.set_shader_parameter("sun_size", 0.05 if not is_day else 0.035)
	sky_mat.set_shader_parameter("cloud_cover", fx[0])
	sky_mat.set_shader_parameter("cloud_lit", Color(1, 1, 1).lerp(sun_col, 0.3).lerp(hor.darkened(0.2), night * 0.85))
	sky_mat.set_shader_parameter("cloud_shade", Color(1, 1, 1).lerp(amb.lerp(top, 0.3), 0.45).lerp(top.darkened(0.2), night * 0.8))
	sky_mat.set_shader_parameter("cloud_time", _cloud_time)
	sky_mat.set_shader_parameter("stars", clampf(night * 1.2 - 0.2, 0.0, 1.0) * (1.0 - fx[0] * 0.8))

	mats.godray.set_shader_parameter("ray_dir", -sun_dir)
	mats.godray.set_shader_parameter("color", sun_col)
	mats.godray.set_shader_parameter("strength", p[9] * fx[3] * 0.32)
	rays_root.visible = p[9] * fx[3] > 0.01

	# Weather accumulation
	var target_snow := 1.0 if weather == "snow" else 0.0
	var target_wet := 1.0 if weather == "rain" else 0.0
	_snow_cover = move_toward(_snow_cover, target_snow, delta * (0.05 if target_snow > _snow_cover else 0.2))
	_wet = move_toward(_wet, target_wet, delta * 0.25)
	if delta == 0.0:
		_snow_cover = target_snow
		_wet = target_wet
	mats.set_all("night", clampf(night * 1.3 - 0.1, 0.0, 1.0))
	mats.set_all("snow", _snow_cover)
	mats.set_all("wet", _wet)
	var water_sky := hor.lerp(top, 0.3)
	mats.get_mat("water").set_shader_parameter("sky", water_sky)
	mats.get_mat("facade").set_shader_parameter("sky_col", water_sky)
	var wl := lerpf(1.0, 0.35, night)
	mats.get_mat("water").set_shader_parameter("light", wl)
	mats.get_mat("falls").set_shader_parameter("light", wl)

	if weather != _last_weather:
		_last_weather = weather
		for key in _particles:
			_particles[key].emitting = _particle_on(key, weather)
	var ff: CPUParticles3D = _particles.get("fireflies")
	if ff:
		ff.emitting = (weather == "fireflies") or (night > 0.5 and biome != "tokyo" and weather == "clear")
	var dust: CPUParticles3D = _particles.get("dust")
	if dust:
		dust.emitting = night < 0.5 and weather in ["clear", "mist", "petals"]


func _desat(c: Color, s: float) -> Color:
	if s >= 0.999:
		return c
	var l := c.get_luminance()
	return Color(l, l, l).lerp(c, s)


func _update_pool(cp: Vector3) -> void:
	var strength := clampf(night * 1.4 - 0.2, 0.0, 1.0)
	if strength <= 0.0 or light_spots.is_empty():
		for l in _pool:
			l.visible = false
		return
	var sorted := light_spots.duplicate()
	sorted.sort_custom(func(a, b): return a[0].distance_squared_to(cp) < b[0].distance_squared_to(cp))
	for i in _pool.size():
		var l: OmniLight3D = _pool[i]
		if i < sorted.size() and sorted[i][0].distance_to(cp) < 70.0:
			l.visible = true
			l.global_position = sorted[i][0]
			l.light_color = sorted[i][1]
			l.omni_range = sorted[i][2]
			l.light_energy = 1.05 * strength
		else:
			l.visible = false


# ------------------------------------------------------------------ particles

func _particle_on(key: String, weather: String) -> bool:
	match key:
		"rain": return weather == "rain"
		"snow": return weather == "snow"
		"petals": return weather == "petals" or (biome == "tokyo" and weather == "clear")
		"butterflies": return weather in ["clear", "petals"] and biome != "tokyo"
	return false


func _pmat(tex: Texture2D, billboard := BaseMaterial3D.BILLBOARD_PARTICLES) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = tex
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = billboard
	m.billboard_keep_scale = true
	return m


func _mk_particles(key: String, amount: int, lifetime: float, box: Vector3, offset: Vector3,
		size: Vector2, tex: Texture2D, col: Color, billboard := BaseMaterial3D.BILLBOARD_PARTICLES) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "P_" + key
	p.amount = amount
	p.lifetime = lifetime
	p.preprocess = lifetime
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = box
	var q := QuadMesh.new()
	q.size = size
	q.material = _pmat(tex, billboard)
	p.mesh = q
	p.color = col
	p.set_meta("offset", offset)
	p.emitting = false
	p.visibility_aabb = AABB(-box * 2.0 - Vector3(0, 20, 0), box * 4.0 + Vector3(0, 40, 0))
	add_child(p)
	_particles[key] = p
	return p


func _make_particles() -> void:
	var dot := TextureForge.dot(4)
	var rain := _mk_particles("rain", 700, 0.9, Vector3(16, 1, 16), Vector3(0, 11, 0), Vector2(0.03, 0.55), dot,
		Color(0.75, 0.82, 0.95, 1), BaseMaterial3D.BILLBOARD_FIXED_Y)
	rain.direction = Vector3(0.05, -1, 0)
	rain.spread = 2.0
	rain.initial_velocity_min = 18.0
	rain.initial_velocity_max = 22.0
	rain.gravity = Vector3(0, -8, 0)

	var snow := _mk_particles("snow", 700, 7.0, Vector3(20, 1, 20), Vector3(0, 10, 0), Vector2(0.09, 0.09), dot,
		Color(1, 1, 1, 1))
	snow.direction = Vector3(0.2, -1, 0.1)
	snow.spread = 25.0
	snow.initial_velocity_min = 1.0
	snow.initial_velocity_max = 2.0
	snow.gravity = Vector3(0.1, -0.35, 0)

	var petals := _mk_particles("petals", 160, 9.0, Vector3(24, 5, 24), Vector3(0, 5, 0), Vector2(0.14, 0.1),
		TextureForge.petal(), Color(1, 1, 1, 1))
	petals.direction = Vector3(1, -0.3, 0.4)
	petals.spread = 40.0
	petals.initial_velocity_min = 0.6
	petals.initial_velocity_max = 1.4
	petals.gravity = Vector3(0.15, -0.3, 0)
	petals.angular_velocity_min = -120
	petals.angular_velocity_max = 120

	var ff := _mk_particles("fireflies", 90, 6.0, Vector3(22, 1.5, 22), Vector3(0, 1.4, 0), Vector2(0.13, 0.13), dot,
		Color(0.9, 1.0, 0.45, 1))
	ff.direction = Vector3(0, 1, 0)
	ff.spread = 180.0
	ff.initial_velocity_min = 0.1
	ff.initial_velocity_max = 0.4
	ff.gravity = Vector3.ZERO
	var fr := Gradient.new()
	fr.set_color(0, Color(1, 1, 1, 0))
	fr.add_point(0.2, Color(1, 1, 1, 1))
	fr.add_point(0.8, Color(1, 1, 1, 1))
	fr.set_color(fr.get_point_count() - 1, Color(1, 1, 1, 0))
	ff.color_ramp = fr

	var dust := _mk_particles("dust", 70, 9.0, Vector3(12, 4, 12), Vector3(0, 2, 0), Vector2(0.035, 0.035), dot,
		Color(1.0, 0.96, 0.8, 1))
	dust.direction = Vector3(0, 1, 0)
	dust.spread = 180.0
	dust.initial_velocity_min = 0.02
	dust.initial_velocity_max = 0.1
	dust.gravity = Vector3(0, 0.01, 0)
	dust.color_ramp = fr

	var bf := _mk_particles("butterflies", 14, 12.0, Vector3(25, 1.2, 25), Vector3(0, 1.3, 0), Vector2(0.14, 0.1), dot,
		Color(1, 1, 1, 1))
	bf.direction = Vector3(1, 0.2, 0)
	bf.spread = 180.0
	bf.initial_velocity_min = 0.6
	bf.initial_velocity_max = 1.2
	bf.gravity = Vector3.ZERO
	var bg := Gradient.new()
	bg.set_color(0, Color("f7d35c"))
	bg.set_color(1, Color("9fd0ff"))
	bg.add_point(0.5, Color("ffffff"))
	bg.add_point(0.75, Color("f79ac0"))
	bf.color_initial_ramp = bg


## Depth pass for photo development: flat env, no particles or rays.
func begin_depth() -> void:
	world_env.environment = depth_env
	for p in _particles.values():
		p.visible = false
	rays_root.visible = false
	sky_mat.set_shader_parameter("depth_mode", 1.0)


func end_depth() -> void:
	world_env.environment = env
	for p in _particles.values():
		p.visible = true
	sky_mat.set_shader_parameter("depth_mode", 0.0)
