extends GdUnitTestSuite
## What the web probe publishes, without a browser: a plain function of the top screen.

const PLAY := "res://ui/screens/play_screen.tscn"


func test_no_screen_reads_as_none() -> void:
	var data := WebProbe.snapshot(null)
	assert_str(data["screen"]).is_equal("none")
	assert_bool(data["night"]).is_false()


func test_a_screen_is_named_by_its_scene() -> void:
	var menu := auto_free(Control.new()) as Control
	menu.scene_file_path = "res://ui/screens/main_menu.tscn"
	var data := WebProbe.snapshot(menu)
	assert_str(data["screen"]).is_equal("main_menu")
	assert_bool(data["night"]).is_false()


func test_a_night_screen_before_its_night_starts_reads_as_no_night() -> void:
	var screen := auto_free(NightScreen.new()) as NightScreen
	assert_bool(WebProbe.snapshot(screen)["night"]).is_false()


func test_a_running_night_reports_round_and_zombies() -> void:
	var screen := auto_free(NightScreen.new()) as NightScreen
	screen.night = auto_free(Night.new()) as Night
	screen.night.state = ClientState.new()
	screen.night.running = true
	screen.night.state.frame = {"round": 3, "remaining": 17}
	screen.night.state.zombies = [{}, {}, {}] as Array[Dictionary]
	var data := WebProbe.snapshot(screen)
	assert_bool(data["night"]).is_true()
	assert_bool(data["running"]).is_true()
	assert_int(data["round"]).is_equal(3)
	assert_int(data["remaining"]).is_equal(17)
	assert_int(data["alive"]).is_equal(3)
	assert_bool(data["touch"]).is_false()
	assert_bool(data["interpolated"]).is_false()
	# A screen that has not built its HUD has no reticle on show.
	assert_bool(data["reticle"]).is_false()


func test_an_online_night_reports_the_players_and_the_round_trip() -> void:
	var screen := auto_free(NightScreen.new()) as NightScreen
	screen.night = auto_free(Night.new()) as Night
	screen.night.state = ClientState.new()
	screen.night.state.player_id = 2
	screen.night.state.frame = {"round": 1, "players": {1: {}, 2: {}, 3: {}}}
	var link := WebSocketLink.new()
	link.rtt_ms = 81.0
	screen.night.link = link
	var data := WebProbe.snapshot(screen)
	assert_int(data["players"]).is_equal(3)
	assert_int(data["player_id"]).is_equal(2)
	assert_float(data["rtt_ms"]).is_equal(81.0)


func test_the_probe_names_the_control_that_has_the_keyboard() -> void:
	var screen := auto_free(Control.new()) as Control
	screen.scene_file_path = "res://ui/screens/lobby_screen.tscn"
	add_child(screen)
	var button := Button.new()
	button.name = "CopyCode"
	screen.add_child(button)
	button.grab_focus()
	assert_str(WebProbe.snapshot(screen)["focus"]).is_equal("CopyCode")
	button.release_focus()
	assert_str(WebProbe.snapshot(screen)["focus"]).is_equal("")


func _play_screen() -> PlayScreen:
	var screen := (load(PLAY) as PackedScene).instantiate() as PlayScreen
	add_child(screen)
	await get_tree().process_frame
	await get_tree().process_frame
	return screen


## A browser smoke walks the Play screen by these names (#743): a control added to the screen
## leaves the names of the others as they are.
func test_the_play_screen_controls_are_named_by_their_setting_for_the_smokes() -> void:
	var screen := await _play_screen()
	var panel := screen.panel
	var wanted := {
		"count_multiplier": panel.count_selector,
		"max_alive": panel.alive_slider,
		"break_seconds": panel.break_slider,
		"bots": panel.bots_selector,
		"bot_skill": panel.skill_selector,
		"Start": screen.start_button,
		"Reset": screen.reset_button,
		"Back": screen.back_button,
	}
	for name: String in wanted:
		(wanted[name] as Control).grab_focus()
		assert_str(WebProbe.snapshot(screen)["focus"]).is_equal(name)
	for card in panel.map_picker.cards:
		card.grab_focus()
		assert_str(WebProbe.snapshot(screen)["focus"]).is_equal(card.info.id)
	screen.queue_free()


