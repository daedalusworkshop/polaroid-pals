extends RefCounted
## All shared world materials, so weather / night / the photo depth pass can
## flip a uniform on everything at once.

const TextureForge := preload("res://world/TextureForge.gd")
const TOON := preload("res://shaders/toon.gdshader")
const FOLIAGE := preload("res://shaders/foliage.gdshader")
const GLOW := preload("res://shaders/glow.gdshader")
const WATER := preload("res://shaders/water.gdshader")
const GODRAY := preload("res://shaders/godray.gdshader")
const FACADE := preload("res://shaders/facade.gdshader")
const FacadeForge := preload("res://world/FacadeForge.gd")

var by_layer := {}      # layer name -> ShaderMaterial
var extra: Array = []   # other materials that take the shared uniforms
var godray: ShaderMaterial


func _init(seed: int = 1) -> void:
	var solid := _mk(TOON)
	by_layer["solid"] = solid

	var terrain := _mk(TOON)
	terrain.set_shader_parameter("terrain", 1.0)
	by_layer["terrain"] = terrain

	var leaf := _mk(FOLIAGE)
	leaf.set_shader_parameter("leaf_tex", TextureForge.leaves(seed))
	by_layer["leaf"] = leaf

	var fern := _mk(FOLIAGE)
	fern.set_shader_parameter("leaf_tex", TextureForge.fern(seed + 1))
	fern.set_shader_parameter("wrap", 0.6)
	by_layer["fern"] = fern

	var grass := _mk(FOLIAGE)
	grass.set_shader_parameter("leaf_tex", TextureForge.grass(seed + 2))
	grass.set_shader_parameter("instanced", 1.0)
	grass.set_shader_parameter("up_normals", 1.0)
	grass.set_shader_parameter("wind", 1.4)
	by_layer["grass"] = grass

	var flower := _mk(FOLIAGE)
	flower.set_shader_parameter("leaf_tex", TextureForge.flower())
	flower.set_shader_parameter("instanced", 1.0)
	flower.set_shader_parameter("up_normals", 1.0)
	flower.set_shader_parameter("wind", 1.4)
	by_layer["flower"] = flower

	by_layer["glow"] = _mk(GLOW)

	var sign := _mk(GLOW)
	sign.set_shader_parameter("glyph_tex", TextureForge.glyphs(seed + 3))
	sign.set_shader_parameter("use_tex", 1.0)
	by_layer["sign"] = sign

	by_layer["water"] = _mk(WATER)
	var falls := _mk(WATER)
	falls.set_shader_parameter("flow", 1.0)
	by_layer["falls"] = falls

	godray = _mk(GODRAY)

	var facade := _mk(FACADE)
	facade.set_shader_parameter("atlas", FacadeForge.atlas(seed + 4))
	by_layer["facade"] = facade

	var cloth := _mk(TOON)
	cloth.set_shader_parameter("sway", 1.0)
	by_layer["cloth"] = cloth
	sign.set_shader_parameter("flicker", 1.0)


func _mk(shader: Shader) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader
	return m


func get_mat(layer: String) -> ShaderMaterial:
	return by_layer.get(layer, by_layer["solid"])


func register(m: ShaderMaterial) -> void:
	extra.append(m)


## Set a uniform on every material that declares it.
func set_all(param: String, value) -> void:
	for m in by_layer.values():
		m.set_shader_parameter(param, value)
	for m in extra:
		m.set_shader_parameter(param, value)
	godray.set_shader_parameter(param, value)
