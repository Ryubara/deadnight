# A player alone on the waiting room closes the tab (Deadnight #1188), over the real backend
# (`spikes/backend`, run by Node on a free port) and the real lobby screen: the screen holds the
# page's last word ready (`PageClosing`) while the player is in a waiting lobby, the request it
# holds is the one a browser's `sendBeacon` sends (`text/plain`, no `Authorization` header, the
# token in the body) and it ends the lobby at once; it holds nothing in a preview, in a night that
# has started, or after the lobby ended, and a screen that is going never takes back the word of
# the one that replaced it.
#
# It needs Node 24 and the backend's packages (`npm ci` in `spikes/backend`); without them the
# suite is skipped with a line saying so.
extends GdUnitTestSuite

const SKIP := "needs node 24 and npm ci in spikes/backend"
const LOBBY := "res://ui/screens/lobby_screen.tscn"

var _backend := BackendFixture.new()


func before_test() -> void:
	await RouterFixture.clear(get_tree())
	PageClosing.armed = {}
	PageClosing.armed_for = ""
	if BackendFixture.why_not() != "":
		return
	assert_bool(await _backend.start(self)).is_true()


func after_test() -> void:
	await RouterFixture.clear(get_tree())
	_backend.stop()
	PageClosing.eval_js = Callable()
	await get_tree().process_frame
	Audio.stop_all()


func after() -> void:
	await Audio.wait_for_mixer()


func _guest(player_name: String) -> TogetherApi:
	var api := TogetherApi.new(self, _backend.url)
	api.isolated = true
	var signed := await api.sign_in(player_name)
	assert_bool(signed["ok"]).is_true()
	return api


func _open(lobby: Dictionary, api: TogetherApi) -> LobbyScreen:
	UIRouter.reset(LOBBY, UITransition.Kind.CUT, {"api": api, "lobby": lobby})
	await UIRouter.idle
	await get_tree().process_frame
	return UIRouter.top() as LobbyScreen


func _listed(api: TogetherApi, code: String) -> bool:
	var listed := await api.list_nights()
	assert_bool(listed["ok"]).is_true()
	for row: Dictionary in listed["nights"]:
		if row["code"] == code:
			return true
	return false


## What a browser's `navigator.sendBeacon(url, body)` sends: a POST of the body as
## `text/plain`, with
## no `Authorization` header and no preflight. Returns the HTTP status.
func _beacon(request: Dictionary) -> int:
	var http := HTTPRequest.new()
	add_child(http)
	var started := http.request(
		str(request["url"]),
		PackedStringArray(["Content-Type: text/plain;charset=UTF-8"]),
		HTTPClient.METHOD_POST,
		str(request["body"])
	)
	assert_int(started).is_equal(OK)
	var answer: Array = await http.request_completed
	http.queue_free()
	return int(answer[1])


func test_a_sole_player_who_closes_the_tab_on_the_waiting_room_ends_the_lobby_at_once(
	_do_skip := BackendFixture.why_not() != "", _skip_reason := SKIP
) -> void:
	var host := await _guest("Ann")
	var looker := await _guest("Looker")
	var made := await host.create_lobby()
	assert_bool(made["ok"]).is_true()
	var lobby: Dictionary = made["lobby"]
	var screen := await _open(lobby, host)

	# The word is ready for this lobby, addressed to the backend's route, with Ann's session in
	# the body.
	assert_str(PageClosing.armed_for).is_equal(str(lobby["id"]))
	var request: Dictionary = PageClosing.armed
	assert_str(str(request["url"])).is_equal(
		"%s/lobbies/%s/page-closed" % [_backend.url, lobby["id"]]
	)
	assert_bool(JSON.parse_string(str(request["body"])).has("token")).is_true()
	assert_bool(await _listed(looker, str(lobby["code"]))).is_true()

	# The tab closes: the browser sends it, and the lobby is gone from the list, its code and its poll.
	assert_int(await _beacon(request)).is_equal(200)
	assert_bool(await _listed(looker, str(lobby["code"]))).is_false()
	assert_str(str((await looker.join_code(str(lobby["code"])))["error"])).is_equal("not_found")
	var read := await host.refresh(lobby)
	assert_str(str(read["error"])).is_equal("not_found")
	screen = null


