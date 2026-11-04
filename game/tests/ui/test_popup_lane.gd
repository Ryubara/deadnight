# gdlint:disable=max-public-methods
extends GdUnitTestSuite
## The popup lane on the HUD (#1064): the cards the server's progression events make, shown the
## moment they arrive, in the middle of a round, under the round banner and clear of every other
## part of the HUD at every canvas the game runs at (and on the phone layout); the words and the
## order of a card (icon, the level beside it, a little padding, then the words); the setting; real
## input never blocked; the helicopter drop's wait; and the sounds each card asks for.

const CANVASES: Array[Vector2] = [
	Vector2(1536, 864),
	Vector2(1920, 1080),
	Vector2(2560, 1080),
	Vector2(2340, 1080),
	Vector2(2880, 1620),
]
## The clear box round the middle of the screen, canvas units: the reticle and its hit markers.
const CROSSHAIR_CLEAR := Vector2(160.0, 160.0)
const FUEL: Array[StringName] = [&"fuel_can"]

var _host: Control
var _fixture: HudFixture
var _hud: Hud
var _cues: Array[StringName] = []


func before_test() -> void:
	UIMotion.reduced = false
	_cues = []


func after_test() -> void:
	UIMotion.reduced = false
	LevelIcons.release()


func _make(canvas: Vector2, players := 1) -> void:
	_host = auto_free(Control.new())
	_host.size = canvas
	add_child(_host)
	_fixture = HudFixture.make(_host, players)
	_hud = _fixture.hud
	_hud.popups.cue.connect(func(sound: StringName) -> void: _cues.append(sound))
	# The tests step the lane by hand: the frames they wait for must not move it too.
	_hud.popups.process_mode = Node.PROCESS_MODE_DISABLED
	_fixture.into_round_one()
	await await_idle_frame()


func _run(seconds: float) -> void:
	var left := seconds
	while left > 0.0001:
		_hud.popups.advance(minf(0.05, left))
		left -= 0.05


func _step(lane: PopupLane, seconds: float) -> void:
	var left := seconds
	while left > 0.0001:
		lane.advance(minf(0.05, left))
		left -= 0.05


## Runs the lane `seconds` forward a frame at a time, so the HUD's columns lay themselves out as
## they do in the game (the lane follows the parts above it by what they have laid out).
func _settle(seconds: float) -> void:
	var left := seconds
	while left > 0.0001:
		await await_idle_frame()
		_hud.popups.advance(minf(0.05, left))
		left -= 0.05


func _level(level: int, player := 1) -> Dictionary:
	return {"type": &"level_up", "player_id": player, "level": level, "total": 0}


func _unlock(slot: StringName, item: StringName, level := 12, player := 1) -> Dictionary:
	return {
		"type": &"unlock_earned", "player_id": player, "level": level, "slot": slot, "item": item
	}


func _tier(level: int, tier_name: String, player := 1) -> Dictionary:
	return {
		"type": &"tier_up",
		"player_id": player,
		"tier": LevelCurve.tier_of(level),
		"tier_name": tier_name,
		"level": level,
	}


func _challenge_done(text := "Put down 40 zombies") -> Dictionary:
	return {
		"type": HudChallenge.EVENT,
		"id": &"d_kills",
		"family": ChallengeDef.Family.DAILY,
		"text": text,
		"before": 39,
		"after": 40,
		"target": 40,
		"checkpoint": 100,
		"completed": true,
		"rung": 0,
		"rungs": 0,
	}


## The events a game server tells a seat whose XP crosses levels 11 and 12 in one tick, the way
## `XpAward` makes them (the real contract, not a hand-made copy of it).
func _server_stack() -> Array[Dictionary]:
	var award := XpAward.new(FUEL, ChallengeClock.fixed(20401.0 * ChallengeClock.DAY_SECONDS))
	award.register(1, "ann", LevelCurve.xp_for(10) + 5, 0)
	award.add_xp(1, LevelCurve.xp_for(12) - LevelCurve.xp_for(10), XpAward.CHALLENGE)
	return award.end_tick(true)


