extends GdUnitTestSuite
## What a night's HUD holds while a part is not in use (#1216). The late-round budget
## (`tools/perf/budget.json`) counts every canvas item of the tree, shown or not, and sat at its
## limit, so a part that is hidden for most of a night makes its words the first time it is needed
## and not before. Each case checks both ends: nothing built while idle, the whole card once used.

var _host: Control


func before_test() -> void:
	UIMotion.reduced = false
	_host = auto_free(Control.new())
	_host.size = Vector2(1920, 1080)
	add_child(_host)


func _items_under(node: Node) -> int:
	return node.find_children("*", "CanvasItem", true, false).size()


func _fixture() -> HudFixture:
	return HudFixture.make(_host, 4)


func test_the_hidden_cards_hold_nothing_until_they_are_needed() -> void:
	var hud := _fixture().hud
	for part: Control in [hud.scoreboard, hud.marquee, hud.boss_bar, hud.challenge]:
		assert_int(_items_under(part)).is_equal(0)


func test_the_scoreboard_makes_its_rows_when_first_held_open() -> void:
	var fixture := _fixture()
	fixture.into_round_one()
	var board := fixture.hud.scoreboard
	assert_int(_items_under(board)).is_equal(0)
	board.set_shown(true)
	assert_int(board.row_ids.size()).is_equal(4)
	assert_str(board.round_text).is_equal("ROUND 01")
	assert_int(_items_under(board)).is_greater(10)
	board.set_shown(false)
	board.set_shown(true)
	assert_int(board.row_ids.size()).is_equal(4)


func test_the_challenge_prompt_makes_its_card_when_a_challenge_moves() -> void:
	var hud := _fixture().hud
	assert_int(_items_under(hud.challenge)).is_equal(0)
	assert_int(hud.challenge.get_child_count()).is_equal(0)
	assert_object(hud.challenge.card).is_not_null()
	assert_int(hud.challenge.get_child_count()).is_equal(1)
	assert_int(_items_under(hud.challenge)).is_greater(5)


func test_the_end_board_makes_its_parts_when_the_night_ends() -> void:
	var board: HudEndBoard = auto_free(HudEndBoard.new())
	_host.add_child(board)
	board.set_safe_insets(Vector4(12.0, 0.0, 12.0, 0.0))
	assert_int(board.get_child_count()).is_equal(0)
	assert_bool(board.visible).is_false()
	var fixture := _fixture()
	fixture.into_round_one()
	board.show_results(fixture.hud.state, "Back in 5", "Back")
	assert_bool(board.visible).is_true()
	assert_int(board.row_ids.size()).is_equal(4)
	assert_str(board.leave_button.text).is_equal("Back")
	assert_int(_items_under(board)).is_greater(15)


func test_the_end_boards_safe_area_is_kept_for_when_it_is_made() -> void:
	var board: HudEndBoard = auto_free(HudEndBoard.new())
	_host.add_child(board)
	board.set_safe_insets(Vector4(30.0, 4.0, 40.0, 8.0))
	assert_int(board.get_child_count()).is_equal(0)
	board.leave_button.text = "x"
	var margin: MarginContainer = board.get_child(0)
	var base := HudStyle.margin()
	assert_int(margin.get_theme_constant(&"margin_left")).is_equal(base + 30)
	assert_int(margin.get_theme_constant(&"margin_bottom")).is_equal(base + 8)


func test_a_popup_card_makes_only_what_its_kind_shows() -> void:
	var challenge: PopupCard = auto_free(PopupCard.new())
	challenge.setup(PopupQueue.Kind.CHALLENGE, {"text": "Do kills 8"})
	assert_int(challenge.get_child_count()).is_equal(4)
	var tier: PopupCard = auto_free(PopupCard.new())
	tier.setup(PopupQueue.Kind.TIER, {"level": 10, "tier_name": "Usher"})
	assert_int(tier.get_child_count()).is_equal(4)
	var level: PopupCard = auto_free(PopupCard.new())
	level.setup(PopupQueue.Kind.LEVEL, {"level": 2})
	assert_int(level.get_child_count()).is_equal(5)
	assert_array(level.lines()).contains(["LEVEL UP"])
	var unlock: PopupCard = auto_free(PopupCard.new())
	var table := LadderUnlocks.shipped()
	var row: Dictionary = table.earned_at(table.levels()[0])[0]
	unlock.setup(PopupQueue.Kind.UNLOCK, {"slot": row["slot"], "item": row["item"], "level": 1})
	assert_int(unlock.get_child_count()).is_equal(5)
	var more: PopupCard = auto_free(PopupCard.new())
	more.setup(PopupQueue.Kind.MORE, {"count": 3})
	assert_int(more.get_child_count()).is_equal(4)
	assert_array(more.lines()).is_equal(["3 NEW ITEMS"])
