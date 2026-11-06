# The prize crane as hosted bots play it (#1322): the maintainer saw bots pay for a play and never
# take the weapon, and roll again until the crane left. The server steps are real (a bot, the lot,
# the rules' crane); only the draw is set up, by the crane's pool, so the prize is known. Ticks are
# run by hand.
extends GdUnitTestSuite

const TICKS_PER_SECOND := 60
const SEED := 41
const LONG_BREAK := 3000.0
const SETTLE_FRAMES := 60
const DOOR := &"door_concession"
const CRANE := &"crane_play"
## A Rookie with the pistol only weighs a prize by the health of the dead its round sends (`HEALTH`,
## a round-3 walker's): it takes the rifle, which does 1.5 times the quick melee, and leaves the
## shotgun on the glass, whose pellets overshoot a walker that thin (#767).
const HEALTH := 66.0
const WANTED := &"weapon_rifle"
const UNWANTED := &"weapon_shotgun"
## Metres a bot is put from the glass to be out of the press's reach (`NightTuning.spot_reach`).
const DISPLACED := 3.5

var _catcher := ErrorCatcher.new()


func after_test() -> void:
	_catcher.stop()


## A night with one Rookie bot that shops for the crane only, the concession open (the crane
## stands behind it), holding `points`; the crane's pool is `pool`.
func _night(pool: Array[StringName], points: int) -> SeatedNight:
	var tuning := RulesFixture.tuning()
	tuning.rounds.intro_seconds = LONG_BREAK
	tuning.rounds.break_seconds = LONG_BREAK
	tuning.economy.item(CRANE).pool = pool
	tuning.rounds.health_base = HEALTH
	var night := await NightFixture.seat(self, 1, tuning, SEED, true)
	var profile := BotProfile.rookie()
	profile.shopping.assign([CRANE])
	profile.saves_for.clear()
	night.seat(1, profile, SEED + 1)
	await night.settle(12)
	_catcher.start()
	night.open_door(DOOR)
	await night.settle(SETTLE_FRAMES)
	night.server.rules.players[1].points = points
	return night


func _stage(night: SeatedNight) -> int:
	return night.server.rules.crane.stage


func _until(night: SeatedNight, seconds: float, done: Callable) -> bool:
	for _tick in int(seconds * TICKS_PER_SECOND):
		night.tick()
		if done.call():
			return true
	return false


func _plays(night: SeatedNight) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	night.on_event = func(event: Dictionary) -> void:
		if event["type"] == &"purchase_made" and event["item_id"] == CRANE:
			found.append(event)
	return found


## Where the glass is pressed from, at the spot the crane stands on now.
func _glass(night: SeatedNight) -> Vector3:
	for spot in night.server.world.shop_spots():
		if spot["kind"] == &"crane" and spot["crane_spot"] == night.server.rules.crane.spot:
			return spot["position"]
	return Vector3.INF


## A point on the walking mesh `metres` from `at`, in the first direction that has one.
func _off_the_glass(night: SeatedNight, at: Vector3, metres: float) -> Vector3:
	var map := night.server.world.map()
	for turn in 8:
		var angle := TAU * float(turn) / 8.0
		var point := at + Vector3(cos(angle), 0.0, sin(angle)) * metres
		var snapped := NavigationServer3D.map_get_closest_point(map, point)
		if Vector2(snapped.x - point.x, snapped.z - point.z).length() < 0.2:
			return snapped
	return Vector3.INF


func test_a_bot_shoved_off_the_glass_while_it_spins_walks_back_and_takes_its_prize() -> void:
	var night := await _night([WANTED], 700)
	(
		assert_bool(
			_until(night, 120.0, func() -> bool: return _stage(night) == CraneState.Stage.SPIN)
		)
		. is_true()
	)
	var glass := _glass(night)
	var away := _off_the_glass(night, glass, DISPLACED)
	assert_bool(away != Vector3.INF).is_true()
	night.server.body_of(1).teleport(away + Vector3(0.0, 0.1, 0.0))
	night.tick()
	assert_str(String(night.frame["players"][1]["prompt"].get("kind", &""))).is_empty()
	var took := _until(
		night, 20.0, func() -> bool: return night.frame["players"][1]["arms"].has(&"rifle")
	)
	assert_bool(took).is_true()
	assert_array(_catcher.lines).is_empty()
	night.dispose()


func test_a_bot_that_let_a_prize_go_does_not_roll_again_in_the_round() -> void:
	var pool: Array[StringName] = [WANTED, UNWANTED]
	var night := await _night(pool, 700)
	var plays := _plays(night)
	(
		assert_bool(
			_until(night, 120.0, func() -> bool: return _stage(night) == CraneState.Stage.SPIN)
		)
		. is_true()
	)
	# The draw lands on the shotgun: the bot stands at the glass and leaves it, as it means to.
	night.server.rules.tuning.economy.item(CRANE).pool = [UNWANTED]
	(
		assert_bool(
			_until(night, 30.0, func() -> bool: return _stage(night) == CraneState.Stage.READY)
		)
		. is_true()
	)
	assert_int(plays.size()).is_equal(1)
	assert_bool(night.frame["players"][1]["arms"].has(&"shotgun")).is_false()
	# The pool is as it was, the bot is as rich as it was, the round is the same one.
	night.server.rules.tuning.economy.item(CRANE).pool = pool
	night.server.rules.players[1].points = 700
	night.run(90 * TICKS_PER_SECOND)
	assert_int(plays.size()).is_equal(1)
	assert_array(_catcher.lines).is_empty()
	night.dispose()


func test_a_bot_takes_the_prize_it_wants_the_moment_it_is_held_out() -> void:
	var night := await _night([WANTED], 700)
	var plays := _plays(night)
	var took := _until(
		night, 120.0, func() -> bool: return night.frame["players"][1]["arms"].has(&"rifle")
	)
	assert_bool(took).is_true()
	assert_int(plays.size()).is_equal(1)
	assert_array(_catcher.lines).is_empty()
	night.dispose()