func _texts(card: PopupCard) -> Array[String]:
	return card.lines()


func test_a_level_up_shows_a_card_at_once_in_the_middle_of_a_round() -> void:
	await _make(Vector2(1920, 1080))
	assert_int(_hud.state.phase).is_equal(HudState.PHASE_ACTIVE)
	_hud.state.apply_event(_level(15))
	assert_bool(_hud.popups.visible).is_false()
	_run(0.1)
	assert_bool(_hud.popups.visible).is_true()
	assert_int(_hud.popups.cards().size()).is_equal(1)
	var card := _hud.popups.cards()[0]
	assert_int(card.kind).is_equal(PopupQueue.Kind.LEVEL)
	assert_array(_texts(card)).contains_exactly(["LEVEL UP", "15", "16", "Tank top"])
	assert_array(_cues).is_equal([&"level_up"])


func test_a_level_card_reads_icon_then_level_then_padding_then_the_words() -> void:
	await _make(Vector2(1920, 1080))
	_hud.state.apply_event(_level(15))
	_run(1.0)
	var card := _hud.popups.cards()[0]
	await await_idle_frame()
	var icon := card.icon
	var number: Label = card.get_child(1)
	var words: Label = card.get_child(0)
	assert_str(number.text).is_equal("15")
	assert_str(words.text).is_equal("LEVEL UP")
	var icon_right := icon.position.x + icon.size.x
	assert_float(number.position.x - icon_right).is_between(0.0, 12.0)
	var gap := words.position.x - (number.position.x + number.size.x)
	assert_float(gap).is_between(8.0, 30.0)
	assert_object(icon.texture).is_same(LevelIcons.texture(15))
	# The next unlock reads the same way: its level, a little padding, its name.
	assert_array(_texts(card)).contains(["16", "Tank top"])


func test_a_level_card_punches_holes_toward_the_next_unlock() -> void:
	# A table of the test's own (the shipped ladder fills in as items get art): the next row with
	# art after level 15 is 16 (one away, seven holes), after 17 it is 20 (three away, five holes).
	var table := LadderUnlocks.from_text(
		(
			'[{"level": 16, "slot": "top", "item": "a", "available": true},'
			+ ' {"level": 18, "slot": "top", "item": "b", "available": false},'
			+ ' {"level": 20, "slot": "top", "item": "c", "available": true}]'
		)
	)
	assert_int(PopupLadder.next_unlock(15, table)["level"]).is_equal(16)
	assert_int(PopupLadder.punched(15, table)).is_equal(7)
	assert_int(PopupLadder.next_unlock(17, table)["level"]).is_equal(20)
	assert_int(PopupLadder.punched(17, table)).is_equal(5)
	# Far from the next row no hole is punched, and on the last level all are.
	assert_int(PopupLadder.punched(1, LadderUnlocks.from_text("[]"))).is_equal(PopupLadder.HOLES)
	var far := LadderUnlocks.from_text(
		'[{"level": 30, "slot": "top", "item": "x", "available": true}]'
	)
	assert_int(PopupLadder.punched(2, far)).is_equal(0)
	assert_int(PopupLadder.punched(55)).is_equal(PopupLadder.HOLES)
	assert_dict(PopupLadder.next_unlock(55)).is_empty()
	# The card shows the count the ladder gives, whatever the shipped table holds.
	await _make(Vector2(1920, 1080))
	_hud.state.apply_event(_level(17))
	_run(0.5)
	assert_int(_hud.popups.cards()[0].punched()).is_equal(PopupLadder.punched(17))


