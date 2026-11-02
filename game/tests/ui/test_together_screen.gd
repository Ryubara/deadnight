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


## An API that answers from the test: no network.
class FakeApi:
	extends TogetherApi
	var joined: Array[String] = []

	func sign_in(_display_name: String = "") -> Dictionary:
		return {"ok": true}

	func join_code(code: String) -> Dictionary:
		joined.append(code)
		if code == "NOPE":
			return {"ok": false, "error": "not_found", "text": TogetherApi.TEXTS["not_found"]}
		return {"ok": true, "lobby": {"id": "lobby-1", "code": code}}


func test_a_night_found_by_a_link_waits_for_a_press_of_play() -> void:
	var screen := _screen()
	var fake := FakeApi.new(screen)
	screen.api = fake
	TogetherScreen.auto_code = "FRIEND1"
	await screen.screen_enter()
	assert_array(fake.joined).is_equal(["FRIEND1"])
	# It did not go in: the invite view shows the code and a Play button, and no invite to hand out.
	assert_str(NightScreen.join_url).is_equal("")
	assert_bool(screen.play_button.is_visible_in_tree()).is_true()
	assert_str(screen.invite_code.text).is_equal("FRIEND1")
	assert_bool(screen.copy_link_button.is_visible_in_tree()).is_false()
	assert_bool(screen.copy_code_button.is_visible_in_tree()).is_false()
	assert_bool(screen.quick_button.is_visible_in_tree()).is_false()
	screen.queue_free()


func test_a_link_to_a_night_that_is_gone_says_so_and_shows_the_menu() -> void:
	var screen := _screen()
	screen.api = FakeApi.new(screen)
	TogetherScreen.auto_code = "NOPE"
	await screen.screen_enter()
	assert_str(screen.status.text).contains("no night with that code")
	assert_bool(screen.quick_button.is_visible_in_tree()).is_true()
	assert_bool(screen.quick_button.disabled).is_false()
	screen.queue_free()


func test_the_controller_note_shows_only_in_a_discord_activity() -> void:
	var screen := _screen()
	screen._process(2.0)
	assert_str(screen._controller_note.text).is_empty()
	assert_bool(screen._controller_note.visible).is_false()
	screen.queue_free()