func test_the_word_is_held_only_while_the_player_is_in_a_waiting_lobby(
	_do_skip := BackendFixture.why_not() != "", _skip_reason := SKIP
) -> void:
	var host := await _guest("Ann")
	var made := await host.create_lobby()
	var lobby: Dictionary = made["lobby"]

	# A preview joins nobody, so the page has nothing to say.
	UIRouter.reset(LOBBY, UITransition.Kind.CUT, {"api": host, "preview": {"code": lobby["code"]}})
	await UIRouter.idle
	await get_tree().process_frame
	assert_bool(PageClosing.armed.is_empty()).is_true()

	var screen := await _open(lobby, host)
	assert_bool(PageClosing.armed.is_empty()).is_false()

	# The night starts: the socket to the game server speaks for the player from here, not the page.
	var started := lobby.duplicate()
	started["state"] = "started"
	screen._on_changed(started)
	assert_bool(PageClosing.armed.is_empty()).is_true()

	# Back to waiting (a finished night reopens the lobby): the word is ready again; the lobby
	# ending takes it back.
	screen._on_changed(lobby)
	assert_bool(PageClosing.armed.is_empty()).is_false()
	screen._on_ended("")
	assert_bool(PageClosing.armed.is_empty()).is_true()


func test_a_screen_that_is_going_does_not_take_back_the_word_of_the_one_that_replaced_it(
	_do_skip := BackendFixture.why_not() != "", _skip_reason := SKIP
) -> void:
	var host := await _guest("Ann")
	var first: Dictionary = (await host.create_lobby())["lobby"]
	var old_screen := await _open(first, host)
	var second: Dictionary = (await host.create_lobby())["lobby"]
	# The next lobby's screen is up before the old one is freed (the router frees it after the
	# new one is in).
	UIRouter.push(LOBBY, UITransition.Kind.CUT, {"api": host, "lobby": second})
	await UIRouter.idle
	await get_tree().process_frame
	assert_str(PageClosing.armed_for).is_equal(str(second["id"]))
	old_screen.free()
	assert_str(PageClosing.armed_for).is_equal(str(second["id"]))
	assert_bool(PageClosing.armed.is_empty()).is_false()


func test_a_row_of_the_server_browser_whose_tab_just_closed_says_so_in_words_and_leaves_the_list(
	_do_skip := BackendFixture.why_not() != "", _skip_reason := SKIP
) -> void:
	var host := await _guest("Ann")
	var other := await _guest("Di")
	var viewer := await _guest("Cy")
	var made: Dictionary = (await host.create_lobby())["lobby"]
	var kept: Dictionary = (await other.create_lobby())["lobby"]
	var lobby_screen := await _open(made, host)
	var request: Dictionary = PageClosing.armed
	assert_bool(request.is_empty()).is_false()

	# Cy's list shows both nights.
	UIRouter.reset(
		"res://ui/screens/server_browser_screen.tscn",
		UITransition.Kind.CUT,
		{"api": viewer, "lobby": {}}
	)
	await UIRouter.idle
	var screen := UIRouter.top() as ServerBrowserScreen
	await _until(
		func() -> bool:
			return screen.feed.state == NightListFeed.State.LOADED and screen.rows().size() == 2
	)
	assert_int(screen.rows().size()).is_equal(2)

	# Ann's tab closes: her lobby is gone at once. Cy's row for it is stale until the next read, and
	# a press on it says the night has ended (words, not an error) and reads the list again.
	assert_int(await _beacon(request)).is_equal(200)
	var row := screen.row_of(str(made["code"]))
	assert_object(row).is_not_null()
	row.pressed.emit()
	await _until(func() -> bool: return screen.note.text == ServerBrowserScreen.GONE)
	assert_str(screen.note.text).is_equal(ServerBrowserScreen.GONE)
	assert_bool(screen.is_busy()).is_false()
	assert_int(UIRouter.depth()).is_equal(1)
	await _until(func() -> bool: return screen.rows().size() == 1)
	assert_str(screen.rows()[0].entry.code).is_equal(str(kept["code"]))
	assert_object(screen.row_of(str(made["code"]))).is_null()
	lobby_screen = null


func _until(condition: Callable, seconds: float = 20.0) -> bool:
	var began := Time.get_ticks_msec()
	while not await condition.call():
		if (Time.get_ticks_msec() - began) / 1000.0 > seconds:
			return false
		await get_tree().create_timer(0.05).timeout
	return true
