class_name ReloadKey
extends Resource
## One pose of a reload (`ReloadMotion`), at a share of the reload's time: where the weapon is
## moved and turned from the hold the aim weight gives, where the left hand is, how far the
## weapon's moving part is open and whether the ammunition is in the left hand. Between two keys
## every number is eased (a smoothstep); the switches (`part_shown`, `ammo`) hold from their key to
## the next (docs/design/animation.md, Reloading).

## Where the left hand's point is measured from.
enum Space {
	## A point on the weapon, in the model's own units (origin the grip, muzzle along -X, up +Y,
	## the gun's left +Z), the hand turned as on the fore-end (the grip's `left_hand`).
	WEAPON,
	## The belt pouch: metres from the hips, in the body's frame (x right, y up, z back).
	BELT,
}

## Share of the reload's time this pose is reached at, 0 to 1.
@export_range(0.0, 1.0, 0.005) var at := 0.0
## How far the weapon moves from its hold, in metres, in the aim's frame: x right, y up, z back.
@export var weapon_offset := Vector3.ZERO
## How far the weapon turns about the grip, in degrees: x the muzzle up, y the muzzle to the left,
## z the top to the left (a roll about the barrel, seen from behind).
@export var weapon_turn := Vector3.ZERO
## Degrees the chest bends forward over the weapon.
@export_range(-30.0, 45.0, 0.5, "suffix:deg") var chest_lean := 0.0
## Degrees the chest turns about the up axis, the left shoulder forward, on top of the hold's
## stance: the weapon goes out to the right of the head (where the shoulder camera sees it) and
## the left arm still reaches it.
@export_range(-45.0, 60.0, 0.5, "suffix:deg") var chest_turn := 0.0
## How far the left hand is on this key's point, 0 (the hold's own: the fore-end, or the clip's
## arm for a one-handed gun) to 1.
@export_range(0.0, 1.0, 0.01) var left := 0.0
@export var left_space := Space.WEAPON
## The left hand's point (`left_space`'s units).
@export var left_point := Vector3.ZERO
## The point is on the moving part: it opens, slides and turns with it.
@export var left_on_part := false
## How far the weapon's moving part is open, 0 (closed, as modelled) to 1 (`ReloadMotion`'s turn
## and slide).
@export_range(0.0, 1.0, 0.01) var part := 0.0
## The moving part is on the weapon (false: it is in the left hand or gone, as a drum taken off).
@export var part_shown := true
## The ammunition is in the left hand (`ReloadMotion.ammo_scene`).
@export var ammo := false
