class_name WeaponHold
extends Resource
## How one weapon sits on the Soldier: its size, where it rests in the aim pose and where the
## support hand goes. Data, one `.tres` per weapon class in `holds/` (docs/design/weapon-hold.md
## has the rule and the numbers); `WeaponHandsIK` and `PlayerAnimation` read it, no weapon has
## code of its own.

## The size rule: a weapon is its real length, scaled by the Soldier's height over a person's,
## and a little more so that it reads (the kit's guns are chunky). One rule, every weapon.
const CHARACTER_HEIGHT := 1.4
const PERSON_HEIGHT := 1.75
const CHUNK := 1.1

## The class the clips are named after (Rifle, Shotgun, Melee).
@export var weapon_class: StringName = &""
## The model scene, origin on the grip, muzzle along its -X, up along +Y.
@export_file("*.glb") var scene := ""
## Size of the model in the hand, on top of the Soldier's own scale (the model is drawn at the
## weapon's real length; the rule is `real length x character height / 1.75 m x chunk`).
@export var model_scale := 1.0
## The weapon's real length in metres, kept so the rule can be checked (docs, tests).
@export var real_length := 1.0
## The model's length along its muzzle axis, at its own scale (the glb's bounds).
@export var model_length := 1.0
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
@export var pitch_offset_deg := 0.0


## The model's length in the game, in metres, with the Soldier's own scale `character_scale`.
func world_length(character_scale: float) -> float:
	return model_length * model_scale * character_scale


## The length the rule asks for, in metres: the real length at the Soldier's size.
func rule_length() -> float:
	return real_length * CHARACTER_HEIGHT / PERSON_HEIGHT * CHUNK
