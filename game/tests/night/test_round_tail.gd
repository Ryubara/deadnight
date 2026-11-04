extends GdUnitTestSuite
## A round never waits for ever on its last dead (#950). The soak found one dead at a window of the
## second map whose boards a person put back as fast as it tore them: it stood beside the jamb, out
## of the person's line of fire, and the round waited two and a half minutes on it (the person
## mends when it has nothing to shoot). Seated night, the real server, the autopilot as the person.

const WINDOW := &"upper_b2"
## Where the soak's person stood: at the left jamb, 1.1 m from the middle of the window, behind the
## wall corner the dead one stood in front of.
const PERSON := Vector3(8.2, 3.5, -7.4)
## Ticks of the longest the round may take after the dead one is at the window: the siege (30 s),
## the boards falling, the walk in and the shot, with room to spare.
const LIMIT_SECONDS := 75.0

var _seated: SeatedNight


func after_test() -> void:
	if _seated != null:
		_seated.dispose()
		_seated = null


## The person mending at the window with a dead one tearing at it from beside the jamb: where the
## soak found them.
func _at_the_window() -> ZombieBody:
	_seated = await SmallMapNight.seat(self, 1, SeatedNight.one_a_round(), 7)
	_seated.seat(1, BotProfile.autopilot(), 7001, true)
	_seated.start_round()
	for _i in 4:
		await get_tree().physics_frame
	_seated.server.body_of(1).teleport(PERSON)
	var zombie := _seated.drop_zombie(Vector3(8.0, 3.4, -9.1), 2.0)
	zombie.gate_id = WINDOW
	return zombie


## Ticks until the round is over (the break begins) or `seconds` pass; returns the seconds it took,
## or -1.0.
func _until_the_round_ends(seconds: float) -> float:
	var start := _seated.server.tick_count
	for tick in int(seconds * 60.0):
		_seated.tick()
		if tick % 30 == 0:
			await get_tree().physics_frame
		if _seated.server.rules.phase == GameRules.Phase.BREAK:
			return float(_seated.server.tick_count - start) / 60.0
	return -1.0


func test_a_dead_at_a_mended_window_does_not_hold_the_round_for_ever() -> void:
	var zombie := await _at_the_window()
	var seconds := await _until_the_round_ends(LIMIT_SECONDS)
	assert_float(seconds).is_greater(0.0)
	assert_bool(zombie.is_alive()).is_false()
