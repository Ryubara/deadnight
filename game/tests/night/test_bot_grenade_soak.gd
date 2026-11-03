# Bots do not hurt themselves with grenades (#805), and the team takes nothing from them (#856). A
# grenade blast hurts its thrower all the way out to its radius (`PlayerBlast`), so a bot that chose
# a throw as before would hurt itself in a crowd. Three bots follow a person round the lot and
# fight the dead for a few minutes of game time on several seeds; every blast they make is measured
# against where the throwing bot stood when it went off, from the body, not from the server's own
# events. The thrower is touched by no more than `BotGrenadier.HARMLESS_SHARE` of its health, and a
# teammate by none (no `player_blasted` for them). The numbers are printed for the pull request.
# How often the bots throw in a free soak depends on the night (and on the runner), so the proof
# that they do throw is a scripted night: a bot, a pack that stands ten metres off and a person
# well clear of it, as `test_bot_grenades.gd` does.
extends GdUnitTestSuite

const STEP := Night.STEP
const SEEDS := [11, 12]
## Game seconds each seeded night runs.
const SECONDS := 90
## Where the scripted pack stands, from home, how many, and where the person stands.
const PACK_AT := Vector3(0.0, 0.0, -10.0)
const PACK_SIZE := 4
const MATE_AT := Vector3(-12.0, 0.0, 6.0)
## The longest the scripted night waits for the bot's blast.
const SCRIPTED_SECONDS := 10
## A person's tour of the field for the bots to follow (offsets from the field's home).
const TOUR := [
	Vector3(-20.0, 0.0, 0.0),
	Vector3(-20.0, 0.0, 14.0),
	Vector3(20.0, 0.0, 14.0),
	Vector3(20.0, 0.0, 0.0),
	Vector3(0.0, 0.0, 0.0),
]


## Counts every blast the bots make into `result` and measures it against where the bot that threw
## it stands (the body, not the server's own events). `person` is the player who is not a bot.
## A `player_blasted` for anyone but the thrower is counted in `mates_blasted`: there must be none.
func _measure(night: SeatedNight, result: Dictionary, person: int = 1) -> void:
	var def := night.server.grenades.def
	night.on_event = func(event: Dictionary) -> void:
		if event["type"] == &"player_blasted" and event["player_id"] != event["thrower_id"]:
			result["mates_blasted"] += 1
		if event["type"] != &"grenade_exploded" or event["thrower_id"] == person:
			return
		result["blasts"] += 1
		var chest := (
			night.server.body_of(event["thrower_id"]).global_position
			+ Vector3.UP * def.player_chest
		)
		var share := PlayerBlast.share(
			(event["point"] as Vector3).distance_to(chest), def.player_full_radius, def.blast_radius
		)
		result["worst"] = maxf(result["worst"], share)
		result["hurt_events"] += 1 if share > 0.0 else 0


func _empty_result() -> Dictionary:
	return {"blasts": 0, "worst": 0.0, "hurt_events": 0, "mates_blasted": 0}


## One night: the grenades the bots threw, and the worst share of its own health any blast took off
## the bot that threw it.
func _night(seed_value: int) -> Dictionary:
	var tuning := SeatedNight.brisk()
	# Big rounds, so there are packs to throw at, and the dead put in front of the players as the
	# movement and fight suites do: a short run has a fight in it.
	tuning.rounds.count_base = 30.0
	tuning.rounds.speed_base = 2.0
	# The person does not fight and must outlast the soak: it is not what is measured.
	tuning.health.max_health = 100000.0
	var night := await NightFixture.seat(self, 4, tuning, seed_value)
	var walker := night.human(1)
	night.seat(2, BotProfile.regular(), seed_value * 10 + 2)
	night.seat(3, BotProfile.veteran(), seed_value * 10 + 3)
	night.seat(4, BotProfile.rookie(), seed_value * 10 + 4)
	night.gather()
	night.stage_the_dead = true
	night.server.rules.apply(RulesAction.skip_break())
	night.give_order(BotOrders.FOLLOW, 1, walker.position())
	var result := _empty_result()
	_measure(night, result)
	var leg := 0
	walker.goto(Autopilot.HOME + TOUR[0])
	for _tick in SECONDS * 60:
		night.tick()
		if walker.arrived():
			leg = (leg + 1) % TOUR.size()
			walker.goto(Autopilot.HOME + TOUR[leg])
	night.dispose()
	return result


## The scripted night: a bot at home, a person at `MATE_AT` and a pack that stands still at
## `PACK_AT`. The bot throws into the pack, and no one is hurt.
func test_a_bot_throws_into_a_pack_and_hurts_no_one() -> void:
	var night := await NightFixture.seat(self, 2, SeatedNight.one_a_round(), 21)
	var profile := BotProfile.regular()
	profile.follows = false
	night.seat(1, profile, 21)
	night.human(2)
	night.start_round()
	night.server.body_of(1).teleport(Autopilot.HOME + Vector3(0.0, 0.1, 0.0))
	night.server.body_of(2).teleport(Autopilot.HOME + MATE_AT + Vector3(0.0, 0.1, 0.0))
	for i in PACK_SIZE:
		var at := Autopilot.HOME + PACK_AT + Vector3(float(i % 2) * 1.2, 0.0, float(i / 2) * 1.2)
		night.server.sim.spawn(1000 + i, 0.0, at).enter(ZombieBody.Mode.CHASE)
	night.run(5)
	var result := _empty_result()
	_measure(night, result, 2)
	for _tick in SCRIPTED_SECONDS * 60:
		night.tick()
		if result["blasts"] > 0:
			break
	night.dispose()
	(
		assert_int(result["blasts"])
		. override_failure_message(
			(
				"the scripted bot threw no grenade into a pack ten metres off in %d s"
				% SCRIPTED_SECONDS
			)
		)
		. is_greater(0)
	)
	assert_int(result["mates_blasted"]).is_equal(0)
	assert_float(result["worst"]).is_less_equal(BotGrenadier.HARMLESS_SHARE + 0.001)


## The free soak: however often the bots throw on this night, no bot is hurt past the limit and no
## teammate at all. (That
## they throw at all is the scripted night's to prove.)
func test_the_bots_do_not_hurt_themselves_or_the_team_in_a_night() -> void:
	for seed_value: int in SEEDS:
		var result := await _night(seed_value)
		print(
			(
				(
					"grenade soak seed %d: %d bot blasts, worst share of the thrower's health %.3f, "
					+ "%d reached the thrower at all, %d player_blasted events on a teammate"
				)
				% [
					seed_value,
					result["blasts"],
					result["worst"],
					result["hurt_events"],
					result["mates_blasted"]
				]
			)
		)
		(
			assert_float(result["worst"])
			. override_failure_message("seed %d" % seed_value)
			. is_less_equal(BotGrenadier.HARMLESS_SHARE + 0.001)
		)
