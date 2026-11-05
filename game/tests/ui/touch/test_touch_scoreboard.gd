extends GdUnitTestSuite
## A finger held on the players' column shows the scoreboard's ticket and lifting hides it
## (Deadnight #1287): the Scoreboard circle is gone, the HUD's column is a place a finger presses
## (the same `scoreboard` action as Tab), a finger that begins there never looks, fires or starts
## the stick, and the weapon strip's places beside it keep their own taps. The ticket fits the
## page and is not under a button on the two phone pages (844 x 390 and 667 x 375 CSS px at a
## pixel ratio of 2), at every interface size, in both hands, from one player to a full room with
## its bots; the first-run hints say it once. These are real touch events through the layer, as a
## browser would send them.

## Windows in pixels and the pixel ratio the browser reports.
const PAGES: Array[Vector3] = [Vector3(1688, 780, 2.0), Vector3(1334, 750, 2.0)]
const UI_SCALES: Array[float] = [0.8, 1.0, 1.25]
const HANDS: Array[bool] = [false, true]
## People and bots in the room: one, a party, eight people, and every seat of a full room.
const PARTIES: Array[Vector2i] = [Vector2i(1, 0), Vector2i(4, 0), Vector2i(8, 0), Vector2i(8, 7)]
## What a fingertip is, CSS px, and the slack a rounding up to whole units leaves.
const FINGER_CSS := 44.0
const SLACK_CSS := 0.05
## The least share of its own size the ticket is shrunk to anywhere in the matrix: the smallest page
## at the biggest interface size with a full room is the worst, at 0.60 when this was written.
const LEAST_SHARE := 0.55

var _window_size := Vector2i.ZERO
var _window_factor := 1.0
var _fixture: TouchFixture
var _looks := 0
var _rules: GameRules


func before_test() -> void:
	_window_size = get_window().size
	_window_factor = get_window().content_scale_factor
	_looks = 0
	UIMotion.reduced = false
	Input.action_release(&"scoreboard")


func after_test() -> void:
	if _fixture != null:
		_fixture.free_all()
		_fixture = null
	Input.action_release(&"scoreboard")
	get_window().size = _window_size
	get_window().content_scale_factor = _window_factor
	MenuScale.pixel_ratio = -1.0
	UIMotion.reduced = false
	await get_tree().process_frame


## The page a player has and the room in it: the window, the interface size and the ratio, the
## touch layer and the HUD on the canvas it makes, in the hand asked for, `party.x` people and
## `party.y` bots.
func _page(page: Vector3, ui_scale: float, left := false, party := Vector2i(1, 0)) -> void:
	var window := Vector2i(int(page.x), int(page.y))
	get_window().size = window
	get_window().content_scale_factor = ui_scale
	MenuScale.pixel_ratio = page.z
	var canvas := Vector2(window) / MenuScale.pixels_per_unit(window, ui_scale)
	_fixture = TouchFixture.make(self, canvas, null, false, true)
	if left:
		_fixture.left_handed(true)
	_fixture.controls.looked.connect(func(_motion: Vector2) -> void: _looks += 1)
	_rules = GameRules.new((load(HudFixture.TUNING) as RulesTuning).duplicate(true), 1958)
	var hud := _fixture.hud
	for i in party.x:
		hud.state.set_player_name(i + 1, "Player %d" % (i + 1))
		hud.feed(_rules.apply(RulesAction.add_player(i + 1)))
	for i in party.y:
		var id := NightBots.id_at(i)
		hud.state.set_player_name(id, NightBots.name_for(id))
		hud.feed(_rules.apply(RulesAction.add_player(id, true)))
	await _settle()


func _settle() -> void:
	for _i in 5:
		await get_tree().process_frame


func _css_per_unit(page: Vector3, ui_scale: float) -> float:
	var window := Vector2i(int(page.x), int(page.y))
	return MenuScale.pixels_per_unit(window, ui_scale) / page.z


