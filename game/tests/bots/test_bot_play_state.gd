# gdlint:disable=max-public-methods
# The bots' play states (#693): a bot plays boldly while healthy, carefully when hurt and safely
# when low, with two numbers for every switch so it does not flicker, and the state changes what it
# does under each order. The state machine on its own (`BotPlayState`), then a bot on a `BotRig`.
extends GdUnitTestSuite

const SPOT := Vector3(0.0, 0.0, 0.0)


func _me(share: float) -> Dictionary:
	return {"health": share * 100.0, "max_health": 100.0}


func _states() -> BotPlayState:
	return BotPlayState.new(BotProfile.veteran())


## Feeds one share a second for each of `shares`, starting at `from`; returns the states reached.
func _walk(play: BotPlayState, shares: Array[float], from := 10.0, step := 1.0) -> Array[int]:
	var seen: Array[int] = []
	var now := from
	for share in shares:
		seen.append(play.update(_me(share), 0, now))
		now += step
	return seen


# --- The state machine ---


func test_a_healthy_bot_is_aggressive() -> void:
	var play := _states()
	assert_int(play.update(_me(1.0), 0, 0.0)).is_equal(BotPlayState.State.AGGRESSIVE)
	assert_str(str(play.state_name())).is_equal("aggressive")


func test_health_takes_a_bot_down_through_careful_to_safe() -> void:
	var play := _states()
	assert_int(play.update(_me(0.55), 0, 1.0)).is_equal(BotPlayState.State.CAREFUL)
	assert_int(play.update(_me(0.30), 0, 2.0)).is_equal(BotPlayState.State.SAFE)
	# A bot that loses it all at once goes straight to safe.
	var other := _states()
	assert_int(other.update(_me(0.2), 0, 1.0)).is_equal(BotPlayState.State.SAFE)


func test_each_switch_has_two_numbers_so_a_bot_at_the_edge_does_not_flicker() -> void:
	var profile := BotProfile.veteran()
	var play := BotPlayState.new(profile)
	play.update(_me(0.3), 0, 0.0)
	assert_int(play.state).is_equal(BotPlayState.State.SAFE)
	# Just over the line it went down at is not enough to come back up.
	var edge := profile.safe_below + 0.05
	assert_float(edge).is_less(profile.safe_above)
	var seen := _walk(play, [edge, edge - 0.02, edge + 0.03, edge], 10.0)
	for state in seen:
		assert_int(state).is_equal(BotPlayState.State.SAFE)
	assert_int(play.changes).is_equal(1)
	# Past the second number it does.
	assert_int(play.update(_me(profile.safe_above + 0.01), 0, 20.0)).is_equal(
		BotPlayState.State.CAREFUL
	)


func test_health_wobbling_across_the_down_line_changes_the_state_once() -> void:
	var profile := BotProfile.veteran()
	var play := BotPlayState.new(profile)
	var wobble: Array[float] = []
	for i in 40:
		wobble.append(profile.careful_below + (0.04 if i % 2 == 0 else -0.04))
	_walk(play, wobble, 10.0, 0.25)
	# Aggressive to careful once, then the wobble stays under `aggressive_above`.
	assert_int(play.changes).is_equal(1)
	assert_int(play.state).is_equal(BotPlayState.State.CAREFUL)


func test_a_bot_becomes_bolder_only_after_the_dwell_and_more_careful_at_once() -> void:
	var profile := BotProfile.veteran()
	var play := BotPlayState.new(profile)
	play.update(_me(0.5), 0, 10.0)
	assert_int(play.state).is_equal(BotPlayState.State.CAREFUL)
	# Fully healed a moment later: not yet.
	assert_int(play.update(_me(1.0), 0, 10.5)).is_equal(BotPlayState.State.CAREFUL)
	assert_int(play.update(_me(1.0), 0, 10.0 + profile.play_state_dwell + 0.1)).is_equal(
		BotPlayState.State.AGGRESSIVE
	)
	# A blow takes it down with no wait.
	assert_int(play.update(_me(0.5), 0, 12.2)).is_equal(BotPlayState.State.CAREFUL)


func test_the_dead_close_in_count_as_lost_health() -> void:
	var profile := BotProfile.veteran()
	var play := BotPlayState.new(profile)
	# Full health with a crowd on it: the cost is capped, and it is enough to be careful.
	play.update(_me(1.0), 20, 5.0)
	assert_float(play.share).is_equal_approx(1.0 - profile.pressure_cap, 0.001)
	assert_int(play.state).is_equal(BotPlayState.State.AGGRESSIVE)
	var crowded := BotPlayState.new(profile)
	crowded.update(_me(0.8), 20, 5.0)
	assert_int(crowded.state).is_equal(BotPlayState.State.CAREFUL)
	# One zombie is not a crowd.
	var one := BotPlayState.new(profile)
	one.update(_me(0.8), 1, 5.0)
	assert_int(one.state).is_equal(BotPlayState.State.AGGRESSIVE)


