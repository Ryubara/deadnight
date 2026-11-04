extends GdUnitTestSuite
## What a ticket says about the player's progression, read only from the claims the backend signed.


func test_the_account_is_read_from_the_claims() -> void:
	var claims := {"xp": 1234.0, "level": 9, "icon": "level_09"}
	assert_dict(TicketVerifier.account_of(claims)).is_equal({"xp": 1234})


func test_a_ticket_without_xp_is_an_account_at_zero() -> void:
	assert_dict(TicketVerifier.account_of({})).is_equal({"xp": 0})


func test_nonsense_is_zero() -> void:
	for bad: Variant in [-5, "99", null, NAN, INF, [1], {"a": 1}]:
		assert_int(TicketVerifier.account_of({"xp": bad})["xp"]).is_equal(0)
