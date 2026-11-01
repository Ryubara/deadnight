class_name TouchLook
extends RefCounted
## Turns a finger's drag into the look the mouse would make. The result is in "mouse pixels", so
## the player's own sensitivity setting, the ADS slow-down and invert Y all still apply.
##
## The drag is measured against the screen's height, so a phone and a tablet turn the same for the
## same swipe: at sensitivity 1 a swipe across the full height turns the view `RADIANS_PER_HEIGHT`.
## A fast flick gains up to `MAX_GAIN` times (to turn round in one swipe), a slow drag stays 1:1
## (to aim).

const RADIANS_PER_HEIGHT := 3.2
## Finger speeds, in canvas units per second, between which the gain rises from 1 to MAX_GAIN.
const SLOW_SPEED := 450.0
const FAST_SPEED := 2400.0
const MAX_GAIN := 1.6

static var mouse_radians_per_pixel: float = (
	(load("res://gameplay/player/player_tuning_default.tres") as PlayerTuning)
	. mouse_radians_per_pixel
)


## `relative` is the drag since the last event (canvas units), `speed` the finger's speed in canvas
## units per second, `view_height` the canvas height.
static func mouse_equivalent(relative: Vector2, speed: float, view_height: float) -> Vector2:
	var gain := lerpf(1.0, MAX_GAIN, clampf(inverse_lerp(SLOW_SPEED, FAST_SPEED, speed), 0.0, 1.0))
	var radians_per_unit := RADIANS_PER_HEIGHT / maxf(view_height, 1.0)
	return relative * gain * radians_per_unit / mouse_radians_per_pixel
