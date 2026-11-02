extends GdUnitTestSuite
## The voice budget on its own: slots, group limits, priorities, cooldowns. No engine audio is
## involved, time is a number the test passes in.

const SLOTS := 8

var _budget: VoiceBudget


func before_test() -> void:
	_budget = VoiceBudget.new(SLOTS, SoundCatalog.group_limits())


func test_slots_fill_then_the_pool_is_never_exceeded() -> void:
	var step := _step()
	var taken := {}
	for i in 40:
		var slot := _budget.acquire(step, 1.0 + i, 0.0, 10.0)
		if slot >= 0:
			taken[slot] = true
	assert_int(_budget.active_count()).is_equal(SLOTS)
	assert_int(taken.size()).is_equal(SLOTS)


func test_a_finished_sound_frees_its_slot() -> void:
	var def := SoundCatalog.get_def(&"shot_pistol")
	var slot := _budget.acquire(def, 1.0, 0.0, 0.5)
	assert_int(slot).is_greater_equal(0)
	assert_bool(_budget.is_active(slot)).is_true()
	_budget.expire(0.49)
	assert_bool(_budget.is_active(slot)).is_true()
	_budget.expire(0.5)
	assert_bool(_budget.is_active(slot)).is_false()
	assert_int(_budget.active_count()).is_equal(0)


func test_cooldown_drops_a_repeat_until_it_has_passed() -> void:
	var def := SoundCatalog.get_def(&"dry_fire")
	assert_int(_budget.acquire(def, 1.0, 1.0, 0.05)).is_greater_equal(0)
	assert_int(_budget.acquire(def, 1.0, 1.05, 0.05)).is_equal(-1)
	assert_int(_budget.acquire(def, 1.0, 1.0 + def.cooldown, 0.05)).is_greater_equal(0)


func test_28_zombies_hold_only_the_group_limit_and_the_nearest_win() -> void:
	var groan := SoundCatalog.get_def(&"zombie_groan")
	var limit: int = SoundCatalog.group_limits()[&"zombie_voice"]
	# Each zombie is clearly louder (nearer) than the one before it, so the last ones must hold the
	# slots.
	var loudness := 0.01
	var all: Array[float] = []
	for i in 28:
		loudness *= 1.25
		all.append(loudness)
		_budget.acquire(groan, loudness, 0.0, 5.0)
		assert_int(_budget.group_count(&"zombie_voice")).is_less_equal(limit)
	assert_int(_budget.group_count(&"zombie_voice")).is_equal(limit)
	var kept: Array[float] = []
	for slot in SLOTS:
		if _budget.is_active(slot):
			kept.append(_budget.loudness_at(slot))
	kept.sort()
	var expected := all.slice(28 - limit)
	for i in limit:
		assert_float(kept[i]).is_equal_approx(expected[i], 0.0001)
	assert_int(_budget.stolen).is_equal(28 - limit)


func test_a_quiet_zombie_cannot_take_a_loud_ones_voice() -> void:
	var groan := SoundCatalog.get_def(&"zombie_groan")
	var limit: int = SoundCatalog.group_limits()[&"zombie_voice"]
	for i in limit:
		_budget.acquire(groan, 1.0, 0.0, 5.0)
	assert_int(_budget.acquire(groan, 0.5, 0.0, 5.0)).is_equal(-1)
	# Just under the 15 percent margin is still dropped, clearly louder gets in.
	assert_int(_budget.acquire(groan, 1.1, 0.0, 5.0)).is_equal(-1)
	assert_int(_budget.acquire(groan, 1.3, 0.0, 5.0)).is_greater_equal(0)


func test_a_full_zombie_group_leaves_room_for_gunfire() -> void:
	var groan := SoundCatalog.get_def(&"zombie_groan")
	for i in 20:
		_budget.acquire(groan, 1.0 + i, 0.0, 5.0)
	var shot := SoundCatalog.get_def(&"shot_rifle")
	assert_int(_budget.acquire(shot, 1.0, 0.0, 1.0)).is_greater_equal(0)
	assert_int(_budget.acquire(shot, 1.0, 0.0, 1.0)).is_greater_equal(0)


func test_a_higher_priority_takes_a_slot_from_a_full_pool() -> void:
	var step := _step()
	for i in SLOTS:
		_budget.acquire(step, 1.0, 0.0, 5.0)
	var sting := SoundCatalog.get_def(&"round_start")
	var slot := _budget.acquire(sting, 0.1, 0.0, 3.0)
	assert_int(slot).is_greater_equal(0)
	assert_str(_budget.sound_at(slot)).is_equal("round_start")
	assert_int(_budget.stolen).is_equal(1)


func test_a_lower_priority_never_takes_a_slot_from_a_higher_one() -> void:
	var sting := SoundCatalog.get_def(&"round_start")
	var other := SoundCatalog.get_def(&"generator_start")
	var shot := SoundCatalog.get_def(&"shot_rifle")
	# One slot budget: the sting holds it, the quieter and the lesser sounds are dropped.
	var tiny := VoiceBudget.new(1, SoundCatalog.group_limits())
	assert_int(tiny.acquire(sting, 0.5, 0.0, 3.0)).is_equal(0)
	assert_int(tiny.acquire(other, 5.0, 0.0, 3.0)).is_equal(-1)
	assert_int(tiny.acquire(shot, 5.0, 0.0, 3.0)).is_equal(-1)
	assert_int(tiny.rejected).is_equal(2)


func test_release_all_empties_the_pool() -> void:
	var def := SoundCatalog.get_def(&"shot_pistol")
	for i in 3:
		_budget.acquire(def, 1.0, 0.0, 5.0)
	_budget.release_all()
	assert_int(_budget.active_count()).is_equal(0)


## A footstep-like sound without the catalog's cooldown, so a test can fill the pool in one instant.
func _step() -> SoundDef:
	return SoundDef.make(&"test_step", "res://none_%d.ogg", 1, {"group": &"step", "priority": 20})
