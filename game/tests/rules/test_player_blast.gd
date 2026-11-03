extends GdUnitTestSuite
## What a blast takes from a player's health (`PlayerBlast`), the one rule the grenade and the ray
## gun's own splash share: all of it inside the full radius, less with the distance, none at the
## edge.

const FULL := 1.0
const EDGE := 8.0


func test_all_of_it_inside_the_full_radius() -> void:
	assert_float(PlayerBlast.share(0.0, FULL, EDGE)).is_equal(1.0)
	assert_float(PlayerBlast.share(FULL, FULL, EDGE)).is_equal(1.0)
	assert_float(PlayerBlast.damage(100.0, 0.5, FULL, EDGE)).is_equal(100.0)


func test_none_at_the_edge_and_beyond_it() -> void:
	assert_float(PlayerBlast.share(EDGE, FULL, EDGE)).is_equal(0.0)
	assert_float(PlayerBlast.share(EDGE + 5.0, FULL, EDGE)).is_equal(0.0)


func test_less_the_further_out_and_never_more_than_the_step_before() -> void:
	var before := 1.0
	for step in range(1, 70):
		var share := PlayerBlast.share(FULL + float(step) * 0.1, FULL, EDGE)
		assert_float(share).is_less_equal(before)
		assert_float(share).is_between(0.0, 1.0)
		before = share


func test_the_numbers_the_maintainer_asked_for() -> void:
	# A few metres off hurts a good part of the health and does not down; a fifth at five metres.
	assert_float(PlayerBlast.share(3.0, FULL, EDGE)).is_between(0.4, 0.6)
	assert_float(PlayerBlast.share(5.0, FULL, EDGE)).is_between(0.1, 0.3)


func test_damage_is_a_share_of_the_health_bar_and_scales() -> void:
	assert_float(PlayerBlast.damage(150.0, 0.0, FULL, EDGE)).is_equal(150.0)
	assert_float(PlayerBlast.damage(100.0, 0.0, FULL, EDGE, 0.25)).is_equal(25.0)
	var half_out := PlayerBlast.damage(100.0, 4.5, FULL, EDGE)
	assert_float(PlayerBlast.damage(100.0, 4.5, FULL, EDGE, 0.25)).is_equal_approx(
		half_out * 0.25, 0.0001
	)


func test_a_distance_that_is_not_a_number_hurts_nobody() -> void:
	assert_float(PlayerBlast.share(NAN, FULL, EDGE)).is_equal(0.0)
	assert_float(PlayerBlast.share(INF, FULL, EDGE)).is_equal(0.0)


func test_a_span_of_no_width_does_not_divide_by_zero() -> void:
	assert_float(PlayerBlast.share(2.0, 2.0, 2.0)).is_equal(1.0)
	assert_float(PlayerBlast.share(2.1, 2.0, 2.0)).is_equal(0.0)


func test_the_distance_for_a_share_is_the_inverse_of_the_share() -> void:
	for wanted in [0.05, 0.1, 0.25, 0.5, 0.9]:
		var apart := PlayerBlast.distance_for(wanted, FULL, EDGE)
		assert_float(PlayerBlast.share(apart, FULL, EDGE)).is_equal_approx(wanted, 0.0001)
	assert_float(PlayerBlast.distance_for(1.0, FULL, EDGE)).is_equal(FULL)
	assert_float(PlayerBlast.distance_for(0.0, FULL, EDGE)).is_equal(EDGE)
