extends GdUnitTestSuite
## The level curve: 18,010 XP to level 55, a table by tier of five that rises and never goes flat,
## and the level computed from raw XP so a retune needs no migration.


func test_the_table_is_the_designs_and_adds_up_to_18010() -> void:
	assert_array(LevelCurve.TIER_COSTS).is_equal(
		[85, 135, 185, 235, 290, 340, 390, 440, 490, 540, 590]
	)
	assert_int(LevelCurve.TIER_NAMES.size()).is_equal(LevelCurve.TIER_COSTS.size())
	assert_int(LevelCurve.total()).is_equal(18010)
	var summed := 0
	for level in range(1, LevelCurve.MAX_LEVEL):
		summed += LevelCurve.to_leave(level)
	assert_int(summed).is_equal(18010)


func test_every_tier_asks_more_than_the_one_before() -> void:
	for tier in range(1, LevelCurve.TIER_COSTS.size()):
		assert_int(LevelCurve.TIER_COSTS[tier]).is_greater(LevelCurve.TIER_COSTS[tier - 1])
	# Levels 51 to 54 all cost 590: it rises to the end and is flat nowhere before it.
	for level in range(51, 55):
		assert_int(LevelCurve.to_leave(level)).is_equal(590)
	assert_int(LevelCurve.to_leave(50)).is_equal(540)
	assert_int(LevelCurve.to_leave(LevelCurve.MAX_LEVEL)).is_equal(0)


func test_tiers_of_five_with_the_last_one_holding_level_55() -> void:
	assert_int(LevelCurve.tier_of(1)).is_equal(0)
	assert_int(LevelCurve.tier_of(5)).is_equal(0)
	assert_int(LevelCurve.tier_of(6)).is_equal(1)
	assert_int(LevelCurve.tier_of(10)).is_equal(1)
	assert_int(LevelCurve.tier_of(54)).is_equal(10)
	assert_int(LevelCurve.tier_of(55)).is_equal(10)
	assert_str(LevelCurve.tier_name(1)).is_equal("Doors Open")
	assert_str(LevelCurve.tier_name(55)).is_equal("Last Reel")
	# Outside the ladder is clamped into it.
	assert_int(LevelCurve.tier_of(0)).is_equal(0)
	assert_int(LevelCurve.tier_of(99)).is_equal(10)


func test_the_curve_at_every_tier_edge() -> void:
	# Level 5 ends the first tier (4 x 85 in, 85 to go), level 6 opens the second (135 a level).
	assert_int(LevelCurve.xp_for(5)).is_equal(340)
	assert_int(LevelCurve.xp_for(6)).is_equal(425)
	assert_int(LevelCurve.level_of(424)).is_equal(5)
	assert_int(LevelCurve.level_of(425)).is_equal(6)
	assert_int(LevelCurve.xp_for(10)).is_equal(965)
	assert_int(LevelCurve.xp_for(54)).is_equal(17420)
	assert_int(LevelCurve.xp_for(55)).is_equal(18010)
	assert_int(LevelCurve.level_of(17419)).is_equal(53)
	assert_int(LevelCurve.level_of(17420)).is_equal(54)
	assert_int(LevelCurve.level_of(18009)).is_equal(54)
	assert_int(LevelCurve.level_of(18010)).is_equal(55)


func test_xp_past_level_55_is_kept_and_shows_a_full_bar() -> void:
	assert_int(LevelCurve.level_of(18010 + 100000)).is_equal(55)
	assert_int(LevelCurve.to_next(18010 + 5)).is_equal(0)
	assert_float(LevelCurve.fraction(18010 + 5)).is_equal(1.0)
	assert_int(LevelCurve.xp_for(80)).is_equal(18010)


func test_the_first_level_and_the_bar_inside_a_level() -> void:
	assert_int(LevelCurve.level_of(0)).is_equal(1)
	assert_int(LevelCurve.level_of(-5)).is_equal(1)
	assert_int(LevelCurve.to_next(0)).is_equal(85)
	assert_int(LevelCurve.to_next(60)).is_equal(25)
	assert_int(LevelCurve.xp_in_level(60)).is_equal(60)
	assert_float(LevelCurve.fraction(0)).is_equal(0.0)
	assert_float(LevelCurve.fraction(60)).is_equal_approx(60.0 / 85.0, 0.0001)
	# Inside level 10 (135 a level): 50 in.
	var inside := LevelCurve.xp_for(10) + 50
	assert_int(LevelCurve.xp_in_level(inside)).is_equal(50)
	assert_float(LevelCurve.fraction(inside)).is_equal_approx(50.0 / 135.0, 0.0001)


func test_xp_for_and_level_of_agree_at_every_level() -> void:
	for level in range(1, LevelCurve.MAX_LEVEL + 1):
		assert_int(LevelCurve.level_of(LevelCurve.xp_for(level))).is_equal(level)
		if level > 1:
			assert_int(LevelCurve.level_of(LevelCurve.xp_for(level) - 1)).is_equal(level - 1)
