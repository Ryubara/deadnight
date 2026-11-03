# A bot's callout in the event feed (bots plan, phase 5): the name and the line's own words.
extends GdUnitTestSuite


func _feed() -> HudFeed:
	var state := HudState.new()
	state.team[2] = {"name": "Moe"}
	var feed := auto_free(HudFeed.new()) as HudFeed
	add_child(feed)
	feed.bind(state)
	return feed


func test_a_bots_callout_is_in_the_feed_in_its_own_words() -> void:
	var feed := _feed()
	feed.on_event({"type": &"bot_say", "player_id": 2, "line": &"reloading", "subject": -1})
	assert_str(feed.texts().back()).is_equal("MOE: " + BotSay.text_of(&"reloading"))
