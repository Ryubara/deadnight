extends GdUnitTestSuite
## The calling cards and emblems (#1070): every piece has one art and exactly one gate (a level or a
## challenge, never both and never two), every grant of a challenge is a piece that exists, what a
## player owns is derived from the level and the finished challenges, and what they wear is held to
## it.

var _plates: PlateCatalog
var _ladder: LadderUnlocks
var _challenges: ChallengeCatalog


func before_test() -> void:
	_plates = PlateCatalog.shipped()
	_ladder = LadderUnlocks.shipped()
	_challenges = ChallengeCatalog.load_default()


func _done(...ids: Array) -> Array[StringName]:
	var found: Array[StringName] = []
	for id: Variant in ids:
		found.append(StringName(str(id)))
	return found


func test_the_shipped_catalogue_has_no_problems() -> void:
	assert_array(_plates.problems()).is_empty()


func test_the_launch_set_is_there() -> void:
	# 11 tier cards and 12 grind cards and 11 odd ones; 11 tier emblems, the starting emblem, 9 easy
	# ones, 12 grind ones and 8 easy and together ones that need a stat of #1074.
	assert_int(_plates.ids(PlateCatalog.CARD).size()).is_equal(34)
	assert_int(_plates.ids(PlateCatalog.EMBLEM).size()).is_equal(41)
	var tiers := 0
	for kind in PlateCatalog.KINDS:
		for id in _plates.ids(kind):
			if _plates.source(kind, id).has("level"):
				tiers += 1
	assert_int(tiers).is_equal(11 + 12)


func test_a_tier_card_comes_at_the_level_the_ladder_gives_it() -> void:
	var seen := 0
	for level in _ladder.levels():
		for row: Dictionary in _ladder.at_level(level):
			if row["slot"] == &"tier_card":
				seen += 1
				assert_int(int(_plates.source(PlateCatalog.CARD, row["item"])["level"])).is_equal(
					level
				)
				assert_bool(row["available"]).is_true()
	assert_int(seen).is_equal(11)


func test_every_grant_of_a_challenge_is_a_piece_and_no_piece_is_given_twice() -> void:
	var given := {}
	for grant in _challenges.grants():
		var key: String = "%s:%s" % [grant["kind"], grant["id"]]
		assert_bool(given.has(key)).override_failure_message("%s is given twice" % key).is_false()
		given[key] = true
		if grant["kind"] in PlateCatalog.KINDS:
			(
				assert_bool(_plates.has(grant["kind"], grant["id"]))
				. override_failure_message("%s has no art" % key)
				. is_true()
			)
	assert_int(given.size()).is_equal(9 + 12 * 2 + 11 + 8)


func test_what_a_player_owns_is_the_level_and_the_finished_challenges() -> void:
	var none := _done()
	assert_array(_plates.owned(PlateCatalog.CARD, 1, none)).is_empty()
	# Level 2 gives the starting emblem; level 5 the first tier's card and emblem.
	assert_array(_plates.owned(PlateCatalog.EMBLEM, 2, none)).contains_exactly([&"admit_one"])
	assert_array(_plates.owned(PlateCatalog.CARD, 5, none)).contains_exactly([&"doors_open"])
	assert_array(_plates.owned(PlateCatalog.CARD, 55, none).slice(-1)).contains_exactly(
		[&"last_reel"]
	)
	assert_int(_plates.owned(PlateCatalog.CARD, 55, none).size()).is_equal(11)
	# A challenge gives its piece once done, and nothing before.
	var done := _done("f_dead_eye")
	assert_bool(_plates.owns(PlateCatalog.CARD, &"dead_eye", 1, none)).is_false()
	assert_bool(_plates.owns(PlateCatalog.CARD, &"dead_eye", 1, done)).is_true()
	assert_bool(_plates.owns(PlateCatalog.EMBLEM, &"dead_eye", 1, done)).is_true()
	assert_bool(_plates.owns(PlateCatalog.CARD, &"dead_eye", 1, _done("f_ironwork"))).is_false()


func test_what_is_worn_is_held_to_what_is_owned() -> void:
	var chosen := {"card": "dead_eye", "emblem": "doors_open"}
	var worn := _plates.worn(chosen, 12, _done("f_dead_eye"))
	assert_str(worn["card"]).is_equal("dead_eye")
	assert_str(worn["emblem"]).is_equal("doors_open")
	# Below level 5 the tier emblem is not theirs; with the challenge not done the card is not either.
	worn = _plates.worn(chosen, 3, _done())
	assert_str(worn["card"]).is_equal("")
	assert_str(worn["emblem"]).is_equal("")
	# An id nobody has is nothing.
	worn = _plates.worn({"card": "nonsense", "emblem": 7}, 55, _done())
	assert_str(worn["card"]).is_equal("")
	assert_str(worn["emblem"]).is_equal("")


func test_every_piece_says_how_to_get_it() -> void:
	for kind in PlateCatalog.KINDS:
		for id in _plates.ids(kind):
			assert_str(_plates.how_to_get(kind, id)).is_not_empty()
			assert_str(_plates.title(kind, id)).is_not_empty()
	assert_str(_plates.how_to_get(PlateCatalog.CARD, &"cartoon")).is_equal("Reach level 10")
	assert_str(_plates.how_to_get(PlateCatalog.CARD, &"ironwork")).is_equal("Mend 1,000 boards")


func test_a_bad_catalogue_is_reported() -> void:
	var text := (
		'{"cards": [{"id": "a", "title": "A", "motif": "ticket", "palette": "brass"},'
		+ ' {"id": "a", "title": "A", "motif": "nope", "palette": "brass"},'
		+ ' {"id": "b", "title": "", "motif": "ticket", "palette": "nowhere"}], "emblems": []}'
	)
	var plates := PlateCatalog.from_parts(
		text, LadderUnlocks.from_text("[]"), ChallengeCatalog.new()
	)
	var found := "\n".join(plates.problems())
	assert_str(found).contains("card a: id used twice")
	assert_str(found).contains("card a: nothing gives it")
	assert_str(found).contains("card b: unknown palette 'nowhere'")
	assert_str(found).contains("card b: no title")
	(
		assert_str(
			"\n".join(
				(
					PlateCatalog
					. from_parts("not json", LadderUnlocks.from_text("[]"), ChallengeCatalog.new())
					. problems()
				)
			)
		)
		. contains("unreadable")
	)


func test_a_piece_with_two_gates_is_reported() -> void:
	var ladder := LadderUnlocks.from_text(
		'[{"level": 5, "slot": "tier_card", "item": "a", "available": true}]'
	)
	var challenges := ChallengeCatalog.new()
	challenges.add_all(
		[{"id": "f", "text": "x", "stat": "kills", "target": 3, "grants": ["card:a"]}],
		ChallengeDef.Family.FEAT
	)
	var plates := (
		PlateCatalog
		. from_parts(
			'{"cards": [{"id": "a", "title": "A", "motif": "ticket", "palette": "brass"}], "emblems": []}',
			ladder,
			challenges
		)
	)
	assert_str("\n".join(plates.problems())).contains("card a: given twice")
