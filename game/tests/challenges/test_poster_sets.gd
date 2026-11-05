extends GdUnitTestSuite
## The poster sets (#1073): six challenges themed as a fake film, each one done uncovers a panel of
## the poster, all six win the set's calling card and emblem. The shipped sets name only feats the
## night counts and none that needs a crowd; the panels and the prize are read from the finished
## challenges (nothing is stored, so the prize is granted once and the save round-trips); the
## game server and a solo night tell a finished set once, and the menu never tells it again.

const DAY := 20401
const ACCOUNT := "account-one"
const DIR := "user://test_poster_sets/"

var _catalog: ChallengeCatalog
var _plates: PlateCatalog
var _sets: PosterSets


func before_test() -> void:
	_catalog = ChallengeCatalog.load_default()
	_plates = PlateCatalog.shipped()
	_sets = PosterSets.shipped()
	DirAccess.make_dir_recursive_absolute(DIR)
	_clear()
	ProgressSeen.path = DIR + "seen.json"


func after_test() -> void:
	ProgressSeen.path = ""
	_clear()


func _clear() -> void:
	for file in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + file)


func _weapon_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	ids.assign(WeaponCatalog.all().map(func(def: WeaponDef) -> StringName: return def.id))
	return ids


func _type_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for type: ZombieType in RulesFixture.tuning().roster.types:
		ids.append(type.id)
	return ids


func _problems(sets: PosterSets, catalog: ChallengeCatalog = null) -> String:
	var against := catalog if catalog != null else _catalog
	return "\n".join(sets.problems(against, _weapon_ids(), _type_ids()))


func _ids(list: Array) -> Array[StringName]:
	var out: Array[StringName] = []
	for id: Variant in list:
		out.append(StringName(str(id)))
	return out


## A catalogue of six small feats, "p1" to "p6" (put down 1 to 6), and a set made of them.
func _small() -> Dictionary:
	var catalog := ChallengeCatalog.new()
	var records: Array = []
	for n in range(1, 7):
		records.append({"id": "p%d" % n, "text": "Put down %d" % n, "stat": "kills", "target": n})
	catalog.add_all(records, ChallengeDef.Family.FEAT)
	var set_text := (
		'{"sets": [{"id": "small", "title": "Small", "lines": ["A"], "palette": "teal", '
		+ '"motif": "bolt", "challenges": ["p1", "p2", "p3", "p4", "p5", "p6"], '
		+ '"grants": ["card:small_card", "emblem:small_emblem"]}]}'
	)
	return {"catalog": catalog, "sets": PosterSets.from_text(set_text)}


## A board of `catalog` whose feats `1..n` of the small set are done.
func _board_with(done: int, account := ACCOUNT) -> ChallengeProfile:
	var profile := ChallengeProfile.fresh_for(account)
	profile.dealt_day = DAY
	for n in range(1, done + 1):
		profile.feats[StringName("p%d" % n)] = n
	return profile


# --- The shipped sets ---


func test_the_launch_has_two_sets_of_six_from_the_counted_feats() -> void:
	var all := _sets.all()
	assert_int(all.size()).is_equal(2)
	var feats := _catalog.of_family(ChallengeDef.Family.FEAT).map(
		func(def: ChallengeDef) -> StringName: return def.id
	)
	# The catalogue has grown with the stats of #1074; the sets name 12 of its feats.
	assert_int(feats.size()).is_greater(12)
	var seen := {}
	for poster_set in all:
		assert_int(poster_set.challenges.size()).is_equal(PosterSet.PANELS)
		for id in poster_set.challenges:
			assert_bool(feats.has(id)).override_failure_message("%s is no feat" % id).is_true()
			assert_bool(seen.has(id)).override_failure_message("%s is in two sets" % id).is_false()
			seen[id] = true
	assert_int(seen.size()).is_equal(12)


func test_a_set_never_lists_a_stat_the_night_does_not_count_or_one_that_needs_a_crowd() -> void:
	assert_str(_problems(_sets)).is_empty()
	for poster_set in _sets.all():
		for id in poster_set.challenges:
			var def := _catalog.get_def(id)
			var stats: Array[StringName] = [def.stat]
			stats.append_array(def.stats)
			for stat in stats:
				assert_bool(ChallengeStats.is_known(stat, _weapon_ids(), _type_ids())).is_true()
				assert_bool(ChallengeStats.CROWD.has(stat)).is_false()


