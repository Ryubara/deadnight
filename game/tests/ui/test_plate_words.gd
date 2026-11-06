extends GdUnitTestSuite
## Whether the words over a calling card can be read, measured from the pixels a player sees
## (#1189). The design check (`test_plate_boxes`: the ink against the seat's colour) says the ink
## was chosen for the colour behind it; this one asks what is on the screen: in a night on a phone a
## unit is 0.72 of a pixel (a page of 844 by 390 at a pixel ratio of 2; 0.36 at a ratio of 1), the
## outline round the words was about a pixel wide and the words a smear of the ink and the card.
##
## Every place that puts words over a card is built (the player box of a party of four, the compact
## box of a party of eight, the box of downed players, the scoreboard, the end board, the lobby's
## seats), once for each card the game has, at the factor that place really runs at (a night: the
## interface size alone; the lobby: the menu's phone factor). The words are the labels whose text
## lies over a card. Each place is drawn three times: as it is, with the words made clear (the
## ground under a word: the card, the strip and everything else the place draws) and with the words
## in one flat colour (`MARKER`: where the letters are, whatever the ground is).
##
## Two readings of a word. `strong`, the issue's: the strongest pixel of the word against the
## ground round it, as a WCAG contrast ratio (4.5 is AA for text). `edge`: the median pixel the
## letters mostly cover against the pixels beside it (0 for a smear: no pixel is half letter).
##
## Needs a real renderer (the tests of a headless run skip: CI does not run them):
## `gds godot -- --path game -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd
## -a res://tests/ui/test_plate_words.gd -c --ignoreHeadlessMode`. Set `PLATE_WORDS_OUT` to a file
## to keep every reading and `PLATE_WORDS_SHOTS` to a folder to keep the pictures.
## docs/research/plate-words-contrast.md has the numbers.

const CANVAS := Vector2i(1920, 1080)
## A phone held sideways: its CSS size, which a window of this size is (a unit is 0.36 of a pixel in
## a night), and the canvas a real phone page has at a pixel ratio of 2 and of 3 (`NightScreen` runs
## the HUD at the interface size alone: 0.72 and 1.08 pixels to the unit).
const PHONE := Vector2i(844, 390)
const PHONE_X2 := Vector2i(1688, 780)
const PHONE_X3 := Vector2i(2532, 1170)
## The ratio the words must reach (WCAG AA for text).
const MIN_RATIO := 4.5
## What the letters must have against what touches them (the median pixel the letters mostly cover).
const MIN_EDGE := 2.0
## A pixel the words changed: the three channels' difference from the ground, summed.
const CHANGED := 0.02
## The colour the letters are drawn in to be found: no other thing in a place is it.
const MARKER := Color(1.0, 0.0, 1.0, 1.0)
const SKIP_WHY := "reads pixels: needs a renderer, not the headless dummy"
const PARTY: Array[int] = [3, 7, 12, 55, 30, 41, 9, 23]
const NAMES: Array[String] = ["Ruby", "Moe", "Dee", "Cal", "Ned", "Ivy", "Sal", "Pat"]

var _window_size := Vector2i.ZERO
var _window_scale := 1.0
var _lines: Array[String] = []
## Every reading of a run: {"place", "reading", "card", "seat", "word", "strong", "core"}.
var _readings: Array[Dictionary] = []


func before_test() -> void:
	UIMotion.reduced = false
	LevelIcons.release()
	HudPortrait.live = false
	_window_size = get_tree().root.size
	_window_scale = get_tree().root.content_scale_factor


func after_test() -> void:
	HudPortrait.live = true
	Input.action_release(Hud.SCOREBOARD_ACTION)
	LobbyScreen.opener = Callable()
	get_tree().root.size = _window_size
	get_tree().root.content_scale_factor = _window_scale
	var path := OS.get_environment("PLATE_WORDS_OUT")
	if not path.is_empty() and not _lines.is_empty():
		var file := FileAccess.open(path, FileAccess.READ_WRITE)
		if file == null:
			file = FileAccess.open(path, FileAccess.WRITE)
		file.seek_end()
		file.store_string("\n".join(_lines) + "\n")
	_lines.clear()