func _label(page: Vector3, ui_scale: float, left: bool, party: Vector2i, what: String) -> String:
	return (
		"%s on %dx%d at %.2f, left hand %s, %d people and %d bots"
		% [what, page.x, page.y, ui_scale, left, party.x, party.y]
	)


## The column's zone, `{}` when there is none.
func _zone() -> Dictionary:
	for zone in _fixture.hud.touch_zones():
		if zone[&"action"] == &"scoreboard":
			return zone
	return {}


func _column() -> Rect2:
	return _zone().get(&"rect", Rect2())


## How far `rect` is from the circle of `id` past its radius: positive when clear of it.
func _clearance(rect: Rect2, circle: Dictionary) -> float:
	var centre: Vector2 = circle[&"centre"]
	return centre.distance_to(centre.clamp(rect.position, rect.end)) - float(circle[&"radius"])


## Every page, interface size, hand and party, with a fresh fixture each time.
func _every_room(check: Callable) -> void:
	for page in PAGES:
		for ui_scale in UI_SCALES:
			for left in HANDS:
				for party in PARTIES:
					await _page(page, ui_scale, left, party)
					await check.call(page, ui_scale, left, party)
					_fixture.free_all()
					_fixture = null


func test_there_is_no_scoreboard_button() -> void:
	for mirrored in HANDS:
		var circles := TouchLayout.buttons(Rect2(0, 0, 2337, 1080), 1.0, mirrored, 122.0)
		assert_bool(circles.has(&"scoreboard")).is_false()
	for row in TouchLayout.BUTTONS:
		assert_bool(row[0] == &"scoreboard").is_false()
	await _page(PAGES[0], 1.0)
	assert_bool(_fixture.controls.circles().has(&"scoreboard")).is_false()
	assert_bool(TouchIcons.has_icon(&"scoreboard")).is_false()


func test_the_column_is_a_zone_of_the_huds_touch_zones_after_the_weapon_places() -> void:
	await _page(PAGES[1], 1.0)
	var actions: Array[StringName] = []
	for zone in _fixture.hud.touch_zones():
		actions.append(zone[&"action"])
	assert_array(actions).is_equal(
		[&"weapon_slot_1", &"weapon_slot_2", &"throw_grenade", &"scoreboard"]
	)
	assert_bool(_fixture.controls.button_boxes().has(_column())).is_true()


func test_the_column_is_at_least_a_fingertip_wide_and_high_on_both_pages() -> void:
	await _every_room(
		func(page: Vector3, ui_scale: float, left: bool, party: Vector2i) -> void:
			var css := _css_per_unit(page, ui_scale)
			var rect := _column()
			var what := _label(page, ui_scale, left, party, "the column")
			assert_bool(rect.has_area()).override_failure_message(what).is_true()
			(
				assert_float(rect.size.x * css)
				. override_failure_message(what + " is %.1f CSS px wide" % (rect.size.x * css))
				. is_greater_equal(FINGER_CSS - SLACK_CSS)
			)
			(
				assert_float(rect.size.y * css)
				. override_failure_message(what + " is %.1f CSS px high" % (rect.size.y * css))
				. is_greater_equal(FINGER_CSS - SLACK_CSS)
			)
	)


func test_the_column_is_on_the_screen_on_its_hands_side_and_over_no_button_or_place() -> void:
	await _every_room(
		func(page: Vector3, ui_scale: float, left: bool, party: Vector2i) -> void:
			var controls := _fixture.controls
			var rect := _column()
			var what := _label(page, ui_scale, left, party, "the column")
			assert_bool(Rect2(Vector2.ZERO, _fixture.host.size).encloses(rect)).is_true()
			var middle := _fixture.host.size.x * 0.5
			assert_bool(rect.get_center().x > middle).override_failure_message(what).is_equal(left)
			for id: StringName in controls.circles():
				var circle: Dictionary = controls.circles()[id]
				var centre: Vector2 = circle[&"centre"]
				var reach := centre.distance_to(centre.clamp(rect.position, rect.end))
				(
					assert_float(reach)
					. override_failure_message("%s touches the %s button" % [what, id])
					. is_greater(float(circle[&"hit"]))
				)
			for zone in _fixture.hud.slots.touch_zones():
				(
					assert_bool(rect.intersects(zone[&"rect"]))
					. override_failure_message("%s is over %s" % [what, zone[&"action"]])
					. is_false()
				)
			# Over the points card and nothing else of the HUD's: the health card is its own.
			assert_bool(rect.encloses(_fixture.hud.points.get_global_rect())).is_true()
			(
				assert_bool(rect.intersects(_fixture.hud.health.get_global_rect()))
				. override_failure_message(what + " is over the health card")
				. is_false()
			)
	)


