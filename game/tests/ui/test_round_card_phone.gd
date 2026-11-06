extends GdUnitTestSuite
## The round card on a phone's page (#1305). With the touch layout up the card takes one row, the
## reels on the left and the caption and the detail on the right, about 90 units high instead of
## 160, and the players' column under it takes the 70 units it frees as room: a party stays one to
## a row, with its names, more often. A desktop and a pad keep the three-line card.

## A page is a window in pixels, the interface size and the pixel ratio the browser reports: a
## phone's 844 x 390 CSS px at ratio 2 is a 1688 x 780 window, a 667 x 375 one is 1334 x 750.
const PHONES: Array[Vector3] = [Vector3(1688, 780, 2.0), Vector3(1334, 750, 2.0)]
const UI_SCALES: Array[float] = [0.8, 1.0, 1.25]
## The platform's safe area on a phone held sideways (a notch and a home bar), canvas units.
const NOTCH := Vector4(96.0, 0.0, 96.0, 24.0)
## The card on one row stands about this high (a reel tile and the padding), and gives up the rest
## of the 160 units of the card in three lines.
const ONE_ROW := 90.0
const THREE_ROWS := 160.0

var _host: Control
var _fixture: HudFixture
var _hud: Hud
var _window_size := Vector2i.ZERO
var _window_factor := 1.0


func before_test() -> void:
	_window_size = get_window().size
	_window_factor = get_window().content_scale_factor
	UIMotion.reduced = false


func after_test() -> void:
	get_window().size = _window_size
	get_window().content_scale_factor = _window_factor
	MenuScale.pixel_ratio = -1.0
	TouchMode.device_is_touch = null
	UIMotion.reduced = false


## Puts the test's window where a phone's page is and gives back the canvas it makes.
func _page(page: Vector3, ui_scale: float) -> Vector2:
	var window := Vector2i(int(page.x), int(page.y))
	get_window().size = window
	get_window().content_scale_factor = ui_scale
	MenuScale.pixel_ratio = page.z
	TouchMode.device_is_touch = true
	return Vector2(window) / MenuScale.pixels_per_unit(window, ui_scale)


## A HUD on a phone's page with `people` people and `bots` bots, the objective on its two lines and
## every perk beside the health card. `card_on_a_row` false puts the round card back in its three
## lines (the card as it was before #1305) to measure what it gave up.
func _night(
	canvas: Vector2, people: int, bots: int, card_on_a_row := true, mirrored := false
) -> void:
	_host = auto_free(Control.new())
	_host.size = canvas
	add_child(_host)
	_fixture = HudFixture.make(_host, people, 1958, false, bots)
	_hud = _fixture.hud
	_fixture.into_round_one()
	_hud.mirrored = mirrored
	_hud.touch_layout = true
	_hud.set_safe_insets(NOTCH)
	_hud.state.set_area("The Concession Stand", "Light the booth to open the back lot")
	_fixture.give_perks(_fixture.rules.tuning.economy.max_tonics)
	if not card_on_a_row:
		_hud.round_part.compact = false


func _settle() -> void:
	for _i in 6:
		await await_idle_frame()


func _label(page: Vector3, ui_scale: float) -> String:
	return "%s at %s" % [Vector2i(int(page.x), int(page.y)), ui_scale]


## Puts the round and the phase on the card and lets the reels and the words settle.
func _say(round_number: int, phase: int, left: int, seconds: float) -> void:
	_hud.state.apply_event({"type": &"round_started", "round": round_number, "zombie_count": left})
	match phase:
		HudState.PHASE_BREAK:
			_hud.state.apply_event({"type": &"break_started", "seconds": seconds})
		HudState.PHASE_OVER, HudState.PHASE_IDLE:
			_hud.state.apply_event({"type": &"phase_changed", "phase": phase})
	await _settle()


