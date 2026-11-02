class_name AimAssistTuning
extends Resource
## Every number of the touch aim assist (`AimAssist`), in one resource. Distances are metres at the
## target, angles radians, rates per second. The player's own strength (0 to 1, the setting
## `controls/touch_aim_assist`) scales what is here; the reasoning and the measured effect are in
## docs/research/aim-assist.md.

@export_group("Reach")
## Beyond this distance from the lens a zombie is not helped.
@export var reach := 30.0
## A zombie more than this far off the view's axis (cosine of the angle) is not helped.
@export_range(0.0, 1.0, 0.05) var front_cos := 0.5
## How high above a walker's feet the assist aims: the chest, the middle of the body zone.
@export var aim_height := 1.2

@export_group("Capture")
## How far from the aim point the crosshair's ray may pass for the assist to act, at full strength.
@export var capture_metres := 1.1
## The share of `capture_metres` left at strength near zero (it grows to the whole at 1).
@export_range(0.0, 1.0, 0.05) var capture_floor := 0.4

@export_group("Friction")
## The look drag's slow-down at the middle of a zombie, at full strength (0.6 keeps 40 percent of
## the drag).
@export_range(0.0, 0.9, 0.05) var friction_max := 0.6

@export_group("Magnetism")
## Per second, how much of the angle between the crosshair and the aim point is closed, at full
## strength and at the middle of the capture.
@export var magnetism_gain := 5.0
## The fastest the pull may turn the view, radians per second, at full strength.
@export var magnetism_max_rate := 0.9
## A turn by the player faster than this (radians per second) is theirs: the pull is gone at it,
## and half gone at half of it, so a flick is never fought.
@export var flick_speed := 2.0

@export_group("Auto-fire")
## The farthest a zombie may be for the trigger to pull itself, whatever the weapon reaches:
## ammunition is limited.
@export var auto_fire_reach := 25.0

@export_group("Balance simulator")
## How much of the shots a modelled thumb misses the assist at full strength wins back (a share
## of `1 - accuracy`). Measured with the thumb bot (`test_aim_assist_bot.gd`); the test fails when
## the assist drifts from it.
@export_range(0.0, 1.0, 0.01) var accuracy_gain := 0.39
## How the win grows with the strength: gain = `accuracy_gain` * strength ^ this. Above 1, so the
## default strength is gentle and the top of the slider is where the help is large.
@export_range(1.0, 3.0, 0.05) var accuracy_curve := 1.8
