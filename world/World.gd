extends Control
## Owns the 3D world and the pixel-art render pipeline:
##   SubViewport (low-res 3D) -> post SubViewport (grade + dither) -> nearest upscale.
## Also develops photos (depth pass + depth of field) and hosts partner avatars.

signal build_progress(text: String)
signal built
signal player_spawned(player)

const Materials := preload("res://world/Materials.gd")
const Atmosphere := preload("res://world/Atmosphere.gd")
const Player := preload("res://player/Player.gd")
const Avatar := preload("res://player/Avatar.gd")
const POST := preload("res://shaders/post.gdshader")
const BIOMES := {
	"ruins": preload("res://world/biomes/Ruins.gd"),
	"alps": preload("res://world/biomes/Alps.gd"),
	"tokyo": preload("res://world/biomes/Tokyo.gd"),
}
const MOSS := {"ruins": 1.0, "alps": 0.0, "tokyo": 0.0}

var view3d: SubViewport
var post_vp: SubViewport
var post_rect: TextureRect
var post_mat: ShaderMaterial
var display: TextureRect
var darkroom: SubViewport
var dark_rect: TextureRect
var dark_mat: ShaderMaterial

var root3d: Node3D
var mats
var biome
var atmos
var player: CharacterBody3D
var avatars := {}                 # peer_id -> Avatar
var preview_cam: Camera3D
var building := false
var playing := false
var world_id := ""
var world_seed := 0
var _preview_t := 0.0
var _net_timer := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view3d = SubViewport.new()
	view3d.name = "View3D"
	view3d.msaa_3d = Viewport.MSAA_DISABLED
	view3d.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	view3d.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view3d.audio_listener_enable_3d = true
	add_child(view3d)

	post_vp = SubViewport.new()
	post_vp.name = "Post"
	post_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(post_vp)
	post_rect = TextureRect.new()
	post_rect.texture = view3d.get_texture()
	post_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	post_mat = ShaderMaterial.new()
	post_mat.shader = POST
	post_rect.material = post_mat
	post_vp.add_child(post_rect)

	darkroom = SubViewport.new()
	darkroom.name = "Darkroom"
	darkroom.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(darkroom)
	dark_rect = TextureRect.new()
	dark_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	dark_mat = ShaderMaterial.new()
	dark_mat.shader = POST
	dark_rect.material = dark_mat
	darkroom.add_child(dark_rect)

	display = TextureRect.new()
	display.name = "Display"
	display.texture = post_vp.get_texture()
	display.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	display.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(display)

	get_viewport().size_changed.connect(_resize)
	_resize()
	Net.state_received.connect(_on_state)
	Net.partner_left.connect(_on_partner_left)


func _resize() -> void:
	var win := get_viewport().get_visible_rect().size
	var h := GameState.pixel_height
	var w := int(round(h * win.x / maxf(win.y, 1.0)))
	w = clampi(w, 200, 1400)
	var s := Vector2i(w, h)
	view3d.size = s
	post_vp.size = s
	post_rect.size = Vector2(s)
	darkroom.size = s
	dark_rect.size = Vector2(s)


func internal_size() -> Vector2i:
	return view3d.size


# ------------------------------------------------------------------ building

func build(id: String, p_seed: int) -> void:
	if building:
		return
	building = true
	world_id = id
	world_seed = p_seed
	var was_playing := playing
	var keep_pos := Vector3.ZERO
	_teardown()
	build_progress.emit("Sketching the land…")
	await _frames(2)
	var t0 := Time.get_ticks_msec()
	mats = Materials.new(p_seed)
	mats.set_all("moss", MOSS.get(id, 0.0))
	biome = BIOMES[id].new(p_seed)
	build_progress.emit("Painting %s…" % GameState.world_name(id))
	await _frames(2)
	biome.generate()
	build_progress.emit("Planting grass and flowers…")
	await _frames(1)
	root3d = Node3D.new()
	root3d.name = "World3D"
	view3d.add_child(root3d)
	var geo_root := Node3D.new()
	geo_root.name = "Geometry"
	root3d.add_child(geo_root)
	biome.geo.build(geo_root, mats)
	biome.build_instances(geo_root, mats)
	build_progress.emit("Letting the light in…")
	await _frames(1)
	atmos = Atmosphere.new()
	atmos.name = "Atmosphere"
	root3d.add_child(atmos)
	atmos.setup(id, mats, biome.geo.light_spots)
	for r in biome.ray_spots:
		atmos.add_ray(r[0], r[1], r[2])
	_extra_scene_bits()
	preview_cam = Camera3D.new()
	preview_cam.name = "PreviewCam"
	preview_cam.fov = 62.0
	preview_cam.far = 1500.0
	root3d.add_child(preview_cam)
	preview_cam.current = true
	atmos.set_camera(preview_cam)
	atmos.apply(GameState.time_of_day, GameState.weather)
	print("World '%s' seed %d built in %d ms" % [id, p_seed, Time.get_ticks_msec() - t0])
	building = false
	if was_playing:
		start_playing()
	built.emit()


