class_name TouchTuning
extends Resource
## The feel of the touch controls in one resource: how a finger's drag turns the view, and when the
## stick sprints. Layout (where the buttons sit and how big) is `TouchLayout`, not tuning. The
## shipped values are in `touch_tuning_default.tres`: edit that file in the inspector;
## `TouchTuning.shipped()` is how the game and the tests read it.

const SHIPPED_PATH := "res://ui/touch/touch_tuning_default.tres"

@export_group("Look")
## A swipe across the full screen height turns the view this many radians at sensitivity 1 (the
## player's own sensitivity setting scales it). Half a turn is about two heights.
@export_range(0.2, 6.0, 0.05, "suffix:rad") var radians_per_height := 1.6
## Finger speeds (canvas units per second) between which the gain rises from 1 to `max_gain`:
## slower than this a drag stays 1:1, to aim.
@export_range(0.0, 3000.0, 10.0, "suffix:/s") var slow_speed := 450.0
## ... and at this speed and above a flick has the whole `max_gain`.
@export_range(0.0, 6000.0, 10.0, "suffix:/s") var fast_speed := 2400.0
## How much a fast flick turns more than a slow drag, to turn round in one swipe.
@export_range(1.0, 4.0, 0.05, "suffix:x") var max_gain := 1.6
## A finger's speed is trusted after this many drags (the first reads wrongly after a jump from
## another position).
@export_range(0, 10, 1) var velocity_warmup_drags := 3
## The view follows the finger this far behind, so a finger sampled at one rate and a page drawn at
## another still turn it every frame, evenly (`LookSmoother`, #598). 0 turns the view the moment a
## sample arrives.
@export_range(0.0, 0.2, 0.005, "suffix:s") var look_smoothing := 0.04
## ... and on a page that draws slowly, at least this many frames behind: a shorter window cannot
## even out samples that fall unevenly between few frames.
@export_range(1.0, 6.0, 0.1, "suffix:frames") var look_smoothing_frames := 2.5

@export_group("Stick")
## The stick's dead zone, as a share of its radius.
@export_range(0.0, 0.5, 0.01) var stick_deadzone := 0.1
## Pushing the stick to this share of its radius starts a sprint ...
@export_range(0.5, 1.0, 0.01) var sprint_on := 0.95
## ... and easing under this share ends it.
@export_range(0.3, 1.0, 0.01) var sprint_off := 0.75

@export_group("Buttons")
## A press lasts at least this long, so a quick tap is still seen by the next physics tick.
@export_range(0.0, 0.5, 0.01, "suffix:s") var min_hold := 0.09
## How often the safe area is read again (the notch and the browser's bars move).
@export_range(0.05, 5.0, 0.05, "suffix:s") var inset_period := 0.5
## The buzz of a press on a phone.
@export_range(0, 100, 1, "suffix:ms") var haptic_ms := 12


## A private copy of the shipped table (`touch_tuning_default.tres`).
static func shipped() -> TouchTuning:
	return (load(SHIPPED_PATH) as TouchTuning).duplicate(true) as TouchTuning
