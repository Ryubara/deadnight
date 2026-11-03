class_name RecutSkin
extends RefCounted
## The skin a re-cut weapon wears (Deadnight #787): `recut_skin.gdshader` put over the palette
## material of
## every mesh under a weapon model, and taken off again. One builder for every view of a weapon:
## the soldier's
## hand (`HeldWeapon`, the night's bodies and the menu's), the bench's cradle (`RecutMachine`),
## and any model
## a future weapon brings, because it reads only what the model already has: a `BaseMaterial3D`
## with its
## palette texture, colour, metallic and roughness. Nothing is made per model.
##
## It swaps the surface's material (`set_surface_override_material`), never adds a pass: a weapon
## draws as many
## times as before (an overlay would draw every surface twice, and the phone's budget is in draw
## calls:
## docs/research/recut-skin.md). A surface whose material is not a plain opaque `BaseMaterial3D`
## (a glass, a
## shader of its own) is left as it is. Taking the skin off puts back what each surface had.
##
## It owns nothing in the tree and reads no clock (the shader has its own `TIME`): `reveal` and
## `boost` are set
## by whoever drives it.

## The meta on the weapon's root that holds the skin it wears.
const META := &"recut_skin"
const SHADER := preload("res://gameplay/weapons/fx/recut_skin.gdshader")

## 0 to 1: how far the skin has swept over the weapon, butt to muzzle (1 is simply worn).
var reveal := 1.0:
	set(value):
		reveal = clampf(value, 0.0, 1.0)
		_set_all(&"reveal", reveal)
## A flash over everything, 0 for none.
var boost := 0.0:
	set(value):
		boost = maxf(value, 0.0)
		_set_all(&"boost", boost)

var _root: Node3D
var _style: RecutStyle
## One per skinned surface: {mesh, index, original (the surface's override before), material}.
var _surfaces: Array[Dictionary] = []


## Puts the skin on every plain surface under `root` and returns it (the one already worn when
## there is
## one: its reveal is set to `start`). `start` 1 shows the finished skin, 0 none of it yet.
static func wear(root: Node3D, start: float = 1.0, style: RecutStyle = null) -> RecutSkin:
	var worn := worn_by(root)
	if worn != null:
		worn.reveal = start
		return worn
	var skin := RecutSkin.new()
	skin._style = style if style != null else RecutStyle.shipped()
	skin._root = root
	skin._cover(root, Transform3D.IDENTITY)
	skin._span()
	skin.reveal = start
	root.set_meta(META, skin)
	return skin


## The skin `root` wears, or null.
static func worn_by(root: Node) -> RecutSkin:
	if root == null or not root.has_meta(META):
		return null
	var skin := root.get_meta(META) as RecutSkin
	return skin if skin != null and not skin._surfaces.is_empty() else null


## Takes the skin off `root`, whatever it wears; nothing when it wears none.
static func strip(root: Node) -> void:
	var skin := worn_by(root)
	if skin != null:
		skin.take_off()
	elif root != null and root.has_meta(META):
		root.remove_meta(META)


## How many surfaces wear the skin.
func surface_count() -> int:
	return _surfaces.size()


## The materials the skin made, one per surface it covers.
func materials() -> Array[ShaderMaterial]:
	var found: Array[ShaderMaterial] = []
	for entry in _surfaces:
		found.append(entry["material"])
	return found


## Puts every surface back as it was and forgets the skin.
func take_off() -> void:
	for entry in _surfaces:
		var mesh := entry["mesh"] as MeshInstance3D
		if is_instance_valid(mesh):
			mesh.set_surface_override_material(entry["index"], entry["original"])
	_surfaces.clear()
	if is_instance_valid(_root) and _root.has_meta(META):
		_root.remove_meta(META)


## A surface the skin can stand in for: an opaque `BaseMaterial3D` (or none: the engine's own
## white).
static func can_cover(material: Material) -> bool:
	if material == null:
		return true
	return (
		material is BaseMaterial3D
		and (material as BaseMaterial3D).transparency == BaseMaterial3D.TRANSPARENCY_DISABLED
	)


func _cover(node: Node, to_root: Transform3D) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		_cover_mesh(node as MeshInstance3D, to_root)
	for child in node.get_children():
		if child is Node3D:
			_cover(child, to_root * (child as Node3D).transform)


func _cover_mesh(mesh: MeshInstance3D, to_root: Transform3D) -> void:
	# A mesh that has a material of its own over the whole of it (an outline or a glow) keeps it.
	if mesh.material_override != null:
		return
	for index in mesh.mesh.get_surface_count():
		var original := mesh.get_surface_override_material(index)
		var own := original if original != null else mesh.mesh.surface_get_material(index)
		if not can_cover(own):
			continue
		var material := _material_for(own as BaseMaterial3D, to_root)
		mesh.set_surface_override_material(index, material)
		_surfaces.append({"mesh": mesh, "index": index, "original": original, "material": material})


func _material_for(own: BaseMaterial3D, to_root: Transform3D) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SHADER
	if own != null:
		material.set_shader_parameter(&"palette", own.albedo_texture)
		material.set_shader_parameter(&"base_colour", own.albedo_color)
		material.set_shader_parameter(&"base_metallic", own.metallic)
		material.set_shader_parameter(&"base_roughness", own.roughness)
	material.set_shader_parameter(&"to_root", Projection(to_root))
	var style := parameters(_style)
	for name: StringName in style:
		material.set_shader_parameter(name, style[name])
	return material


## The shader's uniforms a style sets (a test holds them to the shader's own list: a name the
## shader does not
## have is a value that is silently never read).
static func parameters(style: RecutStyle) -> Dictionary[StringName, Variant]:
	return {
		&"deep": style.deep,
		&"cold": style.cold,
		&"spark": style.spark,
		&"fringe": style.fringe,
		&"darken": style.darken,
		&"skin_metallic": style.metallic,
		&"skin_roughness": style.roughness,
		&"glow": style.glow,
		&"rim_power": style.rim_power,
		&"cell_size": style.cell_size,
		&"live_share": style.live_share,
		&"blink_rate": style.blink_rate,
		&"wave_frequency": style.wave_frequency,
		&"wave_speed": style.wave_speed,
		&"breath_rate": style.breath_rate,
		&"edge": style.front_width,
	}


## The model's length along X, in the weapon's own units, for the sweep: from the lowest to the
## highest X of
## every covered mesh, in the weapon's space.
func _span() -> void:
	var low := INF
	var high := -INF
	for entry in _surfaces:
		var mesh := entry["mesh"] as MeshInstance3D
		var material := entry["material"] as ShaderMaterial
		var to_root := Transform3D(Projection(material.get_shader_parameter(&"to_root")))
		var box := to_root * mesh.get_aabb()
		low = minf(low, box.position.x)
		high = maxf(high, box.end.x)
	if low > high:
		return
	for entry in _surfaces:
		(entry["material"] as ShaderMaterial).set_shader_parameter(&"span", Vector2(low, high))


func _set_all(parameter: StringName, value: Variant) -> void:
	for entry in _surfaces:
		(entry["material"] as ShaderMaterial).set_shader_parameter(parameter, value)
