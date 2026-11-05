extends GdUnitTestSuite
## The feats (#1070, #1071): lasting goals that give a calling card, an emblem or a frame. The
## shipped ones name only stats the night counts, a feat over several stats is as far as the lowest
## of them, and a feat finishes once, says nothing on the way and survives a save.

const DAY := 20401

var _catalog: ChallengeCatalog
var _profile: ChallengeProfile


func before_test() -> void:
	_catalog = ChallengeCatalog.load_default()
	_profile = ChallengeProfile.fresh(5)
	_profile.refresh(_catalog, DAY)


func _weapon_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	ids.assign(WeaponCatalog.all().map(func(def: WeaponDef) -> StringName: return def.id))
	return ids


func _type_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for type: ZombieType in RulesFixture.tuning().roster.types:
		ids.append(type.id)
	return ids


## What a night does to a stat: `value` its count this night, `delta` the step.
func _count(stat: StringName, value: int, delta: int = 1) -> Array[Dictionary]:
	var moved: Array[Dictionary] = []
	for advance in _profile.apply(_catalog, stat, value, delta):
		if advance["family"] == ChallengeDef.Family.FEAT:
			moved.append(advance)
	return moved


func test_the_shipped_feats_are_the_launch_set_and_sound() -> void:
	var feats := _catalog.of_family(ChallengeDef.Family.FEAT)
	assert_int(feats.size()).is_equal(24)
	assert_array(_catalog.problems(_weapon_ids(), _type_ids())).is_empty()
	for def in feats:
		(
			assert_bool(def.grants.is_empty())
			. override_failure_message("%s gives nothing" % def.id)
			. is_false()
		)
		assert_bool(def.is_ladder()).is_false()


func test_every_weapon_and_every_kind_are_in_the_feats_that_ask_for_all_of_them() -> void:
	var weapons: Array[StringName] = []
	for id in _weapon_ids():
		weapons.append(ChallengeStats.weapon_kills(id))
	var rack := _catalog.get_def(&"f_full_rack")
	assert_array(rack.stats).contains_exactly_in_any_order(weapons)
	# The boss is no kind of the dead a player meets every night: it has its own feat.
	var kinds: Array[StringName] = []
	for id in _type_ids():
		if id != &"headliner":
			kinds.append(ChallengeStats.type_kills(id))
	assert_array(_catalog.get_def(&"f_pest_control").stats).contains_exactly_in_any_order(kinds)


func test_a_feat_is_one_total_across_nights_says_nothing_on_the_way_and_finishes_once() -> void:
	# "Mend 10 boards": nine, then the tenth in another night.
	assert_array(_count(ChallengeStats.BOARDS, 9, 9)).is_empty()
	assert_int(_profile.feats[&"f_hammer"]).is_equal(9)
	var last := _count(ChallengeStats.BOARDS, 1, 1)
	assert_int(last.size()).is_equal(1)
	assert_bool(last[0]["completed"]).is_true()
	assert_str(last[0]["id"]).is_equal("f_hammer")
	assert_int(last[0]["checkpoint"]).is_equal(100)
	# Done is done: more boards move nothing of it.
	assert_array(_count(ChallengeStats.BOARDS, 5, 5)).is_empty()


func test_a_feat_in_one_night_keeps_the_best_night() -> void:
	# "Take in 2,000 points in one night": 1,500 and then 400 in other nights do not add up.
	assert_array(_count(ChallengeStats.POINTS, 1500, 1500)).is_empty()
	assert_array(_count(ChallengeStats.POINTS, 400, 400)).is_empty()
	assert_int(_profile.feats[&"f_pocket"]).is_equal(1500)
	var done := _count(ChallengeStats.POINTS, 2000, 1600)
	assert_str(done[0]["id"]).is_equal("f_pocket")
	assert_bool(done[0]["completed"]).is_true()


func test_a_feat_over_several_stats_is_as_far_as_the_lowest() -> void:
	var rack := _catalog.get_def(&"f_full_rack")
	var last: StringName = rack.stats[rack.stats.size() - 1]
	# Every weapon but the last at 250: the lowest is 0, so the feat has not begun.
	for stat in rack.stats.slice(0, rack.stats.size() - 1):
		assert_array(_count(stat, 250, 250)).is_empty()
	assert_int(int(_profile.feats.get(rack.id, 0))).is_equal(0)
	assert_array(_count(last, 100, 100)).is_empty()
	assert_int(_profile.feats[rack.id]).is_equal(100)
	var moved := _count(last, 150, 150)
	assert_int(moved.size()).is_equal(1)
	assert_bool(moved[0]["completed"]).is_true()
	assert_int(_profile.feats[rack.id]).is_equal(250)


func test_the_best_round_finishes_a_feat_on_reaching_it_and_not_before() -> void:
	assert_array(_count(ChallengeStats.ROUND, 4, 4)).is_empty()
	var moved := _count(ChallengeStats.ROUND, 5, 1)
	assert_int(moved.size()).is_equal(1)
	assert_str(moved[0]["id"]).is_equal("f_round_5")
	assert_bool(moved[0]["completed"]).is_true()


func test_a_feat_survives_a_save() -> void:
	_count(ChallengeStats.BOARDS, 6, 6)
	var restored := ChallengeProfile.from_dict(
		JSON.parse_string(JSON.stringify(_profile.to_dict()))
	)
	assert_int(restored.feats[&"f_hammer"]).is_equal(6)
	var moved: Array[Dictionary] = []
	for advance in restored.apply(_catalog, ChallengeStats.BOARDS, 4, 4):
		if advance["family"] == ChallengeDef.Family.FEAT:
			moved.append(advance)
	assert_bool(moved[0]["completed"]).is_true()


func test_a_bad_feat_is_reported() -> void:
	var catalog := ChallengeCatalog.new()
	(
		catalog
		. add_all(
			[
				{
					"id": "a",
					"text": "x",
					"stats": ["kills", "nonsense"],
					"target": 3,
					"grants": ["card:ok"]
				},
				{
					"id": "b",
					"text": "x",
					"stat": "kills",
					"target": 3,
					"grants": ["card:Not Snake", "bad"]
				},
				{
					"id": "c",
					"text": "x",
					"stats": ["kills", "kills:head"],
					"mode": "night",
					"target": 3
				},
			],
			ChallengeDef.Family.FEAT
		)
	)
	var found := "\n".join(catalog.problems(_weapon_ids(), _type_ids()))
	assert_str(found).contains("a: unknown stat 'nonsense'")
	assert_str(found).contains("b: grant 'card:Not Snake' is not")
	assert_str(found).contains("b: grant 'bad' is not")
	assert_str(found).contains("c: only a feat counted in total")
