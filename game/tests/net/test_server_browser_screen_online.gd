# The Server Browser over the real platform backend (`spikes/backend`, run by Node with memory
# storage and guest sign-in), Deadnight #1180. The screen is the real one and every player is a
# `TogetherApi` with a session of its own; the only stand-in is the game server, which is a
# heartbeat the test sends (so the backend has a server to put a night on and a people count to
# list).
#
# Covered: the list shows both kinds with the people count that leaves the bots out; one press on
# either kind puts the player in the night; a night that fills, or ends, while the list is open;
# moving from one lobby to another from inside a lobby; and a player pressing Refresh over and over
# never meets the backend's limit (20 asks in 10 seconds for one account).
#
# It needs Node 24 and the backend's packages (`npm ci` in `spikes/backend`); without them the suite
# is skipped with a line saying so.
extends GdUnitTestSuite

const BROWSER := "res://ui/screens/server_browser_screen.tscn"
const LOBBY := "res://ui/screens/lobby_screen.tscn"
const SKIP := "needs node 24 and npm ci in spikes/backend"

var _backend: BackendFixture
var _entered := 0
## Seconds the feed's clock is ahead of the real one: a read the test wants now is not held back by
## the gap.
var _skew := 0.0


func before_test() -> void:
	_entered = 0
	_skew = 0.0
	_backend = BackendFixture.new()
	if BackendFixture.why_not() != "":
		return
	assert_bool(await _backend.start(self)).is_true()
	await _beat()
	ServerBrowserScreen.opener = func() -> void: _entered += 1


func after_test() -> void:
	ServerBrowserScreen.opener = Callable()
	ServerBrowserScreen.api_factory = Callable()
	# A join through the browser fills the map too, which only a night takes.
	RouterFixture.forget_join()
	await RouterFixture.clear(get_tree())
	_backend.stop()
	await get_tree().process_frame
	Audio.stop_all()


# --- The stack ---


## The game server, as the backend sees it: alive, with room for `capacity` nights, running
## `matches` and holding `players` and `rounds` (match id to a number).
func _beat(matches: Array = [], players := {}, rounds := {}) -> void:
	var sent := await (
		HttpJson
		. send(
			self,
			"POST",
			_backend.url + "/internal/servers/heartbeat",
			{"Authorization": "Bearer " + BackendFixture.GAME_SERVER_SECRET},
			{
				"id": "gs-browser",
				"url": "ws://127.0.0.1:1",
				"activityPath": "/gs",
				"capacity": 8,
				"matchIds": matches,
				"players": players,
				"rounds": rounds,
			}
		)
	)
	assert_int(sent["status"]).is_equal(204)


func _guest(player_name: String) -> TogetherApi:
	var api := TogetherApi.new(self, _backend.url)
	api.isolated = true
	api.guest_path = ""
	assert_bool((await api.sign_in(player_name))["ok"]).is_true()
	return api


## A night in progress held by `host`, with `bots` bots.
func _match_of(host: TogetherApi, bots := 0, round_number := 4) -> Dictionary:
	var lobby: Dictionary = (await host.create_lobby())["lobby"]
	var rules := MatchSettings.new()
	rules.bots = bots
	var started := await host.start(lobby, rules)
	assert_bool(started["ok"]).is_true()
	var held: Dictionary = started["lobby"]
	await _beat([held["matchId"]], {held["matchId"]: 1}, {held["matchId"]: round_number})
	return held


func _open(viewer: TogetherApi, from := {}) -> ServerBrowserScreen:
	UIRouter.reset(BROWSER, UITransition.Kind.CUT, {"api": viewer, "lobby": from})
	await UIRouter.idle
	var screen := UIRouter.top() as ServerBrowserScreen
	await _until(
		func() -> bool:
			return screen.feed.state != NightListFeed.State.IDLE and not screen.feed.is_asking()
	)
	await await_idle_frame()
	return screen


func _until(condition: Callable, seconds: float = 20.0) -> bool:
	var began := Time.get_ticks_msec()
	while not await condition.call():
		if (Time.get_ticks_msec() - began) / 1000.0 > seconds:
			return false
		await get_tree().create_timer(0.05).timeout
	return true


## The list the screen reads again now, whatever the feed's clock says.
func _read_again(screen: ServerBrowserScreen) -> void:
	_skew += 100.0
	screen.feed.clock = func() -> float: return Time.get_ticks_msec() / 1000.0 + _skew
	screen.feed.refresh()
	await _until(func() -> bool: return not screen.feed.is_asking())
	await await_idle_frame()


func _lobby_on_top() -> LobbyScreen:
	await _until(func() -> bool: return UIRouter.top() is LobbyScreen and not UIRouter.busy)
	await await_idle_frame()
	return UIRouter.top() as LobbyScreen


func _members_of(api: TogetherApi, lobby: Dictionary) -> Array:
	var seen := await api.refresh(lobby)
	if not seen["ok"]:
		return []
	var names: Array = []
	for member: Dictionary in seen["lobby"]["members"]:
		names.append(str(member["name"]))
	return names


# --- The list ---


