# A row of the Server Browser (`NightRow`): the words keep their contrast over the map's picture,
# the two kinds of night look different, and the row is a tap target tall.
extends GdUnitTestSuite


func _row(kind: String, players: int, full := false, compact := false) -> NightRow:
	var row := NightRow.new()
	row.compact = compact
	row.entry = NightEntry.from_row(
		BrowserFixture.row(
			"KITE42", "drive_in", kind, players, "Ann", 2, 4 if kind == "match" else null, full
		)
	)
	row.size = Vector2(1100.0, row.custom_minimum_size.y)
	add_child(row)
	return row


func test_the_cream_type_has_four_and_a_half_to_one_over_the_brightest_part_of_every_map() -> void:
	for info in MapRegistry.playable():
		var ratio := NightRow.scrim_contrast(info)
		(
			assert_float(ratio)
			. override_failure_message("%s: contrast %.2f" % [info.id, ratio])
			. is_greater_equal(4.5)
		)


func test_without_the_scrim_the_picture_would_not_hold_the_type() -> void:
	# The teeth of the test above: the same measure with the scrim open (alpha 0) fails on the real
	# pictures, so the scrim is what carries the words.
	var worst := 99.0
	for info in MapRegistry.playable():
		var image := info.preview().get_image()
		var brightest := 0.0
		for y in image.get_height():
			for x in int(image.get_width() * NightRow.TEXT_SHARE):
				brightest = maxf(brightest, NightRow._luminance(image.get_pixel(x, y)))
		worst = minf(worst, (NightRow._luminance(MenuLook.INK) + 0.05) / (brightest + 0.05))
	assert_float(worst).is_less(4.5)


func test_the_scrim_is_darkest_under_the_words_and_lets_the_map_through_at_the_far_end() -> void:
	assert_float(NightRow.scrim_alpha_at(0.0)).is_equal(NightRow.SCRIM_LEFT)
	assert_float(NightRow.scrim_alpha_at(1.0)).is_equal(NightRow.SCRIM_RIGHT)
	assert_float(NightRow.SCRIM_RIGHT).is_less(NightRow.SCRIM_LEFT)
	assert_float(NightRow.SCRIM_RIGHT).is_greater(0.3)


func test_the_two_kinds_have_two_chips_and_two_stripes() -> void:
	var waiting := _row("lobby", 2)
	var running := _row("match", 3)
	assert_str(waiting.chip_text()).is_equal("WAITING")
	assert_str(running.chip_text()).is_equal("IN PROGRESS  ROUND 4")
	assert_that(waiting._chip_fill()).is_not_equal(running._chip_fill())
	assert_that(waiting._chip_fill()).is_equal(NightRow.WAITING_FILL)
	assert_that(running._chip_fill()).is_equal(NightRow.MATCH_FILL)
	waiting.queue_free()
	running.queue_free()


func test_a_chip_keeps_four_and_a_half_to_one_between_its_fill_and_its_type() -> void:
	for pair: Array in [
		[NightRow.WAITING_FILL, NightRow.WAITING_INK],
		[NightRow.MATCH_FILL, NightRow.MATCH_INK],
		[NightRow.FULL_FILL, NightRow.FULL_INK],
		[NightRow.HERE_FILL, NightRow.WAITING_INK],
	]:
		var fill: Color = pair[0]
		var ink: Color = pair[1]
		var hi := maxf(NightRow._luminance(fill), NightRow._luminance(ink))
		var lo := minf(NightRow._luminance(fill), NightRow._luminance(ink))
		assert_float((hi + 0.05) / (lo + 0.05)).is_greater_equal(4.5)


func test_a_full_row_is_the_greyed_chip_and_a_refusing_sound() -> void:
	var full := _row("match", 8, true)
	assert_str(full.chip_text()).is_equal("FULL")
	assert_that(full._chip_fill()).is_equal(NightRow.FULL_FILL)
	assert_str(String(full.ui_sound_role())).is_equal("ticket_soon")
	var open := _row("lobby", 2)
	assert_str(String(open.ui_sound_role())).is_equal("ticket")
	full.queue_free()
	open.queue_free()


func test_a_row_is_a_tap_target_tall_on_both_forms() -> void:
	assert_float(NightRow.HEIGHT).is_greater_equal(MenuLook.TAP_TARGET)
	assert_float(NightRow.COMPACT_HEIGHT).is_greater_equal(MenuLook.TAP_TARGET)
	var phone := _row("lobby", 1, false, true)
	assert_float(phone.custom_minimum_size.y).is_equal(NightRow.COMPACT_HEIGHT)
	phone.queue_free()


func test_a_row_draws_without_a_picture_and_for_every_state() -> void:
	# The draw must not fail for a map with no picture or a row mid-join.
	var row := _row("match", 5)
	row.joining = true
	row.here = true
	await await_idle_frame()
	row.joining = false
	await await_idle_frame()
	row.queue_free()
