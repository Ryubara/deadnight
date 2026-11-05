extends GdUnitTestSuite
## The challenge prompt on the HUD: it appears for a quarter mark, a finish and a milestone step,
## says the right thing in the right words, honours the player's setting, reduced motion and being
## down, and never sits over the crosshair, the round counter or any other part at any canvas the
## game runs at (the desktop windows and a phone held sideways), with the touch layout on and a
## room's eight players too: the strip a fingertip high lifts the players' column to meet the card
## at 0.36 of the screen's height, and the card stands beside the column then (#1299).

const CANVASES: Array[Vector2] = [
	Vector2(1536, 864),
	Vector2(1920, 1080),
	Vector2(2560, 1080),
	Vector2(2340, 1080),
	Vector2(2880, 1620),
]
## The clear box round the middle of the screen, canvas units: the reticle and its hit markers.
const CROSSHAIR_CLEAR := Vector2(160.0, 160.0)
## A page is a window in pixels, the interface size and the pixel ratio the browser reports: a
## phone's 844 x 390 CSS px at ratio 2 is a 1688 x 780 window (a 2337 x 1080 canvas at the usual
## size), a 667 x 375 one is 1334 x 750 (1536 x 864 at 1.25, the smallest canvas there is).
const PHONES: Array[Vector3] = [Vector3(1688, 780, 2.0), Vector3(1334, 750, 2.0)]
const UI_SCALES: Array[float] = [0.8, 1.0, 1.25]
## The parts that come and go, which the card keeps off when it can and meets, as the last resort
## on the smallest page, rather than stand over the cards that stay or a button (`ChallengeFit`).
const SOFT: Array[StringName] = [
	&"Fuel",
	&"Events",
	&"Notices",
	&"Banner",
	&"Marquee",
	&"BossBar",
	&"Prompt",
	&"Popups",
	&"Gains"
]
## The platform's safe area on a phone held sideways (a notch and a home bar), canvas units.
const NOTCH := Vector4(96.0, 0.0, 96.0, 24.0)

var _host: Control
var _fixture: HudFixture
var _hud: Hud
var _window_size := Vector2i.ZERO
var _window_factor := 1.0


func before_test() -> void:
	_window_size = get_window().size
	_window_factor = get_window().content_scale_factor
	UIMotion.reduced = false
	_make(Vector2(1920, 1080))


func after_test() -> void:
	get_window().size = _window_size
	get_window().content_scale_factor = _window_factor
	MenuScale.pixel_ratio = -1.0
	TouchMode.device_is_touch = null
	UIMotion.reduced = false


func _make(canvas: Vector2, players := 1, bots := 0) -> void:
	_host = auto_free(Control.new())
	_host.size = canvas
	add_child(_host)
	_fixture = HudFixture.make(_host, players, 1958, false, bots)
	_hud = _fixture.hud
	_fixture.into_round_one()


func _advance_event(id: StringName, extra := {}) -> Dictionary:
	var event := {
		"type": HudChallenge.EVENT,
		"id": id,
		"family": ChallengeDef.Family.DAILY,
		"text": "Put down 40 zombies",
		"before": 9,
		"after": 10,
		"target": 40,
		"checkpoint": 25,
		"completed": false,
		"rung": 0,
		"rungs": 0,
	}
	event.merge(extra, true)
	return event


func _run(seconds: float) -> void:
	var left := seconds
	while left > 0.0:
		_hud.challenge.advance(0.05)
		left -= 0.05


func _rect(part: Control) -> Rect2:
	return Rect2(part.get_global_rect())


func test_a_quarter_mark_shows_a_card_with_the_count_and_one_hole_punched() -> void:
	_hud.state.apply_event(_advance_event(&"d_kills"))
	assert_bool(_hud.challenge.visible).is_false()
	_run(0.5)
	assert_bool(_hud.challenge.visible).is_true()
	var card := _hud.challenge.card
	assert_str(card.count.text).is_equal("10 / 40")
	assert_str(card.words.text).is_equal("Put down 40 zombies")
	assert_str(card.caption.text).is_equal("TODAY")
	assert_that(card.holes()).is_equal(Vector2i(1, 4))


