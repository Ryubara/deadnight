extends GdUnitTestSuite
## A marker's diamond and a teammate's tag are never under a card of the HUD or a touch button
## (Deadnight #1218): the words of an objective had been moved clear of the cards (#1192) and its
## diamond and the allies' tags had not, so a marker at a corner was drawn under the card there. A
## marker is put on the middle of every card and button, and on its corners, of the busiest HUD, on
## every page a player has, and what it draws is read where it was drawn. On a phone's page (a
## finger is the pointer) the words are 14 CSS px at least; on a desktop they are the 20 units they
## always were.

## A page is a window in pixels, the interface size and the pixel ratio the browser reports; the
## phone's own is 844 x 390 CSS px, which is a 1688 x 780 window at a ratio of 2.
const DESKTOPS: Array[Vector2i] = [
	Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(1024, 768)
]
## The last is a 667 x 375 CSS px phone: at 1.25 its canvas is 1536 x 864 units, the smallest.
const PHONES: Array[Vector3] = [
	Vector3(1688, 780, 2.0), Vector3(2532, 1170, 3.0), Vector3(1334, 750, 2.0)
]
const UI_SCALES: Array[float] = [0.8, 1.0, 1.25]
## How many markers `_one_on_every_card` puts under the cards at once, and how many of them are the
## next door's diamond (the night has one or two of those, and a teammate for every other marker).
## At the largest interface size the diamonds are fewer: one.
const EIGHT := 8
const DIAMONDS := 3
## How many markers each page keeps clear of each other as well as of the cards, in the test below:
## at the largest interface size (1.25) the cards, the buttons and the words are as big as they get,
## and the one column left between them on the smallest canvas (a 667 x 375 CSS px phone is
## 1536 x 864 units, a diamond's words 319 of the column's 344) holds four markers, a diamond and
## three teammates. More are kept off the cards and the buttons but meet each other (#1230).
const LARGEST_SCALE := 1.25
const SMALLEST_HOLDS := 4
## The smallest page there is.
const SMALLEST := Vector3(1334, 750, 1.25)
## The same small phone at the usual interface size: with the weapon strip a fingertip high and the
## right thumb's ring (#1280, #1277) it holds six markers, not eight, before two meet.
const CROWDED := Vector3(1334, 750, 1.0)
const CROWDED_HOLDS := 6
## With Strike up (#1285) its place, in the one column the markers have, is theirs no more: the
## smallest page holds two markers (one a diamond) before two meet, and the crowded page holds eight
## with Strike and Interact both up. They are kept off every card and button all the same.
const STRIKE_HOLDS_SMALLEST := 2
const STRIKE_AND_INTERACT_HOLDS_CROWDED := 8
## The least size of words, CSS px: what the issue and the written floor say.
const FLOOR_CSS := 14.0
## The buttons that show only when they apply.
const CONTEXTUAL: Array[StringName] = [TouchLayout.INTERACT, TouchLayout.STRIKE]

var _window_size := Vector2i.ZERO
var _window_factor := 1.0


func before_test() -> void:
	_window_size = get_window().size
	_window_factor = get_window().content_scale_factor
	TouchMode.device_is_touch = null


func after_test() -> void:
	get_window().size = _window_size
	get_window().content_scale_factor = _window_factor
	MenuScale.pixel_ratio = -1.0
	TouchMode.device_is_touch = null
	UIMotion.reduced = false


## Puts the test's window where a player's is and gives back the canvas it makes.
func _page(window: Vector2i, ui_scale: float, ratio: float) -> Vector2:
	get_window().size = window
	get_window().content_scale_factor = ui_scale
	MenuScale.pixel_ratio = ratio
	return Vector2(window) / MenuScale.pixels_per_unit(window, ui_scale)


