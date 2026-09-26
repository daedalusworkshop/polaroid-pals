extends Node
## Shared session state: who you are, which world, lighting, weather, camera prefs.

signal world_settings_changed          # time / weather / flow changed
signal partner_info_changed

const WORLDS := {
	"ruins": {
		"name": "Jungle Ruins",
		"place": "inspired by Ta Prohm, Angkor",
		"blurb": "Mossy stones, strangler figs and shafts of light.",
		"accent": Color("6fbf5a"),
		"default_time": 9.0,
	},
	"alps": {
		"name": "Alpine Valley",
		"place": "inspired by Lauterbrunnen, Switzerland",
		"blurb": "Wildflower meadows, chalets and waterfalls.",
		"accent": Color("7fb6e8"),
		"default_time": 17.2,
	},
	"tokyo": {
		"name": "Tokyo Backstreets",
		"place": "inspired by Yanaka, Tokyo",
		"blurb": "Lanterns, vending machines and quiet alleys.",
		"accent": Color("f08a78"),
		"default_time": 18.6,
	},
}
const WORLD_ORDER := ["ruins", "alps", "tokyo"]
const WEATHERS := ["clear", "mist", "rain", "snow", "petals", "fireflies"]
const WEATHER_NAMES := {
	"clear": "Clear", "mist": "Mist", "rain": "Rain", "snow": "Snow",
	"petals": "Petals", "fireflies": "Fireflies",
}
const PLAYER_COLORS := [
	Color("e8766b"), Color("f2b35a"), Color("7cc47a"),
	Color("6fa8dc"), Color("b48ad8"), Color("f29bc0"),
]

var player_name := "Photographer"
var player_color: Color = PLAYER_COLORS[0]

var world_id := "ruins"
var world_seed := 1
var time_of_day := 9.0          # hours, 0..24
var time_flowing := false
var weather := "clear"

var mouse_sensitivity := 1.0
var pixel_height := 270          # internal render height (smaller = chunkier)

## peer_id -> {"name": String, "color": Color}
var partners := {}

const SETTINGS_PATH := "user://settings.cfg"


func _ready() -> void:
	_setup_input()
	_load_settings()
	randomize()
	world_seed = randi() % 99999 + 1


func settings_dict() -> Dictionary:
	return {
		"world": world_id, "seed": world_seed, "tod": time_of_day,
		"flow": time_flowing, "weather": weather,
	}


func apply_settings_dict(d: Dictionary) -> void:
	world_id = d.get("world", world_id)
	world_seed = int(d.get("seed", world_seed))
	time_of_day = float(d.get("tod", time_of_day))
	time_flowing = bool(d.get("flow", time_flowing))
	weather = d.get("weather", weather)


func world_name(id: String = "") -> String:
	return WORLDS.get(id if id != "" else world_id, {}).get("name", "?")


func clock_string(t: float = -1.0) -> String:
	if t < 0.0:
		t = time_of_day
	var h := int(t) % 24
	var m := int((t - floor(t)) * 60.0)
	return "%02d:%02d" % [h, m]


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("player", "name", player_name)
	cfg.set_value("player", "color", player_color)
	cfg.set_value("video", "pixel_height", pixel_height)
	cfg.set_value("input", "mouse_sensitivity", mouse_sensitivity)
	cfg.save(SETTINGS_PATH)


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	player_name = cfg.get_value("player", "name", player_name)
	player_color = cfg.get_value("player", "color", player_color)
	pixel_height = cfg.get_value("video", "pixel_height", pixel_height)
	mouse_sensitivity = cfg.get_value("input", "mouse_sensitivity", mouse_sensitivity)


func _setup_input() -> void:
	var keys := {
		"move_forward": [KEY_W, KEY_UP],
		"move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"jump": [KEY_SPACE],
		"sprint": [KEY_SHIFT],
		"camera_toggle": [KEY_C],
		"aperture_open": [KEY_Q],
		"aperture_close": [KEY_E],
		"film_next": [KEY_F],
		"exposure_up": [KEY_X],
		"exposure_down": [KEY_Z],
		"album": [KEY_TAB],
		"chat": [KEY_T, KEY_ENTER],
		"ping": [KEY_G],
		"emote_1": [KEY_1],
		"emote_2": [KEY_2],
		"emote_3": [KEY_3],
		"emote_4": [KEY_4],
		"pause": [KEY_ESCAPE, KEY_P],
		"hide_hud": [KEY_H],
	}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for k in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)
	var mouse := {
		"shutter": MOUSE_BUTTON_LEFT,
		"camera_raise": MOUSE_BUTTON_RIGHT,
	}
	for action in mouse:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		var mev := InputEventMouseButton.new()
		mev.button_index = mouse[action]
		InputMap.action_add_event(action, mev)