func test_the_real_list_shows_a_waiting_lobby_and_a_night_in_progress_with_people_only(
	_do_skip := BackendFixture.why_not() != "", _skip_reason := SKIP
) -> void:
	var ann := await _guest("Ann")
	var bo := await _guest("Bo")
	var cy := await _guest("Cy")
	var running := await _match_of(ann, 3, 6)
	var waiting: Dictionary = (await bo.create_lobby())["lobby"]
	var screen := await _open(cy)
	assert_int(screen.rows().size()).is_equal(2)
	var match_row := screen.row_of(str(running["code"]))
	var lobby_row := screen.row_of(str(waiting["code"]))
	assert_bool(match_row.entry.is_match()).is_true()
	assert_bool(lobby_row.entry.is_match()).is_false()
	assert_str(match_row.chip_text()).is_equal("IN PROGRESS  ROUND 6")
	assert_str(lobby_row.chip_text()).is_equal("WAITING")
	# Ann is the one person in her night; her three bots are a note, not people.
	assert_str(match_row.entry.people_text()).is_equal("1 of 8")
	assert_str(match_row.entry.bots_text()).is_equal("+3 bots")
	assert_str(lobby_row.entry.people_text()).is_equal("1 of 8")
	assert_str(screen.status.text).contains("1 waiting to start")
	assert_str(screen.status.text).contains("1 in progress")


func test_an_empty_backend_says_so_and_a_private_night_is_not_listed(
	_do_skip := BackendFixture.why_not() != "", _skip_reason := SKIP
) -> void:
	var ann := await _guest("Ann")
	var cy := await _guest("Cy")
	var empty := await _open(cy)
	assert_str(empty.status.text).is_equal(ServerBrowserScreen.EMPTY)
	var lobby: Dictionary = (await ann.create_lobby())["lobby"]
	assert_bool((await ann.set_visibility(lobby, false))["ok"]).is_true()
	await _read_again(empty)
	assert_int(empty.rows().size()).is_equal(0)
	assert_bool((await ann.set_visibility(lobby, true))["ok"]).is_true()
	await _read_again(empty)
	assert_int(empty.rows().size()).is_equal(1)


# --- A press ---


func test_one_press_on_a_waiting_lobby_and_one_on_a_night_in_progress_put_the_player_in_them(
	_do_skip := BackendFixture.why_not() != "", _skip_reason := SKIP
) -> void:
	var ann := await _guest("Ann")
	var bo := await _guest("Bo")
	var cy := await _guest("Cy")
	var dee := await _guest("Dee")
	var running := await _match_of(ann)
	var waiting: Dictionary = (await bo.create_lobby())["lobby"]
	# Cy presses the waiting lobby: its lobby screen, and the backend has Cy in it.
	var screen := await _open(cy)
	screen.row_of(str(waiting["code"])).pressed.emit()
	var lobby := await _lobby_on_top()
	assert_str(lobby.code_label.text).is_equal(str(waiting["code"]))
	assert_array(await _members_of(bo, waiting)).contains_exactly(["Bo", "Cy"])
	# Dee presses the night in progress: a ticket, and the night; the backend has Dee in it.
	var other := await _open(dee)
	other.row_of(str(running["code"])).pressed.emit()
	await _until(func() -> bool: return _entered > 0)
	assert_int(_entered).is_equal(1)
	assert_str(NightScreen.join_ticket).is_not_empty()
	assert_array(await _members_of(ann, running)).contains_exactly(["Ann", "Dee"])


# --- While it is open ---


func test_a_night_that_fills_while_the_list_is_open_is_full_on_the_next_read_and_refused_before_it(
	_do_skip := BackendFixture.why_not() != "", _skip_reason := SKIP
) -> void:
	var ann := await _guest("Ann")
	var cy := await _guest("Cy")
	var running := await _match_of(ann)
	var screen := await _open(cy)
	var row := screen.row_of(str(running["code"]))
	assert_bool(row.entry.full).is_false()
	# The game server says the night holds eight people: Cy's list is a few seconds old and still
	# shows room.
	await _beat([running["matchId"]], {running["matchId"]: 8}, {running["matchId"]: 4})
	row.pressed.emit()
	await _until(func() -> bool: return screen.note.text != "" and not screen.is_busy())
	assert_str(screen.note.text).is_equal(TogetherApi.TEXTS["full"])
	assert_int(UIRouter.depth()).is_equal(1)
	assert_array(await _members_of(ann, running)).contains_exactly(["Ann"])
	# And the next read shows it full, greyed, last.
	await _read_again(screen)
	assert_bool(screen.row_of(str(running["code"])).entry.full).is_true()
	assert_str(screen.row_of(str(running["code"])).chip_text()).is_equal("FULL")


