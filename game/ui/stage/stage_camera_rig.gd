class_name StageCameraRig
extends RefCounted
## Moves the menu camera between the tabs' poses. Position, look point, field of view and the
## soldier's turn are critically damped springs (`DampedSpring`, exact for any step), so a move
## starts and stops without a kink and takes the same time at 30 or 144 frames a second. It reads no
## clock of its own: `step(delta)` is the only thing that moves it, so a capture or a test repeats.
## With reduced motion a move is a cut, and the slow sway is off.

## Angular frequency (rad/s) of a move: settles in about 0.85 s.
const MOVE_FREQUENCY := 5.5
## A glance at the pose a tab was left in: how close counts as arrived.
const ARRIVED := 0.01
## The sway that keeps the picture alive: metres and radians per second.
const SWAY_METRES := 0.05
const SWAY_RATE := 0.45

var tab := MenuTab.Id.PLAY

var _camera: Camera3D
var _aspect := 16.0 / 9.0
var _pose := StagePose.new()
var _position := DampedSpring3.new()
var _look := DampedSpring3.new()
var _fov := DampedSpring.new()
var _yaw := DampedSpring.new()
var _clock := 0.0
var _reduced := false
var _goal_position := Vector3.ZERO
var _goal_look := Vector3.ZERO


func _init(camera: Camera3D) -> void:
	_camera = camera


## Whether the camera cuts instead of gliding.
func set_reduced(reduced: bool) -> void:
	_reduced = reduced


func set_aspect(aspect: float) -> void:
	_aspect = aspect
	_retarget()


## Goes to the pose of `to`: a glide, or at once when `cut` or with reduced motion.
func go_to(to: MenuTab.Id, cut := false) -> void:
	tab = to
	_pose = StagePose.for_tab(to)
	_retarget()
	if cut or _reduced:
		_snap()


## The soldier's yaw in radians now.
func hero_yaw() -> float:
	return _yaw.value


## Whether the camera has reached its pose.
func arrived() -> bool:
	return (
		_position.value.distance_to(_goal_position) < ARRIVED
		and _look.value.distance_to(_goal_look) < ARRIVED
		and absf(_fov.value - _pose.fov) < ARRIVED
	)


func step(delta: float) -> void:
	_clock += delta
	if _reduced:
		_snap()
	else:
		_position.step(_goal_position, Vector3.ONE * MOVE_FREQUENCY, delta)
		_look.step(_goal_look, Vector3.ONE * MOVE_FREQUENCY, delta)
		_fov.step(_pose.fov, MOVE_FREQUENCY, delta)
		_yaw.step(deg_to_rad(_pose.hero_yaw), MOVE_FREQUENCY, delta)
	_apply()


func _retarget() -> void:
	var placed := _pose.place(_aspect)
	_goal_position = placed[0]
	_goal_look = placed[1]


func _snap() -> void:
	_position.snap(_goal_position)
	_look.snap(_goal_look)
	_fov.snap(_pose.fov)
	_yaw.snap(deg_to_rad(_pose.hero_yaw))


func _apply() -> void:
	var sway := Vector3.ZERO
	if not _reduced:
		sway = Vector3(sin(_clock * SWAY_RATE), sin(_clock * SWAY_RATE * 1.7 + 1.3) * 0.6, 0.0)
		sway *= SWAY_METRES
	_camera.fov = _fov.value
	_camera.look_at_from_position(_position.value + sway, _look.value + sway * 0.5)
