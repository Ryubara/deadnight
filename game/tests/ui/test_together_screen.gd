# The Play together screen: what it offers, how a night's invite looks, and where it sends a player.
extends GdUnitTestSuite


func _screen() -> TogetherScreen:
	var screen := (
		(load("res://ui/screens/together_screen.tscn") as PackedScene).instantiate()
		as TogetherScreen
	)
	add_child(screen)
	return screen


func test_it_offers_quick_join_a_night_of_your_own_and_a_code() -> void:
	var screen := _screen()
	assert_str(screen.quick_button.text).is_equal("Quick join")
	assert_str(screen.create_button.text).is_equal("Create a night")
	assert_object(screen.code_field).is_not_null()
	assert_bool(screen.code_field.max_length > 0).is_true()
	# No address anywhere: players never see one.
	assert_object(screen.find_child("Address", true, false)).is_null()
	screen.queue_free()


func test_the_address_is_a_developer_setting() -> void:
	var before := TogetherScreen.dev_enabled
	TogetherScreen.dev_enabled = false
	var plain := _screen()
	assert_object(plain.find_child("ServerAddress", true, false)).is_null()
	plain.queue_free()
	TogetherScreen.dev_enabled = true
	var dev := _screen()
	assert_object(dev.find_child("ServerAddress", true, false)).is_not_null()
	dev.queue_free()
	TogetherScreen.dev_enabled = before


func test_an_invite_link_is_the_page_with_the_code() -> void:
	assert_str(TogetherApi.invite_link("ABC123", "https://play.example/index.html?x=1#y")).is_equal(
		"https://play.example/index.html?room=ABC123"
	)
	# Without a page (the desktop) the invite is the code.
	assert_str(TogetherApi.invite_link("ABC123", "")).is_equal("ABC123")


func test_a_discord_activity_connects_through_its_own_proxy() -> void:
	var pass_to := {"url": "wss://deadnight-server.example", "activity_path": "/server"}
	assert_str(TogetherScreen.server_url_of(pass_to, false)).is_equal(
		"wss://deadnight-server.example"
	)
	(
		assert_str(
			TogetherScreen.server_url_of(pass_to, true, "1566609915219419286.discordsays.com")
		)
		. is_equal("wss://1566609915219419286.discordsays.com/server")
	)


func test_what_a_player_reads_for_each_answer_of_the_backend() -> void:
	for reason in ["not_found", "full", "no_server", "already_in_lobby", "network"]:
		assert_bool(TogetherApi.TEXTS.has(reason)).is_true()
	# An answer nobody planned for still says something.
	assert_str(TogetherApi._failed("weird")["text"]).contains("weird")
	assert_bool(TogetherApi._failed("full")["ok"]).is_false()
