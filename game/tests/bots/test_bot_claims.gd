# The claim table (bots plan, phase 5): one bot claims a downed player, the nearest wins, a tie goes
# to the lowest id, the lease runs out unless renewed, a bot in its hold is never displaced, and a
# bot that leaves frees what it held.
extends GdUnitTestSuite

const VICTIM := 9


func test_the_only_bidder_gets_the_claim_and_the_lease_runs_out() -> void:
	var claims := BotClaims.new()
	assert_bool(claims.request(VICTIM, 2, 6.0, 0.0)).is_true()
	assert_int(claims.holder_of(VICTIM, 1.0)).is_equal(2)
	assert_int(claims.holder_of(VICTIM, BotClaims.LEASE + 0.1)).is_equal(0)
	assert_int(claims.count(BotClaims.LEASE + 0.1)).is_equal(0)


func test_a_holder_renews_its_lease_by_asking_again() -> void:
	var claims := BotClaims.new()
	claims.request(VICTIM, 2, 6.0, 0.0)
	claims.request(VICTIM, 2, 5.0, 2.5)
	assert_int(claims.holder_of(VICTIM, 4.0)).is_equal(2)
	assert_int(claims.holder_of(VICTIM, 2.5 + BotClaims.LEASE + 0.1)).is_equal(0)


func test_the_nearest_bidder_wins_when_two_ask_at_once() -> void:
	var claims := BotClaims.new()
	# Nobody holds the body yet: the far bot asks first and holds, the near bot is nearer by more
	# than the margin and takes it at its next think.
	assert_bool(claims.request(VICTIM, 3, 20.0, 0.0)).is_true()
	assert_bool(claims.request(VICTIM, 2, 6.0, 0.05)).is_true()
	assert_int(claims.holder_of(VICTIM, 0.1)).is_equal(2)
	assert_bool(claims.request(VICTIM, 3, 20.0, 0.1)).is_false()


func test_a_small_lead_does_not_move_a_claim() -> void:
	var claims := BotClaims.new()
	claims.request(VICTIM, 3, 8.0, 0.0)
	assert_bool(claims.request(VICTIM, 2, 7.0, 0.1)).is_false()
	assert_int(claims.holder_of(VICTIM, 0.2)).is_equal(3)


func test_a_tie_goes_to_the_lowest_id() -> void:
	# Both bid before any claim exists (two thinks of the same moment): equal distances, so the
	# lower id holds whoever asked first.
	var claims := BotClaims.new()
	claims._bids[VICTIM] = {2: Vector2(6.0, 5.0)}
	assert_bool(claims.request(VICTIM, 4, 6.0, 0.0)).is_false()
	assert_bool(claims.request(VICTIM, 2, 6.0, 0.0)).is_true()


func test_a_bot_in_its_hold_is_never_displaced() -> void:
	var claims := BotClaims.new()
	claims.request(VICTIM, 3, 8.0, 0.0, true)
	assert_bool(claims.is_committed(VICTIM, 0.5)).is_true()
	assert_bool(claims.request(VICTIM, 2, 1.0, 0.5)).is_false()
	assert_int(claims.holder_of(VICTIM, 0.6)).is_equal(3)


func test_a_bot_that_leaves_frees_its_claim_at_once() -> void:
	var claims := BotClaims.new()
	claims.request(VICTIM, 3, 8.0, 0.0)
	claims.release(3)
	assert_int(claims.holder_of(VICTIM, 0.1)).is_equal(0)
	assert_bool(claims.request(VICTIM, 2, 12.0, 0.1)).is_true()


func test_a_bot_holds_one_body_at_a_time_as_the_table_reports_it() -> void:
	var claims := BotClaims.new()
	claims.request(VICTIM, 3, 8.0, 0.0)
	assert_int(claims.held_by(3, 0.5)).is_equal(VICTIM)
	assert_int(claims.held_by(2, 0.5)).is_equal(0)
	claims.release_victim(VICTIM)
	assert_int(claims.held_by(3, 0.5)).is_equal(0)