func test_a_set_that_lists_an_uncountable_stat_is_reported() -> void:
	var catalog := ChallengeCatalog.new()
	var records: Array = []
	for n in range(1, 7):
		records.append(
			{
				"id": "p%d" % n,
				"text": "x",
				"stat": "kills" if n != 2 else "generator_restarts",
				"target": 3
			}
		)
	records[2]["stat"] = "revives"
	catalog.add_all(records, ChallengeDef.Family.FEAT)
	var found := _problems(_small()["sets"], catalog)
	assert_str(found).contains("'p2' counts 'generator_restarts', which the night does not")
	assert_str(found).contains("'p3' needs a crowd ('revives')")


func test_a_badly_made_set_is_reported() -> void:
	var text := (
		'{"sets": [{"id": "a", "title": "", "lines": [], "palette": "nowhere", "motif": "nope", '
		+ '"challenges": ["f_fill", "f_fill", "d_missing"], "grants": []},'
		+ ' {"id": "a", "title": "B", "lines": ["B"], "palette": "teal", "motif": "bolt", '
		+ '"challenges": ["f_fill", "f_hammer", "f_open", "f_regular", "f_gas_man", "f_ironwork"], '
		+ '"grants": ["card:x"]}]}'
	)
	var found := _problems(PosterSets.from_text(text))
	assert_str(found).contains("a: a title and the lines of the poster are needed")
	assert_str(found).contains("a: unknown palette 'nowhere'")
	assert_str(found).contains("a: unknown motif 'nope'")
	assert_str(found).contains("a: 3 challenges, a poster has 6 panels")
	assert_str(found).contains("a: gives nothing")
	assert_str(found).contains("a: no challenge 'd_missing'")
	assert_str(found).contains("a: 'f_fill' is in two sets")
	assert_str(found).contains("set 'a': an id, once")
	assert_str(_problems(PosterSets.from_text("not json"))).contains("unreadable")


# --- Panels, the prize, the save ---


func test_panels_uncover_as_challenges_finish_and_the_set_is_done_at_six() -> void:
	var poster_set := _sets.all()[0]
	var board := ChallengeBoard.new()
	board.catalog = _catalog
	board.profile = ChallengeProfile.fresh(5)
	for count in range(0, 7):
		if count > 0:
			var def := _catalog.get_def(poster_set.challenges[count - 1])
			board.profile.feats[def.id] = def.target
		var entry := board.poster_sets()[0]
		assert_int(entry["count"]).is_equal(count)
		assert_array(entry["uncovered"]).is_equal(range(count))
		assert_bool(entry["done"]).is_equal(count == 6)
		for panel: Dictionary in entry["panels"]:
			assert_bool(panel["done"]).is_equal(int(panel["n"]) <= count)
	# The other set did not move.
	assert_int(board.poster_sets()[1]["count"]).is_equal(0)


func test_a_feat_half_done_uncovers_nothing_and_shows_its_progress() -> void:
	var board := ChallengeBoard.new()
	board.catalog = _catalog
	board.profile = ChallengeProfile.fresh(5)
	board.profile.feats[&"f_gas_man"] = 40
	var panels: Array = board.poster_sets()[0]["panels"]
	var panel: Dictionary = panels[4]
	assert_str(panel["id"]).is_equal("f_gas_man")
	assert_bool(panel["done"]).is_false()
	assert_int(panel["progress"]).is_equal(40)
	assert_int(panel["target"]).is_equal(150)
	assert_int(board.poster_sets()[0]["count"]).is_equal(0)


func test_the_panels_survive_a_save() -> void:
	var path := ChallengeFixture.save_path("poster")
	var board := ChallengeBoard.open(path, ChallengeFixture.clock_on(DAY), _catalog)
	var poster_set := _sets.all()[1]
	for id in poster_set.challenges.slice(0, 4):
		board.profile.feats[id] = _catalog.get_def(id).target
	assert_bool(board.save()).is_true()
	var again := ChallengeBoard.open(path, ChallengeFixture.clock_on(DAY), _catalog)
	var entry := again.poster_sets()[1]
	assert_int(entry["count"]).is_equal(4)
	assert_array(entry["uncovered"]).is_equal([0, 1, 2, 3])
	assert_bool(entry["done"]).is_false()
	# And through the dictionary the account's slot holds.
	var round_trip := ChallengeProfile.from_dict(board.profile.to_dict())
	assert_array(round_trip.feats_done(_catalog)).contains_exactly_in_any_order(
		_ids(poster_set.challenges.slice(0, 4))
	)


