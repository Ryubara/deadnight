extends GdUnitTestSuite
## The hidden challenges as data (#1172): five feats shown as `???` with a riddle until done, each
## with a card and an emblem; *Final cut* derived from the level, not counted; and the map lines
## (`data/areas.json`) that the stand and the second door are read from agree with the map itself.

const HIDDEN: Array[StringName] = [
	&"f_snack_break",
	&"f_long_way_round",
	&"f_dead_on_arrival",
	&"f_standing_room_only",
	&"f_final_cut",
]

var _catalog: ChallengeCatalog
var _plates: PlateCatalog


func before_test() -> void:
	_catalog = ChallengeCatalog.load_default()
	_plates = PlateCatalog.shipped()


func _done(...ids: Array) -> Array[StringName]:
	var found: Array[StringName] = []
	for id: Variant in ids:
		found.append(StringName(str(id)))
	return found


func _weapon_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	ids.assign(WeaponCatalog.IDS)
	return ids


func _type_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for type: ZombieType in RulesFixture.tuning().roster.types:
		ids.append(type.id)
	return ids


# --- The data ---


func test_the_five_hidden_challenges_are_feats_with_a_riddle_a_card_and_an_emblem() -> void:
	var hidden: Array[StringName] = []
	for def in _catalog.of_family(ChallengeDef.Family.FEAT):
		if def.hidden:
			hidden.append(def.id)
	assert_array(hidden).contains_exactly_in_any_order(HIDDEN)
	assert_array(_catalog.problems(_weapon_ids(), _type_ids())).is_empty()
	for id in HIDDEN:
		var def := _catalog.get_def(id)
		assert_str(def.riddle).is_not_empty()
		assert_str(def.hint()).is_equal(def.riddle)
		assert_str(def.words()).is_not_empty()
		var kinds: Array[String] = []
		for grant in def.grants:
			kinds.append(String(grant).split(":")[0])
		assert_array(kinds).contains_exactly_in_any_order(["card", "emblem"])
	# A challenge that is not hidden says its words.
	var plain := _catalog.get_def(&"f_hammer")
	assert_str(plain.hint()).is_equal(plain.words())


func test_a_riddle_never_holds_the_title_or_the_words_of_what_it_hides() -> void:
	for id in HIDDEN:
		var def := _catalog.get_def(id)
		var riddle := def.riddle.to_lower()
		assert_str(riddle).not_contains(def.text.to_lower())
		for grant in def.grants:
			var parts := String(grant).split(":")
			var title := _plates.title(StringName(parts[0]), StringName(parts[1])).to_lower()
			assert_str(riddle).not_contains(title)


func test_no_two_pieces_of_a_kind_share_a_title_so_a_title_names_one_thing() -> void:
	for kind in [PlateCatalog.CARD, PlateCatalog.EMBLEM]:
		var seen := {}
		for id in _plates.ids(kind):
			var title := _plates.title(kind, id).to_lower()
			assert_bool(seen.has(title)).override_failure_message("two of: " + title).is_false()
			seen[title] = true


func test_a_hidden_piece_is_called_three_question_marks_until_it_is_owned() -> void:
	for kind in [PlateCatalog.CARD, PlateCatalog.EMBLEM]:
		assert_bool(_plates.is_hidden(kind, &"snack_break")).is_true()
		assert_str(_plates.shown_title(kind, &"snack_break", false)).is_equal("???")
		assert_str(_plates.shown_title(kind, &"snack_break", true)).is_equal("Snack Break")
		assert_str(_plates.how_to_get(kind, &"snack_break")).is_equal(
			_catalog.get_def(&"f_snack_break").riddle
		)
	# A piece that is not hidden is never veiled, and the ladder's are not hidden.
	assert_str(_plates.shown_title(PlateCatalog.CARD, &"dead_eye", false)).is_equal("Dead Eye")
	assert_bool(_plates.is_hidden(PlateCatalog.CARD, &"cartoon")).is_false()
	assert_str(_plates.shown_title(PlateCatalog.CARD, &"cartoon", false)).is_equal("Cartoon")


