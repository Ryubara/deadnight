extends GdUnitTestSuite
## What the web probe publishes, without a browser: a plain function of the top screen.


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
	var screen := (
		(load("res://ui/screens/lobby_screen.tscn") as PackedScene).instantiate() as LobbyScreen
	)
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
