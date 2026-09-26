extends Control
## Glue: title menu <-> world, HUD, album, pause menu, networking events, sounds.

const World := preload("res://world/World.gd")
const MainMenu := preload("res://ui/MainMenu.gd")
const HUD := preload("res://ui/HUD.gd")
const Album := preload("res://ui/Album.gd")
const PauseMenu := preload("res://ui/PauseMenu.gd")
const Cozy := preload("res://ui/Cozy.gd")
const Sfx := preload("res://audio/Sfx.gd")

var world
var menu
var hud
var album
var pause
var loading: PanelContainer
var loading_label: Label
var sfx
var in_game := false
var _sync_timer := 0.0
var _shot_mode := false


func _ready() -> void:
	theme = Cozy.theme()
	world = World.new()
	add_child(world)
	hud = HUD.new()
	hud.world = world
	hud.visible = false
	add_child(hud)
	menu = MainMenu.new()
	add_child(menu)
	album = Album.new()
	album.visible = false
	add_child(album)
	pause = PauseMenu.new()
	pause.visible = false
	add_child(pause)
	_make_loading()
	sfx = Sfx.new()
	add_child(sfx)

	world.build_progress.connect(_on_build_progress)
	world.built.connect(func(): loading.visible = false)
	world.player_spawned.connect(_on_player_spawned)
	menu.world_selected.connect(_on_menu_world)
	menu.solo_pressed.connect(_on_solo)
	menu.host_pressed.connect(_on_host)
	menu.join_pressed.connect(_on_join)
	hud.chat_submitted.connect(_on_chat_submitted)
	hud.chat_closed.connect(_lock_player.bind(false))
	album.closed.connect(_on_overlay_closed)
	pause.resume.connect(_resume)
	pause.leave.connect(_leave)
	pause.settings_changed.connect(_broadcast_settings)
	pause.world_change.connect(_on_world_change)
	pause.invite.connect(_on_invite)
	pause.pixel_changed.connect(func(): world._resize())

	Net.status.connect(_on_net_status)
	Net.failed.connect(_on_net_failed)
	Net.hosting_started.connect(_on_hosting_started)
	Net.welcome_received.connect(_on_welcome)
	Net.partner_joined.connect(func(_id): hud.toast("Someone is joining your walk…"))
	Net.partner_left.connect(_on_partner_left)
	Net.event_received.connect(_on_event)
	Net.photo_progress.connect(_on_photo_progress)
	GameState.partner_info_changed.connect(func(): world.refresh_avatar_colors())

	var args := OS.get_cmdline_user_args()
	if "shot" in args:
		_shot_mode = true
		_run_shot(args)
		return
	GameState.time_of_day = GameState.WORLDS[GameState.world_id]["default_time"]
	await world.build(GameState.world_id, GameState.world_seed)
	# Invite links: ...?join=CODE drops you straight into your partner's walk.
	var hcode := Net.host_code_from_url()
	if hcode != "":
		Net.host(hcode)
		_enter_world()
		return
	var code := Net.invite_code_from_url()
	if code != "":
		menu.code_edit.text = code
		_on_join(code)




func _make_loading() -> void:
	loading = PanelContainer.new()
	loading.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	loading.position = Vector2(get_viewport_rect().size.x * 0.5 - 170, get_viewport_rect().size.y - 110)
	loading.custom_minimum_size = Vector2(340, 0)
	loading_label = Cozy.label("", 17)
	loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loading.add_child(loading_label)
	loading.visible = false
	add_child(loading)


# ------------------------------------------------------------------ menu

func _on_menu_world(id: String) -> void:
	GameState.world_seed = randi() % 99999 + 1
	await world.build(id, GameState.world_seed)


func _on_solo() -> void:
	Net.leave()
	await _ensure_world()
	_enter_world()


func _on_host() -> void:
	Net.host()
	await _ensure_world()
	_enter_world()


func _on_join(code: String) -> void:
	menu.set_status("Looking for room %s…" % code.strip_edges().to_upper(), true)
	Net.join(code)


func _ensure_world() -> void:
	if world.building:
		await world.built
	if world.world_id != GameState.world_id or world.world_seed != GameState.world_seed:
		await world.build(GameState.world_id, GameState.world_seed)


func _enter_world() -> void:
	GameState.save_settings()
	menu.visible = false
	menu.set_status("", false)
	hud.visible = true
	in_game = true
	world.start_playing()
	_capture()


