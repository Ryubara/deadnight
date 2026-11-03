# Bots raise a downed teammate (bots plan, phase 5): scenarios 4 to 7, 16 and 23 in the lot with
# the real server: a body in the clear is raised and the claim table has one claimer; with three
# zombies at the body the bot kills them first and starts no hold inside the danger; a hold under a
# hit is let go of by the rule and tried again after the dead are cleared; two bots, one raises and
# the other covers; the last one up with a person down and a pack near survives or raises safely; a
# person who takes a bot's seat leaves the claim open for the next bot. Ticks are run by hand.
extends GdUnitTestSuite

const STEP := Night.STEP
const TICKS_PER_SECOND := 60
const SEED := 47
## A round that never begins its spawning, and a break that never ends.
const QUIET := 6000.0
## The body, in metres in front of the field's home, and where the bots stand.
const BODY := Vector3(0.0, 0.0, -9.0)
const BOT_A := Vector3(2.0, 0.0, 6.0)
const BOT_B := Vector3(-2.0, 0.0, 6.0)
## Health of the health bar's worth that a blow is meant to take, and a full health.
const BLOW := 25.0

var _catcher := ErrorCatcher.new()
var _events: Array[Dictionary] = []


func after_test() -> void:
	_catcher.stop()


func _home() -> Vector3:
	return Autopilot.HOME


## A tuning in which no zombie comes by itself (`QUIET`).
func _quiet() -> RulesTuning:
	var tuning := RulesFixture.tuning()
	tuning.rounds.first_spawn_delay = QUIET
	return tuning


## A tuning that sends `count` zombies in the first round, one after another at once, slowly.
func _pack(count: int) -> RulesTuning:
	var tuning := RulesFixture.tuning()
	tuning.rounds.count_base = float(count)
	tuning.rounds.count_linear = 0.0
	tuning.rounds.count_quadratic = 0.0
	tuning.rounds.first_spawn_delay = 0.1
	tuning.rounds.spawn_interval_start = 0.2
	tuning.rounds.spawn_interval_min = 0.2
	tuning.rounds.spawn_interval_floor = 0.2
	tuning.rounds.speed_base = 1.3
	tuning.rounds.speed_step = 0.0
	tuning.rounds.speed_jitter = 0.0
	return tuning


## A night with a person at seat 1 (a stand-in) and bots at the seats of `bot_ids` standing at the
## spots, the round on. The person stands at `BODY`.
func _night(tuning: RulesTuning, bot_ids: Array[int], spots: Array[Vector3]) -> SeatedNight:
	var night := await NightFixture.seat(self, 1 + bot_ids.size(), tuning, SEED)
	night.human(1)
	for i in bot_ids.size():
		night.seat(bot_ids[i], BotProfile.regular(), SEED + bot_ids[i])
	night.start_round()
	_place(night, 1, _home() + BODY)
	for i in bot_ids.size():
		_place(night, bot_ids[i], _home() + spots[i])
	_events.clear()
	night.on_event = func(event: Dictionary) -> void: _events.append(event)
	night.run(12)
	await night.settle(12)
	_catcher.start()
	return night


func _place(night: SeatedNight, id: int, at: Vector3) -> void:
	night.server.body_of(id).teleport(at + Vector3(0.0, 0.1, 0.0))


## Takes player `id` to the ground, as a blow outside a step does, and lets the bots hear it.
func _down(night: SeatedNight, id: int) -> void:
	night.host.hear(night.server.rules.apply(RulesAction.blow(id, 500.0)))


func _bot(night: SeatedNight, id: int) -> BotClient:
	for candidate in night.host.bots:
		if candidate.state.player_id == id:
			return candidate
	return null


func _count(type: StringName) -> int:
	return _events.filter(func(event: Dictionary) -> bool: return event["type"] == type).size()


## Runs until `done` is true or `seconds` pass; returns the seconds it took, or -1.
func _until(night: SeatedNight, seconds: float, done: Callable) -> float:
	for tick in int(seconds * TICKS_PER_SECOND):
		night.tick()
		if done.call():
			return float(tick) / TICKS_PER_SECOND
	return -1.0


func _raised(night: SeatedNight, id: int) -> bool:
	return not night.server.rules.players[id].downed


## Waits for the rules to put `count` zombies on the lot, then places them with `where` (a callable
## of the index) and sends them at the nearest player. Returns them.
func _put_zombies(night: SeatedNight, count: int, where: Callable) -> Array[ZombieBody]:
	var placed: Array[ZombieBody] = []
	for _i in 20 * TICKS_PER_SECOND:
		if night.server.sim.zombies.size() >= count:
			break
		night.tick()
	var ids: Array = night.server.sim.zombies.keys()
	ids.sort()
	for i in mini(count, ids.size()):
		var zombie: ZombieBody = night.server.sim.zombies[ids[i]]
		zombie.position = where.call(i)
		zombie.gate_id = &""
		zombie.enter(ZombieBody.Mode.CHASE)
		placed.append(zombie)
	return placed