func test_each_quarter_punches_one_more_hole() -> void:
	for mark in [25, 50, 75]:
		var event := _advance_event(StringName("m%d" % mark), {"checkpoint": mark})
		_hud.state.apply_event(event)
		_run(0.5)
		assert_that(_hud.challenge.card.holes()).is_equal(Vector2i(mark / 25, 4))
		_run(5.0)


func test_a_finish_punches_the_last_hole_and_says_finished() -> void:
	# With the popup cards on, a finish is a card of the lane (test_popup_lane.gd); the prompt says it
	# itself when the player turned the cards off.
	_hud.popups.mode = PopupLane.Mode.OFF
	_hud.state.apply_event(
		_advance_event(&"d_kills", {"after": 40, "checkpoint": 100, "completed": true})
	)
	_run(0.5)
	assert_str(_hud.challenge.card.caption.text).is_equal("FINISHED")
	assert_str(_hud.challenge.card.count.text).is_equal("40 / 40")
	assert_that(_hud.challenge.card.holes()).is_equal(Vector2i(4, 4))


func test_an_order_and_a_milestone_say_what_they_are() -> void:
	_hud.state.apply_event(_advance_event(&"o_x", {"family": ChallengeDef.Family.ORDER}))
	_run(0.5)
	assert_str(_hud.challenge.card.caption.text).is_equal("ORDER")
	_run(6.0)
	(
		_hud
		. state
		. apply_event(
			_advance_event(
				&"m_kills",
				{
					"family": ChallengeDef.Family.MILESTONE,
					"checkpoint": 0,
					"rung": 3,
					"rungs": 7,
					"target": 1000,
					"after": 1004,
					"text": "Put down 1000 zombies",
					"completed": false,
				}
			)
		)
	)
	_run(0.5)
	assert_str(_hud.challenge.card.caption.text).is_equal("MILESTONE")
	assert_str(_hud.challenge.card.count.text).is_equal("1000")
	assert_that(_hud.challenge.card.holes()).is_equal(Vector2i(3, 7))


func test_an_advance_that_is_no_step_shows_nothing() -> void:
	_hud.state.apply_event(_advance_event(&"d_kills", {"checkpoint": 0}))
	_run(1.0)
	assert_bool(_hud.challenge.visible).is_false()


func test_the_card_fades_in_and_out_and_slides_from_the_edge() -> void:
	_hud.state.apply_event(_advance_event(&"d_kills"))
	_hud.challenge.advance(0.05)
	_hud.challenge.advance(0.05)
	var card := _hud.challenge.card
	assert_float(card.modulate.a).is_between(0.05, 0.95)
	assert_float(card.position.x).is_less(0.0)
	_run(0.5)
	assert_float(card.modulate.a).is_equal(1.0)
	assert_float(card.position.x).is_equal(0.0)
	_run(HudTuning.current().challenge_hold)
	assert_float(card.modulate.a).is_less(1.0)
	_run(HudTuning.current().challenge_out + 0.2)
	assert_bool(_hud.challenge.visible).is_false()


func test_reduced_motion_fades_without_sliding() -> void:
	UIMotion.reduced = true
	_hud.state.apply_event(_advance_event(&"d_kills"))
	_hud.challenge.advance(0.05)
	_hud.challenge.advance(0.05)
	assert_float(_hud.challenge.card.position.x).is_equal(0.0)
	assert_float(_hud.challenge.card.modulate.a).is_less(1.0)


func test_a_card_asks_for_its_sound_once_a_tick_for_a_mark_and_a_pair_for_a_finish() -> void:
	var cues: Array[bool] = []
	_hud.challenge.cue.connect(func(finished: bool) -> void: cues.append(finished))
	_hud.state.apply_event(_advance_event(&"a"))
	_run(0.5)
	# The same challenge moving again while it shows is the same card: no second sound.
	_hud.state.apply_event(_advance_event(&"a", {"checkpoint": 50, "after": 20}))
	_run(0.3)
	assert_array(cues).is_equal([false])
	_run(6.0)
	_hud.popups.mode = PopupLane.Mode.OFF
	_hud.state.apply_event(
		_advance_event(&"b", {"checkpoint": 100, "after": 40, "completed": true})
	)
	_run(0.5)
	assert_array(cues).is_equal([false, true])


