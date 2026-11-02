# What a headless client prints with `--report`: the night as the client sees it, as plain values.
extends GdUnitTestSuite


func test_with_no_night_it_says_so() -> void:
	var data := ClientReport.report(null)
	assert_str(data["event"]).is_equal("client")
	assert_bool(data["night"]).is_false()


func test_an_online_night_reports_who_is_there_and_the_link() -> void:
	var screen := auto_free(NightScreen.new()) as NightScreen
	screen.night = auto_free(Night.new()) as Night
	screen.night.state = ClientState.new()
	screen.night.state.player_id = 2
	screen.night.state.frame = {
		"round": 3, "players": {1: {"pos": Vector3.ONE}, 2: {"pos": Vector3.ZERO, "points": 500}}
	}
	var link := WebSocketLink.new()
	link.rtt_samples.append_array([60.0, 80.0, 100.0])
	link.tick_gaps_ms.append_array([33.0, 34.0, 130.0])
	screen.night.link = link
	var data := ClientReport.report(screen)
	assert_bool(data["night"]).is_true()
	assert_int(data["player_id"]).is_equal(2)
	assert_array(data["players"]).contains_exactly_in_any_order([1, 2])
	assert_int(data["round"]).is_equal(3)
	assert_float(data["rtt"]["mean"]).is_equal(80.0)
	assert_float(data["rtt"]["max"]).is_equal(100.0)
	assert_int(data["gaps"]["n"]).is_equal(3)
	assert_int(data["gaps"]["stalls"]).is_equal(1)
	# Reading the numbers clears them, so each line is about its own seconds.
	assert_int(ClientReport.report(screen)["rtt"]["n"]).is_equal(0)
	# And it is plain data: it prints as JSON.
	assert_str(JSON.stringify(data)).contains('"players"')
