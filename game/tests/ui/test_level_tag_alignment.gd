extends GdUnitTestSuite
## Where a level's icon is set beside its digits (#1161), as numbers: the digits' ink from the
## font's outlines, the icon's body from the manifest, and the places that put the one on the other.
## The pixels they come to are read in `test_level_ink.gd` (which needs a renderer).


func before_test() -> void:
	LevelIcons.release()
	LevelTag.release()


func test_the_digits_ink_is_read_from_the_font_and_moves_with_its_size() -> void:
	var font := HudFonts.SHIPPED_TEXT
	var small := LevelTag.digit_span(font, 20)
	var large := LevelTag.digit_span(font, 40)
	# The digits stand on the baseline and reach about three quarters of the size above it.
	assert_float(small.y).is_equal_approx(0.0, 0.5)
	assert_float(small.x).is_between(-0.9 * 20.0, -0.6 * 20.0)
	# The outlines are hinted to the size, so twice the size is about twice the height.
	assert_float(large.x).is_equal_approx(small.x * 2.0, 3.0)
	assert_float(LevelTag.digits_centre(font, 20, 100.0)).is_equal_approx(
		100.0 + (small.x + small.y) * 0.5, 0.001
	)


func test_an_icons_body_is_centred_on_the_centre_it_is_given() -> void:
	for level in [3, 7, 12, 55]:
		var top := LevelTag.icon_top(50.0, level)
		assert_float(top + LevelIcons.body_centre(level) * LevelTag.ICON).is_equal_approx(
			50.0, 0.001
		)
		# A bigger icon (the night report's) is centred the same way.
		var big := LevelTag.icon_top(50.0, level, 32.0)
		assert_float(big + LevelIcons.body_centre(level) * 32.0).is_equal_approx(50.0, 0.001)


func test_a_label_centred_in_a_row_puts_the_icon_where_its_digits_are() -> void:
	var font := HudFonts.SHIPPED_DISPLAY
	var size_px := 32
	for row in [46.0, 60.0]:
		var block_top := floorf((row - font.get_height(size_px)) * 0.5)
		var digits := LevelTag.digits_centre(
			font, size_px, block_top + LevelTag.line_baseline(font, size_px)
		)
		var top := LevelTag.icon_top_in_row(row, font, size_px, 7)
		assert_float(top + LevelIcons.body_centre(7) * LevelTag.ICON).is_equal_approx(digits, 0.001)
	# A taller row moves the digits and the icon down together.
	var low := LevelTag.icon_top_in_row(60.0, font, size_px, 7)
	var high := LevelTag.icon_top_in_row(46.0, font, size_px, 7)
	assert_float(low - high).is_between(6.0, 8.0)