func test_the_setting_limits_or_silences_the_prompts() -> void:
	_hud.challenge.mode = HudChallenge.Mode.FINISHED_ONLY
	_hud.state.apply_event(_advance_event(&"a"))
	_run(1.0)
	assert_bool(_hud.challenge.visible).is_false()
	_hud.state.apply_event(_advance_event(&"b", {"checkpoint": 0, "rung": 1, "rungs": 4}))
	_run(0.5)
	assert_bool(_hud.challenge.visible).is_true()
	_run(6.0)
	_hud.challenge.mode = HudChallenge.Mode.OFF
	_hud.state.apply_event(
		_advance_event(&"c", {"checkpoint": 100, "after": 40, "completed": true})
	)
	_run(1.0)
	assert_bool(_hud.challenge.visible).is_false()
	assert_int(_hud.challenge.queue.waiting_count()).is_equal(0)


func test_nothing_starts_while_the_local_player_is_down() -> void:
	_fixture.act(RulesAction.set_downed(1, true))
	_hud.state.apply_event(_advance_event(&"a"))
	_run(2.0)
	assert_bool(_hud.challenge.visible).is_false()
	_fixture.act(RulesAction.set_downed(1, false))
	_run(0.5)
	assert_bool(_hud.challenge.visible).is_true()


func test_the_card_makes_no_new_nodes_while_it_shows_and_changes() -> void:
	var made := [0]
	var count := func(node: Node) -> void:
		if is_instance_valid(_hud) and _hud.is_ancestor_of(node):
			made[0] += 1
	get_tree().node_added.connect(count)
	_hud.state.apply_event(_advance_event(&"a"))
	_run(0.5)
	var before: int = made[0]
	for i in 10:
		_hud.state.apply_event(_advance_event(&"a", {"after": 11 + i, "checkpoint": 25}))
		_run(0.2)
	get_tree().node_added.disconnect(count)
	assert_int(made[0]).is_equal(before)


func test_it_stays_clear_of_the_crosshair_and_every_other_part_at_every_canvas() -> void:
	for canvas in CANVASES:
		for mirrored in [false, true]:
			for touch in [false, true]:
				_make(canvas, 4)
				_hud.mirrored = mirrored
				_hud.touch_layout = touch
				_busy_night()
				_raise_the_card()
				await _settle()
				var label := (
					"%s%s%s" % [canvas, " mirrored" if mirrored else "", " touch" if touch else ""]
				)
				assert_array(_faults(label, canvas, [])).is_empty()


## The busiest night a room has on a phone's page (#1299): eight people, and the bots on top (the
## chips of the seventh and fifteenth body stand under the players' boxes), every perk, a long feed
## and a level card in the lane, with the touch layout on, on every page, interface size and hand.
## The card stands clear of every part and every touch button, and in the free ground it takes
## beside the column it ends before the middle of the screen.
func test_on_a_phones_page_it_stays_clear_of_eight_players_and_the_buttons() -> void:
	var faults: Array[String] = []
	for page in PHONES:
		for ui_scale in UI_SCALES:
			for mirrored in [false, true]:
				for bots in [0, NightHost.MAX_PLAYERS - 1]:
					var canvas := _page(page, ui_scale)
					_make(canvas, NightHost.MAX_PLAYERS, bots)
					_hud.mirrored = mirrored
					_hud.touch_layout = true
					_hud.set_safe_insets(NOTCH)
					_busy_night()
					_fixture.give_perks(_fixture.rules.tuning.economy.max_tonics)
					_hud.popups.mode = PopupLane.Mode.ALL
					_hud.state.apply_event(
						{"type": &"level_up", "player_id": 1, "level": 15, "total": 0}
					)
					var held := _buttons(canvas, mirrored)
					# The night screen hands the HUD the boxes of the touch buttons.
					_hud.markers.held = held
					_raise_the_card()
					await _settle()
					var label := (
						"%s at %s%s, %d bots"
						% [
							Vector2i(page.x, page.y),
							ui_scale,
							", left hand" if mirrored else "",
							bots
						]
					)
					# The smallest page at the largest size with a left hand has the buttons and the
					# feeds where the card would stand: it keeps off the cards and the buttons and
					# may meet a row of the feed (a pull request note says so).
					var tight: bool = page.x < 1500.0 and ui_scale > 1.2 and mirrored
					faults.append_array(_faults(label, canvas, held, tight))
					_host.queue_free()
	assert_array(faults).is_empty()