func _skip() -> bool:
	return DisplayServer.get_name() == "headless"


# --- The readings ---


## The game's window at `size`; a night has the interface size alone (1.0 here), a menu the
## phone factor (`MenuScale.factor`). Returns the host the place is built in.
func _window(size: Vector2i, night: bool) -> Control:
	var window := get_tree().root
	window.size = size
	window.content_scale_factor = 1.0 if night else MenuScale.factor(size, 1.0)
	var host := Control.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	window.add_child(host)
	return host


func _picture() -> Image:
	for _i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	return get_tree().root.get_texture().get_image()


static func _luminance(c: Color) -> float:
	return HudPlayerBox._luminance(c)


static func _ratio(a: float, b: float) -> float:
	return (maxf(a, b) + 0.05) / (minf(a, b) + 0.05)


## The labels under `root` whose text lies over a card, with the pixels of the text.
func _words(root: Node) -> Array[Dictionary]:
	var cards: Array[Rect2] = []
	for node in root.find_children("*", "CardArt", true, false):
		var card := node as CardArt
		if card.is_visible_in_tree() and card.card_id != &"":
			var size := card.size
			if card.by_height:
				size.x = minf(size.x, size.y * PlateCompose.CARD_SIZE.x / PlateCompose.CARD_SIZE.y)
			cards.append(Rect2(card.global_position, size))
	var window := get_tree().root
	var found: Array[Dictionary] = []
	for node in root.find_children("*", "Label", true, false):
		var label := node as Label
		if not label.is_visible_in_tree() or label.text.is_empty() or label.size.x < 1.0:
			continue
		var font := label.get_theme_font(&"font")
		var px := label.get_theme_font_size(&"font_size")
		var width := minf(HudStyle.text_width(font, label.text, px), label.size.x)
		var left := 0.0
		match label.horizontal_alignment:
			HORIZONTAL_ALIGNMENT_RIGHT:
				left = label.size.x - width
			HORIZONTAL_ALIGNMENT_CENTER:
				left = (label.size.x - width) * 0.5
		var rect := Rect2(label.global_position + Vector2(left, 0.0), Vector2(width, label.size.y))
		var over := false
		for card in cards:
			over = over or card.intersects(rect)
		if not over:
			continue
		var transform := window.get_final_transform()
		var pixels := Rect2(transform * rect.position, rect.size * transform.get_scale())
		found.append({"label": label, "rect": pixels})
	return found


## The strongest pixel of a word against its ground. The word's pixels are the ones the two pictures
## differ in; its ground is every other pixel of the word's own box, the rows and columns the word
## covers and one pixel round (a label is taller than its letters, and the card above and below a
## strip is not what the letters are read against).
func _read(word: Dictionary, seen: Image, ground: Image, flat: Image) -> Dictionary:
	var rect := word["rect"] as Rect2
	var size := seen.get_size()
	var from := Vector2i(rect.position.floor()).clamp(Vector2i.ZERO, size)
	var to := Vector2i(rect.end.ceil()).clamp(Vector2i.ZERO, size)
	var lit: Array[Vector3i] = []
	for y in range(from.y, to.y):
		for x in range(from.x, to.x):
			var s := seen.get_pixel(x, y)
			var g := ground.get_pixel(x, y)
			if absf(s.r - g.r) + absf(s.g - g.g) + absf(s.b - g.b) > CHANGED:
				lit.append(Vector3i(x, y, 0))
	if lit.is_empty():
		return {}
	var box := Rect2i(lit[0].x, lit[0].y, 1, 1)
	for p in lit:
		box = box.expand(Vector2i(p.x, p.y))
	box = box.grow(1).intersection(Rect2i(Vector2i.ZERO, size))
	var strongest_hi := 0.0
	var strongest_lo := 2.0
	var ground_sum := 0.0
	var ground_n := 0
	for y in range(box.position.y, box.end.y):
		for x in range(box.position.x, box.end.x):
			var s := seen.get_pixel(x, y)
			var g := ground.get_pixel(x, y)
			if absf(s.r - g.r) + absf(s.g - g.g) + absf(s.b - g.b) > CHANGED:
				strongest_hi = maxf(strongest_hi, _luminance(s))
				strongest_lo = minf(strongest_lo, _luminance(s))
			else:
				ground_sum += _luminance(g)
				ground_n += 1
	if ground_n == 0:
		return {}
	var under := ground_sum / float(ground_n)
	return {
		"strong": maxf(_ratio(strongest_hi, under), _ratio(strongest_lo, under)),
		"edge": _edge(box, seen, ground, flat),
	}


