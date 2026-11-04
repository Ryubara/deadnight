# A bot with an empty gun and a train of dead behind it on the second map's side room (issue
# #695): it reloads when it has the gap, or strikes, instead of kiting the train round the rack
# row for the rest of the night, and the round ends. Two kits: a pistol with nothing at all and a
# shotgun that only needs its reload; a shotgun that needs its reload and a fire axe (a bot with a
# blade put the gun away for it and then never took the gun back with the dead at its heels).
extends GdUnitTestSuite

const TICKS_PER_SECOND := 60
## Dead to the round, and the most of them that are on the lot when the bot is put in front of
## them (the rest come after).
const TRAIN := 8
const TRAIN_MIN := 6
## Metres a second the train walks: slower than the bot's run, so it never catches it by itself.
const TRAIN_SPEED := 1.5
## The bot stands at the west end of the side room's south aisle; the train comes from the east.
const BOT_AT := Vector3(2.0, 0.1, -2.0)
const TRAIN_FROM := Vector3(9.0, 0.0, -2.0)
## The train that is at the bot's heels: as fast as the bot's walk, starting a few metres behind.
const HEELS_SPEED := 2.6
const HEELS_FROM := Vector3(5.5, 0.0, -2.0)
const TRAIN_GAP := 0.7
## Rounds in reserve of the gun that needs its reload.
const RESERVE := 120
const SECONDS := 150
## Physics frames the bought door's walking mesh gets to reach the map.
const MAP_FRAMES := 300


func _night() -> SeatedNight:
	var tuning := RulesFixture.tuning()
	tuning.rounds.count_base = float(TRAIN)
	tuning.rounds.count_linear = 0.0
	tuning.rounds.count_quadratic = 0.0
	tuning.rounds.first_spawn_delay = 0.1
	tuning.rounds.spawn_interval_start = 0.3
	tuning.rounds.spawn_interval_min = 0.2
	return await SmallMapNight.seat(self, 1, tuning, 5)


## Gives the bot its kit: the shotgun with `RESERVE` rounds and an empty magazine, and `other`
## beside it. With the pistol as `other` the pistol is the one in hand and has nothing at all; with
## anything else the shotgun is in hand.
func _kit(night: SeatedNight, other: StringName) -> void:
	var combat := night.server.combat
	combat.apply(CombatAction.give_weapon(1, &"shotgun"))
	if other != &"house_pistol":
		combat.apply(CombatAction.give_weapon(1, other, &"house_pistol"))
	combat.apply(CombatAction.equip(1, other if other == &"house_pistol" else &"shotgun"))
	night.run(3)
	for id: StringName in combat.carried(1):
		var state := combat.state_of(1, id)
		state.cancel_reload()
		state.ammo = 0
		state.reserve = RESERVE if id == &"shotgun" else 0


## Runs the train. Returns what happened.
func _play(
	bot_seed: int, other: StringName, speed := TRAIN_SPEED, from := TRAIN_FROM
) -> Dictionary:
	var night := await _night()
	# The door to the side room is bought, as the bots' nights have it by now: the dead have a way in.
	night.open_door(&"door_side")
	await night.settle(MAP_FRAMES)
	night.server.rules.apply(RulesAction.skip_break())
	var seen := {"kills": 0, "reloads": [], "round_ended": false}
	night.on_event = func(event: Dictionary) -> void:
		match event["type"]:
			&"zombie_removed":
				if event["cause"] == &"killed":
					seen["kills"] += 1
			&"reload_started":
				seen["reloads"].append(event["weapon_id"])
			&"round_ended":
				seen["round_ended"] = true
	for _i in 40 * TICKS_PER_SECOND:
		night.tick()
		if night.server.sim.standing_count() >= TRAIN_MIN:
			break
	_kit(night, other)
	seen["carried"] = night.server.combat.carried(1)
	night.server.body_of(1).teleport(BOT_AT)
	var placed := 0
	for zombie: ZombieBody in night.server.sim.zombies.values():
		zombie.position = from + Vector3(TRAIN_GAP * placed, 0.0, 0.0)
		zombie.gate_id = &""
		zombie.speed = speed
		zombie.enter(ZombieBody.Mode.CHASE)
		placed += 1
	seen["placed"] = placed
	night.seat(1, BotProfile.regular(), bot_seed)
	seen["kills"] = 0
	seen["reloads"] = []
	for _i in SECONDS * TICKS_PER_SECOND:
		night.tick()
		if seen["round_ended"]:
			break
	seen["downed"] = night.frame["players"][1].get("downed", false)
	seen["remaining"] = night.server.rules.zombies_remaining()
	night.on_event = Callable()
	night.dispose()
	return seen


func test_a_bot_with_an_empty_gun_and_a_train_takes_up_the_other_gun_and_ends_the_round() -> void:
	var seen := await _play(31, &"house_pistol")
	assert_int(seen["placed"]).is_greater_equal(TRAIN_MIN)
	assert_array(seen["carried"]).has_size(2)
	# It put the empty pistol down and reloaded the shotgun, and the round ended.
	assert_array(seen["reloads"]).contains([&"shotgun"])
	assert_int(seen["kills"]).is_greater_equal(TRAIN)
	assert_bool(seen["round_ended"]).is_true()


func test_a_bot_with_a_dry_gun_and_an_axe_and_a_train_reloads_and_ends_the_round() -> void:
	var seen := await _play(31, &"fire_axe")
	print("TRAIN axe ", seen)
	assert_int(seen["placed"]).is_greater_equal(TRAIN_MIN)
	assert_array(seen["carried"]).has_size(2)
	assert_array(seen["reloads"]).contains([&"shotgun"])
	assert_int(seen["kills"]).is_greater_equal(TRAIN)
	assert_bool(seen["round_ended"]).is_true()


func test_a_bot_with_a_dry_gun_and_an_axe_and_a_train_at_its_heels_strikes_and_ends_the_round(
) -> void:
	var seen := await _play(31, &"fire_axe", HEELS_SPEED, HEELS_FROM)
	print("TRAIN heels ", seen)
	assert_int(seen["placed"]).is_greater_equal(TRAIN_MIN)
	assert_int(seen["kills"]).is_greater_equal(TRAIN)
	assert_bool(seen["round_ended"]).is_true()
