class_name HandGrip
extends Resource
## How the Soldier's hands hold one weapon model (Deadnight #460): where the model sits in the right
## hand, how every finger of that hand bends round it, and where the left hand takes it and how its
## fingers bend. Data, one file per model in `grips/`, written by the grip solver
## (`game/tests/art/solve_grips.gd`) from the model's own hand sockets (`Grip`, `Trigger`,
## `Support`: docs/design/animation.md, "Grips"); `HandGripPose` puts it on the skeleton and the
## test `test_hand_grips.gd` measures it, so no number here is typed by hand.

const DIR := "res://gameplay/player/grips/"

## The model's transform under the right hand bone (`Index1.R`), before the hold's `model_scale`:
## the weapon node's transform is `hold.scaled_local(Vector3.ONE * model_scale)`.
@export var hold := Transform3D.IDENTITY
## The size the grip was solved at (the hold's `model_scale`); another size needs a new solve.
@export var model_scale := 1.0
## The right hand's bones (`Thumb1.R` and every finger joint) as local pose rotations, the
## palm's roots relative to the hand bone at its rest (see `HandGripPose`).
@export var right := {}
## The parts of the right hand that touch the weapon (`HandContact.PARTS`), and the parts that
## must not touch (none may go into it).
@export var right_contacts := PackedStringArray()
## Where the trigger finger rests: `trigger` (on the trigger), `frame` (straight along the frame,
## off the trigger), or empty for a weapon with no trigger.
@export var trigger_finger := ""
## The left hand bone's (`Index1.L`) transform in the model's own space (origin the grip), or
## `has_left` false for a weapon held in one hand.
@export var has_left := false
@export var left_hand := Transform3D.IDENTITY
@export var left := {}
@export var left_contacts := PackedStringArray()

var _mirrored := {}


## The grip of a model by its scene path (`res://assets/weapons/revolver/revolver.glb` is
## `grips/revolver.tres`), or null when it has none yet.
static func for_scene(scene: String) -> HandGrip:
	return for_name(scene.get_file().get_basename())


## The grip by model name (`revolver`, `grenade` for the grenade shell in the hand).
static func for_name(model: String) -> HandGrip:
	var path := DIR + model + ".tres"
	if not ResourceLoader.exists(path):
		return null
	return load(path) as HandGrip


## The right hand's fingers as the left hand's, for a weapon held in each hand (the dual pistols):
## the rig is an exact mirror (each left bone's rest rotation is its right one's with y and z
## turned about), so a pose is mirrored by the same sign flip, bone by bone. The weapon in the left
## hand is the right one mirrored (`HeldWeapon`), so the same fingers close on it.
func mirrored() -> Dictionary:
	if _mirrored.is_empty():
		for key: String in right:
			var q: Quaternion = right[key]
			_mirrored[key.trim_suffix(".R") + ".L"] = Quaternion(q.x, -q.y, -q.z, q.w)
	return _mirrored