func test_a_revived_bot_starts_over() -> void:
	var play := _states()
	play.update(_me(0.1), 0, 1.0)
	play.reset()
	assert_int(play.state).is_equal(BotPlayState.State.AGGRESSIVE)


func test_the_share_is_of_the_bots_own_full_health() -> void:
	var play := _states()
	# 180 of 300 is 0.6: careful, though 180 is more than a hundred.
	assert_int(play.update({"health": 180.0, "max_health": 300.0}, 0, 1.0)).is_equal(
		BotPlayState.State.CAREFUL
	)


# --- What a state asks of the bot ---


func test_a_state_asks_more_distance_the_lower_the_health() -> void:
	var play := _states()
	assert_float(play.margin(1.25)).is_equal(1.25)
	play.update(_me(0.5), 0, 1.0)
	assert_float(play.margin(1.25)).is_equal(BotProfile.veteran().careful_margin)
	play.update(_me(0.2), 0, 2.0)
	assert_float(play.margin(1.25)).is_equal(BotProfile.veteran().safe_margin)
	# A profile that already keeps more keeps it.
	assert_float(play.margin(9.0)).is_equal(9.0)


func test_only_a_healthy_bot_pushes_and_only_a_low_one_stops_wandering() -> void:
	var play := _states()
	assert_bool(play.may_push()).is_true()
	assert_bool(play.may_wander()).is_true()
	play.update(_me(0.5), 0, 1.0)
	assert_bool(play.may_push()).is_false()
	assert_bool(play.may_wander()).is_true()
	play.update(_me(0.2), 0, 2.0)
	assert_bool(play.may_push()).is_false()
	assert_bool(play.may_wander()).is_false()
	assert_bool(play.prefers_open_ground()).is_true()


func test_a_low_bot_gives_a_revive_up_under_pressure_unless_it_is_the_last_one() -> void:
	var play := _states()
	assert_bool(play.gives_up_revive(2.0, false)).is_false()
	play.update(_me(0.2), 0, 1.0)
	assert_bool(play.gives_up_revive(2.0, false)).is_true()
	assert_bool(play.gives_up_revive(2.0, true)).is_false()
	# Nothing near: it goes.
	assert_bool(play.gives_up_revive(40.0, false)).is_false()


func test_a_low_follower_keeps_the_near_side_of_the_band() -> void:
	var play := _states()
	assert_vector(play.follow_band()).is_equal(Vector2.ZERO)
	play.update(_me(0.2), 0, 1.0)
	assert_vector(play.follow_band()).is_equal(BotProfile.veteran().safe_follow_band)
	assert_float(play.follow_band().y).is_less(BotFollow.FIGHT_BAND.y)


func test_a_low_holder_may_back_off_a_few_metres_only() -> void:
	var play := _states()
	assert_bool(play.may_back_off_hold(0.0)).is_false()
	play.update(_me(0.2), 0, 1.0)
	var back := BotProfile.veteran().hold_back
	assert_bool(play.may_back_off_hold(back - 0.5)).is_true()
	assert_bool(play.may_back_off_hold(back + 0.5)).is_false()
	# It is not called back to the spot while it stands within the stretch.
	assert_bool(play.stays_off_hold(back)).is_true()
	assert_bool(play.stays_off_hold(back + 3.0)).is_false()


func test_with_the_states_off_every_answer_is_the_aggressive_bots() -> void:
	var play := _states()
	play.enabled = false
	play.update(_me(0.1), 5, 1.0)
	# The state is read (the soak counts it) and nothing follows from it.
	assert_int(play.state).is_equal(BotPlayState.State.SAFE)
	assert_bool(play.may_push()).is_true()
	assert_bool(play.may_wander()).is_true()
	assert_bool(play.prefers_open_ground()).is_false()
	assert_float(play.margin(1.25)).is_equal(1.25)
	assert_bool(play.gives_up_revive(1.0, false)).is_false()
	assert_bool(play.may_back_off_hold(0.0)).is_false()
	assert_bool(play.stays_off_hold(0.0)).is_false()
	assert_vector(play.follow_band()).is_equal(Vector2.ZERO)


# --- A bot on the rig ---


func _wants_to_back_away(rig: BotRig) -> bool:
	return rig.bot.intent.note == "retreat"


func test_a_low_bot_backs_away_from_a_zombie_a_healthy_one_stands_and_shoots() -> void:
	var healthy := BotRig.new(BotProfile.veteran(), 4)
	healthy.put_zombie(1, Vector3(0, 0, -4))
	healthy.run(90)
	assert_bool(_wants_to_back_away(healthy)).is_false()
	var low := BotRig.new(BotProfile.veteran(), 4)
	low.health = 20.0
	low.put_zombie(1, Vector3(0, 0, -4))
	low.run(90)
	assert_str((low.bot.brain as BotFightBrain).play_state_name()).is_equal("safe")
	assert_bool(_wants_to_back_away(low)).is_true()
	assert_bool(low.bot.intent.reflex != Vector3.ZERO).is_true()
	# It does not stop shooting while it backs away.
	assert_bool(low.shot_ticks.is_empty()).is_false()


