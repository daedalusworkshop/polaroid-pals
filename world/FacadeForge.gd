extends RefCounted
## Paints the facade atlas: an 8x8 grid of 32px pixel-art "bays" that get
## UV-mapped onto building walls (Ian Hubert style: detail lives in the texture).
## Alpha encodes meaning for shaders/facade.gdshader:
##   0          bare wall - the building's own colour shows through
##   0.05-0.5   grime / shadow overlay
##   0.62       shoji paper - glows warmly when the room behind is lit
##   0.78       glass - a little parallax room is rendered behind it
##   1          painted detail

const T_WINDOW := 0       # 0..15  windows: curtains, blinds, plants, flower boxes, AC units
const T_WALL := 16        # 16..23 bare-wall details: pipes, meters, posters, vents, ivy
const T_DOOR := 24        # 24..27 doors
const T_SHOP := 28        # 28..31 shopfront glass
const T_CHALET := 32      # 32..39 chalet windows with shutters + geraniums
const T_SMALL := 40       # 40..43 small windows
const T_SHOJI := 44       # 44..47 shoji paper windows

const GLASS := Color(0.0, 0.0, 0.0, 0.78)
const PAPER_A := 0.62


static func atlas(seed: int = 5) -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var img := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for i in 48:
		var ox := (i % 8) * 32
		var oy := (i / 8) * 32
		if i < T_WALL:
			_window(img, ox, oy, rng, i)
		elif i < T_DOOR:
			_wall(img, ox, oy, rng, i - T_WALL)
		elif i < T_SHOP:
			_door(img, ox, oy, i - T_DOOR)
		elif i < T_CHALET:
			_shop(img, ox, oy, rng)
		elif i < T_SMALL:
			_chalet(img, ox, oy, rng, i - T_CHALET)
		elif i < T_SHOJI:
			_small(img, ox, oy, rng)
		else:
			_shoji(img, ox, oy, rng)
	return ImageTexture.create_from_image(img)


