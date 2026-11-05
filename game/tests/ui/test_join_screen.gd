# The Join screen: what a player types becomes a server address, and the menu offers it.
extends GdUnitTestSuite


func test_an_address_is_made_a_websocket_url() -> void:
	assert_str(JoinScreen.normalize("")).is_equal("ws://localhost:8910")
	assert_str(JoinScreen.normalize("  ")).is_equal("ws://localhost:8910")
	assert_str(JoinScreen.normalize("192.168.1.20")).is_equal("ws://192.168.1.20:8910")
	assert_str(JoinScreen.normalize("host:9000")).is_equal("ws://host:9000")
	assert_str(JoinScreen.normalize("ws://host:9000/")).is_equal("ws://host:9000")
	assert_str(JoinScreen.normalize("wss://night.up.railway.app")).is_equal(
		"wss://night.up.railway.app"
	)
	assert_str(JoinScreen.normalize("https://night.up.railway.app")).is_equal(
		"wss://night.up.railway.app"
	)
	assert_str(JoinScreen.normalize("http://localhost:8910")).is_equal("ws://localhost:8910")


func test_the_main_menu_offers_join_on_the_play_tab() -> void:
	var menu := (load("res://ui/screens/main_menu.tscn") as PackedScene).instantiate() as MainMenu
	add_child(menu)
	var play := menu.shell.panel(MenuTab.Id.PLAY) as PlayPanel
	assert_object(play.button(&"together")).is_not_null()
	assert_object(play.button(&"browser")).is_not_null()
	assert_str(MainMenu.ROUTES[&"together"][0]).is_equal(MainMenu.JOIN_SCREEN)
	menu.queue_free()


func test_the_screen_starts_on_the_local_server() -> void:
	var screen := (
		(load("res://ui/screens/join_screen.tscn") as PackedScene).instantiate() as JoinScreen
	)
	add_child(screen)
	assert_str(screen.address.text).is_equal(JoinScreen.DEFAULT_URL)
	assert_object(screen.join_button).is_not_null()
	screen.queue_free()


func test_the_public_server_is_a_secure_address_that_needs_no_change() -> void:
	assert_str(JoinScreen.normalize(JoinScreen.PUBLIC_URL)).is_equal(JoinScreen.PUBLIC_URL)
	assert_bool(JoinScreen.PUBLIC_URL.begins_with("wss://")).is_true()
