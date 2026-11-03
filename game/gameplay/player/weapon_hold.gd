class_name WeaponHold
extends Resource
## How one weapon sits on the Soldier: its size, where it rests in the aim pose and where the
## support hand goes. Data, one `.tres` per weapon class in `holds/` (docs/design/weapon-hold.md
## has the rule and the numbers); `WeaponHandsIK` and `PlayerAnimation` read it, no weapon has
## code of its own.

## The size rule: a weapon is its real length, scaled by the Soldier's height over a person's,
## and a third more, as the kit draws its guns for the Soldier's big hands (its AK is 1.33 times a
## real one beside him). One rule, every weapon; a small gun whose grip would vanish in the fist
## is drawn larger still (`size_factor`: docs/design/weapon-hold.md, "The size rule").
const CHARACTER_HEIGHT := 1.4
const PERSON_HEIGHT := 1.75
const CHUNK := 1.3

## The class the clips are named after (Rifle, Shotgun, Melee).
@export var weapon_class: StringName = &""
## The model scene, origin on the grip, muzzle along its -X, up along +Y.
@export_file("*.glb") var scene := ""
## Size of the model in the hand, on top of the Soldier's own scale (the model is drawn at the
## weapon's real length; the rule is `real length x character height / 1.75 m x chunk`).
@export_range(0.1, 5.0, 0.01, "or_greater", "suffix:x") var model_scale := 1.0
## How many times the size rule this weapon is drawn at: 1 is the rule. A gun whose pistol grip
## is shorter than the Soldier's fingers under the trigger finger (the revolver, the flare gun) is
## drawn larger until it fills them (docs/design/weapon-hold.md, "The size rule").
@export_range(0.1, 5.0, 0.01, "or_greater", "suffix:x") var size_factor := 1.0
## The weapon's real length in metres, kept so the rule can be checked (docs, tests).
@export_range(0.05, 5.0, 0.01, "or_greater", "suffix:m") var real_length := 1.0
## The model's length along its muzzle axis, at its own scale (the glb's bounds).
@export_range(0.05, 5.0, 0.01, "or_greater", "suffix:m") var model_length := 1.0
## Whether the arms are posed to hold it at the shoulder (guns) or the clip keeps the arm (melee).
@export var shouldered := true
## Where the grip rests, in metres, from the shoulder joint, in the aim's frame: x right, y up,
## z forward is negative (the stock sits against the shoulder behind the grip).
@export var grip_offset := Vector3.ZERO
## The support hand's point on the weapon, in the model's own units (origin the grip).
@export var support := Vector3.ZERO
## The muzzle and the butt of the stock, in the model's own units (origin the grip).
@export var muzzle := Vector3.ZERO
@export var butt := Vector3.ZERO
## Degrees the barrel is raised above the aim line (the aim line runs through the crosshair).
@export_range(-90.0, 90.0, 0.5, "or_greater", "suffix:deg") var pitch_offset_deg := 0.0
## A second copy of the model in the left hand, mirrored: the dual pistols. `grip_offset` is the
## right gun's (from the right shoulder joint); the left gun's is its mirror from the left one, and
## the left hand holds it as the right holds the first (`HandGrip.mirrored`), so both hands close
## on the same grip and the left arm is posed like the right (`WeaponHandsIK`).
@export var dual := false
## Degrees the chest turns while the arms hold the weapon, the left shoulder forward (a shooter's
## stance): the Soldier's arm is short for a two-handed gun's fore-end (docs/design/weapon-hold.md).
@export_range(-180.0, 180.0, 0.5, "or_greater", "suffix:deg") var stance_turn_deg := 0.0


## Whether the model has arrived: a hold file may be ready (class, grip) before its glb is.
func has_model() -> bool:
	return scene != "" and ResourceLoader.exists(scene)


## The model's length in the game, in metres, with the Soldier's own scale `character_scale`.
func world_length(character_scale: float) -> float:
	return model_length * model_scale * character_scale


## The length the rule asks for, in metres: the real length at the Soldier's size.
func rule_length() -> float:
	return real_length * CHARACTER_HEIGHT / PERSON_HEIGHT * CHUNK


## The length this weapon is given: the rule's, times its declared exception (`size_factor`).
func sized_length() -> float:
	return rule_length() * size_factor
