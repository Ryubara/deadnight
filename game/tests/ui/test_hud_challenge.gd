extends GdUnitTestSuite
## The challenge prompt on the HUD: it appears for a quarter mark, a finish and a milestone step,
## says the right thing in the right words, honours the player's setting, reduced motion and being
## down, and never sits over the crosshair, the round counter or any other part at any canvas the
## game runs at (the desktop windows and a phone held sideways).

const CANVASES: Array[Vector2] = [
	Vector2(1536, 864),
	Vector2(1920, 1080),
	Vector2(2560, 1080),
	Vector2(2340, 1080),
	Vector2(2880, 1620),
]
## The clear box round the middle of the screen, canvas units: the reticle and its hit markers.
const CROSSHAIR_CLEAR := Vector2(160.0, 160.0)

var _host: Control
var _fixture: HudFixture
var _hud: Hud


func before_test() -> void:
	UIMotion.reduced = false
	_make(Vector2(1920, 1080))


func after_test() -> void:
	UIMotion.reduced = false


func _make(canvas: Vector2, players := 1) -> void:
	_host = auto_free(Control.new())
	_host.size = canvas
	add_child(_host)
	_fixture = HudFixture.make(_host, players)
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
			_make(canvas, 4)
			_hud.mirrored = mirrored
			_hud.state.set_ammo(30, 150, "Shotgun")
			_hud.state.set_area("The Concession Stand", "Light the booth to open the back lot")
			_hud.state.set_prompt(&"buy_door", "Projection booth door", 750)
			_fixture.act(RulesAction.set_downed(2, true))
			for text in [
				"RUBY OPENED THE PROJECTION BOOTH", "GENERATOR RUNNING LOW", "MOE IS DOWN"
			]:
				_hud.events_feed.push(text)
			_hud.state.apply_event(
				_advance_event(
					&"d_smg_50",
					{"text": "Put down 50 zombies with the submachine gun", "target": 50}
				)
			)
			_fixture.advance(0.6)
			await await_idle_frame()
			await await_idle_frame()
			var card := _rect(_hud.challenge.card)
			var label := "%s%s" % [canvas, " mirrored" if mirrored else ""]
			assert_bool(_hud.challenge.visible).override_failure_message(label).is_true()
			(
				assert_bool(Rect2(Vector2.ZERO, canvas).encloses(card))
				. override_failure_message("%s: the card %s leaves the canvas" % [label, card])
				. is_true()
			)
			var middle := Rect2(canvas * 0.5 - CROSSHAIR_CLEAR * 0.5, CROSSHAIR_CLEAR)
			(
				assert_bool(card.intersects(middle))
				. override_failure_message("%s: the card %s is over the crosshair" % [label, card])
				. is_false()
			)
			for part in _hud.boxed_parts():
				if part == _hud.challenge or not part.is_visible_in_tree():
					continue
				(
					assert_bool(card.intersects(_rect(part)))
					. override_failure_message(
						"%s: the card %s overlaps %s %s" % [label, card, part.name, _rect(part)]
					)
					. is_false()
				)
			assert_float(card.position.x).override_failure_message(label).is_less(canvas.x * 0.25)


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
