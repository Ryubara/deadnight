class_name SprintSway
extends RefCounted
## The gentle sway of the view while the player sprints: a small bob (pitch) on every footfall and
## a slower roll and yaw once per stride, so a run reads in the picture without ever shaking it.
## Rotation only, about the lens, like the shot shake (`CameraShake`); `ThirdPersonCamera`
## multiplies the two and keeps the aim ray apart, so the sway is the view, never the aim.
##
## It is locked to the feet, not to the clock: the phase counts footfalls and advances by ground
## speed over `PlayerTuning.step_distance` (the metres per footstep the audio and the Run clip's
## stride share), so a faster run sways faster and a stopped player holds still. It eases in when
## the sprint starts and out when it stops, and is none at all while walking, aiming, standing or
## downed. A function of the steps it was given, never of real time. The numbers are
## `PlayerTuning`'s "Sprint sway" group.
##
## It belongs to the feet on the ground: the first tick the body is in the air (a jump, a step off a
## ledge, a fall) with the sprint held, the sway is gone at once, with no ease-out, and it comes
## back with the normal ease-in after landing.

## 0 to 1 and linear in time: where the ease between still and swaying has got to.
var level := 0.0
## Footfalls since the sway began (a whole number is a foot landing).
var phase := 0.0

var _tuning: PlayerTuning
var _shake: CameraShake


## `shake` is the shot shake the sway shares its setting with (`scale`, and the trauma it gives way
## to).
func _init(tuning: PlayerTuning, shake: CameraShake) -> void:
	_tuning = tuning
	_shake = shake


## Back to rest (a spawn or a teleport).
func reset() -> void:
	level = 0.0
	phase = 0.0


## Moves the ease and the stride on by `delta` seconds. `sprinting` is the sprint state of the
## body (never just the key), `ground_speed` metres per second and `grounded` whether the body
## stands on the ground (`PlayerMotionState.on_floor`): in the air the sway stops at once.
func step(delta: float, sprinting: bool, ground_speed: float, grounded := true) -> void:
	if not grounded:
		reset()
		return
	var wanted := sprinting and ground_speed >= _tuning.sprint_sway_min_speed
	var seconds := _tuning.sprint_sway_ease_in if wanted else _tuning.sprint_sway_ease_out
	level = move_toward(level, 1.0 if wanted else 0.0, delta / maxf(seconds, 0.001))
	if level <= 0.0:
		phase = 0.0
		return
	phase += ground_speed * delta / _tuning.step_distance


## How much of the tuned sway shows now, 0 to 1: the eased level, the player's setting, and a share
## taken away while a shot kicks the view so the two do not pile up.
func amount() -> float:
	var eased := smoothstep(0.0, 1.0, level)
	var duck := 1.0 - _tuning.sprint_sway_fire_duck * clampf(_shake.trauma, 0.0, 1.0)
	return eased * _shake.scale * duck


## The turn of the lens now, as a basis to multiply the view by.
func rotation() -> Basis:
	var shown := amount()
	if shown <= 0.0:
		return Basis.IDENTITY
	var offset := deg_to_rad(_tuning.sprint_sway_phase_degrees)
	var bob := TAU * phase / maxf(_tuning.sprint_sway_bob_steps, 0.01) + offset
	var sway := TAU * phase / maxf(_tuning.sprint_sway_sway_steps, 0.01) + offset
	return Basis.from_euler(
		Vector3(
			deg_to_rad(_tuning.sprint_sway_pitch_degrees) * shown * sin(bob),
			deg_to_rad(_tuning.sprint_sway_yaw_degrees) * shown * cos(sway),
			deg_to_rad(_tuning.sprint_sway_roll_degrees) * shown * sin(sway)
		)
	)


## The most the sway can turn where the lens looks at the amount now, in degrees (pitch and yaw
## move the look direction; roll only spins the picture).
func peak_degrees() -> float:
	return (
		amount()
		* Vector2(_tuning.sprint_sway_pitch_degrees, _tuning.sprint_sway_yaw_degrees).length()
	)