func test_the_prize_is_the_sets_and_comes_once_with_the_sixth_panel() -> void:
	for poster_set in _sets.all():
		var card := poster_set.piece(PlateCatalog.CARD)
		var emblem := poster_set.piece(PlateCatalog.EMBLEM)
		assert_bool(_plates.has(PlateCatalog.CARD, card)).is_true()
		assert_bool(_plates.has(PlateCatalog.EMBLEM, emblem)).is_true()
		assert_bool(_plates.source(PlateCatalog.CARD, card).has("set")).is_true()
		var done: Array[StringName] = []
		for index in 5:
			done.append(poster_set.challenges[index])
			assert_bool(_plates.owns(PlateCatalog.CARD, card, 55, done)).is_false()
			assert_bool(_plates.owns(PlateCatalog.EMBLEM, emblem, 55, done)).is_false()
		done.append(poster_set.challenges[5])
		assert_bool(_plates.owns(PlateCatalog.CARD, card, 1, done)).is_true()
		assert_bool(_plates.owns(PlateCatalog.EMBLEM, emblem, 1, done)).is_true()
		# Finishing the same challenge again, or all of them twice, grants nothing more.
		done.append_array(poster_set.challenges)
		assert_array(_plates.owned(PlateCatalog.CARD, 1, done)).contains([card])
		assert_int(_plates.owned(PlateCatalog.CARD, 1, done).count(card)).is_equal(1)
		assert_str(_plates.how_to_get(PlateCatalog.CARD, card)).is_equal(
			"Poster set: %s" % poster_set.short
		)
	# The other set's challenges do not give this set's prize, and a level does not either.
	var first := _sets.all()[0]
	(
		assert_bool(
			_plates.owns(
				PlateCatalog.CARD,
				first.piece(PlateCatalog.CARD),
				55,
				_ids(_sets.all()[1].challenges)
			)
		)
		. is_false()
	)


func test_what_is_worn_holds_a_sets_card_to_the_finished_set() -> void:
	var poster_set := _sets.all()[0]
	var chosen := {"card": String(poster_set.piece(PlateCatalog.CARD)), "emblem": "admit_one"}
	var half := _ids(poster_set.challenges.slice(0, 5))
	assert_str(_plates.worn(chosen, 55, half)["card"]).is_equal("")
	assert_str(_plates.worn(chosen, 55, _ids(poster_set.challenges))["card"]).is_equal(
		String(poster_set.piece(PlateCatalog.CARD))
	)


# --- Telling a finished set ---


func test_a_set_is_completed_by_its_last_panel_in_any_order() -> void:
	var poster_set := _sets.all()[0]
	var order := poster_set.challenges.duplicate()
	order.reverse()
	var done: Array[StringName] = []
	for index in order.size():
		done.append(order[index])
		var told := _sets.completed_by(order[index], done)
		assert_bool(told != null).is_equal(index == order.size() - 1)
	# A challenge of no set completes none.
	assert_object(_sets.completed_by(&"f_walk_in", _ids(poster_set.challenges))).is_null()
	# The event carries what the card and the voice need.
	var event := _sets.event_of(poster_set, 3)
	assert_str(event["type"]).is_equal("poster_set_done")
	assert_int(event["player_id"]).is_equal(3)
	assert_str(event["card"]).is_equal(String(poster_set.piece(PlateCatalog.CARD)))
	assert_bool(_sets.event_of(poster_set).has("player_id")).is_false()


func test_the_game_server_tells_the_set_once_after_the_challenge_that_finished_it() -> void:
	var small := _small()
	var rules := RulesFixture.make_rules(1)
	var xp := XpAward.new([&"fuel_can"], ChallengeFixture.clock_on(DAY))
	var award := ChallengeAward.new(xp, [&"fuel_can"])
	award.catalog = small["catalog"]
	award.sets = small["sets"]
	award.clock = ChallengeFixture.clock_on(DAY)
	rules.event_emitted.connect(xp.observe)
	rules.event_emitted.connect(award.observe)
	xp.register(1, "user-1", 0, 0)
	award.seat(1, "user-1")
	award.arrived("user-1", 404, ChallengeAward.NO_BOARD)
	RulesFixture.into_round_one(rules)
	var told: Array[Dictionary] = []
	var kills := 0
	for _i in 6000:
		if rules.phase == GameRules.Phase.BREAK:
			rules.apply(RulesAction.skip_break())
		rules.apply(RulesAction.tick(RulesFixture.STEP))
		for zombie_id in rules.zombie_ids():
			if kills < 9:
				RulesFixture.kill(rules, 1, zombie_id, RulesAction.ZONE_HEAD)
				kills += 1
		told.append_array(award.take_events())
		if kills >= 9:
			break
	var types: Array = (
		told
		. filter(
			func(e: Dictionary) -> bool: return e["type"] in [&"challenge_done", &"poster_set_done"]
		)
		. map(func(e: Dictionary) -> StringName: return e["type"])
	)
	# Six challenges, p1 to p6 (6 kills finish the last); the set comes once, after the sixth.
	(
		assert_array(types)
		. is_equal(
			[
				&"challenge_done",
				&"challenge_done",
				&"challenge_done",
				&"challenge_done",
				&"challenge_done",
				&"challenge_done",
				&"poster_set_done",
			]
		)
	)
	var sets_told := told.filter(
		func(e: Dictionary) -> bool: return e["type"] == &"poster_set_done"
	)
	var done_event: Dictionary = sets_told[0]
	assert_int(done_event["player_id"]).is_equal(1)
	assert_str(done_event["id"]).is_equal("small")