func test_an_unlock_card_says_what_it_is_and_its_name() -> void:
	await _make(Vector2(1920, 1080))
	_hud.state.apply_event(_unlock(&"top", &"letter_jacket", 26))
	_hud.state.apply_event(_unlock(&"colour", &"cherry", 3))
	_hud.state.apply_event(_unlock(&"headwear", &"ushers_cap", 6))
	_run(0.5)
	var cards := _hud.popups.cards()
	assert_array(_texts(cards[0])).is_equal(["NEW TOP", "Letter jacket"])
	assert_array(_texts(cards[1])).is_equal(["NEW COLOUR", "Cherry"])
	assert_array(_texts(cards[2])).is_equal(["NEW HEADWEAR", "Usher's cap"])
	# A colour has its swatch; a cap has a chip with its slot's letter.
	assert_object(PopupLadder.swatch_of(&"colour", &"cherry")).is_not_null()
	assert_object(PopupLadder.swatch_of(&"headwear", &"ushers_cap")).is_null()
	# An unlock card is half the height of a level card.
	assert_float(cards[0].size.y).is_less(PopupCard.LEVEL_SIZE.y * 0.65)
	assert_array(_cues).is_equal([&"unlock", &"unlock", &"unlock"])


func test_a_card_or_a_frame_sounds_with_the_rustle() -> void:
	await _make(Vector2(1920, 1080))
	_hud.state.apply_event(_unlock(&"emblem", &"admit_one", 2))
	_hud.state.apply_event(_unlock(&"plate_frame", &"chrome", 29))
	_run(0.5)
	assert_array(_cues).is_equal([&"card_earned", &"card_earned"])


func test_a_tier_is_one_card_with_the_level_and_the_bigger_sound() -> void:
	await _make(Vector2(1920, 1080))
	_hud.state.apply_event(_level(11))
	_hud.state.apply_event(_tier(11, "Newsreel"))
	_run(0.5)
	var cards := _hud.popups.cards()
	assert_int(cards.size()).is_equal(1)
	assert_int(cards[0].kind).is_equal(PopupQueue.Kind.TIER)
	assert_array(_texts(cards[0])).is_equal(["TIER UP", "11", "NEWSREEL"])
	assert_array(_cues).is_equal([&"tier_up"])


func test_a_tier_that_comes_after_the_level_card_showed_makes_it_a_tier_card() -> void:
	await _make(Vector2(1920, 1080))
	_hud.state.apply_event(_level(11))
	_run(0.5)
	_hud.state.apply_event(_tier(11, "Newsreel"))
	_run(0.1)
	var cards := _hud.popups.cards()
	assert_int(cards.size()).is_equal(1)
	assert_int(cards[0].kind).is_equal(PopupQueue.Kind.TIER)
	assert_array(_cues).is_equal([&"level_up", &"tier_up"])


func test_the_servers_own_events_make_the_cards_in_order() -> void:
	await _make(Vector2(1920, 1080))
	var told := _server_stack()
	var types: Array[StringName] = []
	for event in told:
		types.append(event["type"])
	(
		assert_array(types)
		. is_equal(
			[
				XpAward.GAINED,
				XpAward.LEVEL_UP,
				XpAward.TIER_UP,
				XpAward.UNLOCK,
				XpAward.LEVEL_UP,
				XpAward.UNLOCK,
			]
		)
	)
	# The round banner of the night's start is gone: three cards fit under where it was.
	_fixture.advance(5.0)
	await _settle(0.1)
	_hud.feed(told)
	_run(1.0)
	var kinds: Array[int] = []
	for card in _hud.popups.cards():
		kinds.append(card.kind)
	# Level 11 is a tier card, its shorts follow and then level 12 (three up, its boots wait).
	assert_array(kinds).is_equal(
		[PopupQueue.Kind.TIER, PopupQueue.Kind.UNLOCK, PopupQueue.Kind.LEVEL]
	)
	assert_int(_hud.popups.queue.waiting.size()).is_equal(1)
	_run(10.0)
	assert_array(_cues).is_equal([&"tier_up", &"unlock", &"level_up", &"unlock"])
	assert_bool(_hud.popups.queue.is_idle()).is_true()


