# What a lobby screen is told as the backend's answers change: who joined or left, the host role
# moving, the night starting, the round, and the ends (dropped for being away, the lobby gone).
extends GdUnitTestSuite


## A backend that answers from a list: no network.
class FakeApi:
	extends TogetherApi
	var answers: Array[Dictionary] = []
	var asked := 0

	func refresh(_lobby: Dictionary) -> Dictionary:
		asked += 1
		return answers.pop_front() if not answers.is_empty() else TogetherApi._failed("network")


func _member(id: String, member_name: String, seat: int, host := false) -> Dictionary:
	return {"userId": id, "name": member_name, "seat": seat, "host": host, "away": false}


func _lobby(members: Array, state := "open", round_number: Variant = null) -> Dictionary:
	return {
		"id": "l1",
		"code": "ABC234",
		"hostId": members[0]["userId"],
		"maxPlayers": 4,
		"members": members,
		"state": state,
		"round": round_number,
		"players": null,
	}


func _kinds(events: Array[Dictionary]) -> Array:
	var out := []
	for event in events:
		out.append("%s:%s" % [event["kind"], event.get("name", "")])
	return out


func _watch(api: FakeApi, first: Dictionary, me := "a") -> LobbyWatch:
	var watch := LobbyWatch.new()
	add_child(watch)
	watch.every = 3600.0
	watch.watch(api, first, me)
	return auto_free(watch)


func test_a_friend_who_takes_a_seat_and_one_who_leaves_are_told_by_name() -> void:
	var ann := _member("a", "Ann", 1, true)
	var bo := _member("b", "Bo", 2)
	var alone := _lobby([ann])
	var two := _lobby([ann, bo])
	assert_array(_kinds(LobbyWatch.diff(alone, two, "a"))).is_equal(["joined:Bo"])
	assert_array(_kinds(LobbyWatch.diff(two, alone, "a"))).is_equal(["left:Bo"])
	assert_array(LobbyWatch.diff(two, two, "a")).is_empty()
	# The player's own seat is marked, so the screen does not announce "You joined".
	assert_bool(LobbyWatch.diff(alone, two, "b")[0]["you"]).is_true()


func test_the_host_leaving_passes_the_role_and_the_new_host_is_told() -> void:
	var ann := _member("a", "Ann", 1, true)
	var bo := _member("b", "Bo", 2)
	var cy := _member("c", "Cy", 3)
	var before := _lobby([ann, bo, cy])
	var after := _lobby([bo, cy])
	after["hostId"] = "b"
	var events := LobbyWatch.diff(before, after, "b")
	assert_array(_kinds(events)).is_equal(["left:Ann", "host:Bo"])
	assert_bool(events[1]["you"]).is_true()
	# Cy sees the same change as news about Bo, not about themselves.
	assert_bool(LobbyWatch.diff(before, after, "c")[1]["you"]).is_false()


func test_the_start_and_the_round_are_news_and_an_empty_start_is_not() -> void:
	var ann := _member("a", "Ann", 1, true)
	var open := _lobby([ann])
	var started := _lobby([ann], "started", 0)
	assert_array(_kinds(LobbyWatch.diff(open, started, "b"))).contains(["started:Ann"])
	var later := _lobby([ann], "started", 3)
	var events := LobbyWatch.diff(started, later, "b")
	assert_int(events.size()).is_equal(1)
	assert_int(events[0]["round"]).is_equal(3)
	# No earlier answer, nothing to compare.
	assert_array(LobbyWatch.diff({}, started, "b")).is_empty()


func test_a_poll_with_news_says_changed_and_what_happened_and_a_quiet_one_says_nothing() -> void:
	var ann := _member("a", "Ann", 1, true)
	var bo := _member("b", "Bo", 2)
	var api := FakeApi.new(self)
	var watch := _watch(api, _lobby([ann]))
	var told := []
	watch.happened.connect(func(events: Array) -> void: told.append_array(events))
	var moved := [0]
	watch.changed.connect(func(_held: Dictionary) -> void: moved[0] += 1)
	api.answers = [
		{"ok": true, "lobby": _lobby([ann, bo])}, {"ok": true, "lobby": _lobby([ann, bo])}
	]
	await watch.poll()
	assert_int(moved[0]).is_equal(1)
	assert_array(told.map(func(e: Dictionary) -> String: return e["kind"])).is_equal(["joined"])
	assert_int(watch.lobby["members"].size()).is_equal(2)
	await watch.poll()
	assert_int(moved[0]).is_equal(1)
	assert_int(told.size()).is_equal(1)


func test_a_member_who_is_marked_away_redraws_the_seats_without_an_event() -> void:
	var ann := _member("a", "Ann", 1, true)
	var bo := _member("b", "Bo", 2)
	var api := FakeApi.new(self)
	var watch := _watch(api, _lobby([ann, bo]), "a")
	var away := bo.duplicate()
	away["away"] = true
	var moved := [0]
	var told := []
	watch.changed.connect(func(_held: Dictionary) -> void: moved[0] += 1)
	watch.happened.connect(func(events: Array) -> void: told.append_array(events))
	api.answers = [{"ok": true, "lobby": _lobby([ann, away])}]
	await watch.poll()
	assert_int(moved[0]).is_equal(1)
	assert_array(told).is_empty()


func test_being_dropped_or_a_lobby_that_ended_stops_the_watch_with_words_to_show() -> void:
	for reason in ["not_member", "not_found"]:
		var api := FakeApi.new(self)
		var watch := _watch(api, _lobby([_member("a", "Ann", 1, true)]))
		var said := [""]
		watch.ended.connect(func(text: String) -> void: said[0] = text)
		api.answers = [TogetherApi._failed(reason)]
		await watch.poll()
		assert_str(said[0]).is_equal(TogetherApi.TEXTS[reason])
		assert_bool(watch.running).is_false()
		# Stopped is stopped: no further question goes out.
		await watch.poll()
		assert_int(api.asked).is_equal(1)


func test_a_backend_out_of_reach_is_said_once_after_three_misses_and_again_when_back() -> void:
	var ann := _member("a", "Ann", 1, true)
	var api := FakeApi.new(self)
	var watch := _watch(api, _lobby([ann]))
	var said := []
	watch.trouble.connect(func() -> void: said.append("trouble"))
	watch.recovered.connect(func() -> void: said.append("recovered"))
	for _i in 5:
		await watch.poll()
	assert_array(said).is_equal(["trouble"])
	assert_bool(watch.running).is_true()
	api.answers = [{"ok": true, "lobby": _lobby([ann])}]
	await watch.poll()
	assert_array(said).is_equal(["trouble", "recovered"])