func test_a_finger_held_on_the_column_shows_the_ticket_and_lifting_hides_it() -> void:
	await _page(PAGES[1], 1.0, false, Vector2i(4, 0))
	var board := _fixture.hud.scoreboard
	assert_bool(board.visible).is_false()
	var point := _column().get_center()
	await _fixture.touch(0, point)
	await _settle()
	assert_bool(Input.is_action_pressed(&"scoreboard")).is_true()
	assert_bool(board.visible).is_true()
	assert_array(Array(_fixture.controls.held_buttons())).is_equal(["scoreboard"])
	# Held, not toggled: it stays up for as long as the finger is down.
	await await_millis(400)
	assert_bool(board.visible).is_true()
	assert_int(board.row_ids.size()).is_equal(4)
	await _fixture.lift(0, point)
	await await_millis(250)
	await _settle()
	assert_bool(Input.is_action_pressed(&"scoreboard")).is_false()
	assert_bool(board.visible).is_false()


func test_a_quick_tap_on_the_column_still_lasts_a_tick() -> void:
	await _page(PAGES[1], 1.0)
	await _fixture.tap(_column().get_center())
	assert_bool(Input.is_action_pressed(&"scoreboard")).is_true()
	await await_millis(300)
	assert_bool(Input.is_action_pressed(&"scoreboard")).is_false()


func test_a_finger_that_begins_on_the_column_never_looks_fires_or_starts_the_stick() -> void:
	for left in HANDS:
		await _page(PAGES[1], 1.0, left, Vector2i(4, 0))
		var at := _column().get_center()
		await _fixture.touch(0, at)
		assert_bool(_fixture.controls.is_stick_down()).is_false()
		# The finger wanders, up into the stick's zone and across the screen, as a thumb does.
		for _i in 8:
			at += Vector2(40.0, -60.0) * (-1.0 if left else 1.0)
			await _fixture.drag(0, at, Vector2(40.0, -60.0), 600.0)
		await _fixture.settle_look()
		assert_int(_looks).is_equal(0)
		assert_bool(_fixture.controls.is_stick_down()).is_false()
		assert_vector(_fixture.controls.stick_vector()).is_equal(Vector2.ZERO)
		for action in [&"fire", &"aim", &"jump", &"sprint", &"move_forward", &"move_left"]:
			assert_bool(Input.is_action_pressed(action)).override_failure_message(action).is_false()
		assert_bool(Input.is_action_pressed(&"scoreboard")).is_true()
		await _fixture.lift(0, at)
		await await_millis(250)
		_fixture.free_all()
		_fixture = null


func test_the_stick_still_starts_on_the_free_ground_beside_the_column() -> void:
	await _page(PAGES[1], 1.0, false, Vector2i(4, 0))
	var column := _column()
	# Right of the column and above the strip, inside the stick's zone: not a zone.
	var beside := Vector2(column.end.x + 80.0, column.get_center().y)
	assert_str(String(_fixture.controls.zone_at(beside))).is_equal("")
	await _fixture.touch(0, beside)
	assert_bool(_fixture.controls.is_stick_down()).is_true()
	assert_bool(Input.is_action_pressed(&"scoreboard")).is_false()
	await _fixture.lift(0, beside)


