extends GdUnitTestSuite
## Two players with the same look get one tint moved; every client reaches the same answer.


func _table(ids: Array, preset := 1) -> Dictionary:
	var looks := {}
	for id: int in ids:
		looks[id] = CharacterLook.from_preset(preset)
	return looks


func test_different_looks_are_left_alone() -> void:
	var looks := {1: CharacterLook.from_preset(0), 2: CharacterLook.from_preset(1)}
	var out := LookResolver.resolve(looks)
	assert_bool(out[1].equals(looks[1])).is_true()
	assert_bool(out[2].equals(looks[2])).is_true()
	assert_int(out[1].shift + out[2].shift).is_equal(0)


func test_the_later_player_of_two_identical_looks_is_shifted() -> void:
	var out := LookResolver.resolve(_table([3, 8]))
	assert_int(out[3].shift).is_equal(0)
	assert_int(out[8].shift).is_equal(1)
	assert_bool(out[3].equals(out[8])).is_false()
	# Only the main colour moved, by one palette place.
	var original := CharacterLook.from_preset(1)
	assert_int(out[8].colours[&"primary"]).is_equal(original.colours[&"primary"] + 1)
	for slot in LookCatalog.colour_slots():
		if slot != &"primary":
			assert_int(out[8].colours[slot]).is_equal(original.colours[slot])
	assert_dict(out[8].parts).is_equal(original.parts)


func test_four_identical_players_all_end_up_distinct() -> void:
	var out := LookResolver.resolve(_table([0, 1, 2, 3]))
	var keys := {}
	for id: int in out:
		keys[out[id].key()] = true
	assert_int(keys.size()).is_equal(4)


func test_the_answer_does_not_depend_on_the_order_players_arrived_in() -> void:
	var forward := {}
	var backward := {}
	var ids := [5, 2, 9, 4]
	for id: int in ids:
		forward[id] = CharacterLook.from_preset(2)
	for i in range(ids.size() - 1, -1, -1):
		backward[ids[i]] = CharacterLook.from_preset(2)
	var a := LookResolver.resolve(forward)
	var b := LookResolver.resolve(backward)
	for id: int in ids:
		assert_str(a[id].key()).is_equal(b[id].key())


func test_a_shift_never_lands_on_a_look_somebody_else_already_wears() -> void:
	var looks := _table([1, 3])
	var taken := CharacterLook.from_preset(1)
	taken.shift_colour(&"primary", 1)
	looks[2] = taken
	var out := LookResolver.resolve(looks)
	var keys := {}
	for id: int in out:
		keys[out[id].key()] = true
	assert_int(keys.size()).is_equal(3)


func test_the_input_table_is_not_changed() -> void:
	var looks := _table([1, 2])
	var before: String = looks[2].key()
	LookResolver.resolve(looks)
	assert_str(looks[2].key()).is_equal(before)
	assert_int(looks[2].shift).is_equal(0)
