extends GdUnitTestSuite
## The room code's on-screen keypad (Deadnight #1183): a phone where the system keyboard cannot be
## made to open still types a code. The keys edit the focused field as keystrokes do, take no focus
## from it, and the keypad is up only while a finger has the field.

var _field: LineEdit
var _keypad: CodeKeypad
var _host: Control


func before_test() -> void:
	_host = auto_free(Control.new())
	add_child(_host)
	_field = LineEdit.new()
	_field.max_length = 8
	_field.text_changed.connect(
		func(text: String) -> void:
			var upper := text.to_upper()
			if upper != text:
				var at := _field.caret_column
				_field.text = upper
				_field.caret_column = at
	)
	_host.add_child(_field)
	_keypad = CodeKeypad.attach(_field, _host)
	await await_idle_frame()


func after_test() -> void:
	CodeKeypad.covering = 0.0


func _type(letters: String) -> void:
	for letter in letters:
		_keypad.key_for(letter).pressed.emit()


func test_every_letter_and_digit_has_a_key() -> void:
	for letter in CodeKeypad.DIGITS + CodeKeypad.LETTERS:
		assert_object(_keypad.key_for(letter)).is_not_null()
	assert_int(CodeKeypad.DIGITS.length() + CodeKeypad.LETTERS.length()).is_equal(36)


func test_the_field_s_own_reaction_to_typing_runs_after_a_key() -> void:
	_field.text = "ab"
	_field.caret_column = 2
	_keypad.key_for("C").pressed.emit()
	# The field upcases on `text_changed`, which the key emits as a keystroke would.
	assert_str(_field.text).is_equal("ABC")


func test_a_key_types_at_the_caret_over_the_selection() -> void:
	_field.text = "ABCD"
	_field.select(1, 3)
	_keypad.key_for("Z").pressed.emit()
	assert_str(_field.text).is_equal("AZD")
	assert_int(_field.caret_column).is_equal(2)


func test_a_full_field_takes_no_more() -> void:
	_type("ABCDEFGH")
	_type("J")
	assert_str(_field.text).is_equal("ABCDEFGH")


func test_delete_takes_the_letter_before_the_caret() -> void:
	_type("ABC")
	_keypad.delete_key.pressed.emit()
	assert_str(_field.text).is_equal("AB")
	_field.select_all()
	_keypad.delete_key.pressed.emit()
	assert_str(_field.text).is_equal("")
	_keypad.delete_key.pressed.emit()  # nothing to delete
	assert_str(_field.text).is_equal("")


func test_a_key_makes_the_field_react_as_typing_does() -> void:
	var seen: Array[String] = []
	_field.text_changed.connect(func(text: String) -> void: seen.append(text))
	_type("A")
	_keypad.delete_key.pressed.emit()
	assert_array(seen).contains_exactly(["A", ""])


func test_join_submits_what_is_typed() -> void:
	var sent: Array[String] = []
	_field.text_submitted.connect(func(text: String) -> void: sent.append(text))
	_type("QZ")
	_keypad.join_key.pressed.emit()
	assert_array(sent).contains_exactly(["QZ"])
