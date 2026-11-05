# The Discord Activity plays the website's Play together (#1178): the same screen with the code
# field and the create button, and no lobby made until the player asks. It used to read the lobby of
# the Activity's instance and make one when there was none, so two players who both pressed Play
# together each got a lobby of their own. Every request goes through `HttpJson.responder`, so a
# lobby made by any path (a screen, the sign-in, the server browser) shows in `_requests`.
extends GdUnitTestSuite

var _main: Node
## Every request the game sent: `{"method", "path", "body"}`.
var _requests: Array[Dictionary] = []
var _made := 0
var _profile_cache := ""


func before_test() -> void:
	_requests = []
	_made = 0
	TogetherApi.forget()
	TogetherScreen.auto_code = ""
	TogetherScreen.name_skipped = false
	HttpJson.responder = _answer
	_profile_cache = Settings.get_value(SettingsService.PROFILE_CACHE)
	Settings.set_value(SettingsService.PROFILE_CACHE, "")
	MenuProfile.save_name("Ann")
	await RouterFixture.clear(get_tree())


func after_test() -> void:
	HttpJson.responder = Callable()
	TogetherApi.activity = false
	TogetherApi.forget()
	if is_instance_valid(_main):
		_main.queue_free()
	await RouterFixture.clear(get_tree())
	Settings.set_value(SettingsService.PROFILE_CACHE, _profile_cache)


## The backend, as the game's requests meet it.
func _answer(method: String, url: String, _headers: Dictionary, body: Variant) -> Dictionary:
	var path := url.trim_prefix(TogetherApi.DEFAULT_BACKEND)
	_requests.append({"method": method, "path": path, "body": body})
	if path == "/auth/guest":
		return {
			"status": 200,
			"json": {"token": "session", "user": {"id": "a", "name": "Ann"}, "guestToken": "kept"}
		}
	if method == "POST" and path == "/lobbies":
		_made += 1
		return {"status": 201, "json": _lobby("MADE%d" % _made)}
	if path.begins_with("/lobbies/l"):
		return {"status": 200, "json": _lobby("MADE%d" % maxi(_made, 1))}
	if method == "POST" and path == "/lobbies/preview":
		return {"status": 200, "json": _preview(str(body.get("code", "")))}
	return {"status": 404, "json": {"error": "not_found"}}


func _lobby(code: String) -> Dictionary:
	var host := {"userId": "a", "name": "Ann", "seat": 1, "host": true, "away": false}
	return {
		"id": "l%d" % _made,
		"code": code,
		"hostId": "a",
		"maxPlayers": 4,
		"state": "open",
		"round": null,
		"players": null,
		"members": [host],
	}


func _preview(code: String) -> Dictionary:
	return {
		"code": code,
		"state": "open",
		"round": null,
		"players": 1,
		"maxPlayers": 4,
		"full": false,
		"hostName": "Ann",
		"names": ["Ann"],
	}


## The lobby calls so far: any request that makes or reads a lobby of the Activity.
func _lobby_calls() -> Array[Dictionary]:
	var calls: Array[Dictionary] = []
	for request in _requests:
		if str(request["path"]).begins_with("/lobbies"):
			calls.append(request)
	return calls


func _boot(args: PackedStringArray) -> void:
	_main = (load("res://main.tscn") as PackedScene).instantiate()
	_main.set("launch_args", args)
	add_child(_main)
	await await_idle_frame()
	await UIRouter.idle
	# The sign-in in the background has answered.
	for _i in 120:
		if TogetherApi.signed_in() or not args.has("--instance_id=1234"):
			break
		await await_idle_frame()
	await await_idle_frame()


func _together() -> TogetherScreen:
	UIRouter.push(TogetherScreen.SCREEN, UITransition.Kind.CUT)
	await UIRouter.idle
	# Long enough for anything `screen_enter` started to ask the backend and show what it got.
	for _i in 30:
		await await_idle_frame()
	return UIRouter.top() as TogetherScreen


func _lobby_on_top() -> LobbyScreen:
	for _i in 300:
		if UIRouter.top() is LobbyScreen and not UIRouter.busy:
			break
		await await_idle_frame()
	await await_idle_frame()
	return UIRouter.top() as LobbyScreen


