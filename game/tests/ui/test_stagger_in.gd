extends GdUnitTestSuite
## `UIMotion.stagger_in` ends with every control where its container put it, however it was
## started: from an input event (which runs before the frame's physics step and before the
## container has sorted the controls just shown), twice in a row, or with the layout changing while
## the controls rise.

const ROW_HEIGHT := 40.0
const SEPARATION := 8
const SETTLE_SECONDS := 0.9

var _saved_ticks := 60
var _host: Host


## A column that starts the entrance from an input event, the way a tab click does.
class Host:
	extends VBoxContainer

	var rows: Array[Control] = []

	func _init() -> void:
		add_theme_constant_override(&"separation", SEPARATION)

	func _input(event: InputEvent) -> void:
		if event.is_action_pressed(&"ui_accept"):
			show_rows()

	func show_rows() -> void:
		for row in rows:
			row.queue_free()
		rows.clear()
		for i in 4:
			var row := Control.new()
			row.custom_minimum_size.y = ROW_HEIGHT
			add_child(row)
			rows.append(row)
		UIMotion.stagger_in(rows)


func before_test() -> void:
	_saved_ticks = Engine.physics_ticks_per_second
	# With one step a second almost every frame has none, the frames where the bug shows.
	Engine.physics_ticks_per_second = 1
	_host = Host.new()
	add_child(_host)
	auto_free(_host)
	await _frames(2)


func after_test() -> void:
	# The accept event of the rows' test stays held in the next suite's process (#1254).
	InputFixture.release_all()
	Engine.physics_ticks_per_second = _saved_ticks


func test_rows_started_from_an_input_event_end_in_their_layout() -> void:
	_press_accept()
	await _frames(2)
	await _settled()
	_assert_in_layout("after one entrance")


func test_a_second_entrance_over_the_first_ends_in_the_layout() -> void:
	_press_accept()
	await _frames(3)
	_host.show_rows()
	await _frames(1)
	UIMotion.stagger_in(_host.rows)
	await _settled()
	_assert_in_layout("after an entrance over an entrance")


func test_a_layout_change_during_the_entrance_is_not_undone() -> void:
	_press_accept()
	await _frames(3)
	_host.rows[0].custom_minimum_size.y = ROW_HEIGHT * 2.0
	await _settled()
	assert_float(_host.rows[1].position.y).is_equal_approx(ROW_HEIGHT * 2.0 + SEPARATION, 0.5)
	_assert_in_layout("after the first row grew")


func test_controls_end_fully_shown() -> void:
	_press_accept()
	await _frames(2)
	await _settled()
	for row in _host.rows:
		assert_float(row.modulate.a).is_equal(1.0)


func _assert_in_layout(what: String) -> void:
	var y := 0.0
	for i in _host.rows.size():
		(
			assert_float(_host.rows[i].position.y)
			. override_failure_message(
				"%s: row %d is at %s, not %s" % [what, i, _host.rows[i].position.y, y]
			)
			. is_equal_approx(y, 0.5)
		)
		y += _host.rows[i].size.y + SEPARATION


func _press_accept() -> void:
	var event := InputEventAction.new()
	event.action = &"ui_accept"
	event.pressed = true
	Input.parse_input_event(event)


func _settled() -> void:
	await get_tree().create_timer(SETTLE_SECONDS).timeout
	await _frames(2)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame
