class_name TouchLook
extends RefCounted
## Turns a finger's drag into the look the mouse would make. The result is in "mouse pixels", so
## the player's own sensitivity setting, the ADS slow-down and invert Y all still apply.
##
## The drag is measured against the screen's height, so a phone and a tablet turn the same for the
## same swipe: at sensitivity 1 a swipe across the full height turns the view
## `TouchTuning.radians_per_height` (half a turn is about two heights, a little under one width of a
## phone). A fast flick gains up to `max_gain` times (to turn round in one swipe), a slow drag stays
## 1:1 (to aim). The numbers are `touch_tuning_default.tres`.
##
## Only this layer may turn the view by touch. The browser also reports a finger as a pointer
## move, and Godot's web runtime reads every pointer move as a mouse motion, in device pixels
## (#470): while the layer is up, a mouse motion that is not the layer's own (`DEVICE`) is a
## stray copy of a finger, and `is_stray` says so.

## The `device` of the mouse motion the layer sends, so the player can tell it from the browser's.
const DEVICE := 0x7468

## True while the touch layer is up (set by `TouchControls`).
static var layer_up := false
## The look numbers; `TouchControls` reads the same resource for the stick and the buttons.
static var tuning: TouchTuning = load(TouchTuning.SHIPPED_PATH)
static var mouse_radians_per_pixel: float = (
	(load("res://gameplay/player/player_tuning_default.tres") as PlayerTuning)
	. mouse_radians_per_pixel
)


## `relative` is the drag since the last event (canvas units), `speed` the finger's speed in canvas
## units per second, `view_height` the canvas height.
static func mouse_equivalent(relative: Vector2, speed: float, view_height: float) -> Vector2:
	var blend := clampf(inverse_lerp(tuning.slow_speed, tuning.fast_speed, speed), 0.0, 1.0)
	var gain := lerpf(1.0, tuning.max_gain, blend)
	var radians_per_unit := tuning.radians_per_height / maxf(view_height, 1.0)
	return relative * gain * radians_per_unit / mouse_radians_per_pixel


## A mouse motion that is not the layer's own, with the layer up and a finger the last input: the
## browser's copy of a finger. A real mouse on a tablet still turns the view once it has clicked
## (a click makes the mouse the last input).
static func is_stray(event: InputEvent) -> bool:
	return (
		layer_up and UIInputMode.touch and event is InputEventMouseMotion and event.device != DEVICE
	)
