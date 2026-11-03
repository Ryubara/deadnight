class_name Backdrop
extends Node3D
## The small map's outside, past the playable bounds (issue #638): what the players see through
## windows, broken walls and the broken roof. Nobody walks it and nothing collides with it. The
## scene is written by `tools/world/build_smallmap_backdrop.py` (its sizes and places are constants
## at that script's top).
##
## Every repeated model is one `MultiMeshInstance3D` (one draw for every copy). A multimesh whose
## model is a glTF scene names it in `metadata/source`; its mesh is taken from the scene here, at
## load, because a `.tscn` cannot point into an imported scene. Models exported as `.obj` are plain
## meshes and are set in the scene. The models wear `backdrop_haze.gdshader`, unshaded, which lights
## itself by the moon and the ambient and hazes itself after the scene's fog: this node copies those
## into the materials every frame, so the round's darkening reaches the backdrop. It also runs the
## screen's slow picture and the fires' flicker on its own phase (no `TIME`, so a Movie Maker
## capture and a test see the same frame).

const SOURCE := &"source"
const HAZE_SHADER := preload("res://world/smallmap/backdrop_haze.gdshader")

## The screen's picture drift, the same shader as the lot's screen.
@export var screen_face: MeshInstance3D
## Glow quads that flicker as fire, with their energy at full.
@export var fires: Array[MeshInstance3D] = []

var phase := 0.0
var _haze: Array[ShaderMaterial] = []
var _fire_energy: Array[float] = []
var _meshes := {}
var _moon: DirectionalLight3D


func _ready() -> void:
	# A scene's sub-resources are shared by every copy of it: this node writes into its materials,
	# so each copy gets its own (a menu preview and a match never change each other's haze).
	var copies := {}
	for node in find_children("*", "GeometryInstance3D", true, false):
		var geometry := node as GeometryInstance3D
		var material := geometry.material_override as ShaderMaterial
		if material == null:
			continue
		if not copies.has(material):
			copies[material] = material.duplicate()
		geometry.material_override = copies[material]
		if geometry is MultiMeshInstance3D:
			var multi := geometry as MultiMeshInstance3D
			if multi.has_meta(SOURCE) and multi.multimesh.mesh == null:
				multi.multimesh.mesh = mesh_of(str(multi.get_meta(SOURCE)))
		if material.shader == HAZE_SHADER and not _haze.has(copies[material]):
			_haze.append(copies[material])
	for fire in fires:
		_fire_energy.append(
			float((fire.material_override as ShaderMaterial).get_shader_parameter(&"energy"))
		)
	_sync_haze()
	advance(0.0)


func _process(delta: float) -> void:
	advance(delta)
	_sync_haze()


## The first mesh in a glTF scene, loaded once per path.
func mesh_of(path: String) -> Mesh:
	if not _meshes.has(path):
		var scene := (load(path) as PackedScene).instantiate()
		var found := scene.find_children("*", "MeshInstance3D", true, false)
		_meshes[path] = (found[0] as MeshInstance3D).mesh if not found.is_empty() else null
		scene.free()
	return _meshes[path]


func advance(delta: float) -> void:
	phase += delta
	if screen_face != null:
		(screen_face.material_override as ShaderMaterial).set_shader_parameter(&"phase", phase)
	for index in fires.size():
		var material := fires[index].material_override as ShaderMaterial
		material.set_shader_parameter(&"energy", _fire_energy[index] * flicker(phase + index * 1.7))


## A fire's brightness, 0.7 to 1.0, from the phase alone.
static func flicker(at: float) -> float:
	return 0.85 + 0.1 * sin(at * 11.0) * sin(at * 6.3 + 1.0) + 0.05 * sin(at * 23.0)


func _sync_haze() -> void:
	var world := get_world_3d()
	var environment := world.environment if world != null else null
	if environment == null:
		return
	if _moon == null or not is_instance_valid(_moon):
		_moon = _find_moon()
	# The Compatibility renderer lights in sRGB space (it never linearises a colour), so the colours
	# go in as they are, times their energies, as the renderer's own fog and ambient do.
	var ambient := environment.ambient_light_color * environment.ambient_light_energy
	var haze := environment.fog_light_color * environment.fog_light_energy
	var density := environment.fog_density if environment.fog_enabled else 0.0
	for material in _haze:
		material.set_shader_parameter(&"ambient", Vector3(ambient.r, ambient.g, ambient.b))
		material.set_shader_parameter(&"haze_color", Vector3(haze.r, haze.g, haze.b))
		material.set_shader_parameter(&"fog_density", density)
		if _moon != null:
			var moon := _moon.light_color * (_moon.light_energy if _moon.visible else 0.0)
			material.set_shader_parameter(&"moon_color", Vector3(moon.r, moon.g, moon.b))
			material.set_shader_parameter(&"moon_direction", _moon.global_basis.z.normalized())


## The scene's moon: the first directional light in the tree.
func _find_moon() -> DirectionalLight3D:
	var found := get_tree().root.find_children("*", "DirectionalLight3D", true, false)
	return found[0] as DirectionalLight3D if not found.is_empty() else null
