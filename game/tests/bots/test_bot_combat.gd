# The bot's judgement in a fight (bots plan, phase 3): which zombie to shoot, kill courtesy, when a
# melee swing is a good idea and how far a chase may go. Pure rules on plain data.
extends GdUnitTestSuite

const HERE := Vector3.ZERO


func _zombie(
	id: int, at: Vector3, mode := ZombieBody.Mode.CHASE, look := &"walker", velocity := Vector3.ZERO
) -> Dictionary:
	return {
		"id": id,
		"position": at,
		"mode": mode,
		"look": look,
		"velocity": velocity,
		"visible": true,
	}


func _mate(at: Vector3, facing := 0.0, bot := false) -> Dictionary:
	return {
		"id": 2,
		"pos": at,
		"facing": facing,
		"bot": bot,
		"dead": false,
		"downed": false,
		"hurt_at": -INF,
	}


func _choose(
	combat: BotCombat,
	zombies: Array[Dictionary],
	mates: Array[Dictionary] = [],
	held: WeaponDef = null,
	now := 10.0,
	blow_age := INF
) -> int:
	return combat.choose(zombies, HERE, held, mates, now, blow_age)


func test_the_nearest_zombie_is_shot_first() -> void:
	var combat := BotCombat.new(BotProfile.regular())
	var zombies: Array[Dictionary] = [
		_zombie(1, Vector3(0, 0, -12)), _zombie(2, Vector3(3, 0, -6)), _zombie(3, Vector3(-9, 0, 0))
	]
	assert_int(_choose(combat, zombies)).is_equal(2)


func test_a_swing_under_way_beats_a_nearer_zombie_that_is_only_walking() -> void:
	var combat := BotCombat.new(BotProfile.regular())
	var zombies: Array[Dictionary] = [
		_zombie(1, Vector3(0, 0, -4.0)), _zombie(2, Vector3(0, 0, -5.5), ZombieBody.Mode.ATTACK)
	]
	assert_int(_choose(combat, zombies)).is_equal(2)


func test_a_zombie_on_a_downed_teammate_beats_a_nearer_one() -> void:
	var combat := BotCombat.new(BotProfile.regular())
	var down := _mate(Vector3(10, 0, -6))
	down["downed"] = true
	var mates: Array[Dictionary] = [down]
	var zombies: Array[Dictionary] = [
		_zombie(1, Vector3(0, 0, -5)), _zombie(2, Vector3(10, 0, -7.5))
	]
	assert_int(_choose(combat, zombies, mates)).is_equal(2)
	assert_int(_choose(combat, zombies)).is_equal(1)


func test_a_zombie_on_a_teammate_just_hit_is_worth_more_and_the_bonus_fades() -> void:
	var combat := BotCombat.new(BotProfile.regular())
	# The person looks away (the other way), so the zombie is not one they are working on.
	var hurt := _mate(Vector3(8, 0, -6), -1.5)
	hurt["hurt_at"] = 9.5
	var mates: Array[Dictionary] = [hurt]
	var zombies: Array[Dictionary] = [
		_zombie(1, Vector3(0, 0, -6)), _zombie(2, Vector3(8, 0, -7.5))
	]
	assert_int(_choose(combat, zombies, mates, null, 10.0)).is_equal(2)
	assert_int(_choose(combat, zombies, mates, null, 20.0)).is_equal(1)


func test_a_blow_just_taken_counts_the_zombies_on_the_bot() -> void:
	var combat := BotCombat.new(BotProfile.regular())
	var zombie := _zombie(1, Vector3(0, 0, -2.2))
	var hit := combat.utility(zombie, HERE, null, [], 10.0, 0.5)
	var calm := combat.utility(zombie, HERE, null, [], 10.0, INF)
	assert_float(hit).is_greater(calm)


func test_a_hurt_bot_minds_the_zombie_at_its_feet_more() -> void:
	var combat := BotCombat.new(BotProfile.regular())
	var close := _zombie(1, Vector3(0, 0, -3))
	var far := _zombie(2, Vector3(0, 0, -18))
	var healthy_gap := (
		combat.utility(close, HERE, null, [], 0.0) - combat.utility(far, HERE, null, [], 0.0)
	)
	var hurt_gap := (
		combat.utility(close, HERE, null, [], 0.0, INF, 0.2)
		- combat.utility(far, HERE, null, [], 0.0, INF, 0.2)
	)
	assert_float(hurt_gap).is_greater(healthy_gap)


func test_the_target_in_hand_is_kept_between_two_alike() -> void:
	var combat := BotCombat.new(BotProfile.regular())
	var zombies: Array[Dictionary] = [
		_zombie(1, Vector3(0.0, 0, -8.0)), _zombie(2, Vector3(0.5, 0, -8.05))
	]
	var first := _choose(combat, zombies)
	zombies[0]["position"] = Vector3(0.0, 0, -8.2)
	zombies[1]["position"] = Vector3(0.5, 0, -8.0)
	assert_int(_choose(combat, zombies)).is_equal(first)


