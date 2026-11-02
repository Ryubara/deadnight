class_name PlayerTuning
extends Resource
## Every number that shapes how the third-person player feels, in one resource.
## Speeds are metres per second, accelerations metres per second squared, angles degrees unless a
## name says radians. The reasoning is in docs/research/player-controller.md.

@export_group("Speed")
@export var run_speed := 4.8
## Sprint is available in every direction while not aiming; the body turns to face the way it goes,
## so a sprint toward the camera is a sprint like any other.
@export var sprint_speed := 7.0
## Speed while aiming (the body strafes, facing the view); slow enough to feel deliberate.
@export var aim_speed := 2.6
## The share of the aim speed kept while backing away from the view (1 is no slower than forward).
@export_range(0.3, 1.0, 0.05) var aim_backpedal_scale := 0.75
## The stick or keys must be pushed at least this far (0 to 1) for the sprint key to count, so a
## nudge of the stick does not start a sprint (and its camera pull-back and sway).
@export_range(0.0, 1.0, 0.05) var sprint_min_input := 0.5

@export_group("Acceleration")
## Speed gained per second on the ground while steering below the run speed, and while aiming.
## 4.8 m/s is reached in about 0.13 s.
@export var ground_acceleration := 38.0
## Speed gained per second above the run speed on the way to a sprint: 7 m/s takes about 0.25 s
## from a standstill (0.13 s to the run, then this), so a sprint builds up instead of starting
## at once.
@export var sprint_acceleration := 18.0
## Speed lost per second on the ground with no input, from a run or slower.
@export var ground_friction := 44.0
## The same above the run speed, gentler: a sprint carries on for about 0.7 m after the keys are
## let go (a run for 0.26 m).
@export var sprint_friction := 30.0
## Speed lost per second while input is held but the target is slower (a sprint let go to a run,
## or an aim from a sprint), so the change of pace is eased, not snapped.
@export var ground_deceleration := 30.0
## Steering authority in the air; low so a jump commits you to its direction.
@export var air_acceleration := 6.0

@export_group("Facing")
## Radians per second the body turns toward the way it is moving when not aiming. The velocity
## turns at the same rate, so the body always faces where it goes (no skating) and a change of
## direction is an arc of radius speed / turn_speed (0.34 m at a run).
@export var turn_speed := 14.0
## The same while sprinting: a wider arc (0.78 m at a sprint), more weight.
@export var sprint_turn_speed := 9.0
## Radians per second the body turns to face the view while the aim pose is held (the button, or the
## trigger and `hip_fire_hold` after it). Slow enough that the weapon in the hands, which turns with
## the body, moves a few degrees a tick and never jumps: a view 75 degrees away is faced in 0.16 s.
@export var aim_turn_speed := 8.0

@export_group("Hip fire")
## Firing without aiming turns the body to the view and raises the weapon, with no zoom and no
## camera change (#464, docs/research/hip-fire.md): while the trigger is held, and for
## `hip_fire_hold` after it, the body and the hands hold the aim pose.
## Seconds after the trigger is let go that the pose is still held: the body keeps facing the view,
## so a run of single shots (the slowest weapon fires every 0.9 s) does not swing out and in
## between. After it everything eases out like a released aim button.
@export var hip_fire_hold := 0.8

@export_group("Reload")
## The weapon tilts down about the grip while it reloads and comes back up when it is done, timed to
## the weapon's reload time (`WeaponDef.reload_time`): degrees of the full tilt, and the shares of
## the reload spent going down and coming back up (the rest holds it down).
@export var reload_tilt_degrees := 35.0
@export_range(0.05, 0.45, 0.01) var reload_dip_in := 0.2
@export_range(0.05, 0.45, 0.01) var reload_dip_out := 0.25

@export_group("Pivot")
## A change of direction wider than this (degrees) is a pivot, not an arc: the body plants,
## sheds its speed, turns on the spot, and goes the other way.
@export_range(45.0, 170.0, 5.0) var pivot_angle_degrees := 100.0
## Radians per second the body turns during a pivot (180 degrees in 0.14 s).
@export var pivot_turn_speed := 22.0
## Speed lost per second along the old heading while planting for a pivot (7 m/s in 0.15 s).
@export var pivot_brake := 40.0
## While the body has not yet turned to face a wide change of direction, it moves no faster than
## this (m/s), so it does not moonwalk out of a turn on the spot.
@export var pivot_walk_speed := 1.5
## Below this speed (m/s) the velocity does not steer along an arc: it simply accelerates.
@export var steer_min_speed := 1.0

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

