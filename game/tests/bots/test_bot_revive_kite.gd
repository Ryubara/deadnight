# The last bot up kites the dead while a teammate lies down and the revive is not safe (Deadnight
# #767), unless its profile says it does not: the simulator's weak players never do, the one left
# stands where it is. Only the Rookie's profile turns the kite off.
extends GdUnitTestSuite


func test_the_regular_and_the_veteran_kite_when_they_survive() -> void:
	for profile: BotProfile in [BotProfile.regular(), BotProfile.veteran()]:
		var revive := BotRevive.new(profile)
		revive.mode = BotRevive.Mode.SURVIVE
		assert_float(revive.kite_margin()).is_equal(BotRevive.KITE_MARGIN)


func test_the_rookie_does_not_kite_when_it_survives() -> void:
	var revive := BotRevive.new(BotProfile.rookie())
	revive.mode = BotRevive.Mode.SURVIVE
	assert_float(revive.kite_margin()).is_equal(0.0)


func test_no_bot_keeps_a_margin_when_it_is_not_surviving() -> void:
	var revive := BotRevive.new(BotProfile.regular())
	assert_float(revive.kite_margin()).is_equal(0.0)