## What the maintainer may do next to the column: a fingertip-high tag inside it (#1286 stood there
## once) makes it a fingertip taller, and the card must still be clear of it and of the cards.
func test_a_column_a_fingertip_taller_still_leaves_the_card_clear() -> void:
	var faults: Array[String] = []
	for page in PHONES:
		for ui_scale in UI_SCALES:
			var canvas := _page(page, ui_scale)
			_make(canvas, NightHost.MAX_PLAYERS)
			_hud.touch_layout = true
			_hud.set_safe_insets(NOTCH)
			_busy_night()
			var tag := Control.new()
			tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
			tag.custom_minimum_size = Vector2(
				1.0, MenuScale.tap_units(get_window(), true) + float(HudStyle.GAP)
			)
			_hud.points.get_parent().add_child(tag)
			var buttons := _buttons(canvas, false)
			_hud.markers.held = buttons
			_raise_the_card()
			await _settle()
			var label := "%s at %s with a tag in the column" % [Vector2i(page.x, page.y), ui_scale]
			var held := buttons.duplicate()
			held.append(Rect2(tag.get_global_rect()))
			faults.append_array(_faults(label, canvas, held))
			_host.queue_free()
	assert_array(faults).is_empty()


## The touch buttons' boxes on a phone held sideways, as the touch layer lays them out.
func _buttons(canvas: Vector2, mirrored: bool) -> Array[Rect2]:
	var finger := MenuScale.tap_units(get_window(), true)
	var circles := TouchLayout.buttons(TouchLayout.safe_rect(canvas, NOTCH), 1.0, mirrored, finger)
	var boxes: Array[Rect2] = []
	for id: StringName in circles:
		var reach := Vector2.ONE * float(circles[id][&"radius"])
		boxes.append(Rect2(Vector2(circles[id][&"centre"]) - reach, reach * 2.0))
	return boxes


## Puts the test's window where a phone's page is and gives back the canvas it makes.
func _page(page: Vector3, ui_scale: float) -> Vector2:
	var window := Vector2i(int(page.x), int(page.y))
	get_window().size = window
	get_window().content_scale_factor = ui_scale
	MenuScale.pixel_ratio = page.z
	TouchMode.device_is_touch = true
	return Vector2(window) / MenuScale.pixels_per_unit(window, ui_scale)


func _busy_night() -> void:
	_hud.state.set_ammo(30, 150, "Shotgun")
	_hud.state.set_area("The Concession Stand", "Light the booth to open the back lot")
	_hud.state.set_prompt(&"buy_door", "Projection booth door", 750)
	_fixture.act(RulesAction.set_downed(2, true))
	for text in ["RUBY OPENED THE PROJECTION BOOTH", "GENERATOR RUNNING LOW", "MOE IS DOWN"]:
		_hud.events_feed.push(text)


## The card up with three lines, the longest an order's words run to.
func _raise_the_card() -> void:
	_hud.state.apply_event(
		_advance_event(
			&"d_smg_50", {"text": "Put down 50 zombies with the submachine gun", "target": 50}
		)
	)
	_fixture.advance(0.6)


## Lets the columns lay themselves out and the lane run, a frame at a time.
func _settle() -> void:
	for _i in 40:
		await await_idle_frame()
		_hud.popups.advance(0.05)
		_hud.challenge.advance(0.0)


