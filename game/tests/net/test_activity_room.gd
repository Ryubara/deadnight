# A Discord Activity opens on the main menu with its voice channel made ready in the background
# (signed in, and told what the channel's lobby is); Play together goes to that lobby (#495, #515).
# The backend is replaced by `ActivityRoom.preparer` and a fake `TogetherApi`.
extends GdUnitTestSuite

signal gate

var _calls := 0
var _main: Node


## What the channel has, as the backend's preview answers it.
func _waiting(code: String) -> Dictionary:
	return {
		"ok": true,
		"preview":
		{
			"code": code,
			"state": "open",
			"round": null,
			"players": 1,
			"maxPlayers": 4,
			"full": false,
			"hostName": "Ann",
			"names": ["Ann"],
		}
	}


func before_test() -> void:
	_calls = 0


func after_test() -> void:
	ActivityRoom.preparer = Callable()
	if is_instance_valid(_main):
		_main.queue_free()
	await RouterFixture.clear(get_tree())


func _boot(args: PackedStringArray) -> void:
	_main = (load("res://main.tscn") as PackedScene).instantiate()
	_main.set("launch_args", args)
	add_child(_main)
	await await_idle_frame()
	await UIRouter.idle


## Play together, with the room's API standing in for the backend.
func _together(fake: TogetherApi = null) -> TogetherScreen:
	if fake != null:
		ActivityRoom.current.api = fake
	UIRouter.push(TogetherScreen.SCREEN, UITransition.Kind.CUT)
	await UIRouter.idle
	await await_idle_frame()
	await await_idle_frame()
	return _find_together()


func _find_together() -> TogetherScreen:
	for screen in UIRouter.screens():
		if screen is TogetherScreen:
			return screen
	return null


## An API for the room: it answers the instance preview and the make-a-lobby call.
class RoomApi:
	extends TogetherApi
	var preview_answer := {}
	var created := 0

	func my_id() -> String:
		return "a"

	func sign_in(_display_name: String = "") -> Dictionary:
		return {"ok": true}

	func preview_instance() -> Dictionary:
		return preview_answer

	func create_lobby() -> Dictionary:
		created += 1
		var host := {"userId": "a", "name": "Ann", "seat": 1, "host": true, "away": false}
		return {
			"ok": true,
			"lobby":
			{
				"id": "l1",
				"code": "NEW123",
				"hostId": "a",
				"maxPlayers": 4,
				"state": "open",
				"round": null,
				"players": null,
				"members": [host],
			}
		}


func test_the_activity_opens_on_the_main_menu_with_its_room_ready() -> void:
	ActivityRoom.preparer = func() -> Dictionary:
		_calls += 1
		return _waiting("ROOM42")
	await _boot(PackedStringArray(["--instance_id=1234"]))
	assert_object(UIRouter.top()).is_instanceof(MainMenu)
	assert_object(ActivityRoom.current).is_not_null()
	assert_int(ActivityRoom.current.state).is_equal(ActivityRoom.State.READY)
	assert_str(ActivityRoom.current.preview["code"]).is_equal("ROOM42")
	assert_str(ActivityRoom.current.instance_id).is_equal("1234")
	assert_int(_calls).is_equal(1)


func test_a_channel_nobody_opened_is_ready_with_nothing_to_show() -> void:
	ActivityRoom.preparer = func() -> Dictionary: return TogetherApi._failed("not_found")
	await _boot(PackedStringArray(["--instance_id=1234"]))
	assert_int(ActivityRoom.current.state).is_equal(ActivityRoom.State.READY)
	assert_dict(ActivityRoom.current.preview).is_empty()


func test_play_together_makes_the_lobby_when_the_channel_has_none() -> void:
	ActivityRoom.preparer = func() -> Dictionary: return TogetherApi._failed("not_found")
	await _boot(PackedStringArray(["--instance_id=1234"]))
	var api := RoomApi.new(self)
	api.preview_answer = TogetherApi._failed("not_found")
	await _together(api)
	assert_int(api.created).is_equal(1)
	var lobby := UIRouter.top() as LobbyScreen
	assert_object(lobby).is_not_null()
	assert_str(lobby.code_label.text).is_equal("NEW123")
	assert_bool(lobby.start_button.is_visible_in_tree()).is_true()