func _extra_scene_bits() -> void:
	if biome.has_method("build_extras"):
		biome.build_extras(root3d, mats)


func _teardown() -> void:
	for a in avatars.values():
		a.queue_free()
	avatars.clear()
	player = null
	playing = false
	if root3d:
		root3d.queue_free()
		root3d = null
	atmos = null
	biome = null


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


# ------------------------------------------------------------------ play / preview

func start_playing() -> void:
	if root3d == null or player != null:
		return
	player = Player.new()
	player.name = "Player"
	player.world = self
	root3d.add_child(player)
	var sp: Vector3 = biome.spawn
	# guests spawn a couple of metres beside the host
	if Net.has_partner() and not Net.is_host():
		sp += Vector3(2.0, 0, 1.0)
	player.global_position = biome.at(sp.x, sp.z) + Vector3(0, 1.0, 0)
	player.set_yaw(biome.spawn_yaw)
	player.camera.current = true
	atmos.set_camera(player.camera)
	playing = true
	player_spawned.emit(player)
	for id in GameState.partners:
		_ensure_avatar(id)


func stop_playing() -> void:
	playing = false
	if player:
		player.queue_free()
		player = null
	for a in avatars.values():
		a.queue_free()
	avatars.clear()
	if preview_cam:
		preview_cam.current = true
		atmos.set_camera(preview_cam)


func _process(delta: float) -> void:
	if root3d == null:
		return
	if GameState.time_flowing:
		GameState.time_of_day = fmod(GameState.time_of_day + delta / 120.0, 24.0)
	if not playing and preview_cam:
		_preview_t += delta
		var sp: Vector3 = biome.spawn
		var a := _preview_t * 0.03
		var focus: Vector3 = biome.at(sp.x * 0.3, sp.z * 0.3)
		var pos: Vector3 = focus + Vector3(sin(a) * 38.0, 0, cos(a) * 38.0)
		pos.y = maxf(biome.ground_y(pos.x, pos.z), focus.y) + 9.0
		preview_cam.global_position = pos
		preview_cam.look_at(focus + Vector3(0, 3.0, 0))
	if playing and player:
		_net_timer -= delta
		if _net_timer <= 0.0:
			_net_timer = 1.0 / 15.0
			Net.send_state(player.global_position, player.yaw, player.pitch, player.net_flags())
	_update_post()


func _update_post() -> void:
	var look: Dictionary = player.look() if (playing and player and player.raised) else {}
	_apply_look(post_mat, look)


func _apply_look(m: ShaderMaterial, look: Dictionary) -> void:
	m.set_shader_parameter("exposure", look.get("exposure", 0.0))
	m.set_shader_parameter("saturation", look.get("saturation", 1.05) * 1.02)
	m.set_shader_parameter("contrast", look.get("contrast", 1.0) * 1.06)
	m.set_shader_parameter("lift", look.get("lift", Vector3.ZERO))
	m.set_shader_parameter("gain", look.get("gain", Vector3.ONE))
	m.set_shader_parameter("mono", look.get("mono", 0.0))
	m.set_shader_parameter("vignette", look.get("vignette", 0.22))
	m.set_shader_parameter("grain", look.get("grain", 0.0))


