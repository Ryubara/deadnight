class_name ArrivalPlan
extends RefCounted
## The helicopter drop as a function of time (#1057): where everything of the show is `t` seconds
## in.
## Pure: no node, no clock, no randomness, so the show plays the same on every screen and a test
## reads any moment. `ArrivalCutscene` places its nodes from `sample`.
##
## The frame is the show's own, relative to the landing spot: +X to the right of the picture, +Y up,
## +Z toward the camera, which stands behind and above the spot and looks down at it. The helicopter
## flies in from the left, nose to +X, and hovers over the spot with its door to the camera.
##
## The beats, for a night's opening (a late join has no fly-in; the others scale to fit):
##
##     fly-in            rope lowers      the Soldier slides      stands   fade
##     0 ............ A ............ B ......................... C ...... D ... T
##
## `fade` is 1 at the start (black) and the end, `sound` is how loud the helicopter is, 0 to 1.

## Share of the time between the fly-in's end and the stand that the rope takes to come down.
const ROPE_SHARE := 0.22
## Share of that time the Soldier waits at the door before sliding.
const WAIT_SHARE := 0.1
## The Soldier stands this long on the ground before the fade (seconds).
const STAND_SECONDS := 0.4
## How far the helicopter's nose dips going in, radians, and how far it rolls into the turn.
## How far up the hover height the camera looks: the ground below and the helicopter over it both
## fit.
const TARGET_SHARE := 0.66
## How close the camera comes at the landing (share of its distance), and how much of its view it
## keeps;
## and the seconds before the slide it starts in.
const CLOSE_SHARE := 0.45
const CLOSE_FOV := 0.8
const CLOSE_LEAD := 0.3
const FLY_PITCH := 0.12
const FLY_ROLL := 0.1

var tuning: ArrivalTuning
## True for the night's opening: the helicopter comes in from afar before it hovers.
var fresh := true
## Metres from the helicopter's origin to the rope's anchor along the helicopter's sideways axis
## (its door side), and up from its origin: from the model.
var anchor := Vector3(1.4, 1.6, 0.0)

var _seconds := 0.0


func _init(p_tuning: ArrivalTuning, p_fresh: bool) -> void:
	tuning = p_tuning
	fresh = p_fresh
	_seconds = tuning.seconds_for(fresh)


func seconds() -> float:
	return _seconds


## When the fly-in ends (0 for a late join).
func fly_in_end() -> float:
	return _seconds * tuning.approach_share if fresh else 0.0


## When the rope is all the way down.
func rope_end() -> float:
	var from := fly_in_end()
	return from + (stand_start() - from) * ROPE_SHARE


## When the Soldier's feet reach the ground.
func stand_start() -> float:
	return _seconds - tuning.fade_out_seconds - STAND_SECONDS


## When he lets go of the rope's end and starts down.
func slide_start() -> float:
	var from := fly_in_end()
	return from + (stand_start() - from) * (ROPE_SHARE + WAIT_SHARE)


## Everything of the show at `t`.
func sample(t: float) -> Sample:
	var s := Sample.new()
	s.t = t
	var u := clampf(t / _seconds, 0.0, 1.0)
	var arrive := fly_in_end()
	# The helicopter: in from the left, braking to the hover, then settling.
	var hover := Vector3(0.0, tuning.hover_height, 0.0)
	var flown := 1.0
	if fresh and arrive > 0.0:
		flown = clampf(t / arrive, 0.0, 1.0)
	var brake := 1.0 - pow(1.0 - flown, 2.6)
	var start := Vector3(
		-tuning.approach_distance, tuning.hover_height * 1.5, -tuning.approach_distance * 0.2
	)
	s.heli = start.lerp(hover, brake) if fresh else hover
	# A hover is never still: a slow sway and a bob.
	s.heli += (
		Vector3(sin(t * 0.9) * 0.25, sin(t * 1.7) * 0.12, cos(t * 0.7) * 0.2)
		* smoothstep(0.6, 1.0, flown)
	)
	s.heli_pitch = FLY_PITCH * (1.0 - brake) if fresh else 0.0
	s.heli_roll = -FLY_ROLL * (1.0 - brake) if fresh else 0.0
	# The rope: pays out from the door, hangs straight, sways.
	var rope_from := arrive
	var rope_to := maxf(rope_end(), rope_from + 0.2)
	var paid := smoothstep(rope_from, rope_to, t)
	s.rope_length = (tuning.hover_height + anchor.y) * paid
	s.rope_sway = sin(t * 2.1) * 0.05 * paid
	# The Soldier rides the rope's end down to the ground and lets go.
	var slid := smoothstep(slide_start(), stand_start(), t)
	s.on_rope = t >= rope_to - 0.05 and t < stand_start() + 0.05
	s.soldier_height = lerpf(tuning.hover_height + anchor.y - 1.7, 0.0, slid)
	s.stood = smoothstep(stand_start() - 0.1, stand_start() + STAND_SECONDS, t)
	s.shown = t >= rope_to - 0.2
	# The lamp comes on as the helicopter slows, and burns to the end.
	s.lamp = smoothstep(arrive * 0.45, maxf(arrive, 0.5), t) if fresh else minf(t / 0.4, 1.0)
	s.lamp *= 1.0 - smoothstep(_seconds - tuning.fade_out_seconds, _seconds, t)
	# The camera: behind and above for the helicopter's coming, then in toward the Soldier as he
	# comes down, so the landing is near.
	var back := tuning.camera_back
	var close := smoothstep(slide_start() - CLOSE_LEAD, stand_start() + CLOSE_LEAD, t)
	var far_at := Vector3(
		lerpf(-2.5, 2.0, u), tuning.camera_height, lerpf(back * 1.12, back * 0.92, u)
	)
	var near_at := Vector3(1.5, tuning.camera_height * CLOSE_SHARE, back * CLOSE_SHARE)
	s.camera = far_at.lerp(near_at, close)
	var far_look := Vector3(lerpf(-1.0, 0.0, u), tuning.hover_height * TARGET_SHARE, 0.0)
	s.target = far_look.lerp(Vector3(0.0, s.soldier_height + 1.2, 0.0), close)
	s.fov = (
		lerpf(tuning.camera_fov * 1.04, tuning.camera_fov * 0.94, u) * lerpf(1.0, CLOSE_FOV, close)
	)
	# Black at both ends.
	s.fade = 1.0 - smoothstep(0.0, tuning.fade_in_seconds, t)
	s.fade = maxf(s.fade, smoothstep(_seconds - tuning.fade_out_seconds, _seconds, t))
	# The sound: far at first (the helicopter is heard before it is seen), closing as it comes in,
	# at its loudest over the spot, and dropping with the fade.
	var near := (
		1.0
		- clampf(
			s.heli.distance_to(Vector3(0.0, tuning.hover_height, 0.0)) / tuning.approach_distance,
			0.0,
			1.0
		)
	)
	s.sound = (
		lerpf(0.15, 1.0, near) * (1.0 - smoothstep(_seconds - tuning.fade_out_seconds, _seconds, t))
	)
	return s


## The pose of the show at one moment.
class Sample:
	extends RefCounted
	var t := 0.0
	var heli := Vector3.ZERO
	var heli_pitch := 0.0
	var heli_roll := 0.0
	var rope_length := 0.0
	var rope_sway := 0.0
	var on_rope := false
	var shown := false
	var soldier_height := 0.0
	## 0 on the rope, 1 standing.
	var stood := 0.0
	var lamp := 0.0
	var camera := Vector3.ZERO
	var target := Vector3.ZERO
	var fov := 50.0
	var fade := 1.0
	var sound := 0.0
