class_name InputSampler
extends RefCounted
## Where a client's movement comes from: WASD / arrows, or a seeded random walk (a bot) so captures
## and measurements need no human. Returns the quantised direction the protocol carries.

const BOT_HOLD_MIN_TICKS := 20
const BOT_HOLD_MAX_TICKS := 70

var _bot := false
var _rng := RandomNumberGenerator.new()
var _ticks_left := 0
var _bot_dir := Vector2.ZERO


## `bot_seed` < 0 means a human is driving.
func _init(bot_seed: int = -1) -> void:
	_bot = bot_seed >= 0
	_rng.seed = maxi(bot_seed, 0)


func sample() -> Vector2i:
	var dir := _bot_direction() if _bot else _keyboard_direction()
	return Vector2i((dir.limit_length(1.0) * GameSim.INPUT_MAX).round())


func _keyboard_direction() -> Vector2:
	var x := int(_down(KEY_D, KEY_RIGHT)) - int(_down(KEY_A, KEY_LEFT))
	var y := int(_down(KEY_S, KEY_DOWN)) - int(_down(KEY_W, KEY_UP))
	return Vector2(x, y)


func _down(key: Key, alt: Key) -> bool:
	return Input.is_physical_key_pressed(key) or Input.is_physical_key_pressed(alt)


func _bot_direction() -> Vector2:
	_ticks_left -= 1
	if _ticks_left <= 0:
		_ticks_left = _rng.randi_range(BOT_HOLD_MIN_TICKS, BOT_HOLD_MAX_TICKS)
		var pause := _rng.randf() < 0.1
		_bot_dir = Vector2.ZERO if pause else Vector2.from_angle(_rng.randf() * TAU)
	return _bot_dir
