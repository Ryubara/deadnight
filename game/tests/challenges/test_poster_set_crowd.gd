extends GdUnitTestSuite
## A poster set is playable by one person (#1073): it never lists a stat that needs a crowd. The
## stats of #1074 added three to `revives` (`nights:together`, `rounds:whole_crew`,
## `boards:shared`); `ChallengeStats.CROWD` names all four, a set that lists one is reported, and
## a night played by one person (with a bot beside them) moves none of them.

const SET_TEXT := (
	'{"sets": [{"id": "small", "title": "Small", "lines": ["A"], "palette": "teal", '
	+ '"motif": "bolt", "challenges": ["p1", "p2", "p3", "p4", "p5", "p6"], '
	+ '"grants": ["card:small_card", "emblem:small_emblem"]}]}'
)


func _weapon_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	ids.assign(WeaponCatalog.all().map(func(def: WeaponDef) -> StringName: return def.id))
	return ids


func _type_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for type: ZombieType in RulesFixture.tuning().roster.types:
		ids.append(type.id)
	return ids


## The problems of a set of six feats p1 to p6 whose second counts `stat`.
func _problems_when_the_second_counts(stat: String) -> String:
	var catalog := ChallengeCatalog.new()
	var records: Array = []
	for n in range(1, 7):
		records.append({"id": "p%d" % n, "text": "x", "stat": "kills", "target": 3})
	records[1]["stat"] = stat
	catalog.add_all(records, ChallengeDef.Family.FEAT)
	var sets := PosterSets.from_text(SET_TEXT)
	return "\n".join(sets.problems(catalog, _weapon_ids(), _type_ids()))


func test_the_four_stats_a_person_cannot_make_alone_are_named() -> void:
	var crowd: Array[StringName] = [
		ChallengeStats.REVIVES,
		ChallengeStats.NIGHTS_TOGETHER,
		ChallengeStats.ROUNDS_WHOLE,
		ChallengeStats.BOARDS_SHARED,
	]
	assert_array(ChallengeStats.CROWD).contains_exactly_in_any_order(crowd)
	for stat in crowd:
		assert_bool(ChallengeStats.FIXED.has(stat)).is_true()


func test_a_set_that_lists_a_stat_that_needs_a_crowd_is_reported() -> void:
	for stat in ChallengeStats.CROWD:
		assert_str(_problems_when_the_second_counts(String(stat))).contains(
			"'p2' needs a crowd ('%s')" % stat
		)


func test_a_set_of_solo_stats_has_no_problem() -> void:
	assert_str(_problems_when_the_second_counts("boards_repaired")).is_empty()


func test_a_night_of_one_person_and_a_bot_moves_none_of_them() -> void:
	var bench := MomentsBench.new()
	bench.join(1)
	bench.join(2, true)
	bench.positions = {1: Vector3.ZERO, 2: Vector3.ONE}
	bench.wait(1.0)
	bench.start(1)
	bench.board(1)
	bench.wait(2.0)
	bench.board(1)
	bench.finish(1, [1])
	bench.feed({"type": &"game_over", "round_reached": 1})
	assert_int(bench.n(1, ChallengeStats.BOARDS)).is_equal(2)
	for stat in ChallengeStats.CROWD:
		(
			assert_int(bench.n(1, stat))
			. override_failure_message("a solo night moved %s" % stat)
			. is_equal(0)
		)