## `with_bot`: one of the bodies is a bot, so the bots' tag is up on a phone (#1286).
func _busy_hud(
	canvas: Vector2, insets: Vector4, mirrored: bool, touch: bool, with_bot := true
) -> HudFixture:
	var host: Control = auto_free(Control.new())
	host.size = canvas
	add_child(host)
	var fixture := HudFixture.make(host, NightHost.MAX_PLAYERS)
	var hud := fixture.hud
	hud.mirrored = mirrored
	hud.touch_layout = touch
	hud.set_safe_insets(insets)
	fixture.into_round_one()
	var state := hud.state
	if touch and with_bot:
		state.apply_event({"type": &"player_added", "player_id": 3, "bot": true})
	state.set_ammo(30, 150, "Shotgun")
	state.set_equipment("Flare", 2)
	state.set_area("The Concession Stand", "Light the booth to open the back lot")
	fixture.give_perks(fixture.rules.tuning.economy.max_tonics)
	fixture.act(RulesAction.set_downed(2, true))
	for text in ["RUBY OPENED THE PROJECTION BOOTH", "GENERATOR RUNNING LOW", "MOE IS DOWN"]:
		hud.events_feed.push(text)
	hud.notices.push("CAL CONNECTED")
	hud.fuel.peek()
	fixture.advance(1.0)
	return fixture


## The cards of the middle of the screen up as well as the banner of round one: the prompt of a door
## in reach and the card of a level gained (the lane of the progression's cards, stepped by hand).
func _show_centre_cards(fixture: HudFixture) -> void:
	var hud := fixture.hud
	hud.popups.process_mode = Node.PROCESS_MODE_DISABLED
	# The banner too: its slide in and out runs on real time, and a grid walked over a second or two of
	# frames read it in three places (the failures of a loaded machine).
	hud.banner.process_mode = Node.PROCESS_MODE_DISABLED
	hud.state.set_prompt(&"buy_door", "Projection booth", 750)
	hud.state.apply_event({"type": &"level_up", "player_id": 1, "level": 15, "total": 0})
	await await_idle_frame()
	await await_idle_frame()
	for _i in 20:
		hud.popups.advance(0.05)
	await await_idle_frame()
	await await_idle_frame()


## The touch buttons of a phone held sideways, as the controls lay them out, in the canvas's units.
## Interact and Strike are not among them while they are not up (`TouchControls.button_boxes` leaves
## a button out then, as it is not drawn): the right thumb's five buttons are always there, and
## `up` names the contextual ones that are.
func _buttons(safe: Rect2, mirrored: bool, up: Array[StringName] = []) -> Array[Rect2]:
	var boxes: Array[Rect2] = []
	# The night's fingertip rule: Ping stands a fingertip-sized length under Pause (#1289).
	var finger := MenuScale.tap_units(get_window(), true)
	var circles := TouchLayout.buttons(safe, 1.0, mirrored, finger)
	for id: StringName in circles:
		if id in CONTEXTUAL and not id in up:
			continue
		var circle: Dictionary = circles[id]
		var reach := Vector2.ONE * float(circle[&"radius"])
		boxes.append(Rect2(Vector2(circle[&"centre"]) - reach, reach * 2.0))
	return boxes


## What a marker must stay out of: the cards that are shown (those of the corners and of the middle)
## and the touch buttons, in the
## markers' own units.
func _obstacles(fixture: HudFixture, held: Array[Rect2]) -> Array[Rect2]:
	var found: Array[Rect2] = []
	var origin := fixture.hud.markers.get_global_rect().position
	for card in fixture.hud.corner_cards() + fixture.hud.centre_cards():
		if card.is_visible_in_tree() and card.size != Vector2.ZERO:
			found.append(Rect2(card.get_global_rect().position - origin, card.size))
	found.append_array(held)
	return found


## Markers of each kind on the middle and the four corners of every obstacle, normalised to the
## markers' screen.
func _markers(obstacles: Array[Rect2], screen: Vector2, only := -1) -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	var n := 0
	for rect in obstacles:
		var spots: Array[Vector2] = [
			rect.get_center(),
			rect.position,
			Vector2(rect.end.x, rect.position.y),
			rect.end,
			Vector2(rect.position.x, rect.end.y),
		]
		for spot in spots.size():
			if only >= 0 and spot != only:
				continue
			var share := spots[spot] / screen
			for kind in 5:
				var marker := HudFixture.late_marker(
					StringName("m%d" % n),
					&"objective" if kind == 0 else &"ally",
					share.x,
					share.y,
					30.0,
					"Concession Stand" if kind == 0 else ["Ruby", "Moe", "Dee", "Cal"][n % 4],
					kind >= 3
				)
				marker["dead"] = kind == 4
				if kind == 2 or kind == 3:
					marker["level"] = 7 + n % 40
					marker["icon"] = marker["level"]
				list.append(marker)
				n += 1
	return list


