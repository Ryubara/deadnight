class_name ThumbBot
extends RefCounted
## A modelled thumb on a touch screen, for measuring the aim assist (#286). It stands at the
## origin with the trigger held and turns the view toward the nearest zombie of a crowd that walks
## in, the way a hand does: it follows the target with a lag, its drag is noisy, and the noise
## wanders instead of averaging out. It makes the same calls the game makes (`AimAssist.pick`,
## `friction`, `pull`) and counts, every tick, whether the crosshair is on a zombie's hit zone: the
## share of ticks a held trigger would land. Seeded, no time, no scene.

const STEP := 1.0 / 60.0
const EYE := Vector3(0.0, 1.6, 0.0)
## Zombies in the crowd, how far they start, how fast they walk, and when one has arrived.
const CROWD := 7
const RING_NEAR := 7.0
const RING_FAR := 14.0
const WALK := 1.1
const ARRIVED := 1.6
## The thumb: the share of the angle to the target it closes each tick, the fastest it turns
## (radians per second), the size of a tick's tremor (radians, pitch gets a share of it) and how
## far the tremor wanders on (a share of the last tick's kept).
const FOLLOW := 0.05
const MAX_TURN := 3.0
const TREMOR := 0.006
const PITCH_SHARE := 0.6
const WANDER := 0.9
## How long the thumb takes to notice a zombie moving, in ticks (it aims at where it was).
const LAG := 18

var strength := 0.0
var tuning := AimAssistTuning.new()
var seed_value := 1

var _rng := RandomNumberGenerator.new()
var _zombies: Array[Dictionary] = []
var _history: Array = []
var _yaw := 0.0
var _pitch := 0.0
var _tremor := Vector2.ZERO


## The share of `ticks` the crosshair spent on a zombie.
func hit_share(ticks: int) -> float:
	_rng.seed = seed_value
	_zombies.clear()
	for _i in CROWD:
		_zombies.append(_arrival())
	_history.clear()
	_yaw = 0.0
	_pitch = 0.0
	_tremor = Vector2.ZERO
	var hits := 0
	for _tick in ticks:
		_walk()
		_history.push_back(_positions())
		if _history.size() > LAG:
			_history.pop_front()
		_turn()
		var dir := _direction()
		if AimAssist.on_target(EYE, dir, _targets(), tuning.auto_fire_reach):
			hits += 1
	return float(hits) / float(ticks)


func _turn() -> void:
	var seen: Array = _history[0]
	var goal := _nearest(seen)
	var wanted := AimAssist.view_angles((goal + Vector3.UP * tuning.aim_height - EYE).normalized())
	var error := Vector2(angle_difference(_yaw, wanted.x), wanted.y - _pitch)
	_tremor = (
		_tremor * WANDER + Vector2(_rng.randfn(0.0, TREMOR), _rng.randfn(0.0, TREMOR * PITCH_SHARE))
	)
	var own := (error * FOLLOW).limit_length(MAX_TURN * STEP) + _tremor
	var dir := _direction()
	var found := AimAssist.pick(EYE, dir, _targets(), strength, tuning)
	own *= AimAssist.friction(found, strength, tuning)
	_yaw = wrapf(_yaw + own.x, -PI, PI)
	_pitch = clampf(_pitch + own.y, -1.0, 0.8)
	if strength > 0.0:
		var after := AimAssist.pick(EYE, _direction(), _targets(), strength, tuning)
		var step := AimAssist.pull(
			EYE, _direction(), after, strength, own.length() / STEP, STEP, tuning
		)
		_yaw = wrapf(_yaw + step.x, -PI, PI)
		_pitch = clampf(_pitch + step.y, -1.0, 0.8)


func _direction() -> Vector3:
	return Vector3(-sin(_yaw) * cos(_pitch), sin(_pitch), -cos(_yaw) * cos(_pitch))


func _walk() -> void:
	for i in _zombies.size():
		var zombie := _zombies[i]
		var at: Vector3 = zombie["position"]
		var toward := Vector3(-at.x, 0.0, -at.z)
		if toward.length() < ARRIVED:
			_zombies[i] = _arrival()
			continue
		# A shamble: toward the player, with a slow weave across the path.
		var weave := Vector3(-toward.z, 0.0, toward.x).normalized() * sin(zombie["phase"]) * 0.35
		zombie["phase"] += STEP * 2.0
		zombie["position"] = at + (toward.normalized() * WALK + weave) * STEP
		zombie["yaw"] = atan2(-toward.x, -toward.z) + PI


## A zombie coming in from the front half of the ring, so it is in the thumb's half of the world.
func _arrival() -> Dictionary:
	var angle := _rng.randf_range(-1.1, 1.1)
	var distance := _rng.randf_range(RING_NEAR, RING_FAR)
	return {
		"position": Vector3(sin(angle) * distance, 0.0, -cos(angle) * distance),
		"yaw": 0.0,
		"scale": 1.0,
		"phase": _rng.randf() * TAU,
	}


func _positions() -> Array:
	var places: Array = []
	for zombie in _zombies:
		places.append(zombie["position"])
	return places


func _targets() -> Array:
	return _zombies


func _nearest(places: Array) -> Vector3:
	var best: Vector3 = places[0]
	for place: Vector3 in places:
		if place.length() < best.length():
			best = place
	return best
