# Bots do not hurt themselves or the team with grenades (#805). A grenade blast hurts a player all
# the way out to its radius (`PlayerBlast`), so a bot that chose a throw as before would hurt
# someone in a crowd. Three bots follow a person round the lot and fight the dead for a few minutes
# of game time on several seeds; every blast they make is measured against where every player stood
# when it went off, from the bodies, not from the server's own events. No one is touched by more
# than `BotGrenadier.HARMLESS_SHARE` of their health. The numbers are printed for the pull request.
extends GdUnitTestSuite

const STEP := Night.STEP
const SEEDS := [11, 12]
## Game seconds each seeded night runs.
const SECONDS := 90
## A person's tour of the field for the bots to follow (offsets from the field's home).
const TOUR := [
	Vector3(-20.0, 0.0, 0.0),
	Vector3(-20.0, 0.0, 14.0),
	Vector3(20.0, 0.0, 14.0),
	Vector3(20.0, 0.0, 0.0),
	Vector3(0.0, 0.0, 0.0),
]


## One night: the grenades the bots threw, and the worst share of anyone's health any blast took.
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
	var def := night.server.grenades.def
	var result := {"blasts": 0, "worst": 0.0, "hurt_events": 0, "bots_hurt_events": 0}
	night.on_event = func(event: Dictionary) -> void:
		if event["type"] == &"player_blasted" and event["player_id"] != 1:
			result["bots_hurt_events"] += 1
		if event["type"] != &"grenade_exploded" or event["thrower_id"] == 1:
			return
		result["blasts"] += 1
		for id: int in night.server.rules.players:
			var chest := night.server.body_of(id).global_position + Vector3.UP * def.player_chest
			var share := PlayerBlast.share(
				(event["point"] as Vector3).distance_to(chest),
				def.player_full_radius,
				def.blast_radius
			)
			result["worst"] = maxf(result["worst"], share)
			result["hurt_events"] += 1 if share > 0.0 else 0
	var leg := 0
	walker.goto(Autopilot.HOME + TOUR[0])
	for _tick in SECONDS * 60:
		night.tick()
		if walker.arrived():
			leg = (leg + 1) % TOUR.size()
			walker.goto(Autopilot.HOME + TOUR[leg])
	night.dispose()
	return result


func test_the_bots_throw_without_hurting_themselves_or_the_team() -> void:
	var blasts := 0
	for seed_value: int in SEEDS:
		var result := await _night(seed_value)
		print(
			(
				(
					"grenade soak seed %d: %d bot blasts, worst share of anyone's health %.3f, "
					+ "%d reached a player at all, %d player_blasted events on the bots"
				)
				% [
					seed_value,
					result["blasts"],
					result["worst"],
					result["hurt_events"],
					result["bots_hurt_events"]
				]
			)
		)
		blasts += result["blasts"]
		(
			assert_float(result["worst"])
			. override_failure_message("seed %d" % seed_value)
			. is_less_equal(BotGrenadier.HARMLESS_SHARE + 0.001)
		)
	# The soak is not proof of nothing: the bots did throw.
	assert_int(blasts).is_greater(0)
