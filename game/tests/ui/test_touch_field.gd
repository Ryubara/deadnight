extends GdUnitTestSuite
## A text field a finger taps is as tall as a button (Deadnight #1183).


func test_a_field_is_as_tall_as_the_tokens_controls() -> void:
	var field: LineEdit = auto_free(LineEdit.new())
	TouchField.fit(field)
	assert_float(field.custom_minimum_size.y).is_equal(float(UITokens.active().control_height))


func test_a_taller_field_stays_as_it_is() -> void:
	var field: LineEdit = auto_free(LineEdit.new())
	field.custom_minimum_size.y = 200.0
	TouchField.fit(field)
	assert_float(field.custom_minimum_size.y).is_equal(200.0)