func test_with_the_states_off_a_low_bot_stands_like_a_healthy_one() -> void:
	# The soak's before: the same night with `--no-states`.
	var rig := BotRig.new(BotProfile.veteran(), 4)
	(rig.bot.brain as BotFightBrain).play.enabled = false
	rig.health = 20.0
	rig.put_zombie(1, Vector3(0, 0, -4))
	rig.run(90)
	assert_str((rig.bot.brain as BotFightBrain).play_state_name()).is_equal("safe")
	assert_bool(_wants_to_back_away(rig)).is_false()


func test_a_hurt_bot_keeps_a_wider_margin_than_a_healthy_one() -> void:
	# A zombie 2 m away: inside a careful bot's 2.5 m, outside a healthy one's 1.25 m.
	var healthy := BotRig.new(BotProfile.veteran(), 4)
	healthy.put_zombie(1, Vector3(0, 0, -2))
	healthy.run(90)
	assert_bool(_wants_to_back_away(healthy)).is_false()
	var hurt := BotRig.new(BotProfile.veteran(), 4)
	hurt.health = 50.0
	hurt.put_zombie(1, Vector3(0, 0, -2))
	hurt.run(90)
	assert_str((hurt.bot.brain as BotFightBrain).play_state_name()).is_equal("careful")
	assert_bool(_wants_to_back_away(hurt)).is_true()


func _hold_rig(health: float, apart: float) -> BotRig:
	var orders := BotOrders.new()
	orders.issue(BotOrders.HOLD, 9, SPOT)
	var rig := BotRig.new(BotProfile.veteran(), 4)
	rig.orders = orders.to_frame()
	rig.health = health
	rig.position = SPOT + Vector3(0.0, 0.0, apart)
	rig.put_zombie(1, rig.position + Vector3(0, 0, -3))
	rig.run(90)
	return rig


func test_a_healthy_holder_never_backs_off_its_spot() -> void:
	var rig := _hold_rig(100.0, 0.0)
	assert_bool(_wants_to_back_away(rig)).is_false()


func test_a_low_holder_steps_back_within_a_few_metres_of_the_spot_and_no_farther() -> void:
	var near := _hold_rig(20.0, 1.0)
	assert_str((near.bot.brain as BotFightBrain).play_state_name()).is_equal("safe")
	assert_bool(_wants_to_back_away(near)).is_true()
	var far := _hold_rig(20.0, BotProfile.veteran().hold_back + 1.5)
	assert_bool(_wants_to_back_away(far)).is_false()


func test_a_low_holders_retreat_is_not_pulled_back_to_the_spot() -> void:
	# The zombie is on the spot's side: the heading goes away from it, and is not bent to the spot.
	var rig := _hold_rig(20.0, 1.0)
	var reflex := rig.bot.intent.reflex
	assert_bool(reflex != Vector3.ZERO).is_true()
	# The zombie is toward -z of the bot: away from it is toward +z.
	assert_float(reflex.z).is_greater(0.0)


func test_the_state_is_counted_as_the_bot_changes_it() -> void:
	var rig := BotRig.new(BotProfile.veteran(), 4)
	rig.run(30)
	rig.health = 20.0
	rig.run(30)
	assert_int(int(rig.bot.telemetry.counters.get(&"play_state_changes", 0))).is_equal(1)


func test_a_bot_with_a_tonic_judges_its_health_against_its_own_full() -> void:
	# 120 of 300 is 0.4 (safe), where 120 of a hundred would be a bot at its best.
	var rig := BotRig.new(BotProfile.veteran(), 4)
	rig.max_health = 300.0
	rig.health = 120.0
	rig.run(30)
	assert_str((rig.bot.brain as BotFightBrain).play_state_name()).is_equal("safe")
	assert_float(rig.bot.perception.beliefs.max_health).is_equal(300.0)


func test_the_bot_reads_its_full_health_from_the_events_about_it_only() -> void:
	var rig := BotRig.new(BotProfile.veteran(), 4)
	rig.step(
		[
			{
				"type": &"player_hurt",
				"player_id": 7,
				"damage": 5.0,
				"health": 1.0,
				"max_health": 500.0
			}
		]
	)
	assert_float(rig.bot.perception.beliefs.max_health).is_equal(100.0)
	(
		rig
		. step(
			[
				{
					"type": &"player_healed",
					"player_id": BotRig.ME,
					"health": 100.0,
					"max_health": 150.0,
					"reason": &"tonic",
				}
			]
		)
	)
	assert_float(rig.bot.perception.beliefs.max_health).is_equal(150.0)
