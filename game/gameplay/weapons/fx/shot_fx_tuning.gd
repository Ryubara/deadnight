class_name ShotFxTuning
extends Resource
## How a shot and a flare look: the impact on a wall or a zombie, the flare in flight, the lure
## burning on the ground. Sizes are diameters in metres, times in seconds, colours as the
## inspector's picker shows them. The shipped values are in `shot_fx_tuning_default.tres`: edit that
## file in the inspector; `ShotFxTuning.shipped()` is how the views and the tests read it. The look
## and why: `docs/design/shot-feedback.md`.

const SHIPPED_PATH := "res://gameplay/weapons/fx/shot_fx_tuning_default.tres"

@export_group("Impact: sizes")
## The wall spark's diameter (it stays a couple of frames).
@export_range(0.01, 0.5, 0.005, "suffix:m") var spark_size: float = 0.09
## Rendered frames a spark stays.
@export_range(1, 10, 1, "suffix:frames") var spark_frames: int = 2
## The dust puff on a wall grows from this diameter to `dust_to`.
@export_range(0.01, 0.5, 0.005, "suffix:m") var dust_from: float = 0.09
@export_range(0.01, 0.5, 0.005, "suffix:m") var dust_to: float = 0.2
## The dark dot a wall keeps.
@export_range(0.01, 0.5, 0.005, "suffix:m") var mark_size: float = 0.045
## The blood puff on a zombie grows from this diameter to `blood_to`.
@export_range(0.01, 0.5, 0.005, "suffix:m") var blood_from: float = 0.06
@export_range(0.01, 0.5, 0.005, "suffix:m") var blood_to: float = 0.14
## Quads are nudged this far toward the camera so a wall does not cut them in half.
@export_range(0.0, 0.3, 0.005, "suffix:m") var lift: float = 0.04

@export_group("Impact: times")
## How long the dust puff swells.
@export_range(0.05, 3.0, 0.01, "suffix:s") var dust_seconds: float = 0.28
## How long the dark dot lingers.
@export_range(0.05, 5.0, 0.05, "suffix:s") var mark_seconds: float = 0.8
## How long the blood puff swells.
@export_range(0.05, 3.0, 0.01, "suffix:s") var blood_seconds: float = 0.22

@export_group("Impact: colours")
@export var dust_colour: Color = Color(0.62, 0.58, 0.5)
@export var dust_light_colour: Color = Color(0.82, 0.78, 0.68)
@export var mark_colour: Color = Color(0.1, 0.085, 0.08, 0.85)
@export var blood_colour: Color = Color(0.42, 0.03, 0.05)
@export var blood_light_colour: Color = Color(0.68, 0.1, 0.1)

@export_group("Flare in flight")
## The core is drawn this many times the shot's hit radius, so it reads from the shoulder camera.
@export_range(0.5, 5.0, 0.05) var flare_core_scale: float = 1.3
## The halo's size in hit radii, and how see-through it is.
@export_range(0.5, 10.0, 0.05) var flare_halo_scale: float = 3.5
@export_range(0.0, 1.0, 0.01) var flare_halo_alpha: float = 0.28
@export var flare_core_colour: Color = Color(1.0, 0.82, 0.55)
@export var flare_halo_colour: Color = Color(1.0, 0.45, 0.18)
## How far the halo shrinks at the bottom of a flicker (0 steady, 1 vanishes), and the two rates
## (radians per second) whose product makes the flicker uneven. It lights nothing: a light per flare
## would take a slot the lot's light cap keeps for a flash and a blast.
@export_range(0.0, 1.0, 0.01) var flare_flicker_depth: float = 0.3
@export_range(0.0, 100.0, 0.5, "suffix:rad/s") var flare_flicker_rate_a: float = 31.0
@export_range(0.0, 100.0, 0.5, "suffix:rad/s") var flare_flicker_rate_b: float = 47.0
## A trail dot is dropped every this many steps, fades over `flare_trail_seconds` and is this big.
@export_range(1, 20, 1, "suffix:steps") var flare_trail_every: int = 2
@export_range(0.05, 3.0, 0.05, "suffix:s") var flare_trail_seconds: float = 0.5
@export_range(0.005, 0.5, 0.005, "suffix:m") var flare_trail_radius: float = 0.05

@export_group("Lure on the ground")
@export_range(0.01, 1.0, 0.01, "suffix:m") var lure_core_radius: float = 0.14
@export_range(0.05, 3.0, 0.05, "suffix:m") var lure_halo_radius: float = 0.7
@export_range(0.0, 1.0, 0.01) var lure_halo_alpha: float = 0.3
@export var lure_core_colour: Color = Color(1.0, 0.85, 0.6)
@export var lure_halo_colour: Color = Color(1.0, 0.4, 0.15)
## The glow fades out over the last seconds of the burn.
@export_range(0.05, 5.0, 0.05, "suffix:s") var lure_fade_seconds: float = 1.0
@export_range(0.0, 1.0, 0.01) var lure_flicker_depth: float = 0.35
@export_range(0.0, 100.0, 0.5, "suffix:rad/s") var lure_flicker_rate_a: float = 23.0
@export_range(0.0, 100.0, 0.5, "suffix:rad/s") var lure_flicker_rate_b: float = 37.0
## The flare lies a little off the ground, so its glow is not cut by it.
@export var lure_lift: Vector3 = Vector3(0.0, 0.12, 0.0)

@export_group("Lure embers")
@export_range(0, 64, 1) var lure_ember_count: int = 12
@export_range(0.1, 5.0, 0.05, "suffix:s") var lure_ember_seconds: float = 1.4
@export_range(0.0, 10.0, 0.1, "suffix:m/s") var lure_ember_rise: float = 2.2
@export_range(0.005, 0.5, 0.005, "suffix:m") var lure_ember_size: float = 0.05


## A private copy of the shipped table (`shot_fx_tuning_default.tres`).
static func shipped() -> ShotFxTuning:
	return (load(SHIPPED_PATH) as ShotFxTuning).duplicate(true) as ShotFxTuning