@export_group("Step up")
## The highest ledge the body climbs on its own when it walks into it, in metres. Anything higher
## stays a wall (jump it); a slope is not a ledge and keeps the engine's floor rules.
@export var step_height := 0.3
## Metres of air the lifted body keeps over the ledge's top and over a ceiling, so the tests that
## decide a step do not mistake a touch for a hit. Small against the step height.
@export var step_clearance := 0.02
## A rise below this (metres) is left to the capsule's rounded foot, which rides it by itself.
@export var step_min_rise := 0.02
## Metres of walking after a step during which the body counts as on the floor without touching
## one: the lifted body's rounded foot is still over the ledge's edge for about one body radius,
## and without this it would fall a few centimetres, play the fall and landing, and bounce.
@export var step_settle_distance := 0.5
## The body is lifted onto a ledge in one tick (the simulation, which a server replays), but the
## drawn model eases up: the lag it carries decays at this rate per second (exp), so a climb takes
## about 0.2 s to see (95 percent in 3 / rate) instead of a pop of the step height.
@export var step_view_frequency := 14.0

@export_group("Crouch")
## The capsule's height while crouched (the standing one is `height`); its feet stay where they are.
@export var crouch_height := 1.2
## Walking speed while crouched; every pace (run, aim) is scaled by this over `run_speed`.
@export var crouch_speed := 2.4
## Height of the camera pivot above the feet while crouched (standing: `pivot_height`); the
## pivot's vertical spring eases the change.
@export var crouch_pivot_height := 1.1
## How much of the Walk clip's stepping is laid over the held Duck pose while crouch-walking, at the
## crouch speed (0 slides in the pose, 1 is a standing walk).
@export_range(0.0, 1.0, 0.05) var crouch_walk_blend := 0.6
## The room the stand-up test leaves under a ceiling and around the walls, in metres.
@export var crouch_probe_skin := 0.02

@export_group("Body")
@export var height := 1.8
@export var radius := 0.35

@export_group("Animation")
## Ground speed at which the Run clip's feet stay planted at time scale 1: the speed the planted
## foot sweeps back at over its stance, measured off the clip at `model_scale` (4.28 m/s;
## docs/research/run-clip-speed.md). `tests/player/test_run_gait.gd` fails when it drifts.
@export var run_clip_speed := 4.3
## Ground speed at which the blend from Idle to Run is complete.
@export var run_blend_speed := 2.2
## Metres of travel per footstep event: half the Run clip's cycle (0.708 s) at `run_clip_speed`, so
## a footstep lands when a foot does (held to within 5% by the same test).
@export var step_distance := 1.5
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
## Vertical field of view in degrees, and the same while aiming. The default is 60 (it was 70) and
## the aim view 40 (it was 60): at the maintainer's word, issue #405 ("too far outward", closer to
## the character). The one aim weight blends the two, so a shot from the hip zooms 60 to 40 too.
@export var fov := 60.0
@export var fov_aim := 40.0
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
## Aim zoom, shoulder swap and sprint pull-back. The sprint pull-back settles in 0.35 s (it was
## 0.53 s at 9 rad/s: 1.5 times as fast).
@export var aim_frequency := 24.0
@export var swap_frequency := 16.0
@export var sprint_frequency := 13.5
## Sprint widens the view by this many degrees (it was 6, halved at the maintainer's word, issue
## #405) and lets the camera out by this many metres (the pull-back was 0.3 m; now half that).
@export var sprint_fov_kick := 3.0
@export var sprint_arm_extra := 0.15
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
## Subtle on purpose: the largest turn of the look direction is a quarter of a degree. The camera
## shake setting scales it and Reduced motion turns it off. None at all in the air. Amounts are
## degrees (half of what they were: pitch 0.4, yaw 0.2, roll 0.28, issue #405).
@export var sprint_sway_pitch_degrees := 0.2
@export var sprint_sway_yaw_degrees := 0.1
@export var sprint_sway_roll_degrees := 0.14
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
