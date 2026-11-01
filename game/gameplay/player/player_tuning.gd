class_name PlayerTuning
extends Resource
## Every number that shapes how the third-person player feels, in one resource.
## Speeds are metres per second, accelerations metres per second squared, angles degrees unless a
## name says radians. The reasoning is in docs/research/player-controller.md.

@export_group("Speed")
@export var run_speed := 4.8
@export var sprint_speed := 7.0
## Speed while aiming; slow enough to feel deliberate.
@export var aim_speed := 2.6

@export_group("Acceleration")
## Speed gained per second while on the ground and steering. 4.8 m/s is reached in about 0.13 s.
@export var ground_acceleration := 38.0
## Speed lost per second while on the ground with no input.
@export var ground_friction := 44.0
## Steering authority in the air; low so a jump commits you to its direction.
@export var air_acceleration := 6.0

@export_group("Facing")
## Radians per second the body turns toward the way it is moving.
@export var turn_speed := 14.0
## Radians per second the body turns to face the aim direction while aiming.
@export var aim_turn_speed := 24.0

@export_group("Jump")
## Height of a full jump, in metres.
@export var jump_height := 1.1
## Multiplier on the project gravity; above 1 gives a snappier, less floaty arc.
@export var gravity_scale := 1.7
## Seconds after leaving a ledge during which a jump is still allowed.
@export var coyote_time := 0.1
## Seconds a jump pressed just before landing is remembered.
@export var jump_buffer_time := 0.1
@export var terminal_velocity := 40.0

@export_group("Body")
@export var height := 1.8
@export var radius := 0.35

@export_group("Animation")
## Ground speed at which the Run clip's feet stay planted at time scale 1
## (the kit has no Walk clip).
@export var run_clip_speed := 5.5
## Ground speed at which the blend from Idle to Run is complete.
@export var run_blend_speed := 2.2
## Metres of travel per footstep event.
@export var step_distance := 1.9
## How quickly animation blends follow their targets, per second.
@export var blend_rate := 12.0
## Visual scale on the Soldier import (see docs/design/style.md: kit characters x0.8).
@export var model_scale := 0.8

@export_group("Look")
## Radians of turn per pixel of mouse motion at sensitivity 1.0.
@export var mouse_radians_per_pixel := 0.0022
## Degrees per second at full stick deflection and sensitivity 1.0.
@export var stick_degrees_per_second := 170.0
@export var pitch_min_degrees := -60.0
@export var pitch_max_degrees := 50.0
@export var stick_deadzone := 0.15
## Look sensitivity while aiming is scaled by this, so aiming is steadier.
@export var aim_sensitivity_scale := 0.7

@export_group("Camera")
## Height of the camera pivot above the player's feet.
@export var pivot_height := 1.55
## Sideways offset of the shoulder camera, in metres.
@export var shoulder_offset := 0.75
@export var shoulder_offset_aim := 0.6
@export var arm_length := 2.8
@export var arm_length_aim := 1.9
@export var fov := 75.0
@export var fov_aim := 62.0
## Radius of the sphere swept along the arm so the camera never clips a wall.
@export var arm_margin := 0.25
## Ease rate (per second) of the shoulder swap, aim zoom and arm length.
@export var swap_rate := 9.0
@export var aim_rate := 10.0
