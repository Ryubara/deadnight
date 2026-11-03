# A bot fires a flare to draw the dead off a downed person before it raises them (bots plan, phase
# 5; #646): the real server and the real zombies in the lot, ticks run by hand. A person is down
# and a pack of the dead is about the body; the bot that holds the claim is short of ammunition and
# has no grenade, so it cannot shoot the pack down, but it carries the flare gun. It fires at a
# spot far from the body (never within 4 m of a player), the dead walk to the flare, and the
# revive is held and finished. The same night without the flare gun is the control: the pack
# cannot be cleared and the person is not raised. Outcomes are judged in game ticks, never in
# seconds of a clock.
extends GdUnitTestSuite

const TICKS_PER_SECOND := 60
const SEED := 47
## A round that never begins its spawning.
const QUIET := 6000.0
## The person's place and the bot's, in metres from the field's home. A lane of the drive-in runs
## from the bot to the north-east, so the flare has somewhere to land that is far from the body.
const BODY := Vector3(-12.0, 0.0, -4.0)
const BOT_AT := Vector3(2.0, 0.0, 6.0)
## The pack, and the rounds in the bot's pistol (none in reserve).
const PACK := 8
const ROUNDS := 3
## Metres within which a zombie is of the pack about the body.
const ABOUT_THE_BODY := 10.0
## Seconds after the flare at which the dead are counted nearer it.
const DRAWN_AFTER := 4.0
## Game seconds the night is given: under the bleed-out clock (45 s), which the control must reach.
const WATCH_SECONDS := 40.0

var _catcher := ErrorCatcher.new()
var _events: Array[Dictionary] = []


func after_test() -> void:
	_catcher.stop()


func _home() -> Vector3:
	return Autopilot.HOME


## A tuning that sends `PACK` zombies in the first round at once, slowly.
func _pack() -> RulesTuning:
	var tuning := RulesFixture.tuning()
	tuning.rounds.count_base = float(PACK)
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


## A tuning in which no zombie comes by itself.
func _quiet() -> RulesTuning:
	var tuning := RulesFixture.tuning()
	tuning.rounds.first_spawn_delay = QUIET
	return tuning


## A night with a person at seat 1 (a stand-in) and one bot at seat 2, the round on. With `flare`
## the bot carries the flare gun beside its pistol, which is nearly empty either way, and it has
## no grenade left: a pack cannot be shot down.
func _night(tuning: RulesTuning, flare: bool) -> SeatedNight:
	var night := await NightFixture.seat(self, 2, tuning, SEED)
	night.human(1)
	night.seat(2, BotProfile.regular(), SEED + 2)
	night.start_round()
	_place(night, 1, _home() + BODY)
	_place(night, 2, _home() + BOT_AT)
	if flare:
		night.server.combat.apply(CombatAction.give_weapon(2, &"flare_gun"))
		night.server.combat.apply(CombatAction.equip(2, &"pistol"))
	var pistol := night.server.combat.state_of(2, &"pistol")
	pistol.ammo = ROUNDS
	pistol.reserve = 0
	_bot(night).perception.beliefs.grenades = 0
	_events.clear()
	night.on_event = func(event: Dictionary) -> void: _events.append(event)
	night.run(12)
	await night.settle(12)
	_catcher.start()
	return night


func _place(night: SeatedNight, id: int, at: Vector3) -> void:
	night.server.body_of(id).teleport(at + Vector3(0.0, 0.1, 0.0))


## The rules' answer to a direct blow is not part of a server step, so the bots are told.
func _down(night: SeatedNight, id: int) -> void:
	night.host.hear(night.server.rules.apply(RulesAction.blow(id, 500.0)))


func _bot(night: SeatedNight) -> BotClient:
	return night.host.bots[0]


func _raised(night: SeatedNight) -> bool:
	return not night.server.rules.players[1].downed


func _of(type: StringName) -> Array[Dictionary]:
	return _events.filter(func(event: Dictionary) -> bool: return event["type"] == type)


func _counted(night: SeatedNight, counter: StringName) -> int:
	return int(_bot(night).telemetry.counters.get(counter, 0))


## Waits for the rules to put `PACK` zombies on the lot, then stands them in a ring about the body
## (the nearest 2.5 m out) and sends them at the nearest player.
func _surround(night: SeatedNight) -> void:
	for _i in 30 * TICKS_PER_SECOND:
		if night.server.sim.zombies.size() >= PACK:
			break
		night.tick()
	var ids: Array = night.server.sim.zombies.keys()
	ids.sort()
	for i in mini(PACK, ids.size()):
		var zombie: ZombieBody = night.server.sim.zombies[ids[i]]
		var around := TAU * float(i) / float(PACK)
		var out := 2.5 + float(i % 3)
		zombie.position = _home() + BODY + Vector3(sin(around), 0.0, cos(around)) * out
		zombie.gate_id = &""
		zombie.enter(ZombieBody.Mode.CHASE)