func test_play_together_shows_a_lobby_the_channel_has_as_a_preview_with_join() -> void:
	ActivityRoom.preparer = func() -> Dictionary: return _waiting("ROOM42")
	await _boot(PackedStringArray(["--instance_id=1234"]))
	var api := RoomApi.new(self)
	api.preview_answer = _waiting("ROOM42")
	await _together(api)
	assert_int(api.created).is_equal(0)
	var lobby := UIRouter.top() as LobbyScreen
	assert_object(lobby).is_not_null()
	assert_int(lobby.mode).is_equal(LobbyScreen.Mode.PREVIEW)
	assert_str(lobby.status.text).contains("Waiting room. Ann is hosting")
	assert_bool(lobby.join_button.is_visible_in_tree()).is_true()


func test_coming_back_from_the_lobby_goes_on_to_the_main_menu() -> void:
	ActivityRoom.preparer = func() -> Dictionary: return _waiting("ROOM42")
	await _boot(PackedStringArray(["--instance_id=1234"]))
	var api := RoomApi.new(self)
	api.preview_answer = _waiting("ROOM42")
	await _together(api)
	UIRouter.pop(UITransition.Kind.CUT)
	# The pop shows Together again, which sees it opened the lobby by itself and pops once more.
	for _i in 120:
		if UIRouter.top() is MainMenu:
			break
		await await_idle_frame()
	assert_object(UIRouter.top()).is_instanceof(MainMenu)


func test_a_room_still_being_made_is_waited_for_and_then_used() -> void:
	ActivityRoom.preparer = func() -> Dictionary:
		await gate
		return _waiting("LATE77")
	await _boot(PackedStringArray(["--instance_id=1234"]))
	assert_int(ActivityRoom.current.state).is_equal(ActivityRoom.State.PREPARING)
	var api := RoomApi.new(self)
	api.preview_answer = _waiting("LATE77")
	ActivityRoom.current.api = api
	UIRouter.push(TogetherScreen.SCREEN, UITransition.Kind.CUT)
	await UIRouter.idle
	await await_idle_frame()
	var screen := _find_together()
	assert_str(screen.status.text).is_equal("Getting your night ready...")
	assert_object(UIRouter.top() as LobbyScreen).is_null()
	gate.emit()
	await await_idle_frame()
	await await_idle_frame()
	await UIRouter.idle
	assert_object(UIRouter.top() as LobbyScreen).is_not_null()


func test_a_room_that_failed_is_tried_again_on_each_visit_and_says_why_while_it_fails() -> void:
	ActivityRoom.preparer = func() -> Dictionary:
		_calls += 1
		if _calls <= 2:
			return {"ok": false, "text": "Could not reach the game's servers."}
		return _waiting("BACK99")
	await _boot(PackedStringArray(["--instance_id=1234"]))
	assert_int(ActivityRoom.current.state).is_equal(ActivityRoom.State.FAILED)
	var first := await _together()
	assert_str(first.status.text).is_equal("Could not reach the game's servers.")
	assert_bool(first.quick_button.is_visible_in_tree()).is_true()
	UIRouter.pop(UITransition.Kind.CUT)
	await UIRouter.idle
	# The visit tried again (call 2) and failed again; the next one (call 3) works.
	assert_int(_calls).is_equal(2)
	var api := RoomApi.new(self)
	api.preview_answer = _waiting("BACK99")
	await _together(api)
	assert_int(_calls).is_equal(3)
	assert_object(UIRouter.top() as LobbyScreen).is_not_null()


func test_without_an_instance_id_there_is_no_room_and_the_menu_is_the_menu() -> void:
	await _boot(PackedStringArray())
	assert_object(UIRouter.top()).is_instanceof(MainMenu)
	assert_object(ActivityRoom.current).is_null()
	var screen := await _together()
	assert_bool(screen.quick_button.is_visible_in_tree()).is_true()
