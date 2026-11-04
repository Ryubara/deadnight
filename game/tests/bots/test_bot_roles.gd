# Roles as stances (bots plan, phase 5): the maintainer is whoever's turn it is, one bot flanks only
# when a person keeps an anchor besides, a role is kept ten seconds, and the flank's place is 8 to
# 10 m to the side of the way the people are going (inside the follow band).
extends GdUnitTestSuite

const HERE := Vector3.ZERO


func _bots(count: int) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for i in count:
		found.append({"id": 2 + i, "pos": Vector3(float(i) * 3.0 - 3.0, 0.0, 4.0)})
	return found


func _people(count := 1, velocity := Vector3.ZERO) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for i in count:
		found.append(
			{"pos": Vector3(float(i) * 2.0, 0.0, 0.0), "velocity": velocity, "facing": 0.0}
		)
	return found


func _roles_of(roles: BotRoles, ids: Array[int]) -> Array:
	return ids.map(func(id: int) -> int: return roles.role_of(id))


func test_with_no_person_every_bot_is_an_anchor() -> void:
	var roles := BotRoles.new()
	var none: Array[Dictionary] = []
	roles.update(0.0, _bots(4), none, 0)
	for id in [2, 3, 4, 5]:
		assert_int(roles.role_of(id)).is_equal(BotRoles.Role.ANCHOR)


func test_one_bot_with_one_person_anchors_and_two_bots_leave_one_to_flank() -> void:
	var roles := BotRoles.new()
	roles.update(0.0, _bots(1), _people(), 0)
	assert_int(roles.role_of(2)).is_equal(BotRoles.Role.ANCHOR)
	var team := BotRoles.new()
	team.update(0.0, _bots(2), _people(), 0)
	var seen := [team.role_of(2), team.role_of(3)]
	assert_array(seen).contains_exactly_in_any_order([BotRoles.Role.ANCHOR, BotRoles.Role.FLANK])


func test_every_person_keeps_an_anchor() -> void:
	var roles := BotRoles.new()
	roles.update(0.0, _bots(3), _people(2), 0)
	var flanking := 0
	for id in [2, 3, 4]:
		if roles.role_of(id) == BotRoles.Role.FLANK:
			flanking += 1
	assert_int(flanking).is_equal(1)
	var thin := BotRoles.new()
	thin.update(0.0, _bots(2), _people(2), 0)
	for id in [2, 3]:
		assert_int(thin.role_of(id)).is_equal(BotRoles.Role.ANCHOR)


func test_the_bot_whose_turn_it_is_to_go_on_an_errand_is_the_maintainer() -> void:
	var roles := BotRoles.new()
	roles.update(0.0, _bots(3), _people(), 3)
	assert_int(roles.role_of(3)).is_equal(BotRoles.Role.MAINTAINER)
	var others := [roles.role_of(2), roles.role_of(4)]
	assert_array(others).contains_exactly_in_any_order([BotRoles.Role.ANCHOR, BotRoles.Role.FLANK])
	# It goes back to the band as soon as the turn is over (the next assignment).
	roles.update(BotRoles.REASSIGN_EVERY + 0.1, _bots(3), _people(), 0)
	assert_int(roles.role_of(3)).is_not_equal(BotRoles.Role.MAINTAINER)


func test_a_role_is_kept_ten_seconds_and_the_flank_does_not_swap_with_a_nearer_bot() -> void:
	var roles := BotRoles.new()
	roles.update(0.0, _bots(3), _people(), 0)
	var flank := 0
	for id in [2, 3, 4]:
		if roles.role_of(id) == BotRoles.Role.FLANK:
			flank = id
	# The bots move about; nothing changes before the sticky time, and the flank stays flank.
	var moved: Array[Dictionary] = [
		{"id": 2, "pos": Vector3(9, 0, 9)},
		{"id": 3, "pos": Vector3(-9, 0, 2)},
		{"id": 4, "pos": HERE}
	]
	roles.update(BotRoles.REASSIGN_EVERY + 0.1, moved, _people(), 0)
	assert_int(roles.role_of(flank)).is_equal(BotRoles.Role.FLANK)
	roles.update(BotRoles.STICKY + 1.0, moved, _people(), 0)
	assert_int(roles.role_of(flank)).is_equal(BotRoles.Role.FLANK)


