# The Strike button of the phone (#1285), driven by real touch events over the real layer: it shows
# only while a dead is within reach of the quick melee, presses `quick_melee` for at least a hold's
# minimum, turns the view while a finger that began on it drags, lets the markers know when it is
# up, wears the blade and no word, and is the same for a left hand.
extends GdUnitTestSuite

const CANVASES: Array[Vector2] = [Vector2(2340.0, 1080.0), Vector2(1920.0, 1080.0)]

var _fixture: TouchFixture
var _looks: Array[Vector2] = []


func before_test() -> void:
	UIMotion.reduced = false
	UIInputMode.reset()
	Input.action_release(TouchLayout.STRIKE)


func after_test() -> void:
	if _fixture != null:
		_fixture.free_all()
		_fixture = null


func _start(canvas := CANVASES[0], mirrored := false) -> void:
	_fixture = TouchFixture.make(self, canvas, HudState.new())
	if mirrored:
		_fixture.left_handed()
	_fixture.controls.refresh()
	_looks.clear()
	_fixture.controls.looked.connect(func(relative: Vector2) -> void: _looks.append(relative))
	await await_idle_frame()


func _frames(count := 2) -> void:
	for _i in count:
		await await_idle_frame()


func _up() -> void:
	_fixture.strike_up = true
	await _frames()


func test_it_is_not_there_until_a_dead_is_in_reach() -> void:
	await _start()
	assert_bool(_fixture.controls.strike_up).is_false()
	await _fixture.touch(0, _fixture.at(TouchLayout.STRIKE))
	assert_array(_fixture.controls.held_buttons()).is_empty()
	assert_bool(Input.is_action_pressed(TouchLayout.STRIKE)).is_false()
	await _fixture.lift(0)
	await _up()
	assert_bool(_fixture.controls.strike_up).is_true()
	await _fixture.touch(0, _fixture.at(TouchLayout.STRIKE))
	assert_array(_fixture.controls.held_buttons()).is_equal(PackedStringArray(["quick_melee"]))
	await _fixture.lift(0)


func test_a_press_is_the_quick_melee_action_and_lasts_at_least_the_minimum_hold() -> void:
	await _start()
	await _up()
	var tuning := _fixture.controls.tuning
	assert_float(tuning.min_hold).is_greater_equal(0.09)
	await _fixture.touch(0, _fixture.at(TouchLayout.STRIKE))
	assert_bool(Input.is_action_pressed(TouchLayout.STRIKE)).is_true()
	# Lifted at once: the action stays down for the hold, then goes.
	await _fixture.lift(0)
	assert_bool(Input.is_action_pressed(TouchLayout.STRIKE)).is_true()
	await await_millis(int(tuning.min_hold * 1000.0) + 120)
	assert_bool(Input.is_action_pressed(TouchLayout.STRIKE)).is_false()


func test_a_finger_that_starts_on_it_also_looks_and_does_not_start_the_stick() -> void:
	await _start()
	await _up()
	assert_bool(TouchLayout.looks_when_dragged(TouchLayout.STRIKE)).is_true()
	var at := _fixture.at(TouchLayout.STRIKE)
	await _fixture.touch(0, at)
	await _fixture.drag(0, at + Vector2(40.0, 0.0), Vector2(40.0, 0.0), 300.0)
	await _fixture.drag(0, at + Vector2(80.0, 10.0), Vector2(40.0, 10.0), 300.0)
	await _fixture.settle_look()
	assert_bool(_looks.is_empty()).is_false()
	assert_bool(_fixture.controls.is_stick_down()).is_false()
	await _fixture.lift(0)


func test_it_goes_from_under_a_finger_that_is_on_it_when_the_dead_is_gone() -> void:
	await _start()
	await _up()
	await _fixture.touch(0, _fixture.at(TouchLayout.STRIKE))
	assert_array(_fixture.controls.held_buttons()).is_not_empty()
	_fixture.strike_up = false
	await _frames()
	assert_bool(_fixture.controls.strike_up).is_false()
	assert_array(_fixture.controls.held_buttons()).is_empty()
	await _fixture.lift(0)
	await await_millis(200)
	assert_bool(Input.is_action_pressed(TouchLayout.STRIKE)).is_false()


func test_the_world_markers_keep_clear_of_it_only_while_it_is_up() -> void:
	await _start()
	var circle := _fixture.controls.button_circle(TouchLayout.STRIKE)
	var reach := Vector2.ONE * float(circle[&"radius"])
	var box := Rect2(
		_fixture.controls.get_global_rect().position + Vector2(circle[&"centre"]) - reach,
		reach * 2.0
	)
	assert_bool(_fixture.controls.button_boxes().has(box)).is_false()
	await _up()
	assert_bool(_fixture.controls.button_boxes().has(box)).is_true()


func test_it_wears_the_blade_and_no_word() -> void:
	await _start()
	assert_bool(TouchIcons.has_icon(TouchLayout.STRIKE)).is_true()
	var shapes := HudShapes.new()
	TouchIcons.add(
		shapes, TouchLayout.STRIKE, Vector2(100.0, 100.0), 52.0, Color.WHITE, Color.BLACK
	)
	assert_bool(shapes.is_empty()).is_false()
	# Only Interact keeps a word, and it has no prompt to say here.
	await _up()
	assert_str(_fixture.controls.interact_verb()).is_equal("")


func test_a_left_hand_has_it_on_the_left_in_the_same_place() -> void:
	for canvas in CANVASES:
		await _start(canvas, true)
		await _up()
		var circle := _fixture.controls.button_circle(TouchLayout.STRIKE)
		var corner := Vector2(0.0, canvas.y)
		var offset := Vector2(circle[&"centre"]) - corner
		assert_vector(offset).is_equal_approx(Vector2(575.0, -340.0), Vector2.ONE * 0.01)
		await _fixture.touch(0, _fixture.at(TouchLayout.STRIKE))
		assert_array(_fixture.controls.held_buttons()).is_equal(PackedStringArray(["quick_melee"]))
		await _fixture.lift(0)
		_fixture.free_all()
		_fixture = null


func test_a_layer_without_a_source_never_shows_it() -> void:
	await _start()
	_fixture.controls.strike_ready = Callable()
	_fixture.strike_up = true
	await _frames()
	assert_bool(_fixture.controls.strike_up).is_false()
