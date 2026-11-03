class_name BloodTuning
extends Resource
## How blood looks and how much of it there may be: the five kinds of hit (`BloodClass`), what a
## headshot adds, the colours and the caps. The shipped values are in `blood_tuning_default.tres`:
## edit that file in the inspector; `BloodTuning.shipped()` is how the view and the tests read it.
## The look and why: `docs/design/shot-feedback.md#blood`.

enum Kind { BULLET, PELLETS, RIFLE, MELEE, BLAST }

const SHIPPED_PATH := "res://gameplay/weapons/fx/blood_tuning_default.tres"

@export_group("Kinds of hit")
@export var bullet: BloodClass
@export var pellets: BloodClass
@export var rifle: BloodClass
@export var melee: BloodClass
@export var blast: BloodClass
## A gun that hurts this much (per shot, one pellet) bleeds as a rifle does.
@export_range(10.0, 300.0, 1.0) var rifle_from_damage: float = 60.0
## The damage at which a hit is drawn at its full size, and the smallest share of it a light hit
## keeps.
@export_range(1.0, 300.0, 1.0) var damage_full: float = 95.0
@export_range(0.1, 1.0, 0.01) var damage_least: float = 0.7

@export_group("Headshot")
@export_range(1.0, 3.0, 0.05) var head_drops_scale: float = 1.5
@export_range(1.0, 3.0, 0.05) var head_reach_scale: float = 1.3
@export_range(1.0, 3.0, 0.05) var head_size_scale: float = 1.3
@export_range(1.0, 3.0, 0.05) var head_marks_scale: float = 1.4
## The share of the drops flung back as well, at least.
@export_range(0.0, 1.0, 0.01) var head_back: float = 0.35

@export_group("Colours")
@export var blood_colour: Color = Color(0.5, 0.025, 0.04)
@export var blood_light_colour: Color = Color(0.82, 0.1, 0.1)
@export var head_colour: Color = Color(0.62, 0.03, 0.05)
@export var head_light_colour: Color = Color(0.95, 0.16, 0.14)
## A mark that has dried is this colour.
@export var dried_colour: Color = Color(0.2, 0.02, 0.03)

@export_group("Splash")
## The splash is drawn this far toward the camera, so the zombie's own body does not cut it.
@export_range(0.0, 1.0, 0.01, "suffix:m") var splash_lift: float = 0.3

@export_group("Marks")
## Seconds a ground or wall mark stays before it is gone; it fades over the last share of it.
@export_range(1.0, 120.0, 0.5, "suffix:s") var mark_seconds: float = 30.0
@export_range(0.05, 1.0, 0.01) var mark_fade_share: float = 0.4
## The most marks alive at once on a desktop and in the browser; one past it takes the oldest.
@export_range(4, 256, 1) var marks_desktop: int = 64
@export_range(4, 256, 1) var marks_web: int = 32
## The most splashes alive at once.
@export_range(4, 64, 1) var splashes: int = 24
## A mark is looked for this far along the shot, and this far down from the wound.
@export_range(0.5, 20.0, 0.1, "suffix:m") var wall_reach: float = 3.5
@export_range(0.5, 10.0, 0.1, "suffix:m") var ground_reach: float = 3.0
## A rifle shot or a headshot reaches a wall this much farther.
@export_range(1.0, 4.0, 0.1) var strong_reach_scale: float = 1.6
## How far a ground mark lands from the zombie's feet along the shot, at most.
@export_range(0.0, 3.0, 0.05, "suffix:m") var ground_throw: float = 1.1
## Marks are lifted off the surface this far, plus this much for each metre of distance to the
## camera, so they do not flicker in the depth buffer.
@export_range(0.001, 0.05, 0.001, "suffix:m") var mark_lift: float = 0.01
@export_range(0.0, 0.01, 0.0001) var mark_lift_per_metre: float = 0.002
## A surface whose normal points up at least this much is a floor (else a wall).
@export_range(0.3, 0.95, 0.01) var floor_normal_y: float = 0.7


## A private copy of the shipped table (`blood_tuning_default.tres`).
static func shipped() -> BloodTuning:
	return (load(SHIPPED_PATH) as BloodTuning).duplicate(true) as BloodTuning


## Which kind of hit this is: a melee blow, a gun that fires several pellets, a hard hitter or any
## other bullet. `def` may be null (an event from an older server).
func kind_of(def: WeaponDef, is_melee: bool) -> Kind:
	if is_melee:
		return Kind.MELEE
	if def == null:
		return Kind.BULLET
	if def.pellets > 1:
		return Kind.PELLETS
	if def.damage >= rifle_from_damage:
		return Kind.RIFLE
	return Kind.BULLET


func class_of(kind: Kind) -> BloodClass:
	match kind:
		Kind.PELLETS:
			return pellets
		Kind.RIFLE:
			return rifle
		Kind.MELEE:
			return melee
		Kind.BLAST:
			return blast
	return bullet
