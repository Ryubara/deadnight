class_name EndCamera
extends Camera3D
## The camera of the end of a night (docs/design/end-of-night.md). It starts where the player's own
## lens was (position, direction and field of view), eases out and up over the player in
## `EndTuning.pullback_seconds`, then cuts between the map's authored angles (`EndShot`), one every
## `shot_seconds`, each a slow drift. The pull-back is swept against the walls so the lens never
## goes through one.
##
## Its time is a number (`seek`, `advance`), so a test or a capture places it at any moment of the
## sequence without a clock; the engine moves it each frame (`_process`).

## An angle began (a cut): its number counted from the first angle, 0 for the first.
signal cut(number: int)

## What the lens must not go through: walls, props, doors and the boards across a breach.
const WALL_MASK := PhysicsLayers.WORLD | PhysicsLayers.BOARDS
## The ways the pull-back is tried, as turns from straight back (degrees) and shares of the height:
## in the open the straight way up wins, in a room with a low ceiling a way along the room does.
const TURNS: Array[float] = [0.0, 40.0, -40.0, 80.0, -80.0, 180.0]
const HEIGHT_SHARES: Array[float] = [1.0, 0.5, 0.25]
## How much of its reach a turn of 180 degrees costs a way: a straight way wins a tie.
const TURN_COST := 0.15

var tuning: EndTuning
var shots: Array[EndShot] = []
## Seconds into the sequence.
var clock := 0.0
## The number of the angle on now (counted from the first; past the list's length it wraps), or -1
## during the pull-back.
var shot_number := -1

var _from := Transform3D.IDENTITY
var _from_fov := 70.0
var _focus := Vector3.ZERO
var _to_position := Vector3.ZERO
var _to_basis := Basis.IDENTITY
var _begun := false
## The angle the sequence cuts to first: players do not all see the same one first.
var _first_shot := 0


## Where the pull-back ends for a lens at `lens` over a player at `focus`: back along the way the
## lens was behind them and up, as far as the walls allow. Each way (`TURNS` from straight back,
## at each of the `HEIGHT_SHARES`) is swept from the player and then from the lens to what it
## reached, and the one that gets farthest wins (a straight way on a tie): in the open that is
## straight back and up, in a room with a low ceiling a way along the room.
static func pull_target(
	space: PhysicsDirectSpaceState3D, lens: Vector3, focus: Vector3, p_tuning: EndTuning
) -> Vector3:
	var back := Vector3(lens.x - focus.x, 0.0, lens.z - focus.z)
	back = back.normalized() if back.length() > 0.1 else Vector3.BACK
	var best := lens
	var best_score := -1.0
	for turn in TURNS:
		var way := back.rotated(Vector3.UP, deg_to_rad(turn))
		for share in HEIGHT_SHARES:
			var wanted := (
				focus
				+ way * p_tuning.pullback_distance
				+ Vector3.UP * p_tuning.pullback_height * share
			)
			var up_to := CameraPlacement.sweep(
				space, [], WALL_MASK, focus, wanted - focus, p_tuning.margin
			)
			var reach := focus + (wanted - focus) * up_to
			var along := CameraPlacement.sweep(
				space, [], WALL_MASK, lens, reach - lens, p_tuning.margin
			)
			var end := lens + (reach - lens) * along
			var score := end.distance_to(focus) * (1.0 - TURN_COST * absf(turn) / 180.0)
			if score > best_score + 0.0001:
				best = end
				best_score = score
	return best


## Makes this the current camera, starting from `lens` (the one the player looked through) and
## looking at `focus` (where the player is) with the map's `p_shots`.
func begin(
	lens: Camera3D,
	focus: Vector3,
	p_shots: Array[EndShot],
	p_tuning: EndTuning = null,
	first_shot := 0
) -> void:
	tuning = p_tuning if p_tuning != null else EndTuning.shipped()
	shots = p_shots
	_first_shot = first_shot
	_from = lens.global_transform
	_from_fov = lens.fov
	_focus = focus + Vector3.UP * tuning.look_lift
	_to_position = pull_target(get_world_3d().direct_space_state, _from.origin, focus, tuning)
	_to_basis = EndShot.facing(_focus - _to_position)
	_begun = true
	shot_number = -1
	clock = 0.0
	global_transform = _from
	fov = _from_fov
	make_current()


func _process(delta: float) -> void:
	if _begun:
		advance(delta)


## Moves the sequence on `delta` seconds.
func advance(delta: float) -> void:
	seek(clock + delta)


## Places the camera where it is `seconds` into the sequence.
func seek(seconds: float) -> void:
	clock = maxf(seconds, 0.0)
	if clock < tuning.pullback_seconds:
		_place_pullback(clock / tuning.pullback_seconds)
	else:
		_place_angle(clock - tuning.pullback_seconds)


## The pull-back, eased at both ends so it starts without a jerk and settles into the first angle.
func _place_pullback(progress: float) -> void:
	var eased := smoothstep(0.0, 1.0, progress)
	var turned := Quaternion(_from.basis.orthonormalized()).slerp(Quaternion(_to_basis), eased)
	global_transform = Transform3D(Basis(turned), _from.origin.lerp(_to_position, eased))
	fov = lerpf(_from_fov, tuning.pullback_fov, eased)


func _place_angle(local_seconds: float) -> void:
	if shots.is_empty():
		global_transform = Transform3D(_to_basis, _to_position)
		fov = tuning.pullback_fov
		return
	var progress := local_seconds / tuning.shot_seconds
	var number := int(floor(progress))
	var shot := shots[(number + _first_shot) % shots.size()]
	global_transform = shot.pose(progress - float(number))
	fov = shot.fov
	if number != shot_number:
		shot_number = number
		cut.emit(number)