func _leave() -> void:
	Net.leave()
	in_game = false
	pause.visible = false
	album.visible = false
	hud.visible = false
	world.stop_playing()
	menu.visible = true
	menu.set_status("", false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_player_spawned(p) -> void:
	p.photo_taken.connect(_on_photo_taken)
	for id in GameState.partners:
		world._ensure_avatar(id)


# ------------------------------------------------------------------ networking

func _on_hosting_started(code: String) -> void:
	hud.toast("Room open!  Your code is  %s" % code, Color("ffe3d6"))
	if pause.visible:
		pause.sync()


func _on_welcome() -> void:
	menu.set_status("Found them! Walking over…", true)
	var t := GameState.time_of_day
	await world.build(GameState.world_id, GameState.world_seed)
	GameState.time_of_day = t
	_enter_world()
	var host_name: String = GameState.partners.get(1, {}).get("name", "your partner")
	hud.toast("You joined %s's walk" % host_name, Color("dff3dc"))


func _on_net_failed(reason: String) -> void:
	if in_game:
		hud.toast(reason, Color("ffd6d0"))
		if not Net.is_host():
			_leave()
			menu.set_status(reason, false)
	else:
		menu.set_status(reason, false)


func _on_partner_left(id: int) -> void:
	hud.toast("Your partner left the walk")


func _broadcast_settings() -> void:
	Net.send_event("settings", GameState.settings_dict())


func _on_world_change(id: String, seed: int) -> void:
	Net.send_event("world", {"world": id, "seed": seed})
	await _travel(id, seed)


func _travel(id: String, seed: int) -> void:
	pause.visible = false
	GameState.world_id = id
	GameState.world_seed = seed
	await world.build(id, seed)
	hud.toast("Welcome to %s" % GameState.world_name(id))
	_capture()


func _on_invite() -> void:
	if Net.is_host() and Net.room_code != "":
		return
	Net.host()


func _on_event(id: int, kind: String, data: Dictionary) -> void:
	var info: Dictionary = GameState.partners.get(id, {})
	var who: String = info.get("name", "Partner")
	var col: Color = info.get("color", Color.WHITE)
	match kind:
		"hello":
			hud.toast("%s is here!" % data.get("name", who), Color("dff3dc"))
			sfx.play("chime")
			world.refresh_avatar_colors()
		"shutter":
			if world.avatars.has(id):
				world.avatars[id].do_flash()
			sfx.play("shutter_far")
		"emote":
			if world.avatars.has(id):
				world.avatars[id].play_emote(data.get("kind", ""))
			if data.get("kind", "") == "heart":
				hud.toast("%s sent you a heart" % who, Color("ffe0ec"))
		"chat":
			var text: String = str(data.get("text", ""))
			hud.add_chat(who, text, col)
			if world.avatars.has(id):
				world.avatars[id].say(text)
			sfx.play("pop")
		"ping":
			var p = data.get("pos", Vector3.ZERO)
			hud.add_ping(p, who, col)
			sfx.play("chime")
		"settings":
			GameState.apply_settings_dict(data)
			GameState.world_settings_changed.emit()
			if pause.visible:
				pause.sync()
		"world":
			hud.toast("%s is taking you to %s…" % [who, GameState.world_name(data.get("world", ""))])
			await _travel(data.get("world", GameState.world_id), int(data.get("seed", 1)))
		"hearts":
			PhotoStore.set_hearts(str(data.get("id", "")), data.get("hearts", []))
			if not data.get("hearts", []).is_empty():
				hud.toast("%s hearted a photo" % who, Color("ffe0ec"))


func _on_photo_progress(from_name: String, done: int, total: int) -> void:
	if done == total:
		hud.toast("%s shared a photo  (Tab)" % from_name, Color("fff3d6"))


# ------------------------------------------------------------------ gameplay input

func _on_photo_taken(_meta: Dictionary) -> void:
	hud.flash()
	sfx.play("shutter")


func _on_chat_submitted(text: String) -> void:
	hud.add_chat(GameState.player_name, text, GameState.player_color)
	Net.send_event("chat", {"text": text})
	_lock_player(false)
	_capture()


func _unhandled_input(event: InputEvent) -> void:
	if not in_game or _shot_mode:
		return
	if album.visible or pause.visible or hud.chat_open():
		return
	if event.is_action_pressed("pause"):
		_open_pause()
	elif event.is_action_pressed("album"):
		album.visible = true
		_lock_player(true)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event.is_action_pressed("chat"):
		_lock_player(true)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		hud.open_chat()
	elif event.is_action_pressed("ping") and world.player:
		var pos: Vector3 = world.player.global_position
		hud.add_ping(pos, "You", GameState.player_color)
		Net.send_event("ping", {"pos": pos})
		sfx.play("chime")
	elif event.is_action_pressed("hide_hud"):
		hud.hud_visible = not hud.hud_visible
		hud.modulate.a = 1.0 if hud.hud_visible else 0.0
	else:
		for i in 4:
			if event.is_action_pressed("emote_%d" % (i + 1)):
				_emote(["wave", "heart", "sit", "hop"][i])


func _emote(kind: String) -> void:
	if world.player == null:
		return
	if kind == "sit":
		world.player.sitting = not world.player.sitting
		hud.toast("You sit down for a moment" if world.player.sitting else "You stand up")
	else:
		hud.toast({"wave": "You wave", "heart": "You send a heart", "hop": "You do a little hop"}[kind])
	Net.send_event("emote", {"kind": kind})


func _lock_player(on: bool) -> void:
	if world.player:
		world.player.input_locked = on


func _open_pause() -> void:
	pause.visible = true
	pause.sync()
	_lock_player(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _resume() -> void:
	pause.visible = false
	_on_overlay_closed()


func _on_overlay_closed() -> void:
	_lock_player(false)
	_capture()


func _capture() -> void:
	if in_game:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	if world.atmos:
		sfx.update_ambience(delta, in_game and not world.building, world.world_id, world.atmos.night, GameState.weather)
	if _shot_mode or not in_game:
		return
	# Browsers drop pointer lock on Esc without telling us: treat that as pausing.
	var overlay: bool = album.visible or pause.visible or hud.chat_open() or world.building
	if not overlay and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_open_pause()
	# Keep time in sync while it flows.
	if GameState.time_flowing and Net.is_host() and Net.has_partner():
		_sync_timer -= delta
		if _sync_timer <= 0.0:
			_sync_timer = 15.0
			_broadcast_settings()


# ------------------------------------------------------------------ dev screenshots

## `godot -- shot out=path world=alps tod=17 weather=snow pos=x,z yaw=deg pitch=deg [raise photo lens=N ap=N]`
func _run_shot(args: PackedStringArray) -> void:
	var opts := {}
	for a in args:
		var kv := a.split("=", true, 1)
		opts[kv[0]] = kv[1] if kv.size() > 1 else "1"
	menu.visible = false
	GameState.world_id = opts.get("world", "ruins")
	GameState.time_of_day = float(opts.get("tod", GameState.WORLDS[GameState.world_id]["default_time"]))
	GameState.weather = opts.get("weather", "clear")
	await world.build(GameState.world_id, int(opts.get("seed", 1234)))
	in_game = true
	hud.visible = true
	world.start_playing()
	var p = world.player
	p.set_yaw(deg_to_rad(float(opts.get("yaw", 0))))
	p.pitch = deg_to_rad(float(opts.get("pitch", 0)))
	p.head.rotation.x = p.pitch
	if opts.has("pos"):
		var xz: PackedStringArray = opts["pos"].split(",")
		p.global_position = world.biome.at(float(xz[0]), float(xz[1])) + Vector3(0, 0.3, 0)
	if opts.has("avatar"):
		GameState.partners[2] = {"name": "Mina", "color": GameState.PLAYER_COLORS[5]}
		var av = world._ensure_avatar(2)
		var fwd: Vector3 = -p.global_transform.basis.z
		var ap: Vector3 = world.biome.at(p.global_position.x + fwd.x * 3.5, p.global_position.z + fwd.z * 3.5)
		av.set_target(ap, p.yaw + PI * 0.8, 0.0, 1 if opts.get("avatar") == "raised" else 0)
		if opts.get("avatar") == "wave":
			av.play_emote("wave")
			av.say("look at this view!")
	if opts.has("menu"):
		world.stop_playing()
		hud.visible = false
		menu.visible = true
	if opts.has("raise"):
		p.raised = true
		p.lens_idx = Player_lens(opts.get("lens", "50"))
		p.aperture_idx = int(opts.get("ap", "0"))
	await get_tree().create_timer(float(opts.get("wait", "1.5"))).timeout
	var out: String = opts.get("out", "user://shot.png")
	if opts.has("photo"):
		await p.shoot()
		var m: Dictionary = PhotoStore.photos[PhotoStore.photos.size() - 1]
		var big := PhotoStore.export_png(m["id"])
		var f := FileAccess.open(out.replace(".png", "_photo.png"), FileAccess.WRITE)
		f.store_buffer(big)
		f.close()
		await get_tree().create_timer(0.5).timeout
	if opts.has("album"):
		album.visible = true
		await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out)
	print("SHOT saved ", out)
	get_tree().quit()


func Player_lens(mm: String) -> int:
	var lenses := [16, 24, 35, 50, 85, 135, 200]
	var i := lenses.find(int(mm))
	return i if i >= 0 else 3


func _on_build_progress(t: String) -> void:
	loading_label.text = t
	loading.visible = true


func _on_net_status(t: String) -> void:
	if not in_game:
		menu.set_status(t, true)
