extends RefCounted
## Paints the little pixel textures (leaves, grass, ferns, flowers, glyphs) in code,
## so the whole game ships with zero external art files.


static func _img(w: int, h: int) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	return img


static func _tex(img: Image) -> ImageTexture:
	return ImageTexture.create_from_image(img)


## A cluster of small pointed leaves; greyscale value (tinted by vertex colour).
static func leaves(seed: int = 1) -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var s := 32
	var img := _img(s, s)
	for i in 26:
		var ang := rng.randf() * TAU
		var dist := sqrt(rng.randf()) * 11.0
		var cx := 16.0 + cos(ang) * dist
		var cy := 16.0 + sin(ang) * dist
		var la := rng.randf() * TAU
		var llen := rng.randf_range(3.0, 5.5)
		var lw := rng.randf_range(1.2, 2.0)
		var shade := rng.randf_range(0.78, 1.0)
		var dx := cos(la)
		var dy := sin(la)
		for y in s:
			for x in s:
				var px := x + 0.5 - cx
				var py := y + 0.5 - cy
				var u := px * dx + py * dy
				var v := -px * dy + py * dx
				var t := u / llen
				if t < -1.0 or t > 1.0:
					continue
				var half := lw * (1.0 - t * t)
				if abs(v) <= half:
					var edge := 1.0 if v > half * 0.2 else 0.9
					var hl := 1.08 if (t > 0.3 and v < 0.0) else 1.0
					var val := clampf(shade * edge * hl, 0.0, 1.0)
					img.set_pixel(x, y, Color(val, val, val, 1.0))
	return _tex(img)


## Upright grass blades, darker at the base.
static func grass(seed: int = 2) -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var w := 16
	var h := 16
	var img := _img(w, h)
	for b in 9:
		var x0 := rng.randf_range(1.0, w - 2.0)
		var height := rng.randi_range(6, h - 1)
		var lean := rng.randf_range(-0.35, 0.35)
		for i in height:
			var y := h - 1 - i
			var x := int(round(x0 + lean * i * (float(i) / height)))
			if x < 0 or x >= w:
				continue
			var t := float(i) / height
			var val := lerpf(0.7, 1.05, t)
			img.set_pixel(x, y, Color(minf(val, 1.0), minf(val, 1.0), minf(val, 1.0), 1.0))
	return _tex(img)


## An arching fern frond (drawn upright; cards are tilted outward in 3D).
static func fern(seed: int = 3) -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var w := 16
	var h := 32
	var img := _img(w, h)
	for y in h:
		var t := float(y) / h                      # 0 tip .. 1 base
		var cx := 8
		var width := int(round(sin(t * PI) * 6.5))
		img.set_pixel(cx, y, Color(0.75, 0.75, 0.75, 1))
		if y % 2 == 0:
			for dx in range(1, width + 1):
				var val := lerpf(1.0, 0.8, float(dx) / 7.0)
				var yy := clampi(y - dx / 3, 0, h - 1)
				img.set_pixel(clampi(cx + dx, 0, w - 1), yy, Color(val, val, val, 1))
				img.set_pixel(clampi(cx - dx, 0, w - 1), yy, Color(val * 0.92, val * 0.92, val * 0.92, 1))
	return _tex(img)


## Tiny five-petal blossom (white, tinted per instance).
static func flower() -> ImageTexture:
	var img := _img(8, 8)
	var petal := Color(1, 1, 1, 1)
	var shade := Color(0.85, 0.85, 0.88, 1)
	for p in [Vector2i(3, 1), Vector2i(4, 1), Vector2i(1, 3), Vector2i(1, 4), Vector2i(6, 3), Vector2i(6, 4),
			Vector2i(2, 6), Vector2i(5, 6), Vector2i(2, 2), Vector2i(5, 2), Vector2i(2, 5), Vector2i(5, 5)]:
		img.set_pixelv(p, petal)
	for p in [Vector2i(3, 2), Vector2i(4, 2), Vector2i(2, 3), Vector2i(2, 4), Vector2i(5, 3), Vector2i(5, 4), Vector2i(3, 5), Vector2i(4, 5)]:
		img.set_pixelv(p, shade)
	for p in [Vector2i(3, 3), Vector2i(4, 3), Vector2i(3, 4), Vector2i(4, 4)]:
		img.set_pixelv(p, Color(1.0, 0.85, 0.35, 1))
	return _tex(img)


## 8x8 grid of pseudo-kanji glyphs (alpha = ink) for shop signs.
static func glyphs(seed: int = 7) -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var img := _img(64, 64)
	var ink := Color(1, 1, 1, 1)
	for gy in 8:
		for gx in 8:
			var ox := gx * 8 + 1
			var oy := gy * 8 + 1
			var strokes := rng.randi_range(3, 5)
			for s in strokes:
				if rng.randf() < 0.5:
					var y := oy + rng.randi_range(0, 5)
					var x0 := ox + rng.randi_range(0, 2)
					var x1 := ox + rng.randi_range(3, 5)
					for x in range(x0, x1 + 1):
						img.set_pixel(x, y, ink)
				else:
					var x := ox + rng.randi_range(0, 5)
					var y0 := oy + rng.randi_range(0, 2)
					var y1 := oy + rng.randi_range(3, 5)
					for y in range(y0, y1 + 1):
						img.set_pixel(x, y, ink)
			if rng.randf() < 0.4:
				img.set_pixel(ox + rng.randi_range(0, 5), oy + rng.randi_range(0, 5), ink)
	return _tex(img)


## Soft square particle (for dust, fireflies, rain, snow).
static func dot(size: int = 4) -> ImageTexture:
	var img := _img(size, size)
	img.fill(Color(1, 1, 1, 1))
	return _tex(img)


## A little heart for emotes.
static func heart() -> ImageTexture:
	var rows := [
		"..##.##..",
		".#######.",
		".#######.",
		"..#####..",
		"...###...",
		"....#....",
	]
	var img := _img(9, 6)
	for y in rows.size():
		for x in rows[y].length():
			if rows[y][x] == "#":
				img.set_pixel(x, y, Color(1, 0.45, 0.55, 1))
	return _tex(img)


## Pink sakura petal.
static func petal() -> ImageTexture:
	var img := _img(4, 3)
	for p in [Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1), Vector2i(1, 2), Vector2i(2, 2)]:
		img.set_pixelv(p, Color(1, 0.8, 0.86, 1))
	img.set_pixel(3, 1, Color(1, 0.7, 0.8, 1))
	return _tex(img)
