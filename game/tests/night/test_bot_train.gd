# A bot with an empty gun and a train of dead behind it on the second map's side room (issue
# #695): a bot whose gun has nothing left, with another gun that only needs its reload, took the
# other gun up and reloaded it (or struck) instead of kiting the train round the rack row for the
# rest of the night, and the round ended.
extends GdUnitTestSuite

const STEP := Night.STEP
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
const TRAIN_GAP := 0.7
## The Tommy gun's reserve; the shotgun in hand has nothing at all.
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


## Runs the train: the bot's gun in hand has no round anywhere and the other has `RESERVE` rounds
## and an empty magazine. Returns what happened.
func _play(bot_seed: int) -> Dictionary:
	var night := await _night()
	# The door to the side room is bought, as the bots' nights have it by now: the dead have a way in.
	night.open_door(&"door_side")
	await night.settle(MAP_FRAMES)
	night.server.rules.apply(RulesAction.skip_break())
	var seen := {"kills": 0, "reloads": [], "round_ended": false, "swaps": 0, "quick": 0}
	night.on_event = func(event: Dictionary) -> void:
		match event["type"]:
			&"zombie_removed":
				if event["cause"] == &"killed":
					seen["kills"] += 1
			&"reload_started":
				seen["reloads"].append(event["weapon_id"])
			&"round_ended":
				seen["round_ended"] = true
			&"quick_melee":
				seen["quick"] += 1
	for _i in 40 * TICKS_PER_SECOND:
		night.tick()
		if night.server.sim.standing_count() >= TRAIN_MIN:
			break
	# The pistol in hand has nothing at all; the shotgun only needs its reload.
	night.server.combat.apply(CombatAction.give_weapon(1, &"shotgun"))
	night.server.combat.apply(CombatAction.equip(1, &"pistol"))
	night.run(3)
	var held: StringName = night.frame["players"][1]["weapon"]
	for id: StringName in night.server.combat.carried(1):
		var state := night.server.combat.state_of(1, id)
		state.cancel_reload()
		state.ammo = 0
		state.reserve = 0 if id == held else RESERVE
	seen["held_at_start"] = held
	seen["carried"] = night.server.combat.carried(1)
	night.server.body_of(1).teleport(BOT_AT)
	var placed := 0
	for zombie: ZombieBody in night.server.sim.zombies.values():
		zombie.position = TRAIN_FROM + Vector3(TRAIN_GAP * placed, 0.0, 0.0)
		zombie.gate_id = &""
		zombie.speed = TRAIN_SPEED
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
	seen["held_at_end"] = night.frame["players"][1]["weapon"]
	seen["downed"] = night.frame["players"][1].get("downed", false)
	var left := []
	for zombie: ZombieBody in night.server.sim.zombies.values():
		if zombie.is_alive():
			left.append(zombie.position)
	seen["left"] = left
	seen["bot_at"] = night.server.body_of(1).global_position
	seen["remaining"] = night.server.rules.zombies_remaining()
	night.on_event = Callable()
	night.dispose()
	return seen


func test_a_bot_with_an_empty_gun_and_a_train_behind_it_takes_up_the_other_gun_and_ends_the_round(
) -> void:
	var seen := await _play(31)
	print("TRAIN ", seen)
	assert_int(seen["placed"]).is_greater_equal(TRAIN_MIN)
	assert_array(seen["carried"]).has_size(2)
	# It put the empty gun down and reloaded the one with rounds in reserve.
	assert_array(seen["reloads"]).is_not_empty()
	assert_bool(seen["held_at_end"] != seen["held_at_start"]).is_true()
	assert_int(seen["kills"]).is_greater_equal(TRAIN)
	assert_bool(seen["round_ended"] or seen["downed"]).is_true()
