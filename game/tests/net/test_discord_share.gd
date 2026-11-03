# What Discord answered to "Share in Discord" (#627): the sentence and the probe line for each
# answer the bridge can report, and the lobby showing them. The hint to pick who to send it to is
# shown only while Discord has not refused; a refusal says so and points to Copy the code.
extends GdUnitTestSuite

const CODE := "ABC234"


func after_test() -> void:
	DiscordShare.eval_js = Callable()


func _state(verdict: String, extra: Dictionary = {}) -> Dictionary:
	return (
		{
			"verdict": verdict,
			"ms": 0,
			"success": null,
			"didCopyLink": null,
			"didSendMessage": null,
			"kind": "",
			"code": "",
			"detail": "",
			"invite": "",
			"inviteDetail": ""
		}
		. merged(extra, true)
	)


func test_the_hint_is_shown_only_while_discord_has_not_refused_and_a_window_may_be_up() -> void:
	assert_str(DiscordShare.says(_state("open"), CODE)).is_equal(DiscordShare.HINT)
	for verdict in ["idle", "asking", "shared", "closed", "refused", "unreadable"]:
		var text := DiscordShare.says(_state(verdict, {"didSendMessage": true}), CODE)
		assert_str(text).not_contains(DiscordShare.HINT)


func test_a_refusal_says_discord_opened_nothing_and_points_to_copy_the_code() -> void:
	var text := DiscordShare.says(_state("refused"), CODE)
	assert_str(text).contains("did not open")
	assert_str(text).contains("Copy the code")


func test_a_refusal_with_the_invite_window_open_says_to_send_the_code_by_hand() -> void:
	var text := DiscordShare.says(_state("refused", {"invite": "opened"}), CODE)
	assert_str(text).contains("invite window opened")
	assert_str(text).contains(CODE)


func test_a_window_closed_without_sending_is_not_called_sent() -> void:
	var text := DiscordShare.says(_state("closed", {"success": false}), CODE)
	assert_str(text).contains("closed without sending")
	assert_str(text).not_contains("Sent")


func test_a_share_that_went_out_says_sent() -> void:
	var sent := DiscordShare.says(_state("shared", {"success": true, "didSendMessage": true}), CODE)
	assert_str(sent).is_equal("Sent through Discord.")
	var copied := DiscordShare.says(_state("shared", {"success": true, "didCopyLink": true}), CODE)
	assert_str(copied).contains("copied the link")


func test_the_probe_line_has_discords_own_answer_and_error() -> void:
	var line := DiscordShare.line(
		_state(
			"refused",
			{
				"ms": 38,
				"kind": "rpc",
				"code": "4002",
				"detail": "Invalid command",
				"invite": "failed",
				"inviteDetail": "4002 no"
			}
		)
	)
	assert_str(line).contains("refused after 38 ms")
	assert_str(line).contains("error rpc 4002: Invalid command")
	assert_str(line).contains("invite window: failed (4002 no)")
	var answered := DiscordShare.line(
		_state(
			"closed", {"ms": 2100, "success": false, "didCopyLink": false, "didSendMessage": false}
		)
	)
	assert_str(answered).contains("answer success=false copied=false sent=false")
	var unread := DiscordShare.line(
		_state("unreadable", {"raw": '{"evt":null,"data":{"success":true}}'})
	)
	assert_str(unread).contains("Discord's frame: {")
	assert_str(DiscordShare.line(_state("idle"))).is_empty()


func test_reading_stops_once_the_answer_and_the_invite_window_are_final() -> void:
	assert_bool(DiscordShare.settled(_state("asking"))).is_false()
	assert_bool(DiscordShare.settled(_state("open"))).is_false()
	assert_bool(DiscordShare.settled(_state("refused", {"invite": "asking"}))).is_false()
	assert_bool(DiscordShare.settled(_state("refused", {"invite": "opened"}))).is_true()
	assert_bool(DiscordShare.settled(_state("shared"))).is_true()