## The sentences of every marker that is drawn under an obstacle, or that moved without an arrow
## back to the place it marks.
func _faults(fixture: HudFixture, obstacles: Array[Rect2], where: String) -> Array[String]:
	var found: Array[String] = []
	var markers := fixture.hud.markers
	assert_int(markers.shown.size()).is_greater(0)
	for id: StringName in markers.shown:
		var drawn: Dictionary = markers.shown[id]
		var box: Rect2 = drawn["box"]
		for rect in obstacles:
			if box.intersects(rect):
				found.append("%s: %s %s is under %s" % [where, id, box, rect])
		if bool(drawn["moved"]):
			var back: Vector2 = Vector2(markers.placed[id]["target"]) - Vector2(drawn["at"])
			if Vector2(drawn["arrow"]).dot(back.normalized()) < 0.99:
				found.append("%s: %s moved with no arrow back to its place" % [where, id])
		elif not Vector2(drawn["at"]).is_equal_approx(Vector2(markers.placed[id]["at"])):
			found.append("%s: %s is off its place and not moved" % [where, id])
	for id: StringName in markers.labels:
		for rect in obstacles:
			if Rect2(markers.labels[id]).intersects(rect):
				found.append("%s: the words of %s are under %s" % [where, id, rect])
	return found


## Every marker of the grid on one page, with the touch layer up or not and `up` of its contextual
## buttons (Interact, Strike) showing.
func _run_page(
	window: Vector2i, ui_scale: float, ratio: float, touch: bool, up: Array[StringName] = []
) -> Array[String]:
	var found: Array[String] = []
	var canvas := _page(window, ui_scale, ratio)
	TouchMode.device_is_touch = touch
	var insets := Vector4(96.0, 0.0, 96.0, 24.0) if touch else Vector4.ZERO
	for mirrored in [false, true]:
		var fixture := _busy_hud(canvas, insets, mirrored, touch)
		await _show_centre_cards(fixture)
		var held: Array[Rect2] = []
		if touch:
			held = _buttons(TouchLayout.safe_rect(canvas, insets), mirrored, up)
		fixture.hud.markers.held = held
		var obstacles := _obstacles(fixture, held)
		var where := (
			"%s at %s, ratio %s%s%s"
			% [
				window,
				ui_scale,
				ratio,
				", touch" if touch else "",
				", mirrored" if mirrored else ""
			]
		)
		# One spot's five kinds of marker at a time, as a night has a few markers and not three hundred.
		for rect in obstacles:
			for spot in 5:
				fixture.hud.state.set_markers(_markers([rect], fixture.hud.markers.size, spot))
				await await_idle_frame()
				await await_idle_frame()
				# The cards as they stand when the markers have settled: a card that is still sliding in
				# (the banner) is read where it is now, not where it was when the grid was made.
				found.append_array(_faults(fixture, _obstacles(fixture, held), where))
		fixture.hud.get_parent().queue_free()
	return found


func test_a_marker_is_never_under_a_card_on_a_desktop() -> void:
	var found: Array[String] = []
	for window in DESKTOPS:
		for ui_scale in UI_SCALES:
			found.append_array(await _run_page(window, ui_scale, 1.0, false))
	assert_array(found).is_empty()


func test_a_marker_is_never_under_a_card_or_a_button_on_a_phones_page() -> void:
	var found: Array[String] = []
	for page in PHONES:
		for ui_scale in UI_SCALES:
			found.append_array(
				await _run_page(Vector2i(int(page.x), int(page.y)), ui_scale, page.z, true)
			)
	assert_array(found).is_empty()


func test_a_marker_is_never_under_strike_or_interact_while_they_are_up() -> void:
	var up: Array[StringName] = [TouchLayout.STRIKE, TouchLayout.INTERACT]
	var found: Array[String] = []
	for page in PHONES:
		for ui_scale in UI_SCALES:
			found.append_array(
				await _run_page(Vector2i(int(page.x), int(page.y)), ui_scale, page.z, true, up)
			)
	assert_array(found).is_empty()


