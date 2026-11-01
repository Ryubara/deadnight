class_name CharacterAssembler
extends RefCounted
## Builds a character model from a `CharacterLook`: the Soldier with the look's part options
## switched on, its materials tinted from the palettes, and the seat's armband on the left arm.
##
## Used by the customization preview and by every client for every player in the lot, so it does
## nothing but read the look (no files, no randomness, no time). When the modular parts land, the
## part switch here becomes "instance the part scene of each option"; the callers do not change.

const SOLDIER := "res://assets/characters/soldier/soldier.glb"
## The node the model is built on; the skeleton and its mesh nodes sit below it.
const SKELETON := "Skeleton3D"
## The arm the armband sits on, as a bone attachment of the Soldier's skeleton.
const ARMBAND_BONE := "UpperArm_L"
const ARMBAND_NAME := "Armband"
## The kit Soldier wears its helmet as two surfaces of its Head mesh; a bare head hides them (the
## face, the eyes and the hood stay).
const HEAD_MESH := "Head"
const HELMET_MATERIALS: Array[StringName] = [&"Character_Main", &"Grey"]
## The weapon shown in the right hand of a preview (every weapon is in the file, all visible).
const SHOWN_WEAPON := "Pistol"
## Where the armband sits on the bone (halfway down the arm along the bone's Y axis) and how big
## it is, in the units of the skeleton: the file's armature is scaled by 100.
const ARMBAND_OFFSET := Vector3(0.0, 0.0025, 0.0)
const ARMBAND_RADIUS := 0.0015
const ARMBAND_THICKNESS := 0.0007
## The band is the ring stretched along the arm, so it reads as cloth, not a hoop.
const ARMBAND_STRETCH := 2.4
## Light the armband gives off, so it reads in the dark (not enough to cast light).
const ARMBAND_GLOW := 0.9


## Builds the character. `seat` is the player's place in the lot (0 to 3) and picks the armband.
static func assemble(look: CharacterLook, seat := 0) -> Node3D:
	var model := (load(SOLDIER) as PackedScene).instantiate() as Node3D
	var skeleton := model.find_child(SKELETON, true, false) as Skeleton3D
	_hide_weapons(model)
	_tint(model, look)
	_switch_parts(model, look)
	_add_armband(skeleton, seat)
	return model


## Switches the parts of the look. The kit Soldier is one model, so the only part it can show or
## hide is its helmet; the modular parts replace this with one mesh per part.
static func _switch_parts(model: Node3D, look: CharacterLook) -> void:
	if look.parts[&"headwear"] == &"helmet":
		return
	var head := model.find_child(HEAD_MESH, true, false) as MeshInstance3D
	var hidden := StandardMaterial3D.new()
	hidden.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hidden.albedo_color = Color(1.0, 1.0, 1.0, 0.0)
	for surface in head.mesh.get_surface_count():
		var source := head.mesh.surface_get_material(surface)
		if source != null and HELMET_MATERIALS.has(StringName(source.resource_name)):
			head.set_surface_override_material(surface, hidden)


static func _hide_weapons(model: Node3D) -> void:
	for weapon in model.find_child("Index1_R", true, false).get_children():
		if weapon is MeshInstance3D:
			(weapon as MeshInstance3D).visible = weapon.name == SHOWN_WEAPON


## Gives each body mesh its own copies of the materials, coloured from the look. Only the body,
## head and pads are tinted; the shared materials (and the weapons) are left alone.
static func _tint(model: Node3D, look: CharacterLook) -> void:
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		var instance := mesh as MeshInstance3D
		if (
			instance.name == &"Body"
			or instance.name == &"Head"
			or instance.name.begins_with("Shoulder")
		):
			for surface in instance.mesh.get_surface_count():
				_tint_surface(instance, surface, look)


static func _tint_surface(instance: MeshInstance3D, surface: int, look: CharacterLook) -> void:
	var source := instance.mesh.surface_get_material(surface) as BaseMaterial3D
	if source == null:
		return
	var slot: StringName = LookCatalog.MATERIAL_CHANNELS.get(StringName(source.resource_name), &"")
	if slot == &"":
		return
	var copy := source.duplicate() as BaseMaterial3D
	copy.albedo_color = look.colour(slot)
	instance.set_surface_override_material(surface, copy)


static func _add_armband(skeleton: Skeleton3D, seat: int) -> void:
	var holder := skeleton.find_child(ARMBAND_BONE, false, false) as Node3D
	if holder == null:
		return
	var ring := TorusMesh.new()
	ring.inner_radius = ARMBAND_RADIUS - ARMBAND_THICKNESS
	ring.outer_radius = ARMBAND_RADIUS
	var band := MeshInstance3D.new()
	band.name = ARMBAND_NAME
	band.mesh = ring
	band.position = ARMBAND_OFFSET
	band.scale = Vector3(1.0, ARMBAND_STRETCH, 1.0)
	var colour := LookCatalog.armband_colour(seat)
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.emission_enabled = true
	material.emission = colour
	material.emission_energy_multiplier = ARMBAND_GLOW
	ring.material = material
	holder.add_child(band)
