extends Node
## Tiny procedural sound kit: shutter clicks, chimes, pops, and a soft ambience
## bed (wind + birds by day, crickets by night, rain when it rains). No audio files.

const RATE := 22050

var _sounds := {}
var _players: Array = []
var _wind: AudioStreamPlayer
var _rain: AudioStreamPlayer
var _cricket: AudioStreamPlayer
var _bird_timer := 4.0
var _rng := RandomNumberGenerator.new()
var _enabled := false


func _ready() -> void:
	_rng.seed = 99
	_sounds["shutter"] = _shutter(0.9)
	_sounds["shutter_far"] = _shutter(0.35)
	_sounds["chime"] = _chime()
	_sounds["pop"] = _pop()
	for i in 4:
		_sounds["bird%d" % i] = _bird(i)
	for i in 6:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_wind = _loop_player(_noise_loop(4.0, 0.985, 0.5), -18.0)
	_rain = _loop_player(_noise_loop(3.0, 0.6, 0.35), -80.0)
	_cricket = _loop_player(_crickets(), -80.0)


func play(name: String, volume_db := 0.0, pitch := 1.0) -> void:
	if not _sounds.has(name):
		return
	for p in _players:
		if not p.playing:
			p.stream = _sounds[name]
			p.volume_db = volume_db
			p.pitch_scale = pitch
			p.play()
			return


## Called every frame with the current mood of the world.
func update_ambience(delta: float, active: bool, biome: String, night: float, weather: String) -> void:
	if active and not _enabled:
		_enabled = true
		_wind.play()
		_rain.play()
		_cricket.play()
	if not _enabled:
		return
	var wind_db := -20.0 if biome != "tokyo" else -24.0
	if weather == "snow" or weather == "mist":
		wind_db += 3.0
	_wind.volume_db = lerpf(_wind.volume_db, wind_db if active else -60.0, delta * 2.0)
	_rain.volume_db = lerpf(_rain.volume_db, -14.0 if (active and weather == "rain") else -70.0, delta * 1.5)
	var crick := -24.0 if (active and night > 0.5 and weather != "rain" and weather != "snow") else -70.0
	_cricket.volume_db = lerpf(_cricket.volume_db, crick, delta * 1.0)
	if active and night < 0.4 and weather in ["clear", "petals", "mist"]:
		_bird_timer -= delta
		if _bird_timer <= 0.0:
			_bird_timer = _rng.randf_range(2.5, 9.0)
			play("bird%d" % _rng.randi_range(0, 3), _rng.randf_range(-22.0, -14.0), _rng.randf_range(0.9, 1.15))


# ------------------------------------------------------------------ synthesis

func _wav(samples: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w


func _loop_player(stream: AudioStream, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = db
	add_child(p)
	return p


func _shutter(gain: float) -> AudioStreamWAV:
	var n := int(RATE * 0.16)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var env := exp(-t * 90.0) + 0.8 * exp(-maxf(t - 0.075, 0.0) * 120.0) * float(t > 0.075)
		var noise := _rng.randf_range(-1.0, 1.0)
		lp = lerpf(lp, noise, 0.45)
		s[i] = (lp * 0.8 + sin(t * TAU * 1800.0) * 0.2) * env * gain * 0.8
	return _wav(s)


func _chime() -> AudioStreamWAV:
	var n := int(RATE * 0.9)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var a := sin(t * TAU * 880.0) * exp(-t * 5.0)
		var b := sin(t * TAU * 1318.5) * exp(-maxf(t - 0.12, 0.0) * 5.0) * float(t > 0.12)
		s[i] = (a + b) * 0.25
	return _wav(s)


func _pop() -> AudioStreamWAV:
	var n := int(RATE * 0.12)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		s[i] = sin(t * TAU * (600.0 + 900.0 * exp(-t * 40.0))) * exp(-t * 30.0) * 0.35
	return _wav(s)


func _bird(variant: int) -> AudioStreamWAV:
	var notes: Array = [[3200.0, 4200.0, 3], [2600.0, 3600.0, 2], [3800.0, 2900.0, 4], [2900.0, 4600.0, 2]][variant]
	var dur := 0.11
	var gap := 0.06
	var n := int(RATE * (dur + gap) * notes[2])
	var s := PackedFloat32Array()
	s.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var k := int(t / (dur + gap))
		var lt := t - k * (dur + gap)
		if lt > dur:
			s[i] = 0.0
			continue
		var f := lerpf(notes[0], notes[1], lt / dur)
		phase += TAU * f / RATE
		var env := sin(lt / dur * PI)
		s[i] = sin(phase + sin(phase * 0.5) * 0.6) * env * 0.3
	return _wav(s)


## Seamless filtered noise loop (wind or rain), made seamless with a crossfade.
func _noise_loop(seconds: float, smooth: float, gain: float) -> AudioStreamWAV:
	var n := int(RATE * seconds)
	var fade := int(RATE * 0.5)
	var raw := PackedFloat32Array()
	raw.resize(n + fade)
	var lp := 0.0
	var lp2 := 0.0
	for i in n + fade:
		lp = lerpf(_rng.randf_range(-1.0, 1.0), lp, smooth)
		lp2 = lerpf(lp, lp2, smooth * 0.9)
		var gust := 0.6 + 0.4 * sin(float(i) / RATE * TAU / seconds)
		raw[i] = (lp2 * (8.0 if smooth > 0.9 else 1.0)) * gust * gain
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		s[i] = raw[i]
		if i < fade:
			var k := float(i) / fade
			s[i] = raw[i] * k + raw[n + i] * (1.0 - k)
	return _wav(s, true)


func _crickets() -> AudioStreamWAV:
	var n := int(RATE * 2.0)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var chirp := fmod(t, 0.5) < 0.12
		var pulse := 0.5 + 0.5 * sin(t * TAU * 45.0)
		s[i] = sin(t * TAU * 4300.0) * pulse * (0.18 if chirp else 0.0)
	return _wav(s, true)