func test_a_marker_on_free_ground_stays_where_it_points() -> void:
	var canvas := _page(Vector2i(1920, 1080), 1.0, 1.0)
	var fixture := _busy_hud(canvas, Vector4.ZERO, false, false)
	await await_idle_frame()
	var list: Array[Dictionary] = [
		HudFixture.late_marker(&"door", &"objective", 0.5, 0.3, 20.0, "Booth", false),
		HudFixture.late_marker(&"moe", &"ally", 0.55, 0.6, 12.0, "Moe", false),
		HudFixture.late_marker(&"dee", &"ally", 0.45, 0.62, 12.0, "Dee", true),
	]
	fixture.hud.state.set_markers(list)
	await await_idle_frame()
	await await_idle_frame()
	var markers := fixture.hud.markers
	for id: StringName in [&"door", &"moe", &"dee"]:
		assert_bool(markers.shown[id]["moved"]).is_false()
		assert_vector(markers.shown[id]["at"]).is_equal(markers.placed[id]["at"])
		assert_vector(markers.shown[id]["arrow"]).is_equal(Vector2.ZERO)
	fixture.hud.get_parent().queue_free()


func test_the_words_read_at_14_css_px_on_a_phones_page() -> void:
	for page in PHONES:
		for ui_scale in UI_SCALES:
			var window := Vector2i(int(page.x), int(page.y))
			var canvas := _page(window, ui_scale, page.z)
			TouchMode.device_is_touch = true
			var fixture := _busy_hud(canvas, Vector4.ZERO, false, true)
			await await_idle_frame()
			var markers := fixture.hud.markers
			var css_per_unit := MenuScale.pixels_per_unit(window, ui_scale) / page.z
			var css := markers.label_size * css_per_unit
			var where := "%s at %s" % [window, ui_scale]
			assert_float(css).override_failure_message("%s: %s CSS px" % [where, css]).is_greater(
				FLOOR_CSS - 0.001
			)
			# No bigger than the floor needs, to a unit.
			assert_float(css).is_less(FLOOR_CSS + css_per_unit + 0.001)
			# What is drawn is that size: a tag's name and an objective's words.
			(
				fixture
				. hud
				. state
				. set_markers(
					(
						[
							HudFixture.late_marker(
								&"door", &"objective", 0.5, 0.3, 20.0, "Booth", false
							),
							HudFixture.late_marker(&"moe", &"ally", 0.5, 0.6, 12.0, "Moe", false),
						]
						as Array[Dictionary]
					)
				)
			)
			await await_idle_frame()
			await await_idle_frame()
			assert_float(Rect2(markers.labels[&"door"]).size.y).is_equal(float(markers.label_size))
			assert_float(Rect2(markers.tags[&"moe"]).size.y).is_equal(float(markers.label_size))
			fixture.hud.get_parent().queue_free()


func test_a_desktop_keeps_the_size_it_had() -> void:
	for window in DESKTOPS:
		for ui_scale in UI_SCALES:
			var canvas := _page(window, ui_scale, 1.0)
			var fixture := _busy_hud(canvas, Vector4.ZERO, false, false)
			await await_idle_frame()
			assert_int(fixture.hud.markers.label_size).is_equal(HudStyle.MIN_TEXT)
			fixture.hud.get_parent().queue_free()
	# A laptop with a touch screen at 1920 x 1080: 14 CSS px are 14 units, under the 20 it had.
	var canvas := _page(Vector2i(1920, 1080), 1.0, 1.0)
	TouchMode.device_is_touch = true
	var touch_laptop := _busy_hud(canvas, Vector4.ZERO, false, true)
	await await_idle_frame()
	assert_int(touch_laptop.hud.markers.label_size).is_equal(HudStyle.MIN_TEXT)
	touch_laptop.hud.get_parent().queue_free()


func test_a_window_too_small_to_read_anything_does_not_blow_the_words_up() -> void:
	var window := Window.new()
	window.size = Vector2i(64, 64)
	auto_free(window)
	var units := MenuScale.text_units(window, true, HudStyle.MIN_TEXT)
	# The canvas of a 64 x 64 window is 1920 x 1920 units: 14 CSS px would ask for 420 there.
	var canvas_height := 64.0 / MenuScale.pixels_per_unit(window.size, 1.0)
	assert_int(units).is_less_equal(floori(canvas_height * MenuScale.TEXT_SHARE_MAX))
	assert_int(units).is_less(120)


