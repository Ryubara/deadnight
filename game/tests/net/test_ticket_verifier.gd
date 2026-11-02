# The ticket the platform backend signs, checked by the game server. The tickets in tickets.json are
# made by the backend's own `signToken` (secret 32 times "t", server "gs-test", issued at
# 1_800_000_000 for 60 s; `with_settings` carries the host's rules), so this is the two sides
# agreeing on the bytes.
extends GdUnitTestSuite

const NOW := 1_800_000_010
const SECRET := "tttttttttttttttttttttttttttttttt"

var _tickets: Dictionary


func before_test() -> void:
	_tickets = JSON.parse_string(FileAccess.get_file_as_string("res://tests/net/tickets.json"))


func _verifier() -> TicketVerifier:
	return TicketVerifier.new(SECRET, "gs-test")


func test_a_ticket_the_backend_signed_is_admitted_with_who_and_which_night() -> void:
	var result := _verifier().admit(_tickets["good"], NOW)
	assert_bool(result["ok"]).is_true()
	assert_str(result["user"]).is_equal("user-1")
	assert_str(result["match"]).is_equal("match-1")
	assert_str(result["name"]).is_equal("Ann")


func test_the_rules_the_backend_signed_into_a_ticket_are_read_back() -> void:
	var result := _verifier().admit(_tickets["with_settings"], NOW)
	assert_bool(result["ok"]).is_true()
	assert_str(result["match"]).is_equal("match-3")
	var expected := {"count_multiplier": 2.0, "max_alive": 12, "break_seconds": 0.0}
	assert_dict((result["settings"] as MatchSettings).to_dict()).is_equal(expected)


func test_names_with_other_letters_come_through() -> void:
	var result := _verifier().admit(_tickets["second"], NOW)
	assert_str(result["name"]).is_equal("Bo Ø")
	assert_str(result["match"]).is_equal("match-2")


func test_a_ticket_is_good_once_until_it_would_have_expired() -> void:
	var verifier := _verifier()
	assert_bool(verifier.admit(_tickets["good"], NOW)["ok"]).is_true()
	var again := verifier.admit(_tickets["good"], NOW + 1)
	assert_bool(again["ok"]).is_false()
	assert_str(again["reason"]).is_equal(TicketVerifier.USED)


func test_an_expired_ticket_is_refused() -> void:
	assert_bool(_verifier().admit(_tickets["good"], 1_800_000_061)["ok"]).is_false()
	assert_bool(_verifier().admit(_tickets["good"], 1_800_000_059)["ok"]).is_true()


func test_another_servers_ticket_is_refused_even_with_the_right_key() -> void:
	var result := _verifier().admit(_tickets["other_server"], NOW)
	assert_str(result["reason"]).is_equal(TicketVerifier.WRONG_SERVER)


func test_a_forged_or_foreign_ticket_is_refused() -> void:
	var verifier := _verifier()
	for name in ["wrong_key", "no_jti", "session_kind"]:
		assert_bool(verifier.admit(_tickets[name], NOW)["ok"]).is_false()
	for garbage in ["", "a.b", "a.b.c", "x.y.z.w", "....", _tickets["good"] + "x"]:
		assert_bool(verifier.admit(garbage, NOW)["ok"]).is_false()
	# A payload changed after signing breaks the signature.
	var parts: PackedStringArray = (_tickets["good"] as String).split(".")
	parts[1] = (_tickets["second"] as String).split(".")[1]
	assert_bool(verifier.admit(".".join(parts), NOW)["ok"]).is_false()
	# A key of another secret admits nothing.
	(
		assert_bool(
			TicketVerifier.new("z".repeat(32), "gs-test").admit(_tickets["good"], NOW)["ok"]
		)
		. is_false()
	)


func test_a_ticket_without_rules_admits_with_none_and_one_with_rules_hands_them_over() -> void:
	var plain := TicketMaker.make(SECRET, "gs-test", "m", "ann")
	(
		assert_object(_verifier().admit(plain, int(Time.get_unix_time_from_system()))["settings"])
		. is_null()
	)
	var chosen := {"count_multiplier": 2.0, "max_alive": 12, "break_seconds": 0.0}
	var with_rules := TicketMaker.make(SECRET, "gs-test", "m", "bo", "Bo", 60, chosen)
	var admitted := _verifier().admit(with_rules, int(Time.get_unix_time_from_system()))
	assert_bool(admitted["ok"]).is_true()
	assert_dict((admitted["settings"] as MatchSettings).to_dict()).is_equal(chosen)


func test_a_ticket_whose_rules_this_server_does_not_take_is_refused_and_not_spent() -> void:
	var verifier := _verifier()
	var now := int(Time.get_unix_time_from_system())
	for rules in [
		{"count_multiplier": 6.0, "max_alive": 1, "break_seconds": 0.0},
		{"count_multiplier": 1.0, "max_alive": 41, "break_seconds": 0.0},
		{"count_multiplier": 1.0, "max_alive": 1, "break_seconds": 0.5},
		{"count_multiplier": 1.0},
	]:
		var ticket := TicketMaker.make(SECRET, "gs-test", "m", "x", "X", 60, rules)
		var answer := verifier.admit(ticket, now)
		assert_bool(answer["ok"]).is_false()
		assert_str(answer["reason"]).is_equal(TicketVerifier.BAD_SETTINGS)