func test_a_weapon_that_does_little_at_range_loses_the_far_targets() -> void:
	var combat := BotCombat.new(BotProfile.regular())
	var shotgun := WeaponCatalog.get_def(&"shotgun")
	var near := _zombie(1, Vector3(0, 0, -5))
	var far := _zombie(2, Vector3(0, 0, -20))
	var with_gun := combat.utility(far, HERE, shotgun, [], 0.0)
	assert_float(with_gun).is_less(combat.utility(far, HERE, null, [], 0.0))
	assert_float(combat.utility(near, HERE, shotgun, [], 0.0)).is_greater(with_gun)


# --- Kill courtesy ---


func test_a_zombie_a_person_is_aiming_at_from_afar_is_left_to_them() -> void:
	var combat := BotCombat.new(BotProfile.regular())
	# The person stands 3 m to the right and looks down the field (facing 0 is -z).
	var mates: Array[Dictionary] = [_mate(Vector3(3, 0, 0), 0.0)]
	var theirs := _zombie(1, Vector3(3, 0, -14))
	var spare := _zombie(2, Vector3(-6, 0, -10))
	assert_bool(BotCombat.courtesy_holds(theirs, HERE, mates)).is_true()
	assert_bool(BotCombat.courtesy_holds(spare, HERE, mates)).is_false()
	var both: Array[Dictionary] = [theirs, spare]
	assert_int(_choose(combat, both, mates)).is_equal(2)
	# Alone, the bot holds fire at the one that is theirs.
	var only: Array[Dictionary] = [theirs]
	assert_int(_choose(combat, only, mates)).is_equal(-1)


func test_courtesy_ends_when_the_zombie_is_near_or_swinging_and_for_bots() -> void:
	var mates: Array[Dictionary] = [_mate(Vector3(3, 0, 0), 0.0)]
	assert_bool(BotCombat.courtesy_holds(_zombie(1, Vector3(3, 0, -5.0)), HERE, mates)).is_false()
	var swinging := _zombie(1, Vector3(3, 0, -14), ZombieBody.Mode.ATTACK)
	assert_bool(BotCombat.courtesy_holds(swinging, HERE, mates)).is_false()
	var bots: Array[Dictionary] = [_mate(Vector3(3, 0, 0), 0.0, true)]
	assert_bool(BotCombat.courtesy_holds(_zombie(1, Vector3(3, 0, -14)), HERE, bots)).is_false()
	# A person looking elsewhere is not working on it.
	var turned: Array[Dictionary] = [_mate(Vector3(3, 0, 0), 1.5)]
	assert_bool(BotCombat.courtesy_holds(_zombie(1, Vector3(3, 0, -14)), HERE, turned)).is_false()


# --- Melee ---


func test_a_swing_never_goes_into_a_pack_unless_the_guns_are_dry() -> void:
	for near in range(0, 10):
		for dry in [false, true]:
			var allowed := BotCombat.may_melee(near, dry)
			if near >= BotCombat.PACK_SIZE and not dry:
				assert_bool(allowed).is_false()
			else:
				assert_bool(allowed).is_true()


func test_the_pack_counts_the_believed_zombies_within_four_metres() -> void:
	var beliefs := BotBeliefs.new()
	beliefs.now = 5.0
	for i in 5:
		var contact := _zombie(i + 1, Vector3(float(i), 0, -3.0))
		contact.merge({"believed_at": 0.0, "last_seen": 5.0})
		beliefs.contacts[i + 1] = contact
	# Three of the five are within 4 m of the bot (3.0, 3.2 and 3.6 m); the others are 4.2 and 5 m.
	assert_int(BotCombat.near_count(beliefs, HERE, 3.0)).is_equal(3)
	beliefs.contacts[1]["believed_at"] = 9.0
	assert_int(BotCombat.near_count(beliefs, HERE, 3.0)).is_equal(2)


# --- The leash ---


func test_a_chase_stops_twelve_metres_from_the_nearest_person() -> void:
	var people: Array[Vector3] = [Vector3(0, 0, 0), Vector3(30, 0, 0)]
	var none: Array[Vector3] = []
	for metres in range(0, 20):
		var point := Vector3(0, 0, -float(metres))
		var allowed := BotCombat.leash_allows(point, HERE, people, none)
		assert_bool(allowed).is_equal(float(metres) <= BotCombat.LEASH)
	# The nearest person counts, not the first: a point near the second person is fine.
	assert_bool(BotCombat.leash_allows(Vector3(35, 0, 0), HERE, people, none)).is_true()


func test_the_leash_is_waived_for_a_target_on_a_downed_teammate() -> void:
	var people: Array[Vector3] = [HERE]
	var downed: Array[Vector3] = [Vector3(0, 0, -30)]
	assert_bool(BotCombat.leash_allows(Vector3(0, 0, -28), HERE, people, downed)).is_true()
	assert_bool(BotCombat.leash_allows(Vector3(0, 0, -20), HERE, people, downed)).is_false()


func test_with_nobody_to_stay_near_the_leash_is_from_where_the_bot_stands() -> void:
	var none: Array[Vector3] = []
	assert_bool(BotCombat.leash_allows(Vector3(0, 0, -11), HERE, none, none)).is_true()
	assert_bool(BotCombat.leash_allows(Vector3(0, 0, -13), HERE, none, none)).is_false()