func _menu_of(screen: TogetherScreen) -> Array[String]:
	var seen: Array[String] = []
	for button: UIButton in [screen.browser_button, screen.create_button, screen.join_button]:
		seen.append("%s:%s" % [button.text, button.is_visible_in_tree()])
	seen.append("code:%s" % screen.code_field.is_visible_in_tree())
	return seen


func test_the_activity_opens_on_the_main_menu_signed_in_and_makes_no_lobby() -> void:
	await _boot(PackedStringArray(["--instance_id=1234"]))
	assert_object(UIRouter.top()).is_instanceof(MainMenu)
	assert_bool(TogetherApi.activity).is_true()
	assert_bool(TogetherApi.signed_in()).is_true()
	assert_str(_requests[0]["path"]).is_equal("/auth/guest")
	assert_array(_lobby_calls()).is_empty()


func test_opening_play_together_in_the_activity_makes_and_reads_no_lobby() -> void:
	await _boot(PackedStringArray(["--instance_id=1234"]))
	var screen := await _together()
	# Still on the screen with its choices: nothing took the player to a lobby.
	assert_object(screen).is_not_null()
	assert_bool(screen.create_button.is_visible_in_tree()).is_true()
	assert_bool(screen.code_field.is_visible_in_tree()).is_true()
	assert_bool(screen.create_button.disabled).is_false()
	assert_str(screen.status.text).is_empty()
	assert_array(_lobby_calls()).is_empty()
	assert_int(_made).is_equal(0)


func test_the_activity_shows_the_same_choices_as_the_website() -> void:
	await _boot(PackedStringArray())
	var website := _menu_of(await _together())
	await RouterFixture.clear(get_tree())
	_main.queue_free()
	await await_idle_frame()
	TogetherApi.forget()
	await _boot(PackedStringArray(["--instance_id=1234"]))
	var activity := _menu_of(await _together())
	assert_array(activity).is_equal(website)
	assert_array(activity).contains(["Create a night:true", "code:true"])


func test_create_in_the_activity_makes_one_lobby_and_sends_no_instance_id() -> void:
	await _boot(PackedStringArray(["--instance_id=1234"]))
	var screen := await _together()
	screen.create_button.pressed.emit()
	var lobby := await _lobby_on_top()
	assert_object(lobby).is_not_null()
	assert_str(lobby.code_label.text).is_equal("MADE1")
	var created: Array[Dictionary] = []
	for request in _lobby_calls():
		if request["method"] == "POST" and request["path"] == "/lobbies":
			created.append(request)
	assert_int(created.size()).is_equal(1)
	assert_dict(created[0]["body"]).is_equal({"maxPlayers": NightHost.MAX_PLAYERS})


func test_a_code_made_in_the_activity_is_joined_by_typing_it() -> void:
	await _boot(PackedStringArray(["--instance_id=1234"]))
	var screen := await _together()
	screen.code_field.text = "ROOM42"
	screen.join_button.pressed.emit()
	var lobby := await _lobby_on_top()
	assert_object(lobby).is_not_null()
	assert_int(lobby.mode).is_equal(LobbyScreen.Mode.PREVIEW)
	assert_str(lobby.code_label.text).is_equal("ROOM42")
	# Looked at by its code, nothing joined or made: the lobby calls are that one read.
	assert_int(_lobby_calls().size()).is_equal(1)
	assert_dict(_lobby_calls()[0]["body"]).is_equal({"code": "ROOM42"})


func test_a_link_opened_in_the_activity_reads_that_night() -> void:
	await _boot(PackedStringArray(["--instance_id=1234", "--room=ROOM42"]))
	for _i in 120:
		if UIRouter.top() is LobbyScreen and not UIRouter.busy:
			break
		await await_idle_frame()
	var lobby := UIRouter.top() as LobbyScreen
	assert_object(lobby).is_not_null()
	assert_str(lobby.code_label.text).is_equal("ROOM42")
	assert_int(_made).is_equal(0)


func test_without_an_instance_id_the_run_is_the_website() -> void:
	await _boot(PackedStringArray())
	assert_object(UIRouter.top()).is_instanceof(MainMenu)
	assert_bool(TogetherApi.activity).is_false()
	assert_array(_requests).is_empty()
