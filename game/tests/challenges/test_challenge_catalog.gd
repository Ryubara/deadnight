extends GdUnitTestSuite
## The data files are sound: every challenge names a stat the night counts, ids are unique, ladders
## rise, and there is enough of each kind for a day and a set of orders to be dealt.

var _catalog: ChallengeCatalog


func before_test() -> void:
	_catalog = ChallengeCatalog.load_default()


func _weapon_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	ids.assign(WeaponCatalog.all().map(func(def: WeaponDef) -> StringName: return def.id))
	return ids


func _type_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for type: ZombieType in RulesFixture.tuning().roster.types:
		ids.append(type.id)
	return ids


func test_the_shipped_data_has_no_problems() -> void:
	assert_array(_catalog.problems(_weapon_ids(), _type_ids())).is_empty()


func test_each_family_is_loaded() -> void:
	assert_int(_catalog.of_family(ChallengeDef.Family.DAILY).size()).is_greater(12)
	assert_int(_catalog.of_family(ChallengeDef.Family.ORDER).size()).is_greater(
		ChallengeProfile.ORDER_SLOTS
	)
	assert_int(_catalog.of_family(ChallengeDef.Family.MILESTONE).size()).is_greater(5)


func test_a_day_can_always_be_dealt_from_enough_variety() -> void:
	for tier in DailyRotation.TIERS:
		var pool := _catalog.dailies_of(tier)
		assert_int(pool.size()).is_greater_equal(6)
		var groups := {}
		for def in pool:
			groups[def.group] = true
		assert_int(groups.size()).is_greater_equal(4)


func test_a_ladder_rises_and_a_single_challenge_has_no_steps() -> void:
	for def in _catalog.of_family(ChallengeDef.Family.MILESTONE):
		assert_bool(def.is_ladder()).is_true()
		assert_int(def.target).is_equal(def.steps[0])
	for def in _catalog.of_family(ChallengeDef.Family.DAILY):
		assert_bool(def.is_ladder()).is_false()


func test_the_words_carry_the_number_and_never_the_placeholder() -> void:
	for family in [ChallengeDef.Family.DAILY, ChallengeDef.Family.ORDER]:
		for def in _catalog.of_family(family):
			assert_str(def.words()).not_contains("{n}")
	var kills := _catalog.get_def(&"d_kills_40")
	assert_str(kills.words()).is_equal("Put down 40 zombies")


func test_the_best_stat_is_only_asked_for_in_one_night() -> void:
	for family in [ChallengeDef.Family.DAILY, ChallengeDef.Family.ORDER]:
		for def in _catalog.of_family(family):
			if ChallengeStats.is_best(def.stat):
				assert_int(def.mode).is_equal(ChallengeDef.Mode.ONE_NIGHT)


func test_a_bad_definition_is_reported() -> void:
	var catalog := ChallengeCatalog.new()
	(
		catalog
		. add_all(
			[
				{"id": "a", "text": "x", "stat": "nonsense", "target": 3, "group": "g"},
				{"id": "a", "text": "x", "stat": "kills", "target": 3, "group": "g"},
				{"id": "b", "text": "x", "stat": "kills", "target": 0, "group": "g"},
				{"id": "c", "text": "x", "stat": "round", "target": 2, "group": "g"},
				{"id": "d", "text": "x", "stat": "kills:weapon:laser", "target": 2, "group": "g"},
			],
			ChallengeDef.Family.DAILY
		)
	)
	catalog.add_all(
		[{"id": "m", "text": "x", "stat": "kills", "steps": [5, 5]}], ChallengeDef.Family.MILESTONE
	)
	var found := catalog.problems(_weapon_ids(), _type_ids())
	var text := "\n".join(found)
	assert_str(text).contains("a: unknown stat")
	assert_str(text).contains("a: id used twice")
	assert_str(text).contains("b: the target must be above zero")
	assert_str(text).contains("c: a best stat")
	assert_str(text).contains("d: unknown stat")
	assert_str(text).contains("m: steps must rise")
