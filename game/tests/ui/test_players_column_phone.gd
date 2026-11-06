extends GdUnitTestSuite
## The players' column on a phone's page (#1301). The weapon strip is a fingertip high under it and
## the round and the objective stand over it, so at the largest interface size a room of eight
## people (and the bots' strip of chips on top) stood over the objective by 38 to 106 units. The
## column now takes the teammates two to a row, the points alone in each, when its boxes would
## stand taller than its room, and keeps one to a row, with their names, wherever they fit.

## A page is a window in pixels, the interface size and the pixel ratio the browser reports: a
## phone's 844 x 390 CSS px at ratio 2 is a 1688 x 780 window, a 667 x 375 one is 1334 x 750 (1536 x
## 864 units at 1.25, the smallest canvas there is).
const PHONES: Array[Vector3] = [Vector3(1688, 780, 2.0), Vector3(1334, 750, 2.0)]
const UI_SCALES: Array[float] = [0.8, 1.0, 1.25]
## The platform's safe area on a phone held sideways (a notch and a home bar), canvas units.
const NOTCH := Vector4(96.0, 0.0, 96.0, 24.0)
## What stands over or beside the column that the challenge card does not: the card is placed
## beside the column by its own change (#1299), and the feeds, the lane and the gains are in the
## middle and on the other side.
const NEIGHBOURS: Array[StringName] = [&"Round", &"Objective", &"Health", &"Perks", &"Slots"]

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


## A HUD on a phone's page with `people` people and `bots` bots, the touch layout on, the objective
## on its two lines and every perk beside the health card.
func _night(canvas: Vector2, people: int, bots: int, mirrored := false) -> void:
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


func _settle() -> void:
	for _i in 6:
		await await_idle_frame()


func _rect(part: Control) -> Rect2:
	return part.get_global_rect()


## Every way the column is where it must not be, as sentences: over a neighbour or off the canvas.
func _faults(label: String, canvas: Vector2) -> Array[String]:
	var found: Array[String] = []
	var column := _rect(_hud.points)
	if not Rect2(Vector2.ZERO, canvas).encloses(column):
		found.append("%s: the column %s leaves the canvas" % [label, column])
	for part in _hud.boxed_parts():
		if part == _hud.points or not part.is_visible_in_tree():
			continue
		if not NEIGHBOURS.has(part.name):
			continue
		var overlap := column.intersection(_rect(part))
		if overlap.has_area():
			found.append(
				"%s: the column %s overlaps %s %s" % [label, column, part.name, _rect(part)]
			)
	var objective := _rect(_hud.objective)
	if column.position.y < objective.end.y + float(HudStyle.GAP) - 0.5:
		found.append(
			(
				"%s: the column's top %s is not a gap under the objective %s"
				% [label, column.position.y, objective.end.y]
			)
		)
	return found


## The issue's busiest case and every case under it: the column never stands over the round, the
## objective, the health card, the perks or the weapon strip, on both pages, at every interface
## size, in either hand, with a room of 3 to 8 people, with and without the bots' chips, and with
## two of them down.
func test_the_busiest_column_never_overlaps_the_round_or_the_objective_on_a_phone() -> void:
	var faults: Array[String] = []
	for page in PHONES:
		for ui_scale in UI_SCALES:
			for mirrored in [false, true]:
				for people in [3, 5, 8]:
					for bots in [0, NightHost.MAX_PLAYERS - 1]:
						var canvas := _page(page, ui_scale)
						_night(canvas, people, bots, mirrored)
						if people > 2:
							_fixture.act(RulesAction.set_downed(2, true))
							_fixture.act(RulesAction.set_downed(people, true))
						await _settle()
						var label := (
							"%s at %s%s, %d people, %d bots"
							% [
								Vector2i(page.x, page.y),
								ui_scale,
								", left hand" if mirrored else "",
								people,
								bots
							]
						)
						faults.append_array(_faults(label, canvas))
						_host.queue_free()
	assert_array(faults).is_empty()


## The figures of the issue, before the change: 8 people at 1.25 over the objective by 38 to 106
## units. A column that fits keeps its names and its one box to a row: only the pages and sizes
## that were over it come in pairs. The round card on one row (#1305) took 70 units off the
## figures, so at 1.25 only the eight people with the seven bots (the strip of chips) are over it.
func test_only_the_largest_interface_size_takes_the_pairs() -> void:
	for page in PHONES:
		for ui_scale in UI_SCALES:
			for bots in [0, NightHost.MAX_PLAYERS - 1]:
				var canvas := _page(page, ui_scale)
				_night(canvas, NightHost.MAX_PLAYERS, bots)
				await _settle()
				var label := "%s at %s, %d bots" % [Vector2i(page.x, page.y), ui_scale, bots]
				assert_bool(_hud.points.pairs).override_failure_message(label).is_equal(
					ui_scale > 1.2 and bots > 0
				)
				_host.queue_free()


