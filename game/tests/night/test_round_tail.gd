extends GdUnitTestSuite
## A round never waits for ever on its last dead (#950). The soak found one dead at a window of the
## second map whose boards a person put back as fast as it tore them: it stood beside the jamb, out
## of the person's line of fire, and the round waited two and a half minutes on it (the person
## mends when it has nothing to shoot). Seated night, the real server, a person who holds the use
## button at the window.

const WINDOW := &"side_2"
## Metres along the wall from the middle of the window, at the jamb: the opening is 1.2 m wide, so
## this is in front of the wall beside it, not the gap.
const BESIDE := 1.0
## Ticks of the longest the round may take after the dead one is at the window: the siege (30 s),
## the boards falling, the walk in and the shot, with room to spare.
const LIMIT_SECONDS := 75.0

var _seated: SeatedNight
var _person := Vector3.ZERO
var _facing := Vector3.ZERO


func after_test() -> void:
	if _seated != null:
		_seated.dispose()
		_seated = null


## The person mending at the window with a dead one tearing at it from beside the jamb, which stands
## between them: where the soak found them.
func _at_the_window() -> ZombieBody:
	_seated = await SmallMapNight.seat(self, 1, SeatedNight.one_a_round(), 7)
	_seated.start_round()
	for _i in 4:
		await get_tree().physics_frame
	var gate: ZombieGate = _seated.world.gates()[WINDOW]
	var along := gate.inward.cross(Vector3.UP) * BESIDE
	_person = gate.centre + gate.inward * 0.7 + along + Vector3(0.0, 0.1, 0.0)
	_seated.server.body_of(1).teleport(_person)
	_facing = gate.centre - _person
	var zombie := _seated.drop_zombie(gate.centre - gate.inward * 0.95 + along, 2.0)
	zombie.gate_id = WINDOW
	return zombie


## Ticks until the round is over (the break begins) or `seconds` pass; returns the seconds it took,
## or -1.0. The person shoots the dead one once it is through the boards and in the open.
func _until_the_round_ends(zombie: ZombieBody, seconds: float) -> float:
	var start := _seated.server.tick_count
	for tick in int(seconds * 60.0):
		_mend()
		_seated.tick()
		if zombie.is_alive() and zombie.gate_id == &"":
			_seated.server.director.take_hit(zombie.id, &"head", 10000.0, 1)
		if tick % 30 == 0:
			await get_tree().physics_frame
		if _seated.server.rules.phase == GameRules.Phase.BREAK:
			return float(_seated.server.tick_count - start) / 60.0
	return -1.0


func test_a_dead_at_a_mended_window_does_not_hold_the_round_for_ever() -> void:
	var zombie := await _at_the_window()
	var seconds := await _until_the_round_ends(zombie, LIMIT_SECONDS)
	assert_float(seconds).is_greater(0.0)
	assert_bool(zombie.is_alive()).is_false()


## The person's hand: the use button pressed and held, at the window, facing it (a press that has
## no board to put back does nothing).
func _mend() -> void:
	var command := NightCommand.new()
	command.player_id = 1
	command.use = true
	command.use_held = true
	command.origin = _person + Vector3(0.0, BotLevel.EYE_HEIGHT, 0.0)
	command.motion.yaw = atan2(-_facing.x, -_facing.z)
	command.dir = Vector3(_facing.x, 0.0, _facing.z).normalized()
	_seated.server.apply(bytes_to_var(var_to_bytes(command.to_dict())), 1)
