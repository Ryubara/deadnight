extends GdUnitTestSuite
## The parts that keep a card inside its screen (#980): `UIFitScroll` (a scroll area that asks for
## its content's height and no more than the screen leaves), `UIRow.set_stacked` and
## `set_widths` (a form row for a narrow column), and `MenuPanel.hold` (a tab's column in a scroll
## area the size of the panel).

const SCREEN := Vector2(800.0, 600.0)


## A themed stage of the given size with a card (a `UIPanel`) holding a title, a `UIFitScroll` of
## `rows` rows of `row_height`, and a footer button: what a screen's card is.
func _card(rows: int, row_height: float, canvas := SCREEN) -> Dictionary:
	var stage: Control = auto_free(Control.new())
	stage.theme = UIThemeBuilder.build(UITokens.active())
	stage.size = canvas
	add_child(stage)
	var card := UIPanel.new()
	stage.add_child(card)
	var column := VBoxContainer.new()
	card.add_child(column)
	var title := Label.new()
	title.text = "Title"
	column.add_child(title)
	var scroll := UIFitScroll.new()
	scroll.limit = stage
	column.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	for i in rows:
		var row := Button.new()
		row.custom_minimum_size = Vector2(200.0, row_height)
		content.add_child(row)
	var footer := Button.new()
	footer.text = "Back"
	column.add_child(footer)
	await get_tree().process_frame
	await get_tree().process_frame
	return {"stage": stage, "card": card, "scroll": scroll, "footer": footer}


func test_a_short_card_asks_for_the_height_of_its_content() -> void:
	var parts := await _card(3, 50.0)
	var scroll: UIFitScroll = parts["scroll"]
	var content := scroll.get_child(0) as Control
	var wanted := content.get_combined_minimum_size().y + UIScroll.margins(scroll).y
	assert_float(scroll.custom_minimum_size.y).is_equal_approx(wanted, 1.0)
	assert_float((parts["card"] as Control).size.y).is_less(SCREEN.y)


func test_a_tall_card_stops_at_the_screen_and_keeps_its_footer_on_it() -> void:
	var parts := await _card(30, 50.0)
	var card: Control = parts["card"]
	var footer: Control = parts["footer"]
	var scroll: UIFitScroll = parts["scroll"]
	assert_float(card.get_global_rect().end.y).is_less_equal(SCREEN.y + 1.0)
	assert_float(footer.get_global_rect().end.y).is_less_equal(SCREEN.y + 1.0)
	# The rows that do not fit scroll: there is more below.
	assert_bool(scroll.has_more_below()).is_true()


func test_the_margin_is_kept_free_above_and_below_the_card() -> void:
	var parts := await _card(30, 50.0)
	var scroll: UIFitScroll = parts["scroll"]
	scroll.margin = 40.0
	scroll.fit()
	await get_tree().process_frame
	await get_tree().process_frame
	var card: Control = parts["card"]
	assert_float(card.size.y).is_less_equal(SCREEN.y - 80.0 + 1.0)


func test_a_smaller_screen_shrinks_the_area_and_a_bigger_one_gives_it_back() -> void:
	var parts := await _card(12, 50.0, Vector2(800.0, 2000.0))
	var stage: Control = parts["stage"]
	var scroll: UIFitScroll = parts["scroll"]
	var tall := scroll.custom_minimum_size.y
	stage.size = Vector2(SCREEN.x, 300.0)
	scroll.fit()
	await get_tree().process_frame
	var short := scroll.custom_minimum_size.y
	assert_float(short).is_less(tall)
	stage.size = Vector2(SCREEN.x, 2000.0)
	scroll.fit()
	await get_tree().process_frame
	assert_float(scroll.custom_minimum_size.y).is_equal_approx(tall, 1.0)


func test_a_very_short_screen_still_shows_the_least_height() -> void:
	var parts := await _card(12, 50.0, Vector2(800.0, 100.0))
	var scroll: UIFitScroll = parts["scroll"]
	assert_float(scroll.custom_minimum_size.y).is_greater_equal(scroll.least)


func test_a_steady_area_keeps_its_height_when_the_page_is_short() -> void:
	var parts := await _card(1, 50.0)
	var scroll: UIFitScroll = parts["scroll"]
	scroll.steady = 300.0
	scroll.fit()
	assert_float(scroll.custom_minimum_size.y).is_equal_approx(300.0, 1.0)


# ------------------------------------------------------------------------------- UIRow


func _row(title: String, hint := "") -> UIRow:
	var row := UIRow.new()
	row.title = title
	row.hint = hint
	var selector := UIOptionSelector.new()
	selector.options = PackedStringArray(["One", "Two"])
	row.set_control(selector)
	add_child(auto_free(row))
	return row


func test_a_row_given_narrow_widths_is_narrower_than_the_tokens_form() -> void:
	var row := _row("Hair style")
	var usual := row.get_combined_minimum_size().x
	row.set_widths(150.0, 300.0)
	assert_float(row.get_combined_minimum_size().x).is_less(usual)
	assert_float(row.get_combined_minimum_size().x).is_less_equal(150.0 + 300.0 + 40.0)


func test_a_stacked_row_needs_only_the_controls_width_and_goes_back() -> void:
	var row := _row("Hair style", "Ready-made looks.")
	row.set_widths(150.0, 300.0)
	var beside := row.get_combined_minimum_size()
	row.set_stacked(true)
	await get_tree().process_frame
	var stacked := row.get_combined_minimum_size()
	assert_float(stacked.x).is_less_equal(300.0 + 1.0)
	assert_float(stacked.y).is_greater(beside.y - 1.0)
	# The title is above the control now, and the control still answers `control`.
	var title_y := (row._text_column as Control).get_global_rect().position.y
	assert_float(row.control.get_global_rect().position.y).is_greater(title_y)
	row.set_stacked(false)
	await get_tree().process_frame
	assert_float(row.get_combined_minimum_size().x).is_equal_approx(beside.x, 1.0)
	assert_bool(row.control.is_inside_tree()).is_true()


func test_a_row_without_a_value_column_is_narrower_by_that_column() -> void:
	var row := _row("Face")
	row.set_widths(150.0, 300.0, true)
	var with_column := row.get_combined_minimum_size().x
	row.set_widths(150.0, 300.0, false)
	assert_float(row.get_combined_minimum_size().x).is_less(with_column)
