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
## Height of the camera pivot above the player's feet (about the head).
@export var pivot_height := 1.6
## Sideways offset of the shoulder camera, in metres, and the same while aiming.
@export var shoulder_offset := 0.6
@export var shoulder_offset_aim := 0.65
## Distance behind the pivot, in metres, and the same while aiming.
@export var arm_length := 2.3
@export var arm_length_aim := 1.8
## Vertical field of view in degrees, and the same while aiming.
@export var fov := 70.0
@export var fov_aim := 60.0
## Radius of the sphere swept from the pivot to the lens, so the camera never clips a wall.
@export var arm_margin := 0.25
## The body is hidden when the lens is closer than this to the head, shown again beyond the
## second (a little more, so it does not flicker at the edge).
@export var hide_body_distance := 0.9
@export var show_body_distance := 1.05

@export_group("Camera motion")
## Springs are critically damped: the number is the angular frequency in rad/s, and the camera
## closes 95 percent of a step in 4.75 divided by it seconds (docs/research/shoulder-camera.md).
## The pivot's follow of the body on the ground plane and vertically (slower, so a jump does not
## whip the view), and the follow while sprinting (looser, so speed shows as lag).
@export var follow_frequency := 22.0
@export var follow_frequency_vertical := 10.0
@export var sprint_follow_frequency := 16.0
## Aim zoom, shoulder swap and sprint pull-back.
@export var aim_frequency := 24.0
@export var swap_frequency := 16.0
@export var sprint_frequency := 9.0
## Sprint widens the view by this many degrees and lets the camera out by this many metres.
@export var sprint_fov_kick := 6.0
@export var sprint_arm_extra := 0.3
## A wall pulls the camera in at once; this is the rate (per second) it lets out again.
@export var release_frequency := 6.0
## The view turns toward a steered yaw and pitch (the autopilot's) with this spring.
@export var steer_frequency := 18.0
## A body that moves farther than this in one tick (a spawn, a correction) is not eased to.
@export var snap_distance := 4.0

@export_group("Shake")
## The view shake of a shot, trauma style (`CameraShake`; the amount per weapon is its
## `WeaponDef.shake_trauma`). Trauma drains at this much per second (1 is a full second from the
## top), and the shake is `max_degrees x trauma^exponent x noise`. Subtle on purpose: a shotgun
## blast turns the view by well under a degree. The player scales all of it, or turns it off, in
## the settings (Accessibility).
@export var shake_max_degrees := 1.5
@export var shake_decay := 2.6
@export var shake_exponent := 2.0
## How fast the noise moves, in noise units per second (about this many wobbles a second).
@export var shake_frequency := 14.0
## The roll about the view axis, as a fraction of the pitch and yaw (roll reads as nausea).
@export_range(0.0, 1.0) var shake_roll_fraction := 0.4

@export_group("Sprint sway")
## The gentle sway of the view while sprinting (`SprintSway`): a bob (pitch) every `bob_steps`
## footfalls, and a roll and yaw (a quarter turn apart) every `sway_steps` footfalls. A footfall is
## `step_distance` metres of travel, so the rate follows ground speed like the Run clip does.
## Subtle on purpose: the peaks are under half a degree. The camera shake setting scales it and
## Reduced motion turns it off. Amounts are degrees.
@export var sprint_sway_pitch_degrees := 0.3
@export var sprint_sway_yaw_degrees := 0.15
@export var sprint_sway_roll_degrees := 0.2
## Footfalls for one full bob (1: the head dips on every foot) and for one full roll and yaw (2:
## once per left and right stride).
@export var sprint_sway_bob_steps := 1.0
@export var sprint_sway_sway_steps := 2.0
## Where in the stride a foot lands, as a turn of the bob and the sway.
@export var sprint_sway_phase_degrees := 0.0
## Seconds to ease the sway in when the sprint starts and out when it stops.
@export var sprint_sway_ease_in := 0.4
@export var sprint_sway_ease_out := 0.3
## No sway below this ground speed (m/s), whatever the sprint state says.
@export var sprint_sway_min_speed := 3.0
## While a shot shakes the view the sway gives way by up to this fraction (at full trauma), so the
## two add up without fighting.
@export_range(0.0, 1.0) var sprint_sway_fire_duck := 0.5
