class_name MachineParts
extends RefCounted
## Small builders the lot's machines (`RecutMachine`, `SodaFountain`) draw themselves with: boxes,
## cylinders and spheres in a plain or glowing material, a label, and a weapon model fitted to a
## length. Like the prize crane they need no asset: a machine is primitives, and its look is in its
## numbers.

## The weapon model drawn for each catalogue id (the revolver is `pistol`). The crowbar is never
## drawn on a machine.
const WEAPON_MODELS := {
	&"pistol": "res://assets/weapons/revolver/revolver.glb",
	&"smg": "res://assets/weapons/tommy_gun/tommy_gun.glb",
	&"shotgun": "res://assets/weapons/double_shotgun/double_shotgun.glb",
	&"rifle": "res://assets/weapons/lever_rifle/lever_rifle.glb",
	&"flare_gun": "res://assets/weapons/flare_gun/flare_gun.glb",
	&"mp5": "res://assets/weapons/tommy_gun/tommy_gun.glb",
	&"ppsh": "res://assets/weapons/tommy_gun/tommy_gun.glb",
	&"m4a1": "res://assets/weapons/tommy_gun/tommy_gun.glb",
	&"m249": "res://assets/weapons/m249/m249.glb",
	&"fifty_cal": "res://assets/weapons/fifty_cal/fifty_cal.glb",
	&"pump_870": "res://assets/weapons/pump_870/pump_870.glb",
}

## The weapons whose models the bench loads when one is re-cut, not with the night (#793).
const ON_DEMAND: Array[StringName] = [&"mp5", &"ppsh", &"m4a1", &"m249", &"fifty_cal", &"pump_870"]


static func plain(
	colour: Color, roughness: float = 0.7, metallic: float = 0.0
) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = roughness
	material.metallic = metallic
	return material


## A material that lights itself: `energy` is the emission multiplier.
static func glow(colour: Color, energy: float = 1.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.emission_enabled = true
	material.emission = colour
	material.emission_energy_multiplier = energy
	return material


static func box(
	parent: Node3D, part_name: String, size: Vector3, at: Vector3, material: Material
) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _add(parent, part_name, mesh, at, material)


## A cylinder standing on `axis` (Y upright; X or Z lies it down).
static func cylinder(
	parent: Node3D,
	part_name: String,
	radius: float,
	height: float,
	at: Vector3,
	material: Material,
	axis: Vector3.Axis = Vector3.AXIS_Y,
	segments: int = 20
) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = segments
	mesh.rings = 1
	var node := _add(parent, part_name, mesh, at, material)
	if axis == Vector3.AXIS_X:
		node.rotation.z = PI * 0.5
	elif axis == Vector3.AXIS_Z:
		node.rotation.x = PI * 0.5
	return node


static func sphere(
	parent: Node3D, part_name: String, radius: float, at: Vector3, material: Material
) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 14
	mesh.rings = 7
	return _add(parent, part_name, mesh, at, material)


static func label(
	parent: Node3D, text: String, at: Vector3, size: int, colour: Color, outline: Color
) -> Label3D:
	var node := Label3D.new()
	node.text = text
	node.font_size = size
	node.pixel_size = 0.0045
	node.modulate = colour
	node.outline_size = 16
	node.outline_modulate = outline
	node.position = at
	parent.add_child(node)
	return node


## The model of a catalogue weapon, fitted to `length` metres along X and centred on its holder, or
## null when there is no model for it.
static func weapon_model(weapon_id: StringName, length: float) -> Node3D:
	if not WEAPON_MODELS.has(weapon_id):
		return null
	var scene := load(WEAPON_MODELS[weapon_id]) as PackedScene
	if scene == null:
		return null
	var holder := Node3D.new()
	var model := scene.instantiate() as Node3D
	holder.add_child(model)
	fit(model, length)
	return holder


## Scales and centres a model so its longest side is `length` metres, lying along X.
static func fit(model: Node3D, length: float) -> void:
	var bounds := _bounds(model, Transform3D.IDENTITY)
	if bounds.size == Vector3.ZERO:
		return
	var turn := bounds.size.z > bounds.size.x
	var longest := maxf(bounds.size.x, bounds.size.z) if turn else bounds.size.x
	longest = maxf(longest, bounds.size.y)
	var factor := length / maxf(longest, 0.001)
	model.basis = (
		Basis(Vector3.UP, PI * 0.5 if turn else 0.0) * Basis.from_scale(Vector3.ONE * factor)
	)
	model.position = -(model.basis * bounds.get_center())


static func _bounds(node: Node, to_root: Transform3D) -> AABB:
	var bounds := AABB()
	var first := true
	if node is MeshInstance3D:
		bounds = to_root * (node as MeshInstance3D).get_aabb()
		first = false
	for child in node.get_children():
		if child is Node3D:
			var inner := _bounds(child, to_root * (child as Node3D).transform)
			if inner.size != Vector3.ZERO:
				bounds = inner if first else bounds.merge(inner)
				first = false
	return bounds


static func _add(
	parent: Node3D, part_name: String, mesh: Mesh, at: Vector3, material: Material
) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = part_name
	node.mesh = mesh
	node.material_override = material
	node.position = at
	parent.add_child(node)
	return node