## Zombies standing (not dying) within 14 m of `point`.
func _standing_near(night: SeatedNight, point: Vector3) -> int:
	var count := 0
	for zombie: ZombieBody in night.server.sim.zombies.values():
		if zombie.mode != ZombieBody.Mode.DYING and _flat(zombie.position, point) < 14.0:
			count += 1
	return count


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _seconds_of(night: SeatedNight, seconds: float) -> void:
	night.run(int(seconds * TICKS_PER_SECOND))


# --- Scenario 4 ---


func test_scenario_4_a_downed_person_in_the_clear_is_raised_and_one_bot_claims_them() -> void:
	var ids: Array[int] = [2, 3]
	var spots: Array[Vector3] = [BOT_A, BOT_B]
	var night := await _night(_quiet(), ids, spots)
	_down(night, 1)
	night.run(30)
	assert_int(night.host.team.claims.count(_bot(night, 2).now)).is_equal(1)
	var took := _until(night, 40.0, func() -> bool: return _raised(night, 1))
	assert_float(took).is_greater(0.0)
	var revived := _events.filter(
		func(event: Dictionary) -> bool: return event["type"] == &"player_revived"
	)
	assert_int(revived.size()).is_equal(1)
	assert_bool([2, 3].has(int(revived[0]["reviver_id"]))).is_true()
	assert_int(_count(&"revive_started")).is_equal(1)
	var attempts := 0
	var successes := 0
	for bot in night.host.bots:
		attempts += int(bot.telemetry.counters.get(&"revive_attempts", 0))
		successes += int(bot.telemetry.counters.get(&"revive_successes", 0))
	assert_int(attempts).is_equal(1)
	assert_int(successes).is_equal(1)
	assert_array(_catcher.lines).is_empty()
	night.dispose()


# --- Scenario 5 ---


func test_scenario_5_with_three_zombies_at_the_body_the_bot_kills_them_before_it_holds() -> void:
	var ids: Array[int] = [2, 3]
	var spots: Array[Vector3] = [BOT_A, BOT_B]
	var night := await _night(_pack(3), ids, spots)
	var body := _home() + BODY
	var zombies := _put_zombies(
		night, 3, func(i: int) -> Vector3: return body + Vector3(1.6 + float(i) * 1.2, 0.0, 1.0)
	)
	assert_int(zombies.size()).is_equal(3)
	_down(night, 1)
	var last_kill := -1
	var started := -1
	var live_at_start := -1
	for _i in 60 * TICKS_PER_SECOND:
		night.tick()
		for event in night.last_events:
			if event["type"] == &"zombie_removed" and event["cause"] == &"killed":
				last_kill = night.server.tick_count
			if event["type"] == &"revive_started" and started < 0:
				started = night.server.tick_count
				live_at_start = _standing_near(night, body)
		if _raised(night, 1):
			break
	assert_bool(_raised(night, 1)).is_true()
	assert_int(started).is_greater(0)
	# The hold began only once the three were down.
	assert_int(live_at_start).is_equal(0)
	assert_int(last_kill).is_greater(0)
	assert_int(started).is_greater(last_kill)
	for id in ids:
		assert_int(_bot(night, id).telemetry.counters.get(&"deaths_reviving", 0)).is_equal(0)
	assert_array(_catcher.lines).is_empty()
	night.dispose()


# --- Scenario 6 ---


func test_scenario_6_a_hold_under_a_hit_is_let_go_of_and_tried_again_after_the_clearing() -> void:
	var ids: Array[int] = [2]
	var spots: Array[Vector3] = [Vector3(0.0, 0.0, -6.0)]
	var night := await _night(_pack(2), ids, spots)
	var bot := _bot(night, 2)
	_down(night, 1)
	var holding := _until(night, 30.0, func() -> bool: return night.server.revive().is_reviving(2))
	assert_float(holding).is_greater(0.0)
	night.run(30)
	assert_bool(night.server.revive().is_reviving(2)).is_true()
	# Two zombies come at the bot, and it takes a blow that costs more than the rule allows.
	var here := night.server.body_of(2).global_position
	_put_zombies(
		night, 2, func(i: int) -> Vector3: return here + Vector3(1.5 - float(i) * 3.0, 0.0, 0.0)
	)
	# Their blows are what the rule counts: two on the bot, more than 20 health in a second.
	var let_go := _until(
		night, 6.0, func() -> bool: return int(bot.telemetry.counters.get(&"revive_aborts", 0)) > 0
	)
	assert_float(let_go).is_greater_equal(0.0)
	night.run(3)
	assert_bool(night.server.revive().is_reviving(2)).is_false()
	assert_float(night.server.revive().progress(1)).is_less(BotRevive.COMMITTED_PROGRESS)
	# It kills them and raises the person after all.
	var took := _until(night, 60.0, func() -> bool: return _raised(night, 1))
	assert_float(took).is_greater(0.0)
	assert_int(_count(&"revive_started")).is_greater_equal(2)
	assert_int(bot.telemetry.counters.get(&"revive_successes", 0)).is_equal(1)
	assert_array(_catcher.lines).is_empty()
	night.dispose()