func test_a_stack_of_five_unlocks_and_a_level_in_one_tick() -> void:
	await _make(Vector2(1920, 1080))
	var batch: Array[Dictionary] = [_level(12)]
	for item in [&"boots", &"teal", &"goggles", &"helmet", &"tan"]:
		batch.append(_unlock(&"top", item))
	_hud.feed(batch)
	_run(0.6)
	assert_int(_hud.popups.cards().size()).is_equal(3)
	assert_int(_hud.popups.queue.waiting.size()).is_equal(3)
	_run(20.0)
	assert_array(_cues).has_size(6)
	assert_bool(_hud.popups.queue.is_idle()).is_true()
	assert_bool(_hud.popups.visible).is_false()


func test_only_the_local_players_events_make_cards() -> void:
	await _make(Vector2(1920, 1080), 2)
	_hud.state.apply_event(_level(9, 2))
	_hud.state.apply_event(_unlock(&"top", &"boots", 9, 2))
	_run(1.0)
	assert_int(_hud.popups.cards().size()).is_equal(0)
	_hud.state.apply_event(_level(9, 1))
	_run(0.5)
	assert_int(_hud.popups.cards().size()).is_equal(1)


func test_a_finished_challenge_is_a_card_and_the_prompt_leaves_the_finish_to_it() -> void:
	await _make(Vector2(1920, 1080))
	_hud.state.apply_event(_challenge_done())
	_run(0.5)
	var cards := _hud.popups.cards()
	assert_int(cards.size()).is_equal(1)
	assert_array(_texts(cards[0])).is_equal(["CHALLENGE DONE", "Put down 40 zombies"])
	assert_array(_cues).is_equal([&"challenge_done"])
	for _i in 20:
		_hud.challenge.advance(0.05)
	assert_bool(_hud.challenge.visible).is_false()


func test_with_the_popups_off_the_prompt_says_the_finish_again() -> void:
	await _make(Vector2(1920, 1080))
	_hud.popups.mode = PopupLane.Mode.OFF
	_hud.state.apply_event(_challenge_done())
	_run(1.0)
	for _i in 20:
		_hud.challenge.advance(0.05)
	assert_int(_hud.popups.cards().size()).is_equal(0)
	assert_bool(_hud.challenge.visible).is_true()


func test_the_setting_shows_all_big_ones_only_or_none() -> void:
	await _make(Vector2(1920, 1080))
	var batch: Array[Dictionary] = [_level(12), _unlock(&"top", &"boots"), _challenge_done()]
	_hud.popups.mode = PopupLane.Mode.BIG_ONLY
	_hud.feed(batch)
	_run(0.6)
	var kinds: Array[int] = []
	for card in _hud.popups.cards():
		kinds.append(card.kind)
	assert_array(kinds).is_equal([PopupQueue.Kind.LEVEL, PopupQueue.Kind.CHALLENGE])
	_run(10.0)
	_hud.popups.mode = PopupLane.Mode.OFF
	_hud.feed(batch)
	_run(1.0)
	assert_int(_hud.popups.cards().size()).is_equal(0)
	assert_bool(_hud.popups.queue.is_idle()).is_true()


func test_turning_the_cards_off_takes_the_ones_showing_away() -> void:
	await _make(Vector2(1920, 1080))
	_hud.feed([_level(12), _unlock(&"top", &"boots")])
	_run(0.6)
	assert_int(_hud.popups.cards().size()).is_equal(2)
	_hud.popups.mode = PopupLane.Mode.OFF
	assert_bool(_hud.popups.visible).is_false()
	await await_idle_frame()
	assert_int(_hud.popups.get_child_count()).is_equal(0)


func test_the_players_setting_drives_the_lane_and_its_sounds() -> void:
	await _make(Vector2(1920, 1080))
	var path := QuietSettings.test_path("popup_lane")
	var settings := QuietSettings.make(self, path)
	var link := PopupLink.new(_hud.popups, settings)
	assert_int(_hud.popups.mode).is_equal(PopupLane.Mode.ALL)
	settings.set_value(SettingsService.PROGRESS_POPUPS, 1)
	assert_int(_hud.popups.mode).is_equal(PopupLane.Mode.BIG_ONLY)
	settings.set_value(SettingsService.PROGRESS_POPUPS, 2)
	assert_int(_hud.popups.mode).is_equal(PopupLane.Mode.OFF)
	settings.set_value(SettingsService.PROGRESS_POPUPS, 0)
	assert_int(_hud.popups.mode).is_equal(PopupLane.Mode.ALL)
	assert_int(SettingsService.DEFAULTS[SettingsService.PROGRESS_POPUPS]).is_equal(0)
	assert_object(SettingsService.RANGES[SettingsService.PROGRESS_POPUPS]).is_equal(Vector2(0, 2))
	assert_object(link).is_not_null()
	settings.free()
	DirAccess.remove_absolute(path)