## How far each living zombie is from `point`, by id.
func _distances(night: SeatedNight, point: Vector3) -> Dictionary:
	var found := {}
	for id: int in night.server.sim.zombies:
		var zombie: ZombieBody = night.server.sim.zombies[id]
		if zombie.mode != ZombieBody.Mode.DYING:
			found[id] = _flat(zombie.position, point)
	return found


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Runs the night until the person is up or `WATCH_SECONDS` pass. Notes the tick of the first
## `lure_started` and of the first `revive_started`, where the players stood at the flare, how many
## of the dead had come at least 3 m nearer it `DRAWN_AFTER` seconds on, and the blows the bot took
## from the start of the hold on.
func _play(night: SeatedNight) -> Dictionary:
	var seen := {
		"lure_tick": -1,
		"hold_tick": -1,
		"blows_in_the_hold": 0,
		"players_on_lure": {},
		"drawn": -1,
		"pack": 0,
	}
	var lure_at := Vector3.ZERO
	var first := {}
	for _i in int(WATCH_SECONDS * TICKS_PER_SECOND):
		night.tick()
		for event in night.last_events:
			if event["type"] == &"lure_started" and seen["lure_tick"] < 0:
				seen["lure_tick"] = night.server.tick_count
				lure_at = event["point"]
				var at_the_body := _distances(night, _home() + BODY)
				for id: int in _distances(night, lure_at):
					if float(at_the_body[id]) <= ABOUT_THE_BODY:
						first[id] = _distances(night, lure_at)[id]
				seen["pack"] = first.size()
				for id: int in night.server.rules.players:
					seen["players_on_lure"][id] = night.server.body_of(id).global_position
			if event["type"] == &"revive_started" and seen["hold_tick"] < 0:
				seen["hold_tick"] = night.server.tick_count
			if (
				event["type"] == &"player_hurt"
				and int(event["player_id"]) == 2
				and seen["hold_tick"] >= 0
			):
				seen["blows_in_the_hold"] += 1
		if seen["lure_tick"] >= 0 and seen["drawn"] < 0:
			if night.server.tick_count >= seen["lure_tick"] + int(DRAWN_AFTER * TICKS_PER_SECOND):
				var now := _distances(night, lure_at)
				seen["drawn"] = 0
				for id: int in first:
					if now.has(id) and now[id] <= float(first[id]) - 3.0:
						seen["drawn"] += 1
		if _raised(night):
			break
	return seen


func test_a_bot_that_cannot_clear_the_pack_fires_a_flare_and_raises_the_person() -> void:
	var night := await _night(_pack(), true)
	var body := _home() + BODY
	_surround(night)
	_down(night, 1)
	var seen := _play(night)
	assert_bool(_raised(night)).is_true()
	# The bot's flare burst far from the body and from every player (never within 4 m of one).
	var lures := _of(&"lure_started")
	assert_int(lures.size()).is_greater_equal(1)
	assert_int(int(lures[0]["shooter_id"])).is_equal(2)
	assert_int(_counted(night, &"flares_fired")).is_greater_equal(1)
	var lure: Vector3 = lures[0]["point"]
	assert_float(_flat(lure, body)).is_greater_equal(BotFlare.LANDED_FROM_BODY)
	for id: int in seen["players_on_lure"]:
		assert_float(_flat(lure, seen["players_on_lure"][id])).is_greater(4.0)
	# The dead walked to the flare, the hold began after it and went through without a blow.
	assert_int(seen["drawn"]).is_greater_equal(seen["pack"] / 2)
	assert_int(seen["lure_tick"]).is_greater(0)
	assert_int(seen["hold_tick"]).is_greater(seen["lure_tick"])
	assert_int(seen["blows_in_the_hold"]).is_equal(0)
	assert_int(_counted(night, &"deaths_reviving")).is_equal(0)
	assert_int(_counted(night, &"revive_aborts")).is_equal(0)
	assert_float(night.server.rules.health_of(2)).is_greater(0.0)
	assert_array(_catcher.lines).is_empty()
	night.dispose()


func test_the_same_night_without_the_flare_gun_the_pack_cannot_be_cleared() -> void:
	var night := await _night(_pack(), false)
	_surround(night)
	_down(night, 1)
	var seen := _play(night)
	assert_int(_of(&"lure_started").size()).is_equal(0)
	assert_int(_counted(night, &"flares_fired")).is_equal(0)
	# Without it the person is not raised in the time the flare night raised them.
	assert_bool(_raised(night)).is_false()
	assert_int(seen["hold_tick"]).is_less(0)
	assert_array(_catcher.lines).is_empty()
	night.dispose()


func test_a_body_in_the_clear_is_raised_and_no_flare_is_wasted_on_it() -> void:
	var night := await _night(_quiet(), true)
	_down(night, 1)
	var seen := _play(night)
	assert_bool(_raised(night)).is_true()
	assert_int(_of(&"lure_started").size()).is_equal(0)
	assert_int(seen["hold_tick"]).is_greater(0)
	assert_array(_catcher.lines).is_empty()
	night.dispose()
