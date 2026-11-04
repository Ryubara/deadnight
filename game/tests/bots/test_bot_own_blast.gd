# A bot keeps out of the grenade it threw, and only that one (#872): only the thrower takes a
# grenade's damage (#856). In reach of the blast it steps out; farther off, while the fuse burns, it
# stands and fights instead of walking on toward it (a follow, a chase, an errand), because a runner
# covers the ten metres from the edge of the blast to its middle in the two seconds that are left.
extends GdUnitTestSuite

const BLAST_AT := Vector3(0.0, 0.0, -20.0)
## Past the end of any test.
const UNTIL := 1000.0


func _rig(apart: float, owner: int = BotRig.ME) -> BotRig:
	var rig := BotRig.new(BotProfile.regular(), 5)
	rig.profile.follows = true
	rig.position = BLAST_AT + Vector3(0.0, 0.0, apart)
	rig.bot.team.add_blast(BLAST_AT, UNTIL, owner)
	return rig


func test_a_bot_in_reach_of_its_own_live_grenade_steps_out() -> void:
	var rig := _rig(5.0)
	rig.run(60)
	assert_str(rig.bot.intent.note).is_equal("retreat")


func test_a_bot_farther_off_stands_instead_of_walking_toward_it() -> void:
	var rig := _rig(12.0)
	rig.run(60)
	assert_str(rig.bot.intent.note).is_equal("blast_wait")
	assert_bool(rig.bot.intent.goal.is_finite()).is_false()


func test_a_bot_far_from_its_grenade_goes_on_as_before() -> void:
	var rig := _rig(BotGrenadier.WAIT_RANGE + 4.0)
	rig.run(60)
	assert_str(rig.bot.intent.note).is_not_equal("blast_wait")


func test_a_grenade_another_bot_threw_is_none_of_this_bots_business() -> void:
	# Nothing of it reaches this bot (#856): it neither steps out nor stands for it.
	var rig := _rig(5.0, BotRig.ME + 1)
	rig.run(60)
	assert_str(rig.bot.intent.note).is_not_equal("retreat")
	assert_str(rig.bot.intent.note).is_not_equal("blast_wait")


func test_the_wait_ends_with_the_blast() -> void:
	var rig := _rig(12.0)
	rig.bot.team.blasts.clear()
	rig.bot.team.add_blast(BLAST_AT, 0.5, BotRig.ME)
	rig.run(90)
	assert_str(rig.bot.intent.note).is_not_equal("blast_wait")


func test_the_team_keeps_each_blast_to_its_thrower() -> void:
	var team := BotTeam.new()
	team.add_blast(BLAST_AT, UNTIL, 2)
	var here := BLAST_AT + Vector3(0.0, 0.0, 3.0)
	assert_array(team.blasts_near(here, 8.0, 0.0, 2)).has_size(1)
	assert_array(team.blasts_near(here, 8.0, 0.0, 3)).is_empty()
	assert_array(team.blasts_near(here, 2.0, 0.0, 2)).is_empty()
	assert_array(team.blasts_near(here, 8.0, UNTIL + 1.0, 2)).is_empty()


func test_the_blast_is_where_the_grenade_lies_not_where_it_was_aimed() -> void:
	var team := BotTeam.new()
	team.add_blast(BLAST_AT, UNTIL, 2)
	team.add_blast(BLAST_AT + Vector3(20.0, 0.0, 0.0), UNTIL, 3)
	team.grenade_flying(2, 71)
	team.grenade_flying(3, 72)
	# Another bot's grenade, and one nobody threw, move nothing of ours.
	var lies := BLAST_AT + Vector3(0.0, 0.0, 5.0)
	team.grenade_lies(72, lies + Vector3(50.0, 0.0, 0.0))
	team.grenade_lies(99, lies)
	assert_array(team.blasts_near(lies, 1.0, 0.0, 2)).is_empty()
	team.grenade_lies(71, lies)
	assert_array(team.blasts_near(lies, 1.0, 0.0, 2)).has_size(1)
	assert_array(team.blasts_near(BLAST_AT, 1.0, 0.0, 2)).is_empty()


func test_a_grenade_that_lies_short_of_the_aim_is_stepped_out_of() -> void:
	# Aimed 20 m off, a wall or a prop dropped it 4 m from the bot: the bot hears where it lies.
	var rig := _rig(24.0)
	rig.run(5)
	(
		rig
		. bot
		. hear(
			[
				{"type": &"grenade_thrown", "thrower_id": BotRig.ME, "grenade_id": 7},
				{
					"type": &"grenade_bounced",
					"grenade_id": 7,
					"point": rig.position + Vector3(0.0, 0.0, -4.0),
					"speed": 3.0,
					"wall": true,
					"zombie_id": -1,
				}
			]
		)
	)
	rig.run(30)
	assert_str(rig.bot.intent.note).is_equal("retreat")