func test_a_second_finger_on_the_column_while_the_stick_is_down_holds_the_ticket() -> void:
	await _page(PAGES[1], 1.0, false, Vector2i(4, 0))
	var column := _column()
	var beside := Vector2(column.end.x + 80.0, column.get_center().y)
	await _fixture.touch(0, beside)
	await _fixture.touch(1, column.get_center())
	assert_bool(_fixture.controls.is_stick_down()).is_true()
	assert_bool(Input.is_action_pressed(&"scoreboard")).is_true()
	await _fixture.lift(1, column.get_center())
	await await_millis(250)
	assert_bool(Input.is_action_pressed(&"scoreboard")).is_false()
	assert_bool(_fixture.controls.is_stick_down()).is_true()
	await _fixture.lift(0, beside)


func test_the_weapon_places_beside_the_column_keep_their_own_taps() -> void:
	await _page(PAGES[1], 1.0, false, Vector2i(4, 0))
	for action in [&"weapon_slot_1", &"weapon_slot_2", &"throw_grenade"]:
		var centre := _fixture.zone_centre(action)
		await _fixture.touch(0, centre)
		assert_bool(Input.is_action_pressed(action)).override_failure_message(action).is_true()
		assert_bool(Input.is_action_pressed(&"scoreboard")).is_false()
		await _fixture.lift(0, centre)
		await await_millis(250)
	var column := _column()
	var foot := Vector2(column.get_center().x, column.end.y - 1.0)
	assert_str(String(_fixture.controls.zone_at(foot))).is_equal("scoreboard")
	var strip := _fixture.zone_centre(&"weapon_slot_1")
	assert_str(String(_fixture.controls.zone_at(strip))).is_equal("weapon_slot_1")


func test_the_ticket_fits_the_page_and_is_under_no_button_or_place() -> void:
	await _every_room(
		func(page: Vector3, ui_scale: float, left: bool, party: Vector2i) -> void:
			var controls := _fixture.controls
			var board := _fixture.hud.scoreboard
			var column := _column()
			await _fixture.touch(0, column.get_center())
			await _settle()
			var what := _label(page, ui_scale, left, party, "the ticket")
			assert_bool(board.visible).override_failure_message(what + " is up").is_true()
			var card := board.card_rect()
			var room := _fixture.hud.get_global_rect()
			(
				assert_bool(room.grow(0.5).encloses(card))
				. override_failure_message("%s is %s, off the page %s" % [what, card, room])
				. is_true()
			)
			var share: float = board.get_parent().scale.x
			(
				assert_float(share)
				. override_failure_message("%s is shrunk to %.2f" % [what, share])
				. is_greater_equal(LEAST_SHARE)
			)
			for id: StringName in controls.circles():
				if id == TouchLayout.INTERACT and controls.interact_verb() == "":
					continue
				(
					assert_float(_clearance(card, controls.circles()[id]))
					. override_failure_message("%s is under the %s button" % [what, id])
					. is_greater(0.0)
				)
			for zone in _fixture.hud.touch_zones():
				(
					assert_bool(card.intersects(zone[&"rect"]))
					. override_failure_message("%s is over %s" % [what, zone[&"action"]])
					. is_false()
				)
			await _fixture.lift(0, column.get_center())
			await await_millis(250)
	)


func test_the_ticket_is_where_it_always_was_while_nothing_is_under_it() -> void:
	# The middle of a page of 844 x 390 at 1.0 is clear: the ticket stays in it, whole.
	await _page(PAGES[0], 1.0, false, Vector2i(4, 0))
	await _fixture.touch(0, _column().get_center())
	await _settle()
	var board := _fixture.hud.scoreboard
	var room := _fixture.hud.get_global_rect()
	assert_float(board.get_parent().scale.x).is_equal(1.0)
	assert_float(board.card_rect().get_center().x).is_equal_approx(room.get_center().x, 1.0)
	assert_float(board.card_rect().get_center().y).is_equal_approx(room.get_center().y, 1.0)
	await _fixture.lift(0)
	await await_millis(250)