func test_moving_markers_adds_no_canvas_item() -> void:
	# The night's canvas items are held to a budget (tools/perf/budget.json): a marker is drawn in the
	# one item of its part, wherever it is put.
	var canvas := _page(Vector2i(1688, 780), 1.0, 2.0)
	TouchMode.device_is_touch = true
	var fixture := _busy_hud(canvas, Vector4.ZERO, false, true)
	await await_idle_frame()
	var before := fixture.hud.find_children("*", "CanvasItem", true, false).size()
	var obstacles := _obstacles(fixture, [])
	fixture.hud.state.set_markers(_markers(obstacles, fixture.hud.markers.size))
	await await_idle_frame()
	await await_idle_frame()
	assert_int(fixture.hud.markers.shown.size()).is_greater(100)
	assert_int(fixture.hud.find_children("*", "CanvasItem", true, false).size()).is_equal(before)
	assert_int(fixture.hud.markers.get_child_count()).is_equal(0)
	fixture.hud.get_parent().queue_free()


func test_markers_moved_off_neighbouring_cards_do_not_land_on_each_other() -> void:
	# The objective off the health card and a teammate down on the round card both want the pocket
	# between the cards of the left column (the first capture drew one over the other).
	var canvas := _page(Vector2i(1688, 780), 1.0, 2.0)
	TouchMode.device_is_touch = true
	var fixture := _busy_hud(canvas, Vector4.ZERO, false, true)
	await await_idle_frame()
	var markers := fixture.hud.markers
	var origin := markers.get_global_rect().position
	var list: Array[Dictionary] = []
	var n := 0
	for card: Control in [fixture.hud.health, fixture.hud.round_part, fixture.hud.points]:
		var share := (card.get_global_rect().get_center() - origin) / markers.size
		var down := n == 1
		var marker := HudFixture.late_marker(
			StringName("m%d" % n),
			&"objective" if n == 0 else &"ally",
			share.x,
			share.y,
			30.0,
			"Concession Stand" if n == 0 else "Ruby",
			down
		)
		list.append(marker)
		n += 1
	fixture.hud.state.set_markers(list)
	await await_idle_frame()
	await await_idle_frame()
	for i in 3:
		assert_bool(markers.shown[StringName("m%d" % i)]["moved"]).is_true()
		for j in range(i + 1, 3):
			var one: Rect2 = markers.shown[StringName("m%d" % i)]["box"]
			var other: Rect2 = markers.shown[StringName("m%d" % j)]["box"]
			(
				assert_bool(one.intersects(other))
				. override_failure_message("m%d %s is over m%d %s" % [i, one, j, other])
				. is_false()
			)
	fixture.hud.get_parent().queue_free()


## One marker on the middle of every card shown, in turn an objective, a teammate and a body on the
## ground (the night's capture of the eight): the boxes they took on the last frame.
func _one_on_every_card(fixture: HudFixture, count: int, diamonds: int) -> Dictionary:
	var markers := fixture.hud.markers
	var origin := markers.get_global_rect().position
	var list: Array[Dictionary] = []
	var n := 0
	for card in fixture.hud.corner_cards():
		if not card.is_visible_in_tree() or card.size == Vector2.ZERO or n >= count:
			continue
		var share := (card.get_global_rect().get_center() - origin) / markers.size
		var marker := HudFixture.late_marker(
			StringName("m%d" % n),
			&"objective" if n % 3 == 0 and n / 3 < diamonds else &"ally",
			share.x,
			share.y,
			30.0,
			(
				"Concession Stand"
				if n % 3 == 0 and n / 3 < diamonds
				else ["Ruby", "Moe", "Cal", "Dee"][n % 4]
			),
			n % 3 == 2
		)
		if n % 3 == 1:
			marker["level"] = 3 + n * 7
			marker["icon"] = marker["level"]
		list.append(marker)
		n += 1
	fixture.hud.state.set_markers(list)
	await await_idle_frame()
	await await_idle_frame()
	return markers.shown


## The sentences of every pair of markers whose rectangles meet.
func _touching(shown: Dictionary, where: String) -> Array[String]:
	var found: Array[String] = []
	var ids := shown.keys()
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			var one: Rect2 = shown[ids[i]]["box"]
			var other: Rect2 = shown[ids[j]]["box"]
			if one.intersects(other):
				found.append("%s: %s %s meets %s %s" % [where, ids[i], one, ids[j], other])
	return found