func test_a_hidden_definition_that_is_wrong_is_reported() -> void:
	var catalog := ChallengeCatalog.new()
	(
		catalog
		. add_all(
			[
				{"id": "a", "text": "Do a thing", "stat": "kills", "target": 1, "hidden": true},
				{"id": "b", "text": "Do b", "stat": "kills", "target": 1, "riddle": "Where?"},
				{
					"id": "c",
					"text": "Do c",
					"stat": "kills",
					"target": 1,
					"hidden": true,
					"riddle": "do c"
				},
				{"id": "d", "text": "Own it", "derived": "nonsense", "target": 1},
				{
					"id": "e",
					"text": "Own it",
					"derived": "tier_cards",
					"stat": "kills",
					"target": 1
				},
			],
			ChallengeDef.Family.FEAT
		)
	)
	catalog.add_all(
		[
			{
				"id": "f",
				"text": "A daily",
				"stat": "kills",
				"target": 1,
				"hidden": true,
				"riddle": "x",
				"group": "g"
			}
		],
		ChallengeDef.Family.DAILY
	)
	var found := "\n".join(catalog.problems(_weapon_ids(), _type_ids()))
	assert_str(found).contains("a: a hidden challenge is a feat with a riddle")
	assert_str(found).contains("b: only a hidden challenge has a riddle")
	assert_str(found).contains("c: the riddle says the challenge")
	assert_str(found).contains("d: derived 'nonsense' is not a rule that exists")
	assert_str(found).contains("e: only a feat with no stat is derived")
	assert_str(found).contains("f: a hidden challenge is a feat with a riddle")


# --- Final cut: derived, not counted ---


func test_final_cut_is_done_when_every_tier_card_is_owned_and_not_before() -> void:
	var def := _catalog.get_def(&"f_final_cut")
	assert_str(def.derived).is_equal(ChallengeDef.DERIVED_TIER_CARDS)
	assert_str(def.stat).is_equal("")
	var ladder := LadderUnlocks.shipped()
	var tier_levels: Array[int] = []
	for level in ladder.levels():
		for row: Dictionary in ladder.at_level(level):
			if row["slot"] == &"tier_card":
				tier_levels.append(level)
	assert_int(tier_levels.size()).is_equal(11)
	var last: int = tier_levels.max()
	assert_bool(_plates.is_done(def, last - 1, _done())).is_false()
	assert_bool(_plates.is_done(def, last, _done())).is_true()
	assert_bool(_plates.is_done(def, 1, _done())).is_false()
	# Its pieces follow the same rule, and a stored finish is not needed (or enough alone).
	assert_bool(_plates.owns(PlateCatalog.CARD, &"final_cut", last, _done())).is_true()
	assert_bool(_plates.owns(PlateCatalog.EMBLEM, &"final_cut", last - 1, _done())).is_false()
	assert_bool(_plates.owns(PlateCatalog.CARD, &"final_cut", 1, _done("f_final_cut"))).is_true()


func test_final_cut_follows_the_tier_cards_of_the_ladder_it_is_given() -> void:
	var text := (
		'[{"level": 3, "slot": "tier_card", "item": "a"}, {"level": 6, "slot": "tier_card", "item": "b"},'
		+ ' {"level": 9, "slot": "tier_card", "item": "c"},'
		+ ' {"level": 12, "slot": "tier_emblem", "item": "z"}]'
	)
	var pieces := (
		'{"cards": [{"id": "a", "title": "A", "motif": "ticket", "palette": "brass"},'
		+ ' {"id": "b", "title": "B", "motif": "ticket", "palette": "brass"},'
		+ ' {"id": "c", "title": "C", "motif": "ticket", "palette": "brass"},'
		+ ' {"id": "final_cut", "title": "Final Cut", "motif": "ticket", "palette": "brass"}],'
		+ ' "emblems": [{"id": "z", "title": "Z", "motif": "ticket", "palette": "brass"},'
		+ ' {"id": "final_cut", "title": "Final Cut", "motif": "ticket", "palette": "brass"}]}'
	)
	var plates := PlateCatalog.from_parts(pieces, LadderUnlocks.from_text(text), _catalog)
	var def := _catalog.get_def(&"f_final_cut")
	# The third and last tier card is level 9, not 55; a tier emblem is no tier card.
	assert_bool(plates.is_done(def, 8, _done())).is_false()
	assert_bool(plates.is_done(def, 9, _done())).is_true()
	# With no tier card at all there is nothing to have finished.
	var bare := PlateCatalog.from_parts(pieces, LadderUnlocks.from_text("[]"), _catalog)
	assert_bool(bare.is_done(def, 99, _done())).is_false()


func test_no_stat_the_night_counts_ever_moves_final_cut() -> void:
	var profile := ChallengeProfile.fresh()
	for stat in ChallengeStats.FIXED:
		for advance in profile.apply(_catalog, stat, 1000, 1000):
			assert_str(advance["id"]).is_not_equal("f_final_cut")
	assert_bool(profile.feats.has(&"f_final_cut")).is_false()
	assert_array(_catalog.feats_over(&"")).is_empty()


# --- The stats a hidden challenge counts move it, and say nothing on the way ---