## The card takes one row about 90 units high on both pages, at every interface size, in either
## hand, whatever it says: the caption, every reel and the detail are on it, inside it, the reels
## to the left of the words, the type never under the floor and no word cut.
func test_the_card_takes_one_row_with_everything_it_said_on_a_phone() -> void:
	var faults: Array[String] = []
	var says: Array[Array] = [
		[7, HudState.PHASE_ACTIVE, 400, 0.0],
		[7, HudState.PHASE_BREAK, 0, 30.0],
		[7, HudState.PHASE_OVER, 0, 0.0],
		[7, HudState.PHASE_IDLE, 0, 0.0],
		[100, HudState.PHASE_ACTIVE, 400, 0.0],
		[100, HudState.PHASE_BREAK, 0, 99.0],
	]
	for page in PHONES:
		for ui_scale in UI_SCALES:
			for mirrored in [false, true]:
				var canvas := _page(page, ui_scale)
				_night(canvas, 3, 0, true, mirrored)
				var card: HudRound = _hud.round_part
				for say in says:
					await _say(say[0], say[1], say[2], say[3])
					var label := (
						"%s%s, round %d, '%s'"
						% [
							_label(page, ui_scale),
							", left hand" if mirrored else "",
							say[0],
							card.detail_text
						]
					)
					var rect := card.get_global_rect()
					if absf(rect.size.y - ONE_ROW) > 1.0:
						faults.append("%s: the card is %s high" % [label, rect.size.y])
					if rect.size.x != HudStyle.COLUMN:
						faults.append("%s: the card is %s wide" % [label, rect.size.x])
					var reels := card._reels.get_global_rect()
					var words := card._words.get_global_rect()
					if not rect.encloses(reels) or not rect.encloses(words):
						faults.append("%s: a part leaves the card" % label)
					if reels.end.x > words.position.x:
						faults.append(
							"%s: the reels %s run into the words %s" % [label, reels, words]
						)
					for part: Label in [card._caption, card._detail]:
						if not part.is_visible_in_tree():
							faults.append("%s: '%s' is not shown" % [label, part.text])
						var size_px := part.get_theme_font_size(&"font_size")
						if size_px < HudStyle.MIN_TEXT:
							faults.append("%s: '%s' is %d units" % [label, part.text, size_px])
						var wide := HudStyle.text_width(
							part.get_theme_font(&"font"), part.text, size_px
						)
						if wide > part.size.x + 0.5:
							faults.append(
								"%s: '%s' is %s wide in %s" % [label, part.text, wide, part.size.x]
							)
						if not words.encloses(part.get_global_rect()):
							faults.append("%s: '%s' leaves the words' box" % [label, part.text])
					if card._reels.get_child_count() != str(say[0]).pad_zeros(2).length():
						faults.append("%s: %d reels" % [label, card._reels.get_child_count()])
				_host.queue_free()
	assert_array(faults).is_empty()


## A desktop and a pad keep the card in three lines, with no node added for the row, at three
## canvases; putting the touch layout up takes one row and putting it away brings the lines back.
func test_a_desktop_and_a_pad_keep_the_three_line_card_and_the_touch_layout_toggles_it() -> void:
	for canvas in [Vector2(1536, 864), Vector2(1920, 1080), Vector2(1024, 576)]:
		_host = auto_free(Control.new())
		_host.size = canvas
		add_child(_host)
		_fixture = HudFixture.make(_host, 4, 1958, false, 0)
		_hud = _fixture.hud
		_fixture.into_round_one()
		await _settle()
		var card: HudRound = _hud.round_part
		assert_object(card._row).is_null()
		assert_float(card.size.y).is_equal(THREE_ROWS)
		assert_float(card._reels.get_child(0).custom_minimum_size.y).is_equal(HudReelDigit.TILE.y)
		var nodes := card.find_children("*", "", true, false).size()
		_hud.touch_layout = true
		await _settle()
		assert_object(card._row).is_not_null()
		assert_float(card.size.y).is_equal(ONE_ROW)
		_hud.touch_layout = false
		await _settle()
		assert_object(card._row).is_null()
		assert_float(card.size.y).is_equal(THREE_ROWS)
		assert_int(card.find_children("*", "", true, false).size()).is_equal(nodes)
		assert_object(card._caption.get_parent()).is_equal(card.body)
		assert_object(card._reels.get_parent()).is_equal(card.body)
		assert_object(card._detail.get_parent()).is_equal(card.body)
		assert_float(card._detail.custom_minimum_size.y).is_equal(
			float(HudStyle.TEXT + HudStyle.MD)
		)
		assert_int(card._detail.get_theme_font_size(&"font_size")).is_equal(HudStyle.TEXT)
		_host.queue_free()


