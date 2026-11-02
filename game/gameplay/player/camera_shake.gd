class_name CameraShake
extends RefCounted
## The view shake of a shot, "trauma" style: a shot adds trauma (0 to 1), trauma drains away at a
## steady rate, and the shake is the trauma squared times a smooth noise on each axis, so a light
## shot is barely felt and a stack of shots (a machine gun) is felt more, then settles.
## Only the lens turns by it (`ThirdPersonCamera` keeps the aim ray apart): the shake is the view,
## never the aim. All of it is a function of the steps it was given, never of real time, so a test
## and a capture see the same shake. The numbers are `PlayerTuning`'s "Shake" group.

## The noise on each axis is read from its own line of one noise field.
const AXIS_SPACING := 37.0

## Trauma now, 0 to 1.
var trauma := 0.0
## 0 turns the shake off (the player's setting), 1 is as tuned.
var scale := 1.0

var _tuning: PlayerTuning
var _noise := FastNoiseLite.new()
var _time := 0.0


func _init(tuning: PlayerTuning, noise_seed: int = 1958) -> void:
	_tuning = tuning
	_noise.seed = noise_seed
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 1.0


## A shot of `amount` trauma (a weapon's `WeaponDef.shake_trauma`); trauma never goes past 1.
func add(amount: float) -> void:
	if scale <= 0.0 or amount <= 0.0:
		return
	trauma = minf(trauma + amount, 1.0)


## Drains trauma and moves the noise on by `delta` seconds.
func step(delta: float) -> void:
	if trauma <= 0.0:
		return
	_time += delta
	trauma = maxf(trauma - _tuning.shake_decay * delta, 0.0)


## The turn of the lens now: pitch, yaw and roll in radians, as a basis to multiply the view by.
func rotation() -> Basis:
	if trauma <= 0.0 or scale <= 0.0:
		return Basis.IDENTITY
	var power := pow(trauma, _tuning.shake_exponent) * scale
	var peak := deg_to_rad(_tuning.shake_max_degrees) * power
	var at := _time * _tuning.shake_frequency
	return Basis.from_euler(
		Vector3(
			peak * _noise.get_noise_2d(at, 0.0),
			peak * _noise.get_noise_2d(at, AXIS_SPACING),
			peak * _tuning.shake_roll_fraction * _noise.get_noise_2d(at, 2.0 * AXIS_SPACING)
		)
	)


## The largest angle the shake can turn the lens by at the trauma now, in degrees (an upper bound
## of the noise, for tests and tuning).
func peak_degrees() -> float:
	return _tuning.shake_max_degrees * pow(trauma, _tuning.shake_exponent) * scale