static func _r(img: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	for yy in range(maxi(y, 0), mini(y + h, img.get_height())):
		for xx in range(maxi(x, 0), mini(x + w, img.get_width())):
			img.set_pixel(xx, yy, c)


static func _grime(img: Image, ox: int, oy: int, x0: int, x1: int, y0: int, rng: RandomNumberGenerator) -> void:
	for x in range(x0, x1):
		if rng.randf() < 0.45:
			var n := rng.randi_range(2, 7)
			for k in n:
				var y := y0 + k
				if y < 32 and img.get_pixel(ox + x, oy + y).a == 0.0:
					img.set_pixel(ox + x, oy + y, Color(0.12, 0.1, 0.1, 0.3 * (1.0 - float(k) / n)))


static func _pick(rng: RandomNumberGenerator, arr: Array) -> Color:
	return arr[rng.randi() % arr.size()]


static func _window(img: Image, ox: int, oy: int, rng: RandomNumberGenerator, i: int) -> void:
	var frame := _pick(rng, [Color("c9ccd2"), Color("b8bcc4"), Color("7a5a40"), Color("e8e4dc"), Color("5a5e66")])
	var x0 := 6
	var x1 := 26
	var y0 := 3 if i % 4 == 3 else 5
	var y1 := 22
	_r(img, ox + x0 - 1, oy + y0 - 1, x1 - x0 + 2, y1 - y0 + 2, frame)
	_r(img, ox + x0, oy + y0, x1 - x0, y1 - y0, GLASS)
	_r(img, ox + 15, oy + y0, 2, y1 - y0, frame)
	var cc := _pick(rng, [Color("f2e6c8"), Color("e8a0a0"), Color("a8c8e8"), Color("f0d890"), Color("c8e0b8"), Color("e0c8f0")])
	match i % 8:
		0, 5:
			for x in range(x0, x0 + 4):
				_r(img, ox + x, oy + y0, 1, y1 - y0, cc if x % 2 == 0 else cc.darkened(0.12))
			for x in range(x1 - 4, x1):
				_r(img, ox + x, oy + y0, 1, y1 - y0, cc if x % 2 == 0 else cc.darkened(0.12))
		1:
			for y in range(y0, y0 + (y1 - y0) / 2):
				if y % 2 == 0:
					_r(img, ox + x0, oy + y, x1 - x0, 1, Color("ece8de"))
		2:
			for k in 5:
				var px := x0 + 2 + k * 4
				_r(img, ox + px, oy + y1 - 3, 3, 3, Color("b86a45"))
				for j in 6:
					img.set_pixel(ox + px + rng.randi_range(-1, 3), oy + y1 - 4 - rng.randi_range(0, 4), Color("4f9a45") if j % 2 == 0 else Color("3f7a3c"))
		3:
			for y in range(y0, y1):
				for x in range(x0, 15):
					if (x + y) % 2 == 0:
						img.set_pixel(ox + x, oy + y, Color("f4f2ee"))
		4:
			for x in range(x0, 15):
				_r(img, ox + x, oy + y0, 1, y1 - y0, cc if x % 3 != 0 else cc.darkened(0.15))
		6:
			_r(img, ox + x0, oy + y0, x1 - x0, 4, Color("ece8de"))
			_r(img, ox + 19, oy + 12, 4, 4, Color("f2c230"))
	_r(img, ox + x0 - 2, oy + y1 + 1, x1 - x0 + 4, 2, frame.darkened(0.15))
	var below := rng.randi() % 4
	if below == 0:
		_r(img, ox + x0, oy + y1 + 5, x1 - x0, 4, Color("8a5a3a"))
		_r(img, ox + x0, oy + y1 + 4, x1 - x0, 1, Color("4f8a45"))
		for k in 12:
			img.set_pixel(ox + x0 + rng.randi_range(0, x1 - x0 - 1), oy + y1 + rng.randi_range(3, 5),
				_pick(rng, [Color("e8484f"), Color("f06d8a"), Color("f2d24a"), Color("ffffff")]))
	elif below == 1:
		_r(img, ox + 9, oy + y1 + 4, 14, 6, Color("e4e4e0"))
		for x in range(10, 22, 2):
			_r(img, ox + x, oy + y1 + 5, 1, 4, Color("a8a8a8"))
		_r(img, ox + 23, oy + y1 + 6, 1, 32 - (y1 + 6), Color("c8c8c4"))
	_grime(img, ox, oy, x0, x1, y1 + 3, rng)


static func _wall(img: Image, ox: int, oy: int, rng: RandomNumberGenerator, i: int) -> void:
	match i:
		0:
			_r(img, ox + 14, oy, 3, 32, Color("b8bcc4"))
			for y in [6, 16, 26]:
				_r(img, ox + 13, oy + y, 5, 1, Color("8a8e96"))
			_r(img, ox + 18, oy + 18, 7, 8, Color("d8d8d0"))
			_r(img, ox + 19, oy + 19, 5, 3, Color("303038"))
		1:
			var pc := _pick(rng, [Color("f2c230"), Color("e8604a"), Color("5aa0d8")])
			_r(img, ox + 8, oy + 7, 16, 20, pc)
			_r(img, ox + 10, oy + 9, 12, 1, Color("ffffff"))
			for k in 5:
				_r(img, ox + 10, oy + 12 + k * 3, rng.randi_range(6, 12), 1, Color("222222"))
		2:
			_r(img, ox + 10, oy + 8, 12, 12, Color("a8aab0"))
			for y in range(9, 19, 2):
				_r(img, ox + 11, oy + y, 10, 1, Color("5a5c64"))
			_grime(img, ox, oy, 10, 22, 20, rng)
		3:
			var x := rng.randi_range(8, 22)
			for y in range(31, 3, -1):
				x = clampi(x + rng.randi_range(-1, 1), 3, 28)
				for k in 3:
					img.set_pixel(ox + clampi(x + rng.randi_range(-3, 3), 0, 31), oy + y, _pick(rng, [Color("4f9a45"), Color("3f7a3c"), Color("6aad50")]))
		4:
			_r(img, ox + 9, oy + 10, 12, 14, Color("c8ccd0"))
			_r(img, ox + 11, oy + 12, 5, 3, Color("f2c230"))
			_r(img, ox + 14, oy + 24, 2, 8, Color("5a5e66"))
		5:
			_r(img, ox + 12, oy + 12, 8, 3, Color("e8e0c8"))
			_r(img, ox + 21, oy + 14, 3, 5, Color("5a5e66"))
			_r(img, ox + 11, oy + 18, 10, 6, Color("c8413b"))
			_r(img, ox + 12, oy + 20, 8, 1, Color("303030"))
		6:
			_grime(img, ox, oy, 2, 30, 0, rng)
		_:
			_r(img, ox + 11, oy + 8, 10, 8, Color("b8bcc4"))
			_r(img, ox + 12, oy + 9, 8, 6, GLASS)
			_grime(img, ox, oy, 11, 21, 16, rng)


static func _door(img: Image, ox: int, oy: int, i: int) -> void:
	match i:
		0:
			_r(img, ox + 5, oy + 5, 22, 27, Color("6b4a33"))
			_r(img, ox + 7, oy + 7, 18, 12, GLASS)
			for x in range(9, 25, 4):
				_r(img, ox + x, oy + 7, 1, 12, Color("6b4a33"))
			_r(img, ox + 7, oy + 13, 18, 1, Color("6b4a33"))
		1:
			_r(img, ox + 8, oy + 6, 16, 26, Color("7a8a9a"))
			_r(img, ox + 11, oy + 9, 10, 6, GLASS)
			_r(img, ox + 21, oy + 19, 2, 2, Color("d8c070"))
		2:
			_r(img, ox + 2, oy + 6, 28, 26, Color("b8bcc2"))
			for y in range(7, 32, 2):
				_r(img, ox + 2, oy + y, 28, 1, Color("8a8e96"))
		_:
			_r(img, ox + 5, oy + 4, 22, 28, GLASS)
			for k in 3:
				_r(img, ox + 6 + k * 7, oy + 4, 6, 10, Color("2b3350"))
				_r(img, ox + 8 + k * 7, oy + 7, 2, 3, Color("f2ede2"))
	_r(img, ox + 3, oy + 3, 26, 1, Color(0.1, 0.1, 0.1, 0.3))


static func _shop(img: Image, ox: int, oy: int, rng: RandomNumberGenerator) -> void:
	_r(img, ox + 1, oy + 2, 30, 30, Color("4a4e58"))
	_r(img, ox + 2, oy + 3, 28, 28, GLASS)
	_r(img, ox + 15, oy + 3, 2, 28, Color("4a4e58"))
	for k in 9:
		_r(img, ox + 3 + k * 3, oy + 27, 2, 3, _pick(rng, [Color("e84a3a"), Color("f2c230"), Color("4ac27a"), Color("3a8ae8"), Color("f07aa8")]))
	_r(img, ox + 20, oy + 6, 7, 9, Color("f4f0e4"))
	_r(img, ox + 21, oy + 8, 5, 1, Color("c8413b"))
	_r(img, ox + 21, oy + 11, 4, 1, Color("303030"))


static func _chalet(img: Image, ox: int, oy: int, rng: RandomNumberGenerator, i: int) -> void:
	var shutter: Color = [Color("3f7a52"), Color("b8483e"), Color("3d5f8a"), Color("3f7a52")][i % 4]
	_r(img, ox + 9, oy + 6, 14, 17, Color("f2ede2"))
	_r(img, ox + 10, oy + 7, 12, 15, GLASS)
	_r(img, ox + 15, oy + 7, 2, 15, Color("f2ede2"))
	_r(img, ox + 10, oy + 13, 12, 1, Color("f2ede2"))
	if i % 2 == 0:
		for x in range(10, 22, 2):
			_r(img, ox + x, oy + 7, 1, 3, Color("f6f0e4"))
	for side in [2, 23]:
		_r(img, ox + side, oy + 6, 7, 17, shutter)
		for y in range(7, 22, 2):
			_r(img, ox + side + 1, oy + y, 5, 1, shutter.darkened(0.25))
		if i >= 4:
			_r(img, ox + side + 2, oy + 9, 1, 1, Color("f2ede2"))
			_r(img, ox + side + 4, oy + 9, 1, 1, Color("f2ede2"))
			_r(img, ox + side + 3, oy + 10, 1, 1, Color("f2ede2"))
	_r(img, ox + 7, oy + 25, 18, 4, Color("6e4527"))
	for k in 18:
		img.set_pixel(ox + 7 + rng.randi_range(0, 17), oy + 22 + rng.randi_range(0, 2),
			_pick(rng, [Color("e8484f"), Color("f06d8a"), Color("e84a3a"), Color("4f8a45")]))


static func _small(img: Image, ox: int, oy: int, rng: RandomNumberGenerator) -> void:
	_r(img, ox + 11, oy + 10, 10, 10, Color("d8d2c4"))
	_r(img, ox + 12, oy + 11, 8, 8, GLASS)
	_r(img, ox + 15, oy + 11, 2, 8, Color("d8d2c4"))
	if rng.randf() < 0.5:
		_r(img, ox + 12, oy + 16, 3, 3, Color("4f9a45"))
	_grime(img, ox, oy, 11, 21, 20, rng)


static func _shoji(img: Image, ox: int, oy: int, rng: RandomNumberGenerator) -> void:
	var wood := Color("7a5a40")
	_r(img, ox + 4, oy + 4, 24, 20, wood)
	_r(img, ox + 5, oy + 5, 22, 18, Color(0.96, 0.92, 0.82, PAPER_A))
	for x in range(5, 27, 4):
		_r(img, ox + x, oy + 5, 1, 18, wood)
	for y in range(5, 23, 5):
		_r(img, ox + 5, oy + y, 22, 1, wood)
	_r(img, ox + 3, oy + 24, 26, 2, wood.darkened(0.2))
	_grime(img, ox, oy, 5, 27, 26, rng)
