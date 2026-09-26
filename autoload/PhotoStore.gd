extends Node
## The shared album. Photos are stored at native pixel resolution (crisp and tiny)
## and upscaled with nearest-neighbour when exported / downloaded.

signal photo_added(meta: Dictionary)
signal photo_changed(meta: Dictionary)
signal photo_removed(id: String)

const DIR := "user://photos"
const INDEX := "user://photos/index.json"
const EXPORT_SCALE := 4

var photos: Array = []            # Array[Dictionary], oldest first
var _tex_cache := {}              # id -> ImageTexture


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	_load_index()


func new_id() -> String:
	return "%d_%04d" % [Time.get_unix_time_from_system() * 1000.0, randi() % 10000]


## Store a photo taken locally (or received from a partner).
func add_photo(img: Image, meta: Dictionary) -> Dictionary:
	var m := meta.duplicate()
	if not m.has("id"):
		m["id"] = new_id()
	if find(m["id"]) != -1:
		return m
	m["w"] = img.get_width()
	m["h"] = img.get_height()
	if not m.has("hearts"):
		m["hearts"] = []
	img.save_png(_path(m["id"]))
	photos.append(m)
	_tex_cache[m["id"]] = ImageTexture.create_from_image(img)
	_save_index()
	photo_added.emit(m)
	return m


func add_photo_png(png: PackedByteArray, meta: Dictionary) -> void:
	var img := Image.new()
	if img.load_png_from_buffer(png) != OK:
		push_warning("Received a photo that could not be decoded")
		return
	add_photo(img, meta)


func png_bytes(id: String) -> PackedByteArray:
	return FileAccess.get_file_as_bytes(_path(id))


func find(id: String) -> int:
	for i in photos.size():
		if photos[i]["id"] == id:
			return i
	return -1


func get_meta_of(id: String) -> Dictionary:
	var i := find(id)
	return photos[i] if i != -1 else {}


func get_texture(id: String) -> Texture2D:
	if _tex_cache.has(id):
		return _tex_cache[id]
	var img := Image.load_from_file(_path(id))
	if img == null:
		return null
	var tex := ImageTexture.create_from_image(img)
	_tex_cache[id] = tex
	return tex


func set_hearts(id: String, hearts: Array) -> void:
	var i := find(id)
	if i == -1:
		return
	photos[i]["hearts"] = hearts
	_save_index()
	photo_changed.emit(photos[i])


func toggle_heart(id: String, who: String) -> Array:
	var i := find(id)
	if i == -1:
		return []
	var hearts: Array = photos[i].get("hearts", []).duplicate()
	if who in hearts:
		hearts.erase(who)
	else:
		hearts.append(who)
	set_hearts(id, hearts)
	return hearts


func remove(id: String) -> void:
	var i := find(id)
	if i == -1:
		return
	photos.remove_at(i)
	_tex_cache.erase(id)
	DirAccess.remove_absolute(_path(id))
	_save_index()
	photo_removed.emit(id)


## Upscaled PNG, ready to share outside the game.
func export_png(id: String) -> PackedByteArray:
	var img := Image.load_from_file(_path(id))
	if img == null:
		return PackedByteArray()
	img.resize(img.get_width() * EXPORT_SCALE, img.get_height() * EXPORT_SCALE, Image.INTERPOLATE_NEAREST)
	return img.save_png_to_buffer()


func export_filename(id: String) -> String:
	var m := get_meta_of(id)
	var world := str(m.get("world", "world"))
	var by := str(m.get("by", "me")).to_lower().replace(" ", "_")
	return "polaroid_%s_%s_%s.png" % [world, by, id]


## Browser download on web, save to a folder + open it on desktop.
func download(id: String) -> void:
	var bytes := export_png(id)
	if bytes.is_empty():
		return
	var fname := export_filename(id)
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(bytes, fname, "image/png")
	else:
		var dir := OS.get_system_dir(OS.SYSTEM_DIR_PICTURES).path_join("Polaroid Pals")
		DirAccess.make_dir_recursive_absolute(dir)
		var f := FileAccess.open(dir.path_join(fname), FileAccess.WRITE)
		if f:
			f.store_buffer(bytes)
			f.close()
			OS.shell_show_in_file_manager(dir.path_join(fname))


func _path(id: String) -> String:
	return DIR.path_join(id + ".png")


func _save_index() -> void:
	var f := FileAccess.open(INDEX, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(photos))
		f.close()


func _load_index() -> void:
	if not FileAccess.file_exists(INDEX):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(INDEX))
	if data is Array:
		for m in data:
			if m is Dictionary and m.has("id") and FileAccess.file_exists(_path(m["id"])):
				photos.append(m)