func test_real_input_is_never_blocked() -> void:
	await _make(Vector2(1920, 1080))
	_hud.feed([_level(11), _tier(11, "Newsreel"), _unlock(&"shorts", &"shorts", 11)])
	_hud.feed([_challenge_done()])
	_run(0.6)
	var checked := 0
	for node in _hud.popups.find_children("*", "Control", true, false):
		assert_int((node as Control).mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
		checked += 1
	assert_int(checked).is_greater(10)
	assert_int(_hud.popups.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)


func test_cards_wait_while_the_hud_is_hidden_and_show_when_it_is_back() -> void:
	await _make(Vector2(1920, 1080))
	_hud.hide()
	_hud.feed([_level(12), _unlock(&"top", &"boots")])
	_run(5.0)
	assert_int(_hud.popups.cards().size()).is_equal(0)
	assert_bool(_hud.popups.queue.waiting.size() == 2).is_true()
	_hud.show()
	_run(0.6)
	assert_int(_hud.popups.cards().size()).is_equal(2)
	assert_array(_cues).is_equal([&"level_up", &"unlock"])


func test_reduced_motion_fades_the_cards_without_sliding() -> void:
	UIMotion.reduced = true
	await _make(Vector2(1920, 1080))
	_hud.feed([_level(12), _unlock(&"top", &"boots")])
	var homes: Array[float] = []
	for _i in 12:
		_run(0.05)
		var cards := _hud.popups.cards()
		if cards.size() == 2:
			homes.append(cards[1].position.y)
	assert_int(homes.size()).is_greater(0)
	assert_float(homes.min()).is_equal(homes.max())
	assert_float(_hud.popups.cards()[0].icon.scale.x).is_equal(1.0)


func test_the_lane_stands_under_the_banner_and_the_boss_bar() -> void:
	await _make(Vector2(1920, 1080))
	_hud.banner.show_banner("ROUND 7 SURVIVED", "CATCH YOUR BREATH", HudBanner.Rank.ROUND)
	(
		_hud
		. state
		. apply_event(
			{
				"type": &"zombie_spawn_requested",
				"zombie_id": 900,
				"zombie_type": &"headliner",
				"boss": true,
				"health": 1000.0,
			}
		)
	)
	_fixture.advance(HudTuning.current().banner_in + 0.1)
	_hud.feed([_level(12), _unlock(&"top", &"boots"), _unlock(&"colour", &"teal")])
	await _settle(1.0)
	var lane := _hud.popups.get_global_rect()
	assert_bool(_hud.banner.visible and _hud.boss_bar.visible).is_true()
	assert_float(lane.position.y).is_greater_equal(_hud.banner.get_global_rect().end.y)
	assert_float(lane.position.y).is_greater_equal(_hud.boss_bar.get_global_rect().end.y)


## The busiest moment: a late round with four players and a boss on the lot, a round banner up and
## three cards on the lane. Every card must lie clear of every other part and of the crosshair.
func _problems(canvas: Vector2, touch: bool, mirrored: bool, boss: bool) -> Array[String]:
	await _make(canvas, 4)
	_fixture.fill_late_round()
	_hud.touch_layout = touch
	_hud.mirrored = mirrored
	_hud.banner.show_banner("ROUND 24 SURVIVED", "CATCH YOUR BREATH", HudBanner.Rank.ROUND)
	if boss:
		(
			_hud
			. state
			. apply_event(
				{
					"type": &"zombie_spawn_requested",
					"zombie_id": 901,
					"zombie_type": &"headliner",
					"boss": true,
					"health": 1000.0,
				}
			)
		)
	_hud.feed([_level(12), _unlock(&"top", &"letter_jacket", 12), _unlock(&"colour", &"teal", 12)])
	await _settle(2.0)
	var found: Array[String] = []
	var label := (
		"canvas %s%s%s%s"
		% [
			canvas,
			", touch" if touch else "",
			", mirrored" if mirrored else "",
			", boss bar up" if boss else "",
		]
	)
	var cards := _hud.popups.cards()
	# Under the banner alone three fit on a canvas of 1080 or more, two on the smallest; with a
	# boss bar too only as many as fit, and one at least.
	var wanted := 1 if boss else (3 if canvas.y >= 1080.0 else 2)
	if cards.size() < wanted:
		found.append("%s: %d cards stand, wanted %d" % [label, cards.size(), wanted])
	var middle := Rect2(canvas * 0.5 - CROSSHAIR_CLEAR * 0.5, CROSSHAIR_CLEAR)
	var bounds := Rect2(Vector2.ZERO, canvas)
	for card in cards:
		var rect := Rect2(card.get_global_rect())
		if not bounds.encloses(rect):
			found.append("%s: card %s leaves the canvas" % [label, rect])
		if rect.intersects(middle):
			found.append("%s: card %s is over the crosshair %s" % [label, rect, middle])
		for part in _hud.boxed_parts():
			if part == _hud.popups or not part.is_visible_in_tree():
				continue
			var over := rect.intersection(Rect2(part.get_global_rect()))
			if over.has_area():
				found.append("%s: card %s overlaps %s by %s" % [label, rect, part.name, over.size])
	return found


func test_the_lane_is_clear_of_the_hud_at_every_canvas() -> void:
	var problems: Array[String] = []
	for canvas in CANVASES:
		for boss in [false, true]:
			problems.append_array(await _problems(canvas, false, false, boss))
			_host.queue_free()
	assert_array(problems).is_empty()


func test_the_lane_is_clear_of_the_hud_on_the_phone_layout() -> void:
	var problems: Array[String] = []
	for canvas in [Vector2(2340, 1080), Vector2(1536, 864)]:
		for mirrored in [false, true]:
			for boss in [false, true]:
				problems.append_array(await _problems(canvas, true, mirrored, boss))
				_host.queue_free()
	assert_array(problems).is_empty()


func test_the_menus_overlay_takes_events_and_stands_down_for_a_night() -> void:
	var overlay := MenuPopups.new()
	var layer := auto_free(Control.new()) as Control
	layer.size = Vector2(1920, 1080)
	add_child(layer)
	layer.add_child(overlay)
	await await_idle_frame()
	assert_object(MenuPopups.instance).is_same(overlay)
	MenuPopups.announce([_level(9), _unlock(&"top", &"boots", 9)])
	_step(overlay.lane, 0.6)
	assert_int(overlay.lane.cards().size()).is_equal(2)
	var top := overlay.lane.get_global_rect()
	assert_float(top.position.y).is_equal_approx(MenuPopups.TOP, 1.0)
	assert_float(top.get_center().x).is_equal_approx(960.0, 1.0)
	MenuPopups.set_night(true)
	assert_int(overlay.lane.cards().size()).is_equal(0)
	# What the menu learns meanwhile waits for the night to go, and shows once (#1130).
	MenuPopups.announce([_level(10)])
	_step(overlay.lane, 0.6)
	assert_int(overlay.lane.cards().size()).is_equal(0)
	MenuPopups.set_night(false)
	_step(overlay.lane, 0.6)
	assert_int(overlay.lane.cards().size()).is_equal(1)
	MenuPopups.announce([_level(11)])
	_step(overlay.lane, 0.6)
	assert_int(overlay.lane.cards().size()).is_equal(2)
	layer.remove_child(overlay)
	overlay.free()
	assert_object(MenuPopups.instance).is_null()