func test_a_hidden_feat_is_told_only_when_it_is_done() -> void:
	var profile := ChallengeProfile.fresh()
	# Round 7 of 8 the long way: nothing to say; the 8th finishes it.
	for round_number in range(1, 8):
		for advance in profile.apply(_catalog, ChallengeStats.ROUND_LONG_WAY, round_number, 1):
			assert_str(advance["id"]).is_not_equal("f_long_way_round")
	assert_int(int(profile.feats[&"f_long_way_round"])).is_equal(7)
	var told := profile.apply(_catalog, ChallengeStats.ROUND_LONG_WAY, 8, 1).filter(
		func(a: Dictionary) -> bool: return a["id"] == &"f_long_way_round"
	)
	assert_int(told.size()).is_equal(1)
	assert_bool(told[0]["completed"]).is_true()
	assert_str(told[0]["text"]).is_equal("Reach round 8 without opening the second door")
	for stat in [
		ChallengeStats.BREAKS_STAND, ChallengeStats.DEATHS_ROUND_ONE, ChallengeStats.NIGHTS_FULL_LOT
	]:
		var advances := profile.apply(_catalog, stat, 1, 1)
		var ids := advances.map(func(a: Dictionary) -> StringName: return a["id"])
		assert_bool(ids.size() > 0).override_failure_message(str(stat)).is_true()


# --- The map lines ---


func test_the_stand_rectangle_is_the_concession_floor_of_the_map() -> void:
	# The scene's text, not an instance of it: the floors of the `Concession` node are boxes with a
	# transform (the last three numbers are the centre) and a size.
	var text := FileAccess.get_file_as_string("res://world/drive_in_greybox.tscn")
	var floors := RegEx.create_from_string(
		(
			r'\[node name="Floor\w+" type="CSGBox3D" parent="Concession"\]\s+'
			+ r"transform = Transform3D\(([^)]*)\)[^\[]*?size = Vector3\(([^)]*)\)"
		)
	)
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	var found := 0
	for each in floors.search_all(text):
		var transform := each.get_string(1).split(",")
		var size := each.get_string(2).split(",")
		var half := Vector2(float(size[0]), float(size[2])) * 0.5
		var centre := Vector2(float(transform[9]), float(transform[11]))
		low = low.min(centre - half)
		high = high.max(centre + half)
		found += 1
	assert_int(found).is_equal(4)
	var stand := ChallengeAreas.rect("drive_in", ChallengeAreas.STAND)
	assert_array(Array(stand)).is_equal([low.x, low.y, high.x, high.y])
	# The stand's counter and soda fountain are inside it.
	assert_bool(ChallengeAreas.contains(stand, Vector3(8.2, 0.0, 4.9))).is_true()
	assert_bool(ChallengeAreas.contains(stand, Vector3(0.0, 0.0, -12.0))).is_false()


func test_the_second_door_is_the_second_of_the_lots_doors_and_needs_the_first() -> void:
	var doors: Array[ShopItem] = []
	for item in RulesFixture.tuning().economy.items:
		if item.kind == ShopItem.Kind.DOOR:
			doors.append(item)
	assert_str(ChallengeAreas.second_door("drive_in")).is_equal(doors[1].id)
	assert_str(doors[1].requires).is_equal(doors[0].id)
	# The back rooms name none; a map nobody knows names none.
	assert_str(ChallengeAreas.second_door("small_indoor")).is_equal("")
	assert_str(ChallengeAreas.second_door("nowhere")).is_equal("")
	assert_int(ChallengeAreas.rect("small_indoor", ChallengeAreas.STAND).size()).is_equal(0)


func test_no_poster_set_names_a_hidden_challenge() -> void:
	for poster_set in PosterSets.shipped().all():
		for id in poster_set.challenges:
			(
				assert_bool(_catalog.get_def(id).hidden)
				. override_failure_message("%s lists the hidden challenge %s" % [poster_set.id, id])
				. is_false()
			)
	assert_array(PosterSets.shipped().problems(_catalog, _weapon_ids(), _type_ids())).is_empty()


func test_a_set_that_names_a_hidden_challenge_is_reported() -> void:
	var text := (
		'{"sets": [{"id": "s", "title": "S", "lines": ["S"], "palette": "teal", "motif": "bolt", '
		+ '"challenges": ["f_snack_break", "f_hammer", "f_open", "f_regular", "f_gas_man", '
		+ '"f_ironwork"], "grants": ["card:fifty_foot_feature"]}]}'
	)
	var found := PosterSets.from_text(text).problems(_catalog, _weapon_ids(), _type_ids())
	assert_array(found).contains(["s: 'f_snack_break' is hidden"])


func test_a_stat_that_needs_four_people_is_a_crowd_stat_so_no_set_asks_for_it() -> void:
	assert_bool(ChallengeStats.CROWD.has(ChallengeStats.NIGHTS_FULL_LOT)).is_true()
	assert_bool(ChallengeStats.CROWD.has(ChallengeStats.BREAKS_STAND)).is_false()