func test_a_night_that_ends_while_the_list_is_open_says_so_and_leaves_the_list(
	_do_skip := BackendFixture.why_not() != "", _skip_reason := SKIP
) -> void:
	var bo := await _guest("Bo")
	var cy := await _guest("Cy")
	var waiting: Dictionary = (await bo.create_lobby())["lobby"]
	var other: Dictionary = (await (await _guest("Di")).create_lobby())["lobby"]
	var screen := await _open(cy)
	assert_int(screen.rows().size()).is_equal(2)
	# Bo leaves: his lobby is gone at once. Cy's row for it is stale until the next read.
	assert_bool((await bo.leave(waiting))["ok"]).is_true()
	screen.row_of(str(waiting["code"])).pressed.emit()
	await _until(func() -> bool: return screen.note.text == ServerBrowserScreen.GONE)
	assert_str(screen.note.text).is_equal(ServerBrowserScreen.GONE)
	assert_bool(screen.is_busy()).is_false()
	assert_int(UIRouter.depth()).is_equal(1)
	await _until(func() -> bool: return screen.rows().size() == 1)
	assert_str(screen.rows()[0].entry.code).is_equal(str(other["code"]))


func test_pressing_refresh_over_and_over_never_meets_the_backends_limit(
	_do_skip := BackendFixture.why_not() != "", _skip_reason := SKIP
) -> void:
	var cy := await _guest("Cy")
	await (await _guest("Bo")).create_lobby()
	# The limit is real: 25 asks in a row from one account meet a 429 with its Retry-After.
	var hammer := await _guest("Hammer")
	var refused := {}
	for _i in 25:
		var answer := await hammer.list_nights()
		if not answer["ok"]:
			refused = answer
			break
	assert_str(str(refused.get("error", ""))).is_equal("too_many_requests")
	assert_float(float(refused.get("retry_after", 0.0))).is_equal(10.0)
	# The screen's feed is held under it, whoever asks and however often.
	var screen := await _open(cy)
	var failures := [0]
	screen.feed.failed.connect(func(_t: String, _r: String) -> void: failures[0] += 1)
	var waits := [0]
	screen.feed.waiting.connect(func(_s: float) -> void: waits[0] += 1)
	for _i in 120:
		screen.refresh_button.pressed.emit()
		screen.feed.refresh()
		await get_tree().create_timer(0.02).timeout
	assert_int(screen.feed.asks_in_window()).is_less_equal(NightListFeed.BUDGET)
	assert_int(failures[0]).is_equal(0)
	assert_int(waits[0]).is_equal(0)
	# The same account still gets its answer straight from the backend: it was never limited.
	var direct := await cy.list_nights()
	assert_bool(direct["ok"]).is_true()


# --- Moving ---


func test_from_inside_a_lobby_one_press_moves_the_player_to_another_night_with_no_error(
	_do_skip := BackendFixture.why_not() != "", _skip_reason := SKIP
) -> void:
	var bo := await _guest("Bo")
	var cy := await _guest("Cy")
	var theirs: Dictionary = (await bo.create_lobby())["lobby"]
	var mine: Dictionary = (await cy.create_lobby())["lobby"]
	# Cy is in a waiting lobby of his own, on its screen, and opens the browser from it.
	UIRouter.reset(LOBBY, UITransition.Kind.CUT, {"api": cy, "lobby": mine})
	await UIRouter.idle
	var lobby := UIRouter.top() as LobbyScreen
	lobby.browse_button.pressed.emit()
	await UIRouter.idle
	var screen := UIRouter.top() as ServerBrowserScreen
	await _until(func() -> bool: return screen.row_of(str(theirs["code"])) != null)
	screen.row_of(str(theirs["code"])).pressed.emit()
	var next := await _lobby_on_top()
	assert_str(next.code_label.text).is_equal(str(theirs["code"]))
	assert_array(await _members_of(bo, theirs)).contains_exactly(["Bo", "Cy"])
	# Cy's old lobby had no one else in it: it is gone, and Cy is in one lobby only.
	assert_bool((await cy.refresh(mine))["ok"]).is_false()
	assert_bool(is_instance_valid(lobby) and not lobby.is_queued_for_deletion()).is_false()


func test_from_a_night_in_progress_back_to_the_list_and_on_to_another_night(
	_do_skip := BackendFixture.why_not() != "", _skip_reason := SKIP
) -> void:
	var ann := await _guest("Ann")
	var bo := await _guest("Bo")
	var cy := await _guest("Cy")
	var first := await _match_of(ann)
	var second: Dictionary = (await bo.create_lobby())["lobby"]
	var screen := await _open(cy)
	screen.row_of(str(first["code"])).pressed.emit()
	await _until(func() -> bool: return _entered > 0)
	# The night screen's Leave: say so to the backend, then the list shows again.
	assert_bool((await cy.leave(NightScreen.return_lobby))["ok"]).is_true()
	screen.screen_resume()
	await _until(
		func() -> bool:
			return not screen.feed.is_asking() and screen.row_of(str(second["code"])) != null
	)
	screen.row_of(str(second["code"])).pressed.emit()
	var lobby := await _lobby_on_top()
	assert_str(lobby.code_label.text).is_equal(str(second["code"]))
	assert_array(await _members_of(ann, first)).contains_exactly(["Ann"])
	assert_array(await _members_of(bo, second)).contains_exactly(["Bo", "Cy"])