# ------------------------------------------------------------------ partners

func _ensure_avatar(id: int) -> Node3D:
	if avatars.has(id):
		return avatars[id]
	if root3d == null:
		return null
	var info: Dictionary = GameState.partners.get(id, {"name": "Partner", "color": Color.WHITE})
	var av := Avatar.new()
	av.name = "Avatar_%d" % id
	av.setup(info.get("color", Color.WHITE), mats)
	root3d.add_child(av)
	var sp: Vector3 = biome.spawn
	av.global_position = biome.at(sp.x, sp.z)
	avatars[id] = av
	return av


func _on_state(id: int, pos: Vector3, yaw: float, pitch: float, flags: int) -> void:
	if not playing:
		return
	var av = _ensure_avatar(id)
	if av:
		av.set_target(pos, yaw, pitch, flags)


func _on_partner_left(id: int) -> void:
	if avatars.has(id):
		avatars[id].queue_free()
		avatars.erase(id)


func refresh_avatar_colors() -> void:
	for id in avatars:
		var info: Dictionary = GameState.partners.get(id, {})
		if info.has("color"):
			avatars[id].set_color(info["color"])


# ------------------------------------------------------------------ photography

## Develop a photo from the current camera. Returns the finished Image.
func develop_photo(settings: Dictionary) -> Image:
	await RenderingServer.frame_post_draw
	var color_img := view3d.get_texture().get_image()
	var depth_img: Image = null
	var use_dof: bool = settings.get("blur", 0.0) > 0.3
	if use_dof:
		post_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		mats.set_all("depth_mode", 1.0)
		atmos.begin_depth()
		for a in avatars.values():
			a.set_depth_mode(true)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		depth_img = view3d.get_texture().get_image()
		mats.set_all("depth_mode", 0.0)
		atmos.end_depth()
		for a in avatars.values():
			a.set_depth_mode(false)
		post_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	dark_rect.texture = ImageTexture.create_from_image(color_img)
	_apply_look(dark_mat, settings)
	dark_mat.set_shader_parameter("seed", randf() * 100.0)
	if use_dof and depth_img:
		dark_mat.set_shader_parameter("depth_tex", ImageTexture.create_from_image(depth_img))
		dark_mat.set_shader_parameter("use_dof", 1.0)
		var fd: float = settings.get("focus_dist", 10.0)
		dark_mat.set_shader_parameter("focus", _center_depth(depth_img, fd))
		dark_mat.set_shader_parameter("blur", settings.get("blur", 0.0))
		dark_mat.set_shader_parameter("dof_scale", settings.get("dof_scale", 6.0))
	else:
		dark_mat.set_shader_parameter("use_dof", 0.0)
	darkroom.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var out := darkroom.get_texture().get_image()
	out.convert(Image.FORMAT_RGB8)
	return out


## Where on the (full-res) screen a world point lands, for HUD name tags.
func screen_point(world_pos: Vector3) -> Variant:
	var cam: Camera3D = view3d.get_camera_3d()
	if cam == null or cam.is_position_behind(world_pos):
		return null
	var p := cam.unproject_position(world_pos)
	var s := Vector2(view3d.size)
	var win := get_viewport().get_visible_rect().size
	var scale := maxf(win.x / s.x, win.y / s.y)
	var off := (win - s * scale) * 0.5
	return p * scale + off


## The 3D view lives in a plain SubViewport, so forward gameplay input by hand.
func _unhandled_input(event: InputEvent) -> void:
	if playing and player and not player.input_locked:
		player.handle_input(event)


## Encoded depth at the frame centre (median of a small cross) = the focus plane.
## Reading it back from the depth pass keeps us independent of colour-space quirks.
func _center_depth(img: Image, fallback_dist: float) -> float:
	var cx := img.get_width() / 2
	var cy := img.get_height() / 2
	var vals: Array[float] = []
	for o in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		vals.append(img.get_pixel(cx + o.x, cy + o.y).r)
	vals.sort()
	var v: float = vals[2]
	if v >= 0.999:
		return 1.0
	return v if v > 0.0 else clampf(sqrt(fallback_dist / 250.0), 0.0, 1.0)
