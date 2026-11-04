extends GdUnitTestSuite
## The table of what each level gives (`unlocks.json`, the design page's ladder): the numbers the
## design page states, and a table read from text.


func _items(rows: Array) -> Array:
	return rows.map(func(row: Dictionary) -> StringName: return row["item"])


func _slots(rows: Array) -> Array:
	return rows.map(func(row: Dictionary) -> StringName: return row["slot"])


func test_the_shipped_table_is_the_designs() -> void:
	var table := LadderUnlocks.shipped()
	# The back rooms open at level 10, with the tier's card and emblem.
	assert_array(_slots(table.at_level(10))).contains_exactly_in_any_order(
		[&"map", &"tier_card", &"tier_emblem"]
	)
	assert_array(_items(table.earned_at(10))).is_equal([&"back_rooms"])
	# Every row is in the ladder, and ten colours are given across it.
	var colours := 0
	for level in table.levels():
		assert_bool(level >= 2 and level <= LevelCurve.MAX_LEVEL).is_true()
		for row: Dictionary in table.at_level(level):
			assert_int(row["level"]).is_equal(level)
			if row["slot"] == &"colour":
				colours += 1
	assert_int(colours).is_equal(10)
	# A tier card every fifth level, 11 of them.
	var cards := 0
	for level in range(5, 56, 5):
		cards += _slots(table.at_level(level)).count(&"tier_card")
	assert_int(cards).is_equal(11)


func test_a_level_with_no_row_gives_only_its_icon() -> void:
	var table := LadderUnlocks.shipped()
	assert_array(table.at_level(23)).is_empty()
	assert_array(table.earned_at(1)).is_empty()


func test_an_item_without_art_is_listed_but_not_earned() -> void:
	var text := (
		'[{"level": 4, "slot": "top", "item": "a", "available": true},'
		+ ' {"level": 4, "slot": "neck", "item": "b", "available": false},'
		+ ' {"level": "x"}, 7]'
	)
	var table := LadderUnlocks.from_text(text)
	assert_int(table.at_level(4).size()).is_equal(2)
	assert_array(_items(table.earned_at(4))).is_equal([&"a"])
	assert_array(LadderUnlocks.from_text("not json").levels()).is_empty()