func test_the_flank_gives_up_its_place_when_the_people_are_gone_after_the_sticky_time() -> void:
	var roles := BotRoles.new()
	roles.update(0.0, _bots(3), _people(), 0)
	var none: Array[Dictionary] = []
	roles.update(BotRoles.REASSIGN_EVERY + 0.1, _bots(3), none, 0)
	var flanking := 0
	for id in [2, 3, 4]:
		if roles.role_of(id) == BotRoles.Role.FLANK:
			flanking += 1
	assert_int(flanking).is_equal(1)
	roles.update(BotRoles.STICKY + 1.0, _bots(3), none, 0)
	for id in [2, 3, 4]:
		assert_int(roles.role_of(id)).is_equal(BotRoles.Role.ANCHOR)


func test_a_bot_that_leaves_loses_its_role() -> void:
	var roles := BotRoles.new()
	roles.update(0.0, _bots(3), _people(), 0)
	roles.update(BotRoles.REASSIGN_EVERY + 0.1, _bots(2), _people(), 0)
	assert_int(roles.role_of(4)).is_equal(BotRoles.Role.ANCHOR)


func test_the_flank_holds_eight_to_ten_metres_to_the_side_of_the_heading() -> void:
	var walking := _people(1, Vector3(0, 0, -3.0))
	var place := BotRoles.flank_centre(walking)
	assert_float(Vector2(place.x, place.z).length()).is_between(
		BotRoles.FLANK_NEAR, BotRoles.FLANK_FAR
	)
	# Beside the way they go, not ahead of or behind them.
	assert_float(absf(place.z)).is_less(0.01)
	var standing := _people(1)
	standing[0]["facing"] = PI * 0.5
	var there := BotRoles.flank_centre(standing)
	assert_float(Vector2(there.x, there.z).length()).is_between(
		BotRoles.FLANK_NEAR, BotRoles.FLANK_FAR
	)


func test_the_flank_holds_only_while_the_people_stand_and_never_far_from_them() -> void:
	assert_float(BotRoles.speed_of(_people(2))).is_equal(0.0)
	assert_float(BotRoles.speed_of(_people(2, Vector3(0, 0, -3.0)))).is_equal_approx(3.0, 0.001)
	assert_float(BotRoles.speed_of(_people(2, Vector3(0, 0, -3.0)))).is_greater(
		BotRoles.FLANK_STILL
	)
	var people := _people(1)
	var far := BotRoles.within_limit(Vector3(30, 0, 0), people)
	assert_float(Vector2(far.x, far.z).length()).is_equal_approx(BotRoles.FLANK_LIMIT, 0.001)
	var near := Vector3(5, 0, 1)
	assert_vector(BotRoles.within_limit(near, people)).is_equal(near)


func test_the_flank_stays_inside_the_follow_band_with_the_slack_of_standing_at_its_place() -> void:
	# A flank is still with the person: its farthest place is the band's far edge, and a bot standing
	# at the edge of its place (`HOLD_RADIUS` and a half) is still within the 12 m the follow counts.
	assert_float(BotRoles.FLANK_FAR).is_equal(BotFollow.CALM_BAND.y)
	assert_float(BotRoles.FLANK_LIMIT).is_less_equal(BotFollow.CALM_BAND.y)
	assert_float(BotRoles.FLANK_LIMIT + BotFightBrain.HOLD_RADIUS * 1.5).is_less_equal(12.0)


func test_the_flank_has_places_on_both_sides_nearer_and_farther_to_try() -> void:
	var people := _people(1, Vector3(0, 0, -3.0))
	var choices := BotRoles.flank_choices(people)
	assert_int(choices.size()).is_equal(4)
	for place in choices:
		assert_float(Vector2(place.x, place.z).length()).is_between(
			BotRoles.FLANK_NEAR, BotRoles.FLANK_FAR
		)
	# The first is the place `flank_centre` names; another is across the group from it.
	assert_vector(choices[0]).is_equal(BotRoles.flank_centre(people))
	assert_float(choices[0].x * choices[1].x).is_less(0.0)
