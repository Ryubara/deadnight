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


func test_the_chosen_card_and_emblem_and_the_finished_challenges_are_read_when_there() -> void:
	var claims := {
		"xp": 10, "card": "dead_eye", "emblem": "walk_in", "done": ["f_dead_eye", "f_walk_in"]
	}
	assert_dict(TicketVerifier.account_of(claims)).is_equal(
		{"xp": 10, "card": "dead_eye", "emblem": "walk_in", "done": ["f_dead_eye", "f_walk_in"]}
	)


func test_the_chosen_frame_is_read_with_them() -> void:
	var account := TicketVerifier.account_of({"xp": 10, "frame": "filmstrip", "done": []})
	assert_str(account["frame"]).is_equal("filmstrip")
	assert_bool(TicketVerifier.account_of({"xp": 10, "frame": 3}).has("frame")).is_false()


func test_a_card_or_a_list_that_is_not_text_is_left_out() -> void:
	var account := TicketVerifier.account_of(
		{"xp": 5, "card": 7, "emblem": ["a"], "done": ["ok", 3, null, {"a": 1}]}
	)
	assert_bool(account.has("card")).is_false()
	assert_bool(account.has("emblem")).is_false()
	assert_array(account["done"]).is_equal(["ok"])
	assert_bool(TicketVerifier.account_of({"xp": 5, "done": "x"}).has("done")).is_false()