func test_a_blow_when_the_hold_is_far_along_does_not_make_the_bot_let_go() -> void:
	var ids: Array[int] = [2]
	var spots: Array[Vector3] = [Vector3(0.0, 0.0, -6.0)]
	var night := await _night(_quiet(), ids, spots)
	var bot := _bot(night, 2)
	_down(night, 1)
	_until(night, 30.0, func() -> bool: return night.server.revive().is_reviving(2))
	_until(night, 5.0, func() -> bool: return night.server.revive().progress(1) > 0.7)
	night.host.hear(night.server.rules.apply(RulesAction.blow(2, BLOW)))
	night.run(20)
	assert_int(bot.telemetry.counters.get(&"revive_aborts", 0)).is_equal(0)
	assert_float(_until(night, 5.0, func() -> bool: return _raised(night, 1))).is_greater(0.0)
	night.dispose()


# --- Scenario 7 ---


func test_scenario_7_two_bots_one_person_down_one_raises_and_the_other_covers() -> void:
	var ids: Array[int] = [2, 3]
	var spots: Array[Vector3] = [BOT_A, BOT_B]
	var night := await _night(_pack(4), ids, spots)
	_put_zombies(
		night,
		4,
		func(i: int) -> Vector3: return _home() + BODY + Vector3(14.0 + float(i) * 2.0, 0.0, 3.0)
	)
	_down(night, 1)
	var covered := false
	var holders: Dictionary = {}
	for _i in 60 * TICKS_PER_SECOND:
		night.tick()
		for id in ids:
			var mode: BotRevive.Mode = _mode(_bot(night, id))
			if mode == BotRevive.Mode.COVER:
				covered = true
		for event in night.last_events:
			if event["type"] == &"revive_started":
				holders[int(event["player_id"])] = true
		if _raised(night, 1):
			break
	assert_bool(_raised(night, 1)).is_true()
	assert_int(holders.size()).is_equal(1)
	assert_bool(covered).is_true()
	assert_array(_catcher.lines).is_empty()
	night.dispose()


func _mode(bot: BotClient) -> BotRevive.Mode:
	return (bot.brain as BotFightBrain).revive.mode


# --- Scenario 16 ---


func test_scenario_16_the_last_bot_up_with_a_person_down_survives_the_round_or_raises_safely(
) -> void:
	var ids: Array[int] = [2]
	var spots: Array[Vector3] = [Vector3(0.0, 0.0, 2.0)]
	var night := await _night(_pack(8), ids, spots)
	var body := _home() + BODY
	_put_zombies(
		night,
		8,
		func(i: int) -> Vector3:
			return body + Vector3(2.0 + float(i % 4) * 1.4, 0.0, 2.0 + float(i / 4))
	)
	_down(night, 1)
	var bot := _bot(night, 2)
	var survived := false
	var kited := false
	for _i in 150 * TICKS_PER_SECOND:
		night.tick()
		if _mode(bot) == BotRevive.Mode.SURVIVE:
			kited = true
		survived = _raised(night, 1)
		if survived or night.server.rules.phase == GameRules.Phase.OVER:
			break
	assert_int(night.server.rules.phase).is_not_equal(GameRules.Phase.OVER)
	assert_bool(survived).is_true()
	assert_bool(kited).is_true()
	# The person's own fall was made by hand, outside a step: no other player went down.
	assert_int(_count(&"player_downed")).is_equal(0)
	assert_array(_catcher.lines).is_empty()
	night.dispose()


# --- Scenario 23 ---


func test_scenario_23_a_person_who_takes_a_bots_seat_leaves_the_claim_open_to_the_next_bot(
) -> void:
	var ids: Array[int] = [2, 3]
	var spots: Array[Vector3] = [BOT_A, Vector3(-6.0, 0.0, 12.0)]
	var night := await _night(_quiet(), ids, spots)
	_down(night, 1)
	night.run(20)
	var now := _bot(night, 2).now
	assert_int(night.host.team.claims.holder_of(1, now)).is_equal(2)
	# The person joins in bot 2's seat: the server frees it, the host lets the bot go.
	night.host.hear(night.server.apply({"type": NightServer.LEAVE, "player_id": 2}))
	night.host.release(2)
	night.server.apply({"type": NightServer.JOIN, "player_id": 2, "local": false})
	night.human(2)
	assert_bool(night.host.bot_ids.has(2)).is_false()
	assert_int(night.host.team.claims.holder_of(1, now)).is_equal(0)
	var took := _until(night, 40.0, func() -> bool: return _raised(night, 1))
	assert_float(took).is_greater(0.0)
	var revived := _events.filter(
		func(event: Dictionary) -> bool: return event["type"] == &"player_revived"
	)
	assert_int(int(revived[0]["reviver_id"])).is_equal(3)
	assert_array(_catcher.lines).is_empty()
	night.dispose()