## How the letters stand out from what touches them: the median, over the pixels the letters mostly
## cover (at least half `MARKER` in the flat picture), of the contrast between the pixel as it is
## drawn and the average of the pixels beside it that the letters do not cover. 0 when no pixel is
## half letter (a smear: the strokes are thinner than a pixel).
func _edge(box: Rect2i, seen: Image, ground: Image, flat: Image) -> float:
	var size := seen.get_size()
	var core := {}
	for y in range(box.position.y, box.end.y):
		for x in range(box.position.x, box.end.x):
			if _coverage(flat, ground, x, y) >= 0.5:
				core[Vector2i(x, y)] = true
	if core.is_empty():
		return 0.0
	var ratios: Array[float] = []
	for key: Vector2i in core:
		var around := 0.0
		var n := 0
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var at := key + Vector2i(dx, dy)
				if core.has(at) or at.x < 0 or at.y < 0 or at.x >= size.x or at.y >= size.y:
					continue
				around += _luminance(seen.get_pixel(at.x, at.y))
				n += 1
		if n > 0:
			ratios.append(_ratio(_luminance(seen.get_pixel(key.x, key.y)), around / float(n)))
	if ratios.is_empty():
		return 0.0
	ratios.sort()
	return ratios[ratios.size() / 2]


## How much of `MARKER` a pixel of `flat` is over the same pixel of `ground`, 0 to 1.
func _coverage(flat: Image, ground: Image, x: int, y: int) -> float:
	var g := ground.get_pixel(x, y)
	var p := flat.get_pixel(x, y)
	var d := Vector3(MARKER.r - g.r, MARKER.g - g.g, MARKER.b - g.b)
	var v := Vector3(p.r - g.r, p.g - g.g, p.b - g.b)
	var length := d.length_squared()
	return v.dot(d) / length if length > 0.01 else 0.0


## Draws `place` (already built in `host`), hides its words, draws it again and reads every word.
func _measure(
	host: Control, place: String, reading: String, card: StringName, seat_of: Callable
) -> void:
	var words := _words(host)
	var seen := await _picture()
	for word in words:
		(word["label"] as Label).modulate.a = 0.0
	var ground := await _picture()
	for word in words:
		var label := word["label"] as Label
		label.modulate.a = 1.0
		# Flat: only the letters, in a colour nothing else is (a dark outline on a dark card is not
		# seen by a difference of two pictures).
		label.add_theme_color_override(&"font_color", MARKER)
		label.add_theme_color_override(&"font_shadow_color", Color.TRANSPARENT)
		if label is HudLabel:
			(label as HudLabel).halo_size = 0
	var flat := await _picture()
	var shots := OS.get_environment("PLATE_WORDS_SHOTS")
	for word in words:
		var out := _read(word, seen, ground, flat)
		if out.is_empty():
			continue
		var label := word["label"] as Label
		var line := {
			"place": place,
			"reading": reading,
			"card": card,
			"seat": int(seat_of.call(label)),
			"word": "%s %s" % [label.name, label.text],
			"strong": float(out["strong"]),
			"edge": float(out["edge"]),
		}
		_readings.append(line)
		_lines.append(
			(
				"%s | %s | %s | seat %d | %s | %.2f | %.2f"
				% [place, reading, card, line["seat"], line["word"], line["strong"], line["edge"]]
			)
		)
	if not shots.is_empty() and not words.is_empty():
		seen.save_png(
			"%s/%s_%s_%s.png" % [shots, place.replace(" ", "_"), reading.replace(" ", "_"), card]
		)


# --- The places ---


func _hud(host: Control, card: StringName, count: int) -> HudFixture:
	var fixture := HudFixture.make(host, count)
	var state := fixture.hud.state
	for i in count:
		state.set_player_level(i + 1, PARTY[i], PARTY[i])
		state.set_player_plate(i + 1, card, &"admit_one", &"gold")
	state.round_number = 9
	return fixture


