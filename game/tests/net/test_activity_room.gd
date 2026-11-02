# A Discord Activity opens on the main menu, with the night of its voice channel made ready in the
# background; Play together shows it at once (#495). The backend is replaced by
# `ActivityRoom.preparer`.
extends GdUnitTestSuite

signal gate

var _calls := 0
var _main: Node


func before_test() -> void:
	_calls = 0


func after_test() -> void:
	ActivityRoom.preparer = Callable()
	if is_instance_valid(_main):
		_main.queue_free()
	await RouterFixture.clear(get_tree())


func _lobby(code: String) -> Dictionary:
	return {"ok": true, "lobby": {"id": "lobby-1", "code": code, "state": "started"}}


func _boot(args: PackedStringArray) -> void:
	_main = (load("res://main.tscn") as PackedScene).instantiate()
	_main.set("launch_args", args)
	add_child(_main)
	await await_idle_frame()
	await UIRouter.idle


func _together() -> TogetherScreen:
	UIRouter.push(TogetherScreen.SCREEN, UITransition.Kind.CUT)
	await UIRouter.idle
	await await_idle_frame()
	return UIRouter.top() as TogetherScreen


func test_the_activity_opens_on_the_main_menu_with_its_room_ready() -> void:
	ActivityRoom.preparer = func() -> Dictionary:
		_calls += 1
		return _lobby("ROOM42")
	await _boot(PackedStringArray(["--instance_id=1234"]))
	assert_object(UIRouter.top()).is_instanceof(MainMenu)
	assert_object(ActivityRoom.current).is_not_null()
	assert_int(ActivityRoom.current.state).is_equal(ActivityRoom.State.READY)
	assert_str(ActivityRoom.current.lobby["code"]).is_equal("ROOM42")
	assert_str(ActivityRoom.current.instance_id).is_equal("1234")
	assert_int(_calls).is_equal(1)


func test_play_together_shows_the_ready_room_with_one_press_to_go_in() -> void:
	ActivityRoom.preparer = func() -> Dictionary:
		_calls += 1
		return _lobby("ROOM42")
	await _boot(PackedStringArray(["--instance_id=1234"]))
	var screen := await _together()
	assert_object(screen).is_not_null()
	assert_str(screen.invite_code.text).is_equal("ROOM42")
	assert_bool(screen.invite_code.is_visible_in_tree()).is_true()
	assert_bool(screen.play_button.is_visible_in_tree()).is_true()
	assert_bool(screen.play_button.disabled).is_false()
	assert_bool(screen.quick_button.is_visible_in_tree()).is_false()
	# Nothing was asked of the backend for this visit: the room was made on the menu.
	assert_int(_calls).is_equal(1)


func test_a_room_still_being_made_is_waited_for_and_then_shown() -> void:
	ActivityRoom.preparer = func() -> Dictionary:
		await gate
		return _lobby("LATE77")
	await _boot(PackedStringArray(["--instance_id=1234"]))
	assert_int(ActivityRoom.current.state).is_equal(ActivityRoom.State.PREPARING)
	var screen := await _together()
	assert_str(screen.status.text).is_equal("Getting your night ready...")
	assert_bool(screen.play_button.is_visible_in_tree()).is_false()
	gate.emit()
	await await_idle_frame()
	await await_idle_frame()
	assert_str(screen.invite_code.text).is_equal("LATE77")
	assert_bool(screen.play_button.is_visible_in_tree()).is_true()


func test_a_room_that_failed_is_tried_again_on_each_visit_and_says_why_while_it_fails() -> void:
	ActivityRoom.preparer = func() -> Dictionary:
		_calls += 1
		if _calls <= 2:
			return {"ok": false, "text": "Could not reach the game's servers."}
		return _lobby("BACK99")
	await _boot(PackedStringArray(["--instance_id=1234"]))
	assert_int(ActivityRoom.current.state).is_equal(ActivityRoom.State.FAILED)
	var first := await _together()
	assert_str(first.status.text).is_equal("Could not reach the game's servers.")
	assert_bool(first.quick_button.is_visible_in_tree()).is_true()
	UIRouter.pop(UITransition.Kind.CUT)
	await UIRouter.idle
	# The visit tried again (call 2) and failed again; the next one (call 3) works.
	assert_int(_calls).is_equal(2)
	var second := await _together()
	assert_int(_calls).is_equal(3)
	assert_str(second.invite_code.text).is_equal("BACK99")


func test_a_night_entered_from_the_room_makes_it_stale_and_the_next_visit_a_fresh_one() -> void:
	ActivityRoom.preparer = func() -> Dictionary:
		_calls += 1
		return _lobby("ROOM%d" % _calls)
	await _boot(PackedStringArray(["--instance_id=1234"]))
	ActivityRoom.current.mark_used()
	assert_int(ActivityRoom.current.state).is_equal(ActivityRoom.State.STALE)
	var screen := await _together()
	assert_int(_calls).is_equal(2)
	assert_str(screen.invite_code.text).is_equal("ROOM2")


func test_without_an_instance_id_there_is_no_room_and_the_menu_is_the_menu() -> void:
	await _boot(PackedStringArray())
	assert_object(UIRouter.top()).is_instanceof(MainMenu)
	assert_object(ActivityRoom.current).is_null()
	var screen := await _together()
	assert_bool(screen.quick_button.is_visible_in_tree()).is_true()
	assert_bool(screen.play_button.is_visible_in_tree()).is_false()