func test_off_the_web_nothing_is_asked_and_nothing_is_read() -> void:
	assert_bool(DiscordShare.ask("hi", CODE)).is_false()
	assert_dict(DiscordShare.read()).is_empty()


func _lobby(page: Array) -> LobbyScreen:
	var api := LobbyFixture.FakeApi.new(self)
	api.lobby = LobbyFixture.lobby([LobbyFixture.member("a", "Ann", 1, true)])
	await RouterFixture.clear(get_tree())
	var screen := (load(LobbyScreen.SCREEN) as PackedScene).instantiate() as LobbyScreen
	screen.params = {"api": api, "lobby": api.lobby}
	add_child(screen)
	screen.watch.every = 3600.0
	await screen.screen_enter()
	# The page: `page[0]` is what the bridge reports now, every JS call is kept in `page[1]`.
	DiscordShare.eval_js = func(js: String) -> Variant:
		page[1].append(js)
		return JSON.stringify(page[0]) if js.contains("shareJson") else null
	return screen


func test_the_lobby_asks_with_the_code_and_shows_no_hint_until_discord_has_not_refused() -> void:
	var page := [_state("asking"), []]
	var screen := await _lobby(page)
	screen.share_button.pressed.emit()
	assert_str(page[1][0]).contains("deadnightDiscord.share(").contains(CODE)
	assert_str(screen.share_says.text).is_equal("Asking Discord...")
	assert_str(screen.note.text).not_contains(DiscordShare.HINT)
	page[0] = _state("open", {"ms": 1200})
	await get_tree().create_timer(0.5).timeout
	assert_str(screen.share_says.text).is_equal(DiscordShare.HINT)
	assert_str(screen.share_probe.text).contains("open after 1200 ms")
	screen.free()


func test_the_lobby_says_so_when_discord_refuses_and_shows_the_error() -> void:
	var page := [_state("asking"), []]
	var screen := await _lobby(page)
	screen.share_button.pressed.emit()
	page[0] = _state(
		"refused", {"ms": 12, "kind": "rpc", "code": "4002", "detail": "Invalid command"}
	)
	await get_tree().create_timer(0.5).timeout
	assert_str(screen.share_says.text).contains("did not open").contains("Copy the code")
	assert_str(screen.share_says.text).not_contains(DiscordShare.HINT)
	assert_str(screen.share_probe.text).contains("error rpc 4002: Invalid command")
	screen.free()


func test_what_discord_answered_is_scrolled_into_view_in_a_short_window() -> void:
	var api := LobbyFixture.FakeApi.new(self)
	api.lobby = (
		LobbyFixture
		. lobby(
			[
				LobbyFixture.member("a", "Ann", 1, true),
				LobbyFixture.member("b", "Bo", 2),
				LobbyFixture.member("c", "Cy", 3),
				LobbyFixture.member("d", "Di", 4),
			]
		)
	)
	await RouterFixture.clear(get_tree())
	var window := auto_free(SubViewport.new()) as SubViewport
	window.size = Vector2i(1280, 720)
	add_child(window)
	var screen := (load(LobbyScreen.SCREEN) as PackedScene).instantiate() as LobbyScreen
	screen.params = {"lobby": api.lobby, "api": api}
	window.add_child(screen)
	screen.watch.every = 3600.0
	await screen.screen_enter()
	var page := [_state("refused", {"ms": 12, "kind": "rpc", "code": "4002", "detail": "x"}), []]
	DiscordShare.eval_js = func(_js: String) -> Variant: return JSON.stringify(page[0])
	screen.share_button.pressed.emit()
	for _i in 4:
		await get_tree().process_frame
	var visible_rect := screen._scroll.get_global_rect()
	var label_rect := screen.share_probe.get_global_rect()
	assert_bool(screen.share_probe.is_visible_in_tree()).is_true()
	assert_float(label_rect.end.y).is_less_equal(visible_rect.end.y + 1.0)
	assert_float(label_rect.position.y).is_greater_equal(visible_rect.position.y - 1.0)
	screen.free()
