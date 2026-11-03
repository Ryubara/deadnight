# What the HUD says of a grenade that hurt or downed a player: whose it was, in the feed (#805).
extends GdUnitTestSuite


func _feed() -> HudFeed:
	var state := HudState.new()
	state.local_player_id = 1
	state.team[1] = {"name": "Ruby"}
	state.team[2] = {"name": "Moe"}
	state.team[3] = {"name": "Ada", "bot": true}
	var feed := auto_free(HudFeed.new()) as HudFeed
	add_child(feed)
	feed.bind(state)
	return feed


func _hurt(player: int, by: int, health: float, harm := &"grenade") -> Dictionary:
	return {
		"type": &"player_hurt",
		"player_id": player,
		"damage": 41.6,
		"health": health,
		"max_health": 100.0,
		"bearing": 0.0,
		"source_id": -1,
		"harm": harm,
		"by_id": by,
	}


func _down(player: int, by: int, harm := &"grenade") -> Dictionary:
	return {
		"type": &"player_downed",
		"player_id": player,
		"cause": &"blow",
		"bearing": 0.0,
		"bleed_seconds": 30.0,
		"harm": harm,
		"by_id": by,
	}


func test_ones_own_grenade_that_hurt_says_so_with_the_damage() -> void:
	var feed := _feed()
	feed.on_event(_hurt(1, 1, 58.4))
	assert_str(feed.texts().back()).is_equal("YOUR OWN GRENADE HIT YOU  -42")


func test_a_teammates_grenade_names_the_teammate() -> void:
	var feed := _feed()
	feed.on_event(_hurt(1, 2, 58.4))
	assert_str(feed.texts().back()).is_equal("MOE'S GRENADE HIT YOU  -42")
	var bot := _feed()
	bot.on_event(_hurt(1, 3, 58.4))
	assert_str(bot.texts().back()).is_equal("ADA BOT'S GRENADE HIT YOU  -42")


func test_a_blast_that_downs_is_the_down_lines_alone() -> void:
	var feed := _feed()
	feed.on_event(_hurt(1, 1, 0.0))
	feed.on_event(_down(1, 1))
	assert_array(feed.texts()).contains_exactly(["RUBY BLEW THEMSELVES UP"])
	var other := _feed()
	other.on_event(_down(2, 1))
	assert_str(other.texts().back()).is_equal("MOE WAS BLOWN UP BY RUBY'S GRENADE")


func test_what_a_grenade_did_to_someone_else_is_not_news_but_the_down_is() -> void:
	var feed := _feed()
	feed.on_event(_hurt(2, 1, 58.4))
	assert_array(feed.texts()).is_empty()


func test_a_zombies_blow_and_a_plain_down_read_as_before() -> void:
	var feed := _feed()
	feed.on_event(_hurt(1, 0, 58.4, &""))
	assert_array(feed.texts()).is_empty()
	feed.on_event(_down(2, 0, &""))
	assert_str(feed.texts().back()).is_equal("MOE IS DOWN")