## A column in pairs is still a thing to read and to hold: its boxes keep the type of a compact
## box, every number is inside its box, and the column is at least as tall as the strip's fingertip
## (the place a held finger opens the scoreboard from, #1295).
func test_a_column_in_pairs_keeps_its_type_and_stays_a_place_to_hold() -> void:
	var canvas := _page(PHONES[1], 1.25)
	_night(canvas, NightHost.MAX_PLAYERS, NightHost.MAX_PLAYERS - 1)
	await _settle()
	var points := _hud.points
	assert_bool(points.pairs).is_true()
	var left := _rect(points).position.x
	var seen := {}
	for entry in points.shown:
		if entry.has("chip"):
			continue
		var box := points.box_of(int(entry["id"]))
		if box.is_local:
			assert_float(box.size.x).is_equal(HudStyle.COLUMN)
			continue
		assert_bool(box.paired).is_true()
		assert_float(box.size.x).is_equal(HudPlayerBox.PAIR_WIDTH)
		assert_float(box.size.y).is_equal(HudPlayerBox.COMPACT_HEIGHT)
		# The type of a compact box (24), never under the HUD's own floor.
		var size_px := box._number.get_theme_font_size(&"font_size")
		assert_int(size_px).is_greater_equal(HudStyle.MIN_TEXT)
		assert_int(size_px).is_equal(HudStyle.TEXT)
		assert_float(box.number_width()).is_less_equal(box.number_size().x + 0.5)
		# The number sits inside the box from side to side (its label is a line high, which is a
		# little more than a compact box, as in every compact box).
		assert_float(box._number.position.x).is_greater_equal(HudPlayerBox.PADDING)
		assert_float(box._number.position.x + box._number.size.x).is_less_equal(box.size.x)
		seen[Vector2(box.get_global_rect().position.x - left, box.get_global_rect().position.y)] = true
	# Seven teammates stand in two columns of four rows (the last row has one).
	var xs := {}
	var ys := {}
	for at: Vector2 in seen:
		xs[roundf(at.x)] = true
		ys[roundf(at.y)] = true
	assert_int(xs.size()).is_equal(2)
	assert_int(ys.size()).is_equal(4)
	assert_float(points.size.y).is_greater_equal(MenuScale.tap_units(get_window(), true))
	assert_float(points.size.x).is_equal(HudStyle.COLUMN)


## What a pair shows of a teammate: the points, or DOWN in the danger colour while they are down,
## with no name, level badge or emblem (a half row has not the room), keeping the card and frame.
func test_a_paired_box_shows_the_points_or_down_and_nothing_a_half_row_cannot_hold() -> void:
	var canvas := _page(PHONES[1], 1.25)
	_night(canvas, NightHost.MAX_PLAYERS, NightHost.MAX_PLAYERS - 1)
	_hud.state.apply_event({"type": &"points_changed", "player_id": 3, "total": 12500, "delta": 0})
	_hud.state.set_player_level(3, 14, 2)
	_hud.state.set_player_plate(3, &"cartoon", &"walk_in", &"chrome")
	await _settle()
	var box := _hud.points.box_of(3)
	assert_bool(box.paired).is_true()
	assert_str(box.number_text).is_equal("12500")
	assert_bool(box._name.visible).is_false()
	assert_object(box.shown_level).is_equal(Vector2i.ZERO)
	assert_str(box.shown_emblem).is_equal("")
	assert_str(box.shown_card).is_equal("cartoon")
	assert_str(box.shown_frame).is_equal("chrome")
	_fixture.act(RulesAction.set_downed(3, true))
	await _settle()
	assert_str(box.number_text).is_equal("DOWN")
	var danger := UITokens.active().danger
	var down_ink := HudPlayerBox.legible(danger, box.fill(), HudPlayerBox.DOWN_CONTRAST)
	assert_object(box._number.get_theme_color(&"font_color")).is_equal(down_ink)
	_fixture.act(RulesAction.set_downed(3, false))
	await _settle()
	assert_str(box.number_text).is_equal("12500")
	assert_object(box._number.get_theme_color(&"font_color")).is_equal(box.ink)


