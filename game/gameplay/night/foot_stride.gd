class_name FootStride
extends RefCounted
## When a player who is only seen in frames (the other players of an online night) puts a foot
## down. A body that is simulated here says it itself (`Player.footstep`); a remote one is a
## position every few ticks, so this reads the stride from it the way the simulation does: a step
## for every `step_distance` metres of ground covered while on the ground (`PlayerSimulation`).
##
## A frame has no "on the ground" flag, so it is read from the height: a body that rises or falls
## faster than `AIR_SPEED` for two samples in a row is airborne (a ledge's step-up is one sample),
## and lands again when it is back at the height it left from, or has been still in height for a
## few samples (it landed on something higher). No steps are counted while airborne, down or
## nearly still.

## Ground speed under which a body is standing, as in the simulation (m/s).
const MIN_SPEED := 0.5
## Vertical speed above which a body is leaving the ground or falling (m/s).
const AIR_SPEED := 2.0
## A landing is height within this of where the jump started (m), or this many calm samples.
const LAND_HEIGHT := 0.12
const LAND_CALM_SPEED := 0.3
const LAND_CALM_SAMPLES := 3
## A jump of more than this in one sample is a teleport (a respawn), not a run (m/s).
const TELEPORT_SPEED := 40.0

## Metres of ground per step.
var step_distance := 1.9
## The ground speed of the last sample (m/s), what the sound's level reads.
var speed := 0.0

var _known := false
var _tick := 0
var _position := Vector3.ZERO
var _ground_y := 0.0
var _airborne := false
var _fast_samples := 0
var _calm_samples := 0
var _travelled := 0.0


func _init(stride := 1.9) -> void:
	step_distance = stride


func is_airborne() -> bool:
	return _airborne


## Takes the next sample (the frame's `tick` and the player's position, `seconds_per_tick` long) and
## returns how many feet came down since the last one: usually 0 or 1.
func advance(tick: int, point: Vector3, downed: bool, seconds_per_tick: float) -> int:
	var dt := float(tick - _tick) * seconds_per_tick
	var before := _position
	var known := _known
	_known = true
	_tick = tick
	_position = point
	if not known or dt <= 0.0:
		_ground_y = point.y
		return 0
	var flat := Vector2(point.x - before.x, point.z - before.z).length()
	var vertical := (point.y - before.y) / dt
	speed = flat / dt
	if speed > TELEPORT_SPEED or absf(vertical) > TELEPORT_SPEED:
		_reset(point)
		return 0
	_track_air(point.y, vertical)
	if _airborne or downed or speed < MIN_SPEED:
		return 0
	_travelled += flat
	var steps := 0
	while _travelled >= step_distance:
		_travelled -= step_distance
		steps += 1
	return steps


func _reset(point: Vector3) -> void:
	_airborne = false
	_fast_samples = 0
	_calm_samples = 0
	_travelled = 0.0
	_ground_y = point.y
	speed = 0.0


func _track_air(height: float, vertical: float) -> void:
	if not _airborne:
		if absf(vertical) > AIR_SPEED:
			_fast_samples += 1
			if _fast_samples >= 2:
				_airborne = true
				_calm_samples = 0
		else:
			_fast_samples = 0
			_ground_y = height
		return
	_calm_samples = _calm_samples + 1 if absf(vertical) < LAND_CALM_SPEED else 0
	if (
		(height <= _ground_y + LAND_HEIGHT and vertical <= 0.0)
		or _calm_samples >= LAND_CALM_SAMPLES
	):
		_airborne = false
		_fast_samples = 0
		_ground_y = height