func test_the_ticket_goes_back_to_the_middle_when_the_touch_layout_goes() -> void:
	await _page(PAGES[1], 1.25, false, Vector2i(8, 0))
	await _fixture.touch(0, _column().get_center())
	await _settle()
	var holder := _fixture.hud.scoreboard.get_parent() as Control
	assert_float(holder.scale.x).is_less(1.0)
	await _fixture.lift(0)
	await await_millis(250)
	_fixture.hud.touch_layout = false
	Input.action_press(&"scoreboard")
	await _settle()
	assert_float(holder.scale.x).is_equal(1.0)
	assert_float(holder.offset_left).is_equal(0.0)
	assert_float(holder.offset_right).is_equal(0.0)
	Input.action_release(&"scoreboard")


func test_the_hints_say_it_once_beside_the_column_and_a_hold_ends_it() -> void:
	await _every_room(
		func(page: Vector3, ui_scale: float, left: bool, party: Vector2i) -> void:
			var hints := _fixture.controls.hints
			var what := _label(page, ui_scale, left, party, "the hint")
			assert_array(hints.showing()).contains([TouchHints.SCOREBOARD])
			assert_str(hints.text_for(TouchHints.SCOREBOARD)).is_equal("HOLD FOR SCORES")
			var rect := hints.rect_of(TouchHints.SCOREBOARD)
			var column := _column()
			(
				assert_bool(_fixture.controls.safe_rect().encloses(rect))
				. override_failure_message(what)
				. is_true()
			)
			(
				assert_bool(rect.intersects(column))
				. override_failure_message(what + " is over the column")
				. is_false()
			)
			assert_bool(rect.get_center().x > column.get_center().x).is_equal(not left)
			for id: StringName in _fixture.controls.circles():
				(
					assert_float(_clearance(rect, _fixture.controls.circles()[id]))
					. override_failure_message("%s is over the %s button" % [what, id])
					. is_greater(0.0)
				)
			for zone in _fixture.hud.slots.touch_zones():
				(
					assert_bool(rect.intersects(zone[&"rect"]))
					. override_failure_message("%s is over %s" % [what, zone[&"action"]])
					. is_false()
				)
			await _fixture.touch(0, column.get_center())
			assert_bool(hints.is_seen(TouchHints.SCOREBOARD)).is_true()
			assert_array(hints.showing()).not_contains([TouchHints.SCOREBOARD])
			await _fixture.lift(0, column.get_center())
			await await_millis(250)
	)


func test_the_hint_waits_for_a_column_to_point_at() -> void:
	_fixture = TouchFixture.make(self, TouchFixture.PHONE, null, false, false)
	await _settle()
	assert_array(_fixture.controls.hints.showing()).not_contains([TouchHints.SCOREBOARD])


func test_a_desktop_hud_has_no_column_zone_and_its_ticket_is_where_it_was() -> void:
	var host: Control = auto_free(Control.new())
	host.size = Vector2(1920, 1080)
	add_child(host)
	var fixture := HudFixture.make(host, 4)
	await _settle()
	assert_dict(fixture.hud.scoreboard_zone()).is_empty()
	assert_array(fixture.hud.touch_zones()).is_empty()
	Input.action_press(&"scoreboard")
	await _settle()
	assert_bool(fixture.hud.scoreboard.visible).is_true()
	var holder := fixture.hud.scoreboard.get_parent() as Control
	assert_float(holder.scale.x).is_equal(1.0)
	assert_float(holder.offset_left).is_equal(0.0)
	assert_float(fixture.hud.scoreboard.card_rect().get_center().x).is_equal_approx(960.0, 1.0)
	Input.action_release(&"scoreboard")


func test_no_key_is_needed_for_it_on_a_phone() -> void:
	await _page(PAGES[1], 1.0, false, Vector2i(2, 0))
	assert_bool(Input.is_action_pressed(&"scoreboard")).is_false()
	assert_bool(Input.is_key_pressed(KEY_TAB)).is_false()
	await _fixture.touch(0, _column().get_center())
	await _settle()
	assert_bool(Input.is_action_pressed(&"scoreboard")).is_true()
	assert_bool(_fixture.hud.scoreboard.visible).is_true()
	await _fixture.lift(0)