## The bot count and the bot skill share a row; a smoke taps each selector's arrow by its own name.
func test_the_play_screen_spots_the_bot_count_and_the_skill_apart() -> void:
	var screen := await _play_screen()
	var spots := {}
	for entry in str(WebProbe.snapshot(screen)["spots"]).split("|"):
		var key := entry.rsplit(":", true, 1)
		spots[key[0]] = key[1]
	assert_bool(spots.has("bots:end")).is_true()
	assert_bool(spots.has("bot_skill:end")).is_true()
	var bots_end := float(str(spots["bots:end"]).split(",")[0])
	var skill_end := float(str(spots["bot_skill:end"]).split(",")[0])
	var skill_centre := float(str(spots["bot_skill"]).split(",")[0])
	assert_float(bots_end).is_less(skill_centre)
	assert_float(skill_end).is_greater(skill_centre)
	screen.queue_free()


func test_an_online_night_reports_where_the_body_and_the_server_have_the_player() -> void:
	var screen := auto_free(NightScreen.new()) as NightScreen
	var night := auto_free(Night.new()) as Night
	screen.night = night
	night.remote = true
	night.state = ClientState.new()
	night.state.player_id = 2
	night.state.frame = {"players": {2: {"pos": Vector3(4.0, 0.0, -3.0)}}}
	var body := auto_free(Player.new()) as Player
	body.state.position = Vector3(1.5, 0.0, 2.5)
	night._body = body
	night.stalls.check(0.0)
	night.stalls.check(900.0)
	var data := WebProbe.snapshot(screen)
	assert_float(data["body_x"]).is_equal(1.5)
	assert_float(data["body_z"]).is_equal(2.5)
	assert_float(data["server_x"]).is_equal(4.0)
	assert_float(data["server_z"]).is_equal(-3.0)
	assert_int(data["stalls"]).is_equal(1)
	assert_float(data["stall_longest_ms"]).is_equal(900.0)


func test_the_together_screen_says_when_it_asks_for_a_name() -> void:
	var screen := (
		(load("res://ui/screens/together_screen.tscn") as PackedScene).instantiate()
		as TogetherScreen
	)
	add_child(screen)
	assert_bool(WebProbe.snapshot(screen)["naming"]).is_false()
	TogetherScreen.name_skipped = false
	screen.call("_show_menu")
	screen.get("_naming").visible = true
	assert_bool(WebProbe.snapshot(screen)["naming"]).is_true()
	screen.queue_free()


func test_the_lobby_reports_its_code_its_seats_and_the_buttons_it_shows() -> void:
	var held := {
		"id": "l1",
		"code": "ABC234",
		"hostId": "a",
		"maxPlayers": 4,
		"state": "open",
		"round": null,
		"players": null,
		"members":
		[
			{"userId": "a", "name": "Ann", "seat": 1, "host": true, "away": false},
			{"userId": "b", "name": "Bo", "seat": 2, "host": false, "away": false},
		],
	}
	var screen := (load(LobbyScreen.SCREEN) as PackedScene).instantiate() as LobbyScreen
	var api := TogetherApi.new(self)
	api.isolated = true
	api._own_user = {"id": "a"}
	screen.params = {"api": api, "lobby": held}
	add_child(screen)
	var data := WebProbe.snapshot(screen)
	assert_str(data["screen"]).is_equal("lobby_screen")
	assert_str(data["room_code"]).is_equal("ABC234")
	assert_str(data["lobby_seats"]).is_equal("1  Ann  HOST|2  Bo|3  (open)|4  (open)")
	assert_str(data["lobby_buttons"]).is_equal("Start")
	assert_str(data["room_status"]).contains("2 of 4 here")
	screen.queue_free()
