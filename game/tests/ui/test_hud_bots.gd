# Bots are labelled as bots in the HUD (#643, bots.md decision 2): BOT after the name on every part
# that writes a name, no "joined" notice for a bot seated at the start, and a notice when a person
# takes a bot's seat and the label goes.
extends GdUnitTestSuite

var _host: Control


func before_test() -> void:
	UIMotion.reduced = false
	_host = auto_free(Control.new())
	_host.size = Vector2(1920, 1080)
	add_child(_host)


func _with_bot() -> HudFixture:
	var fixture := HudFixture.make(_host, 1)
	fixture.hud.state.set_player_name(2, "Ash")
	fixture.act(RulesAction.add_player(2, true))
	return fixture


func test_a_bot_seat_is_marked_in_the_team_and_named_with_bot_after_it() -> void:
	var fixture := _with_bot()
	var state := fixture.hud.state
	assert_bool(state.team[2]["bot"]).is_true()
	assert_bool(state.team[1]["bot"]).is_false()
	assert_str(HudState.name_of(state.team[2])).is_equal("ASH BOT")
	assert_str(HudState.name_of(state.team[1])).is_equal("RUBY")


func test_the_boxes_and_the_scoreboard_show_the_label() -> void:
	var fixture := _with_bot()
	fixture.into_round_one()
	await get_tree().process_frame
	var box := fixture.hud.points.box_of(2)
	assert_object(box).is_not_null()
	var found := false
	for label in box.find_children("*", "Label", true, false):
		found = found or (label as Label).text == "ASH BOT"
	assert_bool(found).is_true()
	assert_str(fixture.hud.scoreboard._cells(2)[0]).starts_with("ASH BOT")
	assert_str(fixture.hud.scoreboard._cells(1)[0]).is_equal("RUBY")


func test_a_bot_seated_at_the_start_is_no_notice_and_a_person_taking_its_seat_is() -> void:
	var fixture := _with_bot()
	# The person's own seat said so; the bot's said nothing.
	assert_array(fixture.hud.notices.history).is_equal(["RUBY JOINED"])
	fixture.hud.state.set_player_name(2, "Cy")
	fixture.act(RulesAction.seat_person(2))
	assert_bool(fixture.hud.state.team[2]["bot"]).is_false()
	assert_str(HudState.name_of(fixture.hud.state.team[2])).is_equal("CY")
	assert_array(fixture.hud.notices.history).is_equal(["RUBY JOINED", "CY JOINED"])


func test_a_snapshot_marks_the_bots_for_a_late_joiner() -> void:
	var fixture := _with_bot()
	var late := HudFixture.make(_host, 1)
	late.hud.state.load_snapshot(fixture.rules.to_dict())
	assert_bool(late.hud.state.team[2]["bot"]).is_true()
	assert_bool(late.hud.state.team[1]["bot"]).is_false()
