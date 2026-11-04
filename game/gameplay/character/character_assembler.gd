class_name CharacterAssembler
extends RefCounted
## Builds a character model from a `CharacterLook`: the modular Soldier dressed by `SoldierLook`
## (the parts of the look switched on, one palette material), standing in its idle pose, with the
## armband of the player's seat on the right arm.
##
## Used by the customization preview and by every client for every player in the lot, so it does
## nothing but read the look (no randomness, no time).

const SKELETON := "Skeleton3D"
## The idle clip the character stands in.
const IDLE := "Idle"
## The arm the seat armband goes on, and the bone after it (which gives the arm's direction).
const ARMBAND_BONE := "UpperArm.R"
const ARMBAND_NEXT := "LowerArm.R"
const ARMBAND_NAME := "Armband"
const ARMBAND_BONE_NODE := "ArmbandBone"
## How far down the upper arm the band sits (0 the shoulder, 1 the elbow). At the middle (0.5) it
## sank up to 6 cm into the chest in the menu's pistol hold (#895, `ClipFit`).
const ARMBAND_ALONG := 0.65
## Size of the band in metres: the ring's outer radius and its thickness, stretched along the arm.
const ARMBAND_RADIUS := 0.085
const ARMBAND_THICKNESS := 0.022
const ARMBAND_STRETCH := 2.2
## Light the armband gives off, so it reads in the dark (not enough to cast light).
const ARMBAND_GLOW := 0.9


## Builds the character. `seat` is the player's place in the lot (0 to 7) and picks the armband.
static func assemble(look: CharacterLook, seat := 0) -> Node3D:
	var model := SoldierLook.instantiate()
	dress(model, look, seat)
	var player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if player != null and player.has_animation(IDLE):
		player.get_animation(IDLE).loop_mode = Animation.LOOP_LINEAR
		player.play(IDLE)
	return model


## Puts `look` and the armband of `seat` on a Soldier model that already stands somewhere (a
## player's body, which has its own animation), in place of what it wore before. What the look does
## not wear leaves the model (`SoldierLook.trim`): four bodies and four HUD portraits are alive in a
## night, and each would otherwise hold every part of the catalogue.
static func dress(model: Node, look: CharacterLook, seat := 0) -> void:
	var worn := look.to_soldier_look()
	SoldierLook.apply(model, worn)
	SoldierLook.trim(model, worn)
	var skeleton := model.find_child(SKELETON, true, false) as Skeleton3D
	var band := skeleton.get_node_or_null(ARMBAND_BONE_NODE)
	if band != null:
		skeleton.remove_child(band)
		band.queue_free()
	_add_armband(skeleton, seat)


static func _add_armband(skeleton: Skeleton3D, seat: int) -> void:
	var upper := skeleton.find_bone(ARMBAND_BONE)
	var next := skeleton.find_bone(ARMBAND_NEXT)
	if upper < 0 or next < 0:
		return
	# The arm's direction in the bone's own space, whatever the file's bone axes are.
	var rest := skeleton.get_bone_global_rest(upper)
	var along := rest.basis.inverse() * (skeleton.get_bone_global_rest(next).origin - rest.origin)
	var attachment := BoneAttachment3D.new()
	attachment.name = ARMBAND_BONE_NODE
	skeleton.add_child(attachment)
	attachment.bone_name = ARMBAND_BONE
	var ring := TorusMesh.new()
	ring.inner_radius = ARMBAND_RADIUS - ARMBAND_THICKNESS
	ring.outer_radius = ARMBAND_RADIUS
	var colour := LookCatalog.armband_colour(seat)
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.emission_enabled = true
	material.emission = colour
	material.emission_energy_multiplier = ARMBAND_GLOW
	ring.material = material
	var band := MeshInstance3D.new()
	band.name = ARMBAND_NAME
	band.mesh = ring
	band.position = along * ARMBAND_ALONG
	band.basis = (
		Basis(Quaternion(Vector3.UP, along.normalized()))
		* Basis.from_scale(Vector3(1.0, ARMBAND_STRETCH, 1.0))
	)
	attachment.add_child(band)