func test_markers_one_on_each_card_keep_clear_of_the_cards_and_of_each_other() -> void:
	var found: Array[String] = []
	for page in PHONES:
		for ui_scale in UI_SCALES:
			var window := Vector2i(int(page.x), int(page.y))
			var canvas := _page(window, ui_scale, page.z)
			TouchMode.device_is_touch = true
			var insets := Vector4(96.0, 0.0, 96.0, 24.0)
			var largest := ui_scale == LARGEST_SCALE
			var smallest := Vector3(page.x, page.y, ui_scale) == SMALLEST
			var count := SMALLEST_HOLDS if smallest else EIGHT
			if Vector3(page.x, page.y, ui_scale) == CROWDED:
				count = CROWDED_HOLDS
			for mirrored in [false, true]:
				var fixture := _busy_hud(canvas, insets, mirrored, true)
				await _show_centre_cards(fixture)
				var held := _buttons(TouchLayout.safe_rect(canvas, insets), mirrored)
				fixture.hud.markers.held = held
				var where := "%s at %s%s" % [window, ui_scale, ", mirrored" if mirrored else ""]
				var shown := await _one_on_every_card(fixture, count, 1 if largest else DIAMONDS)
				assert_int(shown.size()).is_equal(count)
				found.append_array(_faults(fixture, _obstacles(fixture, held), where))
				found.append_array(_touching(shown, where))
				fixture.hud.get_parent().queue_free()
	assert_array(found).is_empty()


func test_the_smallest_page_keeps_eight_markers_off_every_card_and_button() -> void:
	# Eight, three of them diamonds, one on each card: more than the one column left holds, so some
	# meet each other, and none is under a card, a button, the banner, the prompt or a popup card.
	var window := Vector2i(int(SMALLEST.x), int(SMALLEST.y))
	var canvas := _page(window, SMALLEST.z, 2.0)
	TouchMode.device_is_touch = true
	var insets := Vector4(96.0, 0.0, 96.0, 24.0)
	var found: Array[String] = []
	for mirrored in [false, true]:
		var fixture := _busy_hud(canvas, insets, mirrored, true)
		await _show_centre_cards(fixture)
		var held := _buttons(TouchLayout.safe_rect(canvas, insets), mirrored)
		fixture.hud.markers.held = held
		var shown := await _one_on_every_card(fixture, EIGHT, DIAMONDS)
		assert_int(shown.size()).is_equal(EIGHT)
		found.append_array(_faults(fixture, _obstacles(fixture, held), "smallest"))
		fixture.hud.get_parent().queue_free()
	assert_array(found).is_empty()


func test_the_smallest_page_keeps_markers_off_the_interact_button_while_it_is_up() -> void:
	# Something to use: the interact button is up too, and a marker is under none of the buttons.
	var window := Vector2i(int(SMALLEST.x), int(SMALLEST.y))
	var canvas := _page(window, SMALLEST.z, 2.0)
	TouchMode.device_is_touch = true
	var insets := Vector4(96.0, 0.0, 96.0, 24.0)
	var found: Array[String] = []
	for mirrored in [false, true]:
		var fixture := _busy_hud(canvas, insets, mirrored, true)
		await _show_centre_cards(fixture)
		var held := _buttons(
			TouchLayout.safe_rect(canvas, insets), mirrored, [TouchLayout.INTERACT]
		)
		fixture.hud.markers.held = held
		var shown := await _one_on_every_card(fixture, SMALLEST_HOLDS, 1)
		assert_int(shown.size()).is_equal(SMALLEST_HOLDS)
		found.append_array(_faults(fixture, _obstacles(fixture, held), "interact up"))
		fixture.hud.get_parent().queue_free()
	assert_array(found).is_empty()


## One marker on every card of the busiest HUD on `page`, with `up` buttons up as well as the
## right thumb's five: `count` of them, `diamonds` of those the next door's, none under a card or a
## button and none meeting another, for either hand.
func _holds_with(page: Vector3, up: Array[StringName], count: int, diamonds: int) -> Array[String]:
	var window := Vector2i(int(page.x), int(page.y))
	var canvas := _page(window, page.z, 2.0)
	TouchMode.device_is_touch = true
	var insets := Vector4(96.0, 0.0, 96.0, 24.0)
	var found: Array[String] = []
	for mirrored in [false, true]:
		var fixture := _busy_hud(canvas, insets, mirrored, true)
		await _show_centre_cards(fixture)
		var held := _buttons(TouchLayout.safe_rect(canvas, insets), mirrored, up)
		fixture.hud.markers.held = held
		var where := "%s at %s%s" % [window, page.z, ", mirrored" if mirrored else ""]
		var shown := await _one_on_every_card(fixture, count, diamonds)
		assert_int(shown.size()).is_equal(count)
		found.append_array(_faults(fixture, _obstacles(fixture, held), where))
		found.append_array(_touching(shown, where))
		fixture.hud.get_parent().queue_free()
	return found