func test_a_solo_night_tells_the_set_once_and_notes_it_for_the_menu() -> void:
	var small := _small()
	var board := ChallengeBoard.new()
	board.catalog = small["catalog"]
	board.profile = _board_with(5)
	board.clock = ChallengeFixture.clock_on(DAY)
	var session := ChallengeSession.new(board)
	session.sets = small["sets"]
	var told: Array[Dictionary] = []
	session.set_finished.connect(func(event: Dictionary) -> void: told.append(event))
	# Five panels: a finish of the fifth tells nothing.
	session._on_advanced({"id": &"p5", "completed": true})
	assert_array(told).is_empty()
	board.profile.feats[&"p6"] = 6
	session._on_advanced({"id": &"p6", "completed": true})
	assert_int(told.size()).is_equal(1)
	assert_str(told[0]["id"]).is_equal("small")
	assert_bool(told[0].has("player_id")).is_true()
	# A step on the way (not completed) says nothing, and the hud forwards the event it is given.
	session._on_advanced({"id": &"p6", "completed": false})
	assert_int(told.size()).is_equal(1)


func test_a_set_finished_while_away_is_told_by_the_menu_once_and_not_after_the_night_showed_it(
) -> void:
	var small := _small()
	var catalog: ChallengeCatalog = small["catalog"]
	var sets: PosterSets = small["sets"]
	var after := _board_with(6)
	# The cache (before) has five panels: the sixth was finished by a night the server played.
	var told := ProgressNews.challenges_after_read(
		ACCOUNT, _board_with(5), after, catalog, DAY, sets
	)
	(
		assert_array(told.map(func(e: Dictionary) -> StringName: return e["type"]))
		. is_equal([&"poster_set_done"])
	)
	assert_str(told[0]["id"]).is_equal("small")
	# Already in the cache (a solo night finished it and showed it): nothing.
	(
		assert_array(
			ProgressNews.challenges_after_read(ACCOUNT, _board_with(6), after, catalog, DAY, sets)
		)
		. is_empty()
	)
	# The night showed it live: the ledger has it, and the read does not tell it again.
	ProgressSeen.note_set(&"small", ACCOUNT)
	assert_bool(ProgressSeen.open().was_told(ACCOUNT, ProgressSeen.set_key(&"small"))).is_true()
	(
		assert_array(
			ProgressNews.challenges_after_read(ACCOUNT, _board_with(5), after, catalog, DAY, sets)
		)
		. is_empty()
	)
	# The ledger is spent by that read, and a second note is one entry.
	assert_bool(ProgressSeen.open().told.is_empty()).is_true()
	ProgressSeen.note_set(&"small", ACCOUNT)
	ProgressSeen.note_set(&"small", ACCOUNT)
	assert_int(ProgressSeen.open().told.size()).is_equal(1)


func test_a_cache_that_is_not_the_accounts_tells_no_set() -> void:
	var small := _small()
	var catalog: ChallengeCatalog = small["catalog"]
	(
		assert_array(
			ProgressNews.challenges_after_read(
				ACCOUNT, _board_with(5, "someone-else"), _board_with(6), catalog, DAY, small["sets"]
			)
		)
		. is_empty()
	)
	(
		assert_array(
			ProgressNews.challenges_after_read(
				ACCOUNT, null, _board_with(6), catalog, DAY, small["sets"]
			)
		)
		. is_empty()
	)