## Where the room is enough nothing changes: names, badges and one box to a row, as before, and on
## any screen with no touch layout (the desktop and a pad) the column never goes to pairs, however
## small the canvas.
func test_a_desktop_and_a_pad_keep_one_box_to_a_row_at_every_canvas() -> void:
	for canvas in [Vector2(1536, 864), Vector2(1920, 1080), Vector2(1024, 576)]:
		_host = auto_free(Control.new())
		_host.size = canvas
		add_child(_host)
		_fixture = HudFixture.make(_host, NightHost.MAX_PLAYERS, 1958, false, 7)
		_hud = _fixture.hud
		_fixture.into_round_one()
		_hud.state.set_area("The Concession Stand", "Light the booth to open the back lot")
		await _settle()
		assert_bool(_hud.points.pairs).is_false()
		assert_float(_hud.points.room).is_equal(INF)
		assert_bool(_hud.points.box_of(2).paired).is_false()
		assert_float(_hud.points.box_of(2).size.x).is_equal(HudStyle.COLUMN)
		_host.queue_free()


## Putting the touch layout away puts the names back, and a smaller room takes them again.
func test_the_pairs_follow_the_touch_layout() -> void:
	var canvas := _page(PHONES[1], 1.25)
	_night(canvas, NightHost.MAX_PLAYERS, NightHost.MAX_PLAYERS - 1)
	await _settle()
	assert_bool(_hud.points.pairs).is_true()
	_hud.touch_layout = false
	await _settle()
	assert_bool(_hud.points.pairs).is_false()
	assert_float(_hud.points.box_of(2).size.x).is_equal(HudStyle.COLUMN)
	assert_str(_hud.points.box_of(2).name_text).is_equal("MOE")
	_hud.touch_layout = true
	await _settle()
	assert_bool(_hud.points.pairs).is_true()


## The room is measured against the objective at its tallest, so the column does not move or change
## shape when the words do: one line, two lines and none leave the column where it is.
func test_the_column_does_not_move_when_the_objective_words_change() -> void:
	var canvas := _page(PHONES[1], 1.25)
	_night(canvas, NightHost.MAX_PLAYERS, NightHost.MAX_PLAYERS - 1)
	await _settle()
	var room := _hud.points.room
	var top := _rect(_hud.points).position.y
	for words in [
		"Light the booth", "", "Light the booth to open the back lot and then more words"
	]:
		_hud.state.set_area("The Concession Stand" if words != "" else "", words)
		await _settle()
		assert_float(_hud.points.room).is_equal(room)
		assert_float(_rect(_hud.points).position.y).is_equal(top)
		assert_bool(_hud.points.pairs).is_true()
		var tall := _hud.objective.max_height()
		assert_float(_rect(_hud.objective).size.y).is_less_equal(tall)


## The objective's tallest height is the card's real one with two lines on every page and size.
func test_the_objectives_tallest_height_is_its_height_with_two_lines() -> void:
	for page in PHONES:
		for ui_scale in UI_SCALES:
			var canvas := _page(page, ui_scale)
			_night(canvas, 2, 0)
			await _settle()
			assert_float(_rect(_hud.objective).size.y).is_equal(_hud.objective.max_height())
			_host.queue_free()


## The rows' arithmetic: the height the column measures for one box to a row and for pairs is what
## it lays out, and no two of its boxes or chips overlap, for every party the game has.
func test_the_stack_height_is_what_it_lays_out_and_its_boxes_never_overlap() -> void:
	_host = auto_free(Control.new())
	_host.size = Vector2(1920, 1080)
	add_child(_host)
	for people in range(1, NightHost.MAX_PLAYERS + 1):
		for bots in [0, 3, NightHost.MAX_PLAYERS - 1]:
			for columns in [1, 2]:
				var fixture := HudFixture.make(_host, people, 1958, false, bots)
				fixture.into_round_one()
				var points := fixture.hud.points
				# No room at all puts the teammates in pairs; no limit keeps one to a row.
				points.room = INF if columns == 1 else 0.0
				await await_idle_frame()
				await await_idle_frame()
				var label := "%d people, %d bots, %d columns" % [people, bots, columns]
				var stack: HudPointsStack = points._column
				assert_float(stack.size.y).override_failure_message(label).is_equal(
					stack.height_at(stack.mate_columns)
				)
				var rects: Array[Rect2] = []
				for child in stack.get_children():
					if (child as Control).visible:
						rects.append(Rect2((child as Control).position, (child as Control).size))
				for i in rects.size():
					assert_bool(Rect2(Vector2.ZERO, stack.size).encloses(rects[i])).is_true()
					for j in range(i + 1, rects.size()):
						(
							assert_bool(rects[i].intersects(rects[j]))
							. override_failure_message(
								"%s: %s meets %s" % [label, rects[i], rects[j]]
							)
							. is_false()
						)
				fixture.hud.queue_free()
				await await_idle_frame()
