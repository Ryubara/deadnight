class_name LookSmoother
extends RefCounted
## Spreads a finger's look over the frames it is drawn in (#598).
##
## A touch screen reports the finger at its own rate (60 or 120 times a second) and the page draws
## at another, never an even number of samples per frame. Applied as they arrive, the same steady
## drag turned the view in jumps: a frame with a sample turned the whole step, the frames between
## turned nothing (measured in the web build: 2 of 3 frames still, the biggest step 3 times the
## mean). The look waits here instead, and each frame lets out a share of what is waiting, so the
## view moves every frame at the finger's own speed and ends where the finger put it.
##
## The share is the frame's length over a window: `time_constant` seconds, or `frames` frames when
## the page is slow (a window shorter than a few frames cannot even out samples that fall unevenly
## between them). A window of N frames is a delay of about N frames behind the finger. Zero
## `time_constant` lets everything out at once, as before.

## Under this (mouse pixels) the rest goes out at once, so a tail never creeps for ever.
const REST := 0.02
## How fast the average frame length follows the frames (0 to 1 per frame).
const FRAME_FOLLOW := 0.1
## A frame this long is a hitch, not the page's pace: it does not stretch the window.
const MAX_PACE := 0.1

## What is still to be turned, in mouse pixels.
var pending := Vector2.ZERO
## The window in seconds at the least. `TouchTuning.look_smoothing`.
var time_constant := 0.04
## The window in frames at the least. `TouchTuning.look_smoothing_frames`.
var frames := 2.5

var _pace := 0.0


## A new step of the drag, in mouse pixels.
func add(motion: Vector2) -> void:
	pending += motion


## What to turn this frame, which lasted `delta` seconds; takes it out of `pending`.
func step(delta: float) -> Vector2:
	if time_constant <= 0.0:
		return take_all()
	var seen := minf(delta, MAX_PACE)
	_pace = seen if _pace == 0.0 else lerpf(_pace, seen, FRAME_FOLLOW)
	# A share proportional to the frame's length (all of it once the frame is longer than the window),
	# so a drag at a steady speed turns a steady angle per second whatever the frames take: the share
	# of an exponential would turn a long frame less than its length asks.
	var window := maxf(time_constant, frames * _pace)
	var out := pending * clampf(delta / window, 0.0, 1.0)
	if (pending - out).length() < REST:
		return take_all()
	pending -= out
	return out


## Everything that is waiting, at once (a finger that lifted for good, a menu that opened).
func take_all() -> Vector2:
	var out := pending
	pending = Vector2.ZERO
	return out


func is_idle() -> bool:
	return pending == Vector2.ZERO