func test_the_shipped_menu_read_tells_a_shipped_set_finished_elsewhere() -> void:
	var poster_set := _sets.all()[0]
	var after := ChallengeProfile.fresh_for(ACCOUNT)
	after.dealt_day = DAY
	for id in poster_set.challenges:
		after.feats[id] = _catalog.get_def(id).target
	var before := ChallengeProfile.fresh_for(ACCOUNT)
	before.dealt_day = DAY
	var told := ProgressNews.challenges_after_read(ACCOUNT, before, after, _catalog, DAY)
	(
		assert_array(
			told.filter(func(e: Dictionary) -> bool: return e["type"] == &"poster_set_done")
		)
		. has_size(1)
	)


# --- The voice ---


func test_a_finished_set_is_its_own_cheer_over_a_tier_and_the_challenge_that_finished_it() -> void:
	var cheer := SoldierVoiceCatalog.cheer_of(_sets.event_of(_sets.all()[0], 1))
	assert_str(cheer).is_equal("poster_set")
	assert_int(SoldierVoiceCatalog.takes_of(&"poster_set")).is_equal(3)
	assert_bool(SoldierVoiceCatalog.cheers_over(&"poster_set", &"challenge_done")).is_true()
	assert_bool(SoldierVoiceCatalog.cheers_over(&"poster_set", &"tier_up")).is_true()
	assert_bool(SoldierVoiceCatalog.cheers_over(&"challenge_done", &"poster_set")).is_false()
	# The weight of a finished challenge stays what the maintainer decided.
	assert_int(SoldierVoiceCatalog.CHEER_WEIGHT[&"challenge_done"]).is_equal(2)


# --- The night report ---


func test_a_solo_night_puts_the_finished_set_on_the_report_once_when_two_feats_finish_together(
) -> void:
	var small := _small_kills()
	var board := ChallengeBoard.new()
	board.catalog = small["catalog"]
	board.profile = ChallengeProfile.fresh_for(ACCOUNT)
	board.profile.dealt_day = DAY
	board.clock = ChallengeFixture.clock_on(DAY)
	var session := ChallengeSession.new(board)
	session.sets = small["sets"]
	var state := ClientState.new()
	state.player_id = 1
	session.attach(state)
	var report := ReportTracker.follow(state, [&"fuel_can"])
	var heard: Array[Dictionary] = []
	state.event_received.connect(
		func(event: Dictionary) -> void:
			if event["type"] == PosterSets.DONE:
				heard.append(event)
	)
	var made := ChallengeFixture.night(1)
	state.apply_events(made["events"])
	var rules: GameRules = made["rules"]
	rules.apply(RulesAction.start())
	rules.apply(RulesAction.skip_break())
	var killed := 0
	for _i in 4000:
		state.apply_events(rules.apply(RulesAction.tick(RulesFixture.STEP)))
		for zombie_id in rules.zombie_ids():
			if killed < 3:
				killed += 1
				state.apply_events(RulesFixture.kill(rules, 1, zombie_id, RulesAction.ZONE_HEAD))
		if killed >= 3:
			break
	# Kills 1, 2 and 3 finish two feats each (the last pair in one event): the set is said once.
	assert_int(heard.size()).is_equal(1)
	assert_int(heard[0]["player_id"]).is_equal(1)
	var shown: Array = report.model()["sets"]
	assert_int(shown.size()).is_equal(1)
	assert_str(shown[0]["id"]).is_equal("small")
	assert_str(shown[0]["card"]).is_equal("small_card")
	# The card says it, an unkept night included (no account holds this one).
	var card := HudNightReport.new()
	add_child(card)
	card.show_report(report.model())
	assert_array(card.sets_text).has_size(1)
	assert_bool(report.is_kept()).is_false()
	card.free()
	# A set of another player is not on this report.
	state.event_received.emit(_sets.event_of(_sets.all()[0], 2))
	assert_int((report.model()["sets"] as Array).size()).is_equal(1)


## Like `_small`, but its feats finish by one, one, two, two, three and three kills.
func _small_kills() -> Dictionary:
	var small := _small()
	var catalog := ChallengeCatalog.new()
	var targets := [1, 1, 2, 2, 3, 3]
	var records: Array = []
	for n in targets.size():
		var target: int = targets[n]
		records.append(
			{
				"id": "p%d" % (n + 1),
				"text": "Put down %d" % target,
				"stat": "kills",
				"target": target
			}
		)
	catalog.add_all(records, ChallengeDef.Family.FEAT)
	small["catalog"] = catalog
	return small