## The seat a player box stands for: the seats are the player ids in order.
func _seat_of_box(label: Label) -> int:
	var node: Node = label
	while node != null and not node is HudPlayerBox:
		node = node.get_parent()
	return (node as HudPlayerBox).player_id if node != null else 0


## The seat a row of a board stands for: the name in the row (the fixture's names, in seat order).
func _seat_of_row(label: Label) -> int:
	var node: Node = label
	while node != null and not node is PanelContainer:
		node = node.get_parent()
	if node == null:
		return 0
	for seat in NAMES.size():
		for text in node.find_children("*", "Label", true, false):
			if (text as Label).text.to_lower() == NAMES[seat].to_lower():
				return seat + 1
	return 0


func _hud_place(place: String, count: int, board: String, downed: Array[int] = []) -> void:
	var cards := PlateCatalog.shipped().ids(PlateCatalog.CARD)
	var readings := {
		"1080p": [CANVAS, true],
		"night on a phone": [PHONE, true],
		"night on a phone x2": [PHONE_X2, true],
		"night on a phone x3": [PHONE_X3, true],
	}
	for reading: String in readings:
		for card in cards:
			var host := _window(readings[reading][0], readings[reading][1])
			var fixture := _hud(host, card, count)
			for id in downed:
				fixture.act(RulesAction.set_downed(id, true))
			var root: Node = fixture.hud
			var seat_of := Callable(self, "_seat_of_box")
			match board:
				"scoreboard":
					Input.action_press(Hud.SCOREBOARD_ACTION)
					fixture.hud.scoreboard.set_shown(true)
					fixture.hud.scoreboard.refresh()
					root = fixture.hud.scoreboard
					seat_of = Callable(self, "_seat_of_row")
				"end board":
					var end := HudEndBoard.new()
					fixture.hud.add_child(end)
					end.show_results(fixture.hud.state, "THE CROWD WINS", "Leave")
					root = end
					seat_of = Callable(self, "_seat_of_row")
			await get_tree().process_frame
			await _measure(root as Control, place, reading, card, seat_of)
			host.queue_free()
			await get_tree().process_frame


func _lobby(card: StringName, seats: Array) -> Control:
	var members: Array = []
	for i in seats.size():
		(
			members
			. append(
				{
					"userId": "u%d" % i,
					"name": NAMES[int(seats[i]) - 1],
					"seat": seats[i],
					"host": i == 0,
					"away": false,
					"level": PARTY[int(seats[i]) - 1],
					"icon": "level_%02d" % PARTY[int(seats[i]) - 1],
					"card": card,
					"emblem": "admit_one",
					"frame": "gold",
				}
			)
		)
	var held := {
		"id": "l1",
		"code": "ABC234",
		"hostId": "u0",
		"maxPlayers": seats.size(),
		"members": members,
		"state": "open",
		"round": null,
	}
	var api := LobbyFixture.FakeApi.new(self)
	api.lobby = held
	LobbyScreen.opener = func() -> void: pass
	var screen := (load(LobbyScreen.SCREEN) as PackedScene).instantiate() as LobbyScreen
	screen.params = {"lobby": held, "api": api}
	# The router's stage gives every screen the game's theme: without it the seats are set in
	# Godot's default font and a row is half as tall.
	var host := _window(get_tree().root.size, false)
	host.theme = UIThemeBuilder.build(UITokens.active())
	host.add_child(screen)
	screen.watch.every = 3600.0
	await screen.screen_enter()
	await get_tree().process_frame
	return host


func _lobby_place() -> void:
	var cards := PlateCatalog.shipped().ids(PlateCatalog.CARD)
	for reading: String in ["1080p", "phone in the menu", "phone in the menu x2"]:
		var size := (
			CANVAS
			if reading == "1080p"
			else (PHONE if reading == "phone in the menu" else PHONE_X2)
		)
		for card in cards:
			# The panel scrolls on a phone and only the first seat is on screen: one lobby for a seat.
			var groups: Array = [[1, 2, 3, 4]] if size == CANVAS else [[1], [2], [3], [4]]
			for seats: Array in groups:
				get_tree().root.size = size
				var host := await _lobby(card, seats)
				var seat_of := func(label: Label) -> int:
					return seats[0] if seats.size() == 1 else _seat_of_lobby(host, label)
				await _measure(host, "lobby seat", reading, card, seat_of)
				host.queue_free()
				await get_tree().process_frame