func test_the_smallest_page_keeps_markers_off_the_strike_button_while_it_is_up() -> void:
	var found := await _holds_with(SMALLEST, [TouchLayout.STRIKE], STRIKE_HOLDS_SMALLEST, 1)
	assert_array(found).is_empty()


func test_the_crowded_page_keeps_markers_off_strike_and_interact_while_both_are_up() -> void:
	var up: Array[StringName] = [TouchLayout.STRIKE, TouchLayout.INTERACT]
	var found := await _holds_with(CROWDED, up, STRIKE_AND_INTERACT_HOLDS_CROWDED, DIAMONDS)
	assert_array(found).is_empty()


func test_a_marker_keeps_clear_of_the_banner_the_prompt_and_a_popup_card() -> void:
	# A desktop, a phone's page, and the smallest page there is: the window, the interface size and
	# the pixel ratio.
	var pages: Array[Array] = [
		[Vector2i(1920, 1080), 1.0, 1.0],
		[Vector2i(1688, 780), 1.0, 2.0],
		[Vector2i(1334, 750), 1.25, 2.0]
	]
	for page in pages:
		var desktop: bool = page[2] == 1.0
		var window: Vector2i = page[0]
		var canvas := _page(window, page[1], page[2])
		TouchMode.device_is_touch = not desktop
		var insets := Vector4.ZERO if desktop else Vector4(96.0, 0.0, 96.0, 24.0)
		var fixture := _busy_hud(canvas, insets, false, not desktop)
		await _show_centre_cards(fixture)
		var hud := fixture.hud
		var held: Array[Rect2] = []
		if not desktop:
			held = _buttons(TouchLayout.safe_rect(canvas, insets), false)
		hud.markers.held = held
		var origin := hud.markers.get_global_rect().position
		var cards := hud.centre_cards()
		var middle: Array[Rect2] = []
		for card in [hud.banner, hud.prompt, hud.popups]:
			assert_bool(card.is_visible_in_tree()).is_true()
			assert_vector(card.size).is_not_equal(Vector2.ZERO)
			middle.append(Rect2(card.get_global_rect().position - origin, card.size))
		assert_int(cards.size()).is_equal(5)
		for rect in middle:
			for spot in 5:
				hud.state.set_markers(_markers([rect], hud.markers.size, spot))
				await await_idle_frame()
				await await_idle_frame()
				var found := _faults(fixture, _obstacles(fixture, held), "%s" % window)
				assert_array(found).is_empty()
		fixture.hud.get_parent().queue_free()


func test_a_tag_at_the_top_edge_stays_on_the_screen() -> void:
	for page in [Vector3(1920, 1080, 1.0), Vector3(1688, 780, 2.0)]:
		var desktop: bool = page.z == 1.0
		var window := Vector2i(int(page.x), int(page.y))
		var canvas := _page(window, 1.0, page.z)
		TouchMode.device_is_touch = not desktop
		var fixture := _busy_hud(canvas, Vector4.ZERO, false, not desktop)
		await await_idle_frame()
		var markers := fixture.hud.markers
		var list: Array[Dictionary] = []
		var n := 0
		for top in [0.0, 0.004, 0.02, 0.05]:
			for across in [0.4, 0.5, 0.6, 0.95]:
				var marker := HudFixture.late_marker(
					StringName("t%d" % n), &"ally", across, top, 12.0, "Ruby", n % 4 >= 2
				)
				marker["dead"] = n % 4 == 3
				if n % 2 == 1:
					marker["level"] = 7 + n
					marker["icon"] = marker["level"]
				list.append(marker)
				n += 1
		fixture.hud.state.set_markers(list)
		await await_idle_frame()
		await await_idle_frame()
		assert_int(markers.tags.size()).is_equal(n)
		for id: StringName in markers.tags:
			var tag: Rect2 = markers.tags[id]
			var inside := Rect2(Vector2.ZERO, markers.size)
			(
				assert_bool(inside.encloses(tag))
				. override_failure_message(
					"%s: the tag %s is not on the screen %s" % [id, tag, inside]
				)
				. is_true()
			)
		fixture.hud.get_parent().queue_free()