## Every way the card is where it must not be, as sentences: off the canvas, over the crosshair,
## over a shown part or over the boxes in `held` (the touch buttons), or past the middle of the
## screen when it is not on the left edge.
func _faults(
	label: String, canvas: Vector2, held: Array[Rect2], soft_may_meet := false
) -> Array[String]:
	var found: Array[String] = []
	if not _hud.challenge.visible:
		return ["%s: the card is not shown" % label]
	var card := _rect(_hud.challenge.card)
	if not Rect2(Vector2.ZERO, canvas).encloses(card):
		found.append("%s: the card %s leaves the canvas" % [label, card])
	var middle := Rect2(canvas * 0.5 - CROSSHAIR_CLEAR * 0.5, CROSSHAIR_CLEAR)
	if card.intersects(middle):
		found.append("%s: the card %s is over the crosshair" % [label, card])
	for part in _hud.boxed_parts():
		if part == _hud.challenge or not part.is_visible_in_tree():
			continue
		if soft_may_meet and SOFT.has(part.name):
			continue
		if card.intersects(_rect(part)):
			found.append("%s: the card %s overlaps %s %s" % [label, card, part.name, _rect(part)])
	for box in held:
		if card.intersects(box):
			found.append("%s: the card %s is over the touch box %s" % [label, card, box])
	# On the edge of the screen, as it always was, or beside the column and short of the middle.
	if card.position.x >= canvas.x * 0.25 and card.end.x > canvas.x * 0.5 - CROSSHAIR_CLEAR.x * 0.5:
		found.append(
			"%s: the card %s is neither on the edge nor short of the middle" % [label, card]
		)
	return found


func test_the_words_are_never_cut_even_the_longest() -> void:
	for text in [
		"Put down 100 zombies with the submachine gun",
		"Take down 60 zombies with the crowbar and a very long second clause",
	]:
		_hud.state.apply_event(_advance_event(&"long", {"text": text}))
		_run(0.5)
		await await_idle_frame()
		await await_idle_frame()
		var words := _hud.challenge.card.words
		var font := words.get_theme_font(&"font")
		var size := words.get_theme_font_size(&"font_size")
		var block := font.get_multiline_string_size(
			words.text, HORIZONTAL_ALIGNMENT_LEFT, words.size.x, size
		)
		assert_int(words.get_line_count()).is_less_equal(3)
		assert_float(block.y).is_less_equal(words.size.y + 1.0)
		_run(6.0)


## The card made narrow (beside the players' column on the smallest page) wraps its words onto more
## lines and never cuts them, keeps the type no smaller than the HUD's least, and measures what it
## says it measures: the height `size_at` gave is the height the card has once it is laid out.
func test_the_card_made_narrow_wraps_its_words_and_is_the_height_it_measured() -> void:
	for text in [
		"Put down 50 zombies with the submachine gun",
		"Take down 60 zombies with the crowbar and a very long second clause",
	]:
		# A card of its own: the HUD under a test places its card again every frame it shows.
		var card := HudChallengeCard.new()
		auto_free(card)
		_host.add_child(card)
		card.show_advance(_advance_event(&"long", {"text": text}))
		var last := 0.0
		for width in [HudChallengeCard.WIDTH, 253.0, HudChallengeCard.MIN_WIDTH]:
			var measured := card.size_at(width)
			assert_float(measured.x).is_equal(width)
			# A narrower card is never shorter.
			assert_float(measured.y).is_greater_equal(last)
			last = measured.y
			await await_idle_frame()
			await await_idle_frame()
			assert_float(card.get_combined_minimum_size().x).is_equal(width)
			assert_float(card.get_combined_minimum_size().y).is_equal_approx(measured.y, 0.5)
			var words := card.words
			var size := words.get_theme_font_size(&"font_size")
			assert_int(size).is_greater_equal(HudStyle.MIN_TEXT)
			var block := words.get_theme_font(&"font").get_multiline_string_size(
				words.text, HORIZONTAL_ALIGNMENT_LEFT, words.custom_minimum_size.x, size
			)
			assert_float(block.y).is_less_equal(words.custom_minimum_size.y + 1.0)