## The room flows into the column: with the card on one row the column's room is what the three
## lines left it plus the 70 units the card gave up, and the objective stays under the card.
func test_the_column_gets_the_room_the_card_gave_up() -> void:
	for page in PHONES:
		for ui_scale in UI_SCALES:
			for mirrored in [false, true]:
				var canvas := _page(page, ui_scale)
				_night(canvas, 8, 7, false, mirrored)
				await _settle()
				var before := _hud.points.room
				var tall := _hud.round_part.size.y
				_hud.round_part.compact = true
				await _settle()
				var label := "%s%s" % [_label(page, ui_scale), ", left hand" if mirrored else ""]
				assert_float(tall).override_failure_message(label).is_equal(THREE_ROWS)
				var freed := _hud.points.room - before
				assert_float(freed).override_failure_message(label).is_equal(
					tall - _hud.round_part.size.y
				)
				assert_float(freed).override_failure_message(label).is_greater_equal(
					THREE_ROWS - ONE_ROW - 1.0
				)
				assert_float(_hud.objective.get_global_rect().position.y).is_equal(
					_hud.round_part.get_global_rect().end.y + float(HudStyle.GAP)
				)
				_host.queue_free()


## The room that is left in the busiest case, for the bots' tag of #1300 (a fingertip and a gap):
## at 1.25 with eight people and seven bots the column, in pairs, ends 72 to 75 units short of its
## room (it was 2 to 5 with the card in three lines). The tag needs more, so it still cannot move
## into the column there; where the party is smaller or the bots are away the room is bigger.
func test_the_room_left_for_the_bots_tag_at_the_busiest_case() -> void:
	for page in PHONES:
		var canvas := _page(page, 1.25)
		_night(canvas, NightHost.MAX_PLAYERS, NightHost.MAX_PLAYERS - 1)
		await _settle()
		var spare := _hud.points.room - _hud.points.size.y
		var tag := MenuScale.tap_units(get_window(), true) + float(HudStyle.GAP)
		assert_bool(_hud.points.pairs).is_true()
		assert_float(spare).is_between(70.0, 76.0)
		assert_float(spare).is_less(tag)
		_host.queue_free()


## How often the names come back (a party stays one to a row), counted over every party of 3 to 8
## people, with and without the seven bots, on both pages at the three sizes: only 1.25 was ever
## short of room, and there the card on one row keeps the names for 10 of 12 parties instead of 6,
## and never costs one.
func test_the_card_on_one_row_only_ever_brings_the_names_back() -> void:
	for page in PHONES:
		for ui_scale in UI_SCALES:
			var kept := [0, 0]
			for bots in [0, NightHost.MAX_PLAYERS - 1]:
				for people in range(3, NightHost.MAX_PLAYERS + 1):
					var here := []
					for on_a_row in [false, true]:
						var canvas := _page(page, ui_scale)
						_night(canvas, people, bots, on_a_row)
						await _settle()
						here.append(not _hud.points.pairs)
						kept[int(on_a_row)] += int(not _hud.points.pairs)
						_host.queue_free()
					var label := "%s, %d people, %d bots" % [_label(page, ui_scale), people, bots]
					# Names never go for the card on a row.
					assert_bool(here[0] and not here[1]).override_failure_message(label).is_false()
			if ui_scale < 1.2:
				assert_array(kept).is_equal([12, 12])
			else:
				assert_array(kept).is_equal([6, 10])