## The seat of a lobby row by the label's height on the screen: the rows are in seat order.
func _seat_of_lobby(host: Control, label: Label) -> int:
	var rows: Array = (host.get_child(0) as LobbyScreen).get("_seat_rows")
	for i in rows.size():
		var row := rows[i]["level"] as Control
		if absf(row.global_position.y - label.global_position.y) < 30.0:
			return i + 1
	return 0


## Writes the table of a place: for each reading and seat, the median and the worst over the cards
## of `strong` (against `MIN_RATIO`) and of `edge` (against `MIN_EDGE`). Returns the failing ones.
func _table(place: String) -> Array[String]:
	var out: Array[String] = []
	var by_key := {}
	for r in _readings:
		if r["place"] != place:
			continue
		var key := "%s | seat %d" % [r["reading"], r["seat"]]
		if not by_key.has(key):
			by_key[key] = []
		(by_key[key] as Array).append(r)
	var keys := by_key.keys()
	keys.sort()
	for key: String in keys:
		var rows: Array = by_key[key]
		var strong: Array = rows.map(func(r: Dictionary) -> float: return r["strong"])
		var edge: Array = rows.map(func(r: Dictionary) -> float: return r["edge"])
		strong.sort()
		edge.sort()
		var low_strong := strong.filter(func(v: float) -> bool: return v < MIN_RATIO).size()
		var low_edge := edge.filter(func(v: float) -> bool: return v < MIN_EDGE).size()
		_lines.append(
			(
				"TABLE %s | %s | readings %d | strong median %.2f worst %.2f below %d "
				+ (
					"| edge median %.2f worst %.2f below %d"
					% [
						place,
						key,
						rows.size(),
						strong[strong.size() / 2],
						strong[0],
						low_strong,
						edge[edge.size() / 2],
						edge[0],
						low_edge
					]
				)
			)
		)
		if low_strong > 0 or low_edge > 0:
			(
				out
				. append(
					(
						"%s %s: strongest pixel worst %.2f (%d below %.1f), letters worst %.2f (%d below %.1f) of %d"
						% [
							place,
							key,
							strong[0],
							low_strong,
							MIN_RATIO,
							edge[0],
							low_edge,
							MIN_EDGE,
							rows.size()
						]
					)
				)
			)
	return out


func _check(place: String) -> void:
	var failing := _table(place)
	(
		assert_array(failing)
		. override_failure_message("words over a card hard to read: %s" % ["; ".join(failing)])
		. is_empty()
	)


# --- The tests ---


func test_the_words_on_a_player_box_read_on_every_card(
	_do_skip := _skip(), _skip_reason := SKIP_WHY
) -> void:
	await _hud_place("player box", 4, "")
	_check("player box")


func test_the_words_on_a_compact_box_read_on_every_card(
	_do_skip := _skip(), _skip_reason := SKIP_WHY
) -> void:
	await _hud_place("compact box", 8, "")
	_check("compact box")


func test_the_words_on_a_downed_players_box_read_on_every_card(
	_do_skip := _skip(), _skip_reason := SKIP_WHY
) -> void:
	await _hud_place("downed box", 4, "", [2, 3, 4])
	_check("downed box")


func test_the_words_on_the_scoreboard_read_on_every_card(
	_do_skip := _skip(), _skip_reason := SKIP_WHY
) -> void:
	await _hud_place("scoreboard", 4, "scoreboard")
	_check("scoreboard")


func test_the_words_on_the_end_board_read_on_every_card(
	_do_skip := _skip(), _skip_reason := SKIP_WHY
) -> void:
	await _hud_place("end board", 4, "end board")
	_check("end board")


func test_the_words_on_a_lobby_seat_read_on_every_card(
	_do_skip := _skip(), _skip_reason := SKIP_WHY
) -> void:
	await _lobby_place()
	_check("lobby seat")
