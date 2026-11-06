extends GdUnitTestSuite
## Where the level's digits and its icon sit on the page, read from the pixels (#1161). The two are
## placed from a box each, and a box is not what is seen: a font's digits sit at their own height in
## the line (the line keeps room for a descender), and an icon's art has padding of its own in its
## cell, a different amount for each of its three frames. So the test draws every place the badge
## is shown and reads the rows the digits' glyphs cover and the rows the icon covers, each from a
## picture where only that thing is in one flat colour (`MARKER`: the label's own colour, outline
## and shadow set clear; the icon atlas with its colours replaced and its alpha kept), so that no
## colour of the place can hide an edge. Both must have one vertical centre, within a tolerance.
##
## What counts as the icon: its body, the ink above the strip of five progress bulbs
## (`LevelIcons.BULBS_TOP`: the bulbs' top edge in the 128 px source, bulbs at y 120, radius 5.2,
## stroke 2). The bulbs are small dots under the badge, and a player reads the badge by its frame
## and glyph, so the body is what has to meet the digits; the centre of the whole ink (bulbs
## included, 1 to 2 units lower) is reported beside it in `ink.txt` as "to whole".
##
## Two ways of reading the same place:
## - `exact`: a viewport four times the canvas (the geometry, with no pixel rounding in it), the
##   gap in canvas units (a unit is a pixel at 1080p).
## - `real`: the game's own window at the size and content scale a player has (a desktop at the
##   three interface sizes; a phone, 844 x 390, at the factor the place really runs at: the HUD's
##   places at the night's, the interface size alone, 0.36 pixels to the unit; the lobby at the
##   menu's phone factor 2), the gap in the pixels a player sees.
##
## Needs a real renderer (the tests of a headless run skip: CI does not run them): `gds godot --
## --path game -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/ui/test_level_ink.gd
## -c --ignoreHeadlessMode`. Set `LEVEL_INK_SHOTS` to a folder to keep the pictures and the numbers
## (docs/research/level-badge-alignment.md).

const CANVAS := Vector2i(1920, 1080)
const PHONE := Vector2i(844, 390)
## The same phone as a web page has it (#1197): an 844 x 390 CSS pixel page at the pixel ratio of 2
## the game reports is a 1688 x 780 window. The menu's factor 2 and the night's 1 then give twice
## the pixels to a unit that `PHONE` does (1.44 and 0.72 against 0.72 and 0.36), and the digits and
## the icon land on other whole pixels, so the places are read there too.
const PAGE := Vector2i(1688, 780)
const PAGE_RATIO := 2.0
## Largest gap between the digits' centre and the icon body's. The engine sets a glyph on a whole
## unit and the icon's art lands where it falls, so half a unit is the best a place can do:
## 0.75 in the `exact` reading (which has no rounding of its own); in the `real` ones the rows of
## glyph and icon are each whole pixels too (a centre read from them is off by up to a half
## each), so 1 px at one pixel to the unit, and 1.5 px where a unit is not a pixel (a phone's 0.72,
## the interface sizes 0.8 and 1.25: the glyphs are sized to whole pixels).
const TOLERANCE_EXACT := 0.75
const TOLERANCE_REAL := 1.0
const TOLERANCE_SCALED := 1.5
## How many times the canvas the `exact` viewport is.
const SAMPLE := 4
## A one-digit level and a two-digit one, of each of the three frames the art has (a ticket for
## levels 1 to 5, a token for 6 to 10, a sign for 11 to 15; the same by tier after).
const LEVELS: Array[int] = [3, 7, 12, 55]
## A party of eight (the compact boxes show from five): the first four are `LEVELS`.
const PARTY: Array[int] = [3, 7, 12, 55, 30, 41, 9, 23]
## The interface sizes the settings offer on a desktop (`SettingsService.UI_SCALE`: 0.8 to 1.25).
const UI_SCALES: Array[float] = [0.8, 1.0, 1.25]
## The interface sizes read on a phone in a night. Not 0.8: there a unit is 0.29 pixels, the digits
## are one to four rows tall and a row reading cannot tell a half unit from a unit and a half (the
## `exact` reading has the geometry at every size).
const PHONE_NIGHT_SCALES: Array[float] = [1.0, 1.25]
## The colour the digits and the icons are drawn in to be read: no other thing in a place is it.
const MARKER := Color(1.0, 0.0, 1.0, 1.0)
const SKIP_WHY := "reads pixels: needs a renderer, not the headless dummy"

var _tokens := UITokens.active()
var _report: Array[String] = []
var _window_size := Vector2i.ZERO
var _window_scale := 1.0
var _touch: Variant


func before_test() -> void:
	# Reduced motion holds a marquee panel's chase of bulbs still: it is lit in other bulbs in each of
	# a place's three pictures, and a bulb under the digits is read as ink (#1348).
	UIMotion.reduced = true
	LevelIcons.release()
	LevelTag.release()
	HudPortrait.live = false
	_window_size = get_tree().root.size
	_window_scale = get_tree().root.content_scale_factor
	_touch = TouchMode.device_is_touch


func after_test() -> void:
	UIMotion.reduced = false
	HudPortrait.live = true
	Input.action_release(Hud.SCOREBOARD_ACTION)
	LobbyScreen.opener = Callable()
	get_tree().root.size = _window_size
	get_tree().root.content_scale_factor = _window_scale
	TouchMode.device_is_touch = _touch
	PageSize.css_override = null
	var folder := OS.get_environment("LEVEL_INK_SHOTS")
	if not folder.is_empty() and not _report.is_empty():
		var file := FileAccess.open(folder.path_join("ink.txt"), FileAccess.READ_WRITE)
		if file == null:
			file = FileAccess.open(folder.path_join("ink.txt"), FileAccess.WRITE)
		file.seek_end()
		file.store_string("\n".join(_report) + "\n")
	_report.clear()


# --- The two ways of reading ---


## A way of drawing a place and reading its picture.
class Reading:
	extends RefCounted
	var name := ""
	## The host the place is built in, and how to take a picture of it.
	var host: Control
	var viewport: Viewport
	## Pixels of the picture for one canvas unit.
	var scale := 1.0
	## How many pixels of the picture are one pixel of the player's screen.
	var oversample := 1.0
	var image: Image
	## The largest gap between the digits' and the icon's centres this reading accepts, in the pixels
	## of the player's screen.
	var tolerance := TOLERANCE_EXACT


## A viewport `SAMPLE` times the canvas, with a control of the canvas's size in it.
func _exact() -> Reading:
	var reading := Reading.new()
	reading.name = "exact"
	var port := SubViewport.new()
	port.size = CANVAS * SAMPLE
	port.transparent_bg = true
	port.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	port.gui_disable_input = true
	add_child(auto_free(port))
	port.canvas_transform = Transform2D.IDENTITY.scaled(Vector2.ONE * float(SAMPLE))
	var host := Control.new()
	host.size = Vector2(CANVAS)
	port.add_child(host)
	reading.host = host
	reading.viewport = port
	reading.scale = float(SAMPLE)
	reading.oversample = float(SAMPLE)
	return reading


## The game's window at `size`, at the player's interface size `ui_scale`. The factor is the one the
## screen under test really runs at: the menus and the lobby have the menu's phone factor (2 on a
## phone, `MenuScale.factor`); a night has the interface size alone (`NightScreen._ready`), which on
## a phone is about 0.36 pixels to the unit, half the menu's 0.72. `night` asks for the second.
func _real(size: Vector2i, ui_scale := 1.0, night := false) -> Reading:
	var reading := Reading.new()
	reading.name = "real_%dx%d_%sx%.2f" % [size.x, size.y, "night_" if night else "", ui_scale]
	var window := get_tree().root
	window.size = size
	if size == PAGE:
		TouchMode.device_is_touch = true
		PageSize.css_override = Vector2(size) / PAGE_RATIO
	else:
		PageSize.css_override = null
	window.content_scale_factor = ui_scale if night else MenuScale.factor(size, ui_scale)
	var host := Control.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	window.add_child(host)
	auto_free(host)
	reading.host = host
	reading.viewport = window
	reading.scale = window.get_final_transform().get_scale().x
	reading.oversample = 1.0
	var whole_scale := is_equal_approx(reading.scale, 1.0)
	reading.tolerance = TOLERANCE_REAL if whole_scale else TOLERANCE_SCALED
	return reading


func _picture(reading: Reading) -> void:
	for _i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	reading.image = reading.viewport.get_texture().get_image()


# --- The measuring ---


## A badge in a place: the icon and the digits as nodes (made clear for the ground picture and
## recoloured for the flat one), or only as rectangles when the place draws them itself (the tags:
## its hook takes them away).
class Badge:
	extends RefCounted
	var label := ""
	var icon_node: CanvasItem
	var level_node: CanvasItem
	## Canvas rectangles, for a node, read from it.
	var icon_rect := Rect2()
	var level_rect := Rect2()
	var ink := Color.WHITE
	var icon_level := 1


func _node_badge(
	label: String, icon: CanvasItem, level: Label, ink: Color, icon_level: int
) -> Badge:
	var badge := Badge.new()
	badge.label = label
	badge.icon_node = icon
	badge.level_node = level
	badge.ink = ink
	badge.icon_level = icon_level
	return badge


func _refresh_rects(badges: Array[Badge]) -> void:
	for badge in badges:
		if badge.icon_node != null:
			badge.icon_rect = _global(badge.icon_node)
			badge.level_rect = _global(badge.level_node)


func _global(node: CanvasItem) -> Rect2:
	var control := node as Control
	return Rect2(control.global_position, control.size)


func _clear(badges: Array[Badge], hidden: bool) -> void:
	for badge in badges:
		if badge.icon_node != null:
			badge.icon_node.modulate.a = 0.0 if hidden else 1.0
			badge.level_node.modulate.a = 0.0 if hidden else 1.0


## An atlas of the level icons' silhouettes: every pixel `MARKER`, the alpha as it was. Drawn in
## the icons' place, it shows where the art is whatever its colours and the ground's are (a dark
## outline on a dark card is not seen by a difference of the two).
func _flat_atlas() -> Texture2D:
	var image := LevelIcons.atlas().get_image()
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	for y in image.get_height():
		for x in image.get_width():
			image.set_pixel(x, y, Color(MARKER.r, MARKER.g, MARKER.b, image.get_pixel(x, y).a))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


func _recolour(badges: Array[Badge]) -> void:
	var flat := _flat_atlas()
	# What draws icons straight from the atlas (the tags over heads) takes the flat one.
	LevelIcons._atlases[LevelIcons.CELL_SMALL] = flat
	for badge in badges:
		if badge.icon_node is TextureRect:
			var cut := AtlasTexture.new()
			cut.atlas = flat
			cut.region = LevelIcons.region(badge.icon_level)
			(badge.icon_node as TextureRect).texture = cut
		if badge.level_node == null:
			continue
		var label := badge.level_node as Label
		label.add_theme_color_override(&"font_color", MARKER)
		label.add_theme_color_override(&"font_shadow_color", Color.TRANSPARENT)
		label.add_theme_color_override(&"font_outline_color", Color.TRANSPARENT)
		label.add_theme_constant_override(&"outline_size", 0)
		if label is HudLabel:
			(label as HudLabel).halo_size = 0


## How much of `ink` over `ground` the pixel (x, y) of `image` is, 0 to 1 and over (the pixel's
## difference from the ground along the ink's difference from it, four channels).
func _coverage(image: Image, ground: Image, ink: Color, x: int, y: int) -> float:
	var g := ground.get_pixel(x, y)
	var p := image.get_pixel(x, y)
	var d := Vector4(ink.r - g.r, ink.g - g.g, ink.b - g.b, ink.a - g.a)
	var v := Vector4(p.r - g.r, p.g - g.g, p.b - g.b, p.a - g.a)
	var length := d.length_squared()
	return v.dot(d) / length if length > 0.01 else 0.0


## The rows (picture pixels, first and one past the last) of `area` where `hit(x, y)` is true.
func _rows(reading: Reading, area: Rect2, hit: Callable) -> Vector2:
	var size := reading.image.get_size()
	var from := Vector2i((area.position * reading.scale).floor()).clamp(Vector2i.ZERO, size)
	# The pixels wholly inside the area (the body's area ends at the bulbs' edge, and a pixel the edge
	# crosses is partly bulb).
	var to := Vector2i((area.end * reading.scale).floor()).clamp(Vector2i.ZERO, size)
	var first := -1
	var last := -1
	for y in range(from.y, to.y):
		for x in range(from.x, to.x):
			if hit.call(x, y):
				if first < 0:
					first = y
				last = y
				break
	return Vector2(first, last + 1) if first >= 0 else Vector2.ZERO


## The gap between the digits' centre and the icon body's centre in the pixels of the player's
## screen (positive: the digits sit lower), for each badge of `badges`, recorded and returned.
## `ground` is the place with the badges made clear, `flat` the place with them in `MARKER`.
func _gaps(
	reading: Reading, badges: Array[Badge], ground: Image, flat: Image, place: String
) -> Array[float]:
	var out: Array[float] = []
	for badge in badges:
		var with_badge := reading.image
		# The icon: its silhouette in `MARKER` (the flat atlas), over the ground.
		var icon_rows := _rows(
			reading,
			badge.icon_rect.grow(1.0),
			func(x: int, y: int) -> bool: return _coverage(flat, ground, MARKER, x, y) >= 0.5
		)
		# The digits: flat in `MARKER` where the place's nodes can be recoloured, else in the ink the
		# place draws them in.
		var seen := flat if badge.level_node != null else with_badge
		var ink := MARKER if badge.level_node != null else badge.ink
		var s := reading.scale
		var digit_rows := _rows(
			reading,
			badge.level_rect.grow_individual(0.0, 8.0, 0.0, 8.0),
			func(x: int, y: int) -> bool: return _coverage(seen, ground, ink, x, y) >= 0.5
		)
		var name := "%s, %s, level %d" % [place, reading.name, badge.icon_level]
		(
			assert_bool(digit_rows == Vector2.ZERO)
			. override_failure_message(name + ": no digits seen")
			. is_false()
		)
		(
			assert_bool(icon_rows == Vector2.ZERO)
			. override_failure_message(name + ": no icon seen")
			. is_false()
		)
		# Whole: every frame's ink is at least 57 of 64 rows (the ticket's), so a shorter picture
		# is an icon that something is drawn over (a plate's frame). Where a pixel is more than a
		# unit (a phone in a night: 0.36 pixels to the unit) the first and last row, read at half
		# coverage, may each lose half a pixel: one pixel of slack.
		var slack := 1.0 / s if s < 1.0 else 0.0
		(
			assert_float((icon_rows.y - icon_rows.x) / s)
			. override_failure_message(name + ": the icon is covered (%s rows)" % [icon_rows])
			. is_greater_equal(LevelTag.ICON * 55.0 / 64.0 - slack)
		)
		var digits_at := (digit_rows.x + digit_rows.y) * 0.5
		var whole := (icon_rows.x + icon_rows.y) * 0.5
		# The body: the icon's ink above the strip of pips (rows read the same way as the icon's).
		var above := badge.icon_rect
		above = Rect2(
			above.position.x - 1.0,
			above.position.y - 1.0,
			above.size.x + 2.0,
			above.size.y * LevelIcons.BULBS_TOP + 1.0
		)
		var body_rows := _rows(
			reading,
			above,
			func(x: int, y: int) -> bool: return _coverage(flat, ground, MARKER, x, y) >= 0.5
		)
		var body := (body_rows.x + body_rows.y) * 0.5
		var gap := (digits_at - body) / reading.oversample
		var line := (
			"%s: digits %.2f..%.2f icon %.2f..%.2f (px, x%.2f) gap to body %+.2f to whole %+.2f"
			% [
				name,
				digit_rows.x,
				digit_rows.y,
				icon_rows.x,
				icon_rows.y,
				s,
				gap,
				(digits_at - whole) / reading.oversample
			]
		)
		print(line)
		_report.append(line)
		out.append(gap)
	return out


## Takes the pictures of a place (as it is, with the badges made clear, and with the digits and
## icons in flat colour) and checks every badge's gap against the reading's tolerance. `hook`, for a
## place that draws its badges itself, takes `true` to take them away, `false` to bring them back.
func _check(
	reading: Reading, badges: Array[Badge], place: String, shot: String, hook := Callable()
) -> void:
	_refresh_rects(badges)
	await _picture(reading)
	var with_badge := reading.image
	_save(with_badge, "%s_%s" % [shot, reading.name])
	_report_crop(reading, badges, shot)
	_clear(badges, true)
	if hook.is_valid():
		hook.call(true)
	await _picture(reading)
	var ground := reading.image
	_clear(badges, false)
	if hook.is_valid():
		hook.call(false)
	_recolour(badges)
	if hook.is_valid():
		hook.call(false)
	await _picture(reading)
	var flat := reading.image
	_save(flat, "%s_%s_flat" % [shot, reading.name])
	LevelIcons.release()
	reading.image = with_badge
	var gaps := _gaps(reading, badges, ground, flat, place)
	var tolerance := reading.tolerance
	for i in gaps.size():
		(
			assert_float(absf(gaps[i]))
			. override_failure_message(
				(
					"%s, %s, level %d: the digits' centre is %+.2f px from the icon's (at most %.2f px)"
					% [place, reading.name, badges[i].icon_level, gaps[i], tolerance]
				)
			)
			. is_less_equal(tolerance)
		)


## Where the badges are in the picture, for a tool that cuts them out of it (the pull request's
## pictures): `CROP shot reading x y w h`, in the picture's pixels, a little round the badges and
## their names.
func _report_crop(reading: Reading, badges: Array[Badge], shot: String) -> void:
	var union := Rect2()
	for i in badges.size():
		var one := badges[i].icon_rect.merge(badges[i].level_rect)
		union = one if i == 0 else union.merge(one)
	union = union.grow_individual(24.0, 12.0, 160.0, 12.0)
	_report.append(
		(
			"CROP %s %s %d %d %d %d"
			% [
				shot,
				reading.name,
				int(union.position.x * reading.scale),
				int(union.position.y * reading.scale),
				int(union.size.x * reading.scale),
				int(union.size.y * reading.scale)
			]
		)
	)


func _save(image: Image, name: String) -> void:
	var folder := OS.get_environment("LEVEL_INK_SHOTS")
	if not folder.is_empty():
		image.save_png("%s/%s.png" % [folder, name])


# --- The places ---


func _skip() -> bool:
	return DisplayServer.get_name() == "headless"


## The HUD of a party of `count`, each at one of `PARTY`'s levels, with a card, emblem and frame
## each when `plates`.
func _hud(host: Control, plates: bool, count := LEVELS.size()) -> HudFixture:
	var fixture := HudFixture.make(host, count)
	var state := fixture.hud.state
	for i in count:
		state.set_player_level(i + 1, PARTY[i], PARTY[i])
		if plates:
			state.set_player_plate(i + 1, &"cartoon", &"admit_one", &"gold")
	state.round_number = 9
	return fixture


func _boxes(reading: Reading, plates: bool, count := LEVELS.size()) -> Array[Badge]:
	var fixture := _hud(reading.host, plates, count)
	await get_tree().process_frame
	var badges: Array[Badge] = []
	for i in count:
		var box := fixture.hud.points.box_of(i + 1)
		var level := box.get("_level") as Label
		badges.append(
			_node_badge(
				"box",
				box.get("_icon") as CanvasItem,
				level,
				level.get_theme_color(&"font_color"),
				PARTY[i]
			)
		)
	return badges


func _scoreboard(reading: Reading, plates: bool) -> Array[Badge]:
	var fixture := _hud(reading.host, plates)
	Input.action_press(Hud.SCOREBOARD_ACTION)
	fixture.hud.scoreboard.set_shown(true)
	fixture.hud.scoreboard.refresh()
	await get_tree().process_frame
	return _badges_by_name(fixture.hud.scoreboard, "scoreboard")


func _end_board(reading: Reading, plates: bool) -> Array[Badge]:
	var fixture := _hud(reading.host, plates)
	var board := HudEndBoard.new()
	fixture.hud.add_child(board)
	board.show_results(fixture.hud.state, "THE CROWD WINS", "Leave")
	await get_tree().process_frame
	return _badges_by_name(board, "end board")


## The icons and levels a `HudLevelCell` made, in row order.
func _badges_by_name(root: Node, label: String) -> Array[Badge]:
	var icons := root.find_children("Icon", "TextureRect", true, false)
	var levels := root.find_children("Level", "Label", true, false)
	var badges: Array[Badge] = []
	for i in mini(icons.size(), levels.size()):
		var level := levels[i] as Label
		badges.append(
			_node_badge(
				label,
				icons[i] as CanvasItem,
				level,
				level.get_theme_color(&"font_color"),
				int(level.text)
			)
		)
	return badges


## The level row of the night report: the icon and "LEVEL n" (its capitals stand for the digits).
func _night_report(reading: Reading) -> Array[Badge]:
	var fixture := _hud(reading.host, false, 1)
	var board := HudEndBoard.new()
	fixture.hud.add_child(board)
	board.show_results(fixture.hud.state, "THE CROWD WINS", "Leave")
	var model := EndBoardFixtures.fullest_report()
	board.show_report(model)
	await get_tree().process_frame
	var icon := board.find_children("LevelIcon", "TextureRect", true, false)[0] as TextureRect
	var words := board.find_children("LevelText", "Label", true, false)[0] as Label
	var to := int(model["level_to"])
	return [_node_badge("report", icon, words, words.get_theme_color(&"font_color"), to)]


## The lobby with one seat for each of `levels`. On a phone the panel scrolls and only the first
## seat is on the screen, so a phone reading is one lobby for each level.
func _lobby(reading: Reading, plates: bool, levels: Array = LEVELS) -> Array[Badge]:
	var members: Array = []
	for i in levels.size():
		var member := {
			"userId": "u%d" % i,
			"name": ["Ruby", "Moe", "Dee", "Cal"][LEVELS.find(levels[i])],
			"seat": i + 1,
			"host": i == 0,
			"away": false,
			"level": levels[i],
			"icon": "level_%02d" % levels[i],
		}
		if plates:
			member["card"] = "cartoon"
			member["emblem"] = "admit_one"
			member["frame"] = "gold"
		members.append(member)
	var held := {
		"id": "l1",
		"code": "ABC234",
		"hostId": "u0",
		"maxPlayers": levels.size(),
		"members": members,
		"state": "open",
		"round": null,
	}
	var api := LobbyFixture.FakeApi.new(self)
	api.lobby = held
	LobbyScreen.opener = func() -> void: pass
	var screen := (load(LobbyScreen.SCREEN) as PackedScene).instantiate() as LobbyScreen
	screen.params = {"lobby": held, "api": api}
	# The router's stage gives every screen the game's theme (fonts, sizes): without it the seats are
	# set in Godot's default and a row is half as tall.
	reading.host.theme = UIThemeBuilder.build(UITokens.active())
	reading.host.add_child(screen)
	screen.watch.every = 3600.0
	await screen.screen_enter()
	await get_tree().process_frame
	var badges: Array[Badge] = []
	var rows: Array = screen.get("_seat_rows")
	for i in levels.size():
		var level := rows[i]["level"] as Label
		badges.append(
			_node_badge(
				"lobby seat",
				rows[i]["icon"] as CanvasItem,
				level,
				level.get_theme_color(&"font_color"),
				levels[i]
			)
		)
	return badges


func _tags(reading: Reading, out: Array) -> Array[Badge]:
	var fixture := HudFixture.make(reading.host, 2)
	var state := fixture.hud.state
	var list: Array[Dictionary] = []
	for i in LEVELS.size():
		(
			list
			. append(
				{
					"id": &"player_%d" % (i + 2),
					"kind": &"ally",
					# In the middle band, clear of the HUD's cards at every window.
					"x": 0.4 + 0.13 * i,
					"y": 0.3,
					"distance": 5.0,
					"label": "Moe",
					"important": false,
					"level": LEVELS[i],
					"icon": LEVELS[i],
				}
			)
		)
	state.set_markers(list)
	await get_tree().process_frame
	var badges: Array[Badge] = []
	for i in LEVELS.size():
		var parts: Dictionary = fixture.hud.markers.tag_parts[&"player_%d" % (i + 2)]
		var badge := Badge.new()
		badge.label = "tag"
		badge.icon_rect = parts["icon"]
		badge.level_rect = parts["level"]
		badge.ink = _tokens.ink
		badge.icon_level = LEVELS[i]
		badges.append(badge)
	out.append(
		func(hidden: bool) -> void:
			var none: Array[Dictionary] = []
			state.set_markers(none if hidden else list)
	)
	return badges


# --- The tests ---


## Builds a place in each reading and checks it. `build` takes the reading and returns the badges.
## `in_night` is whether the place is shown in a night (the HUD: the interface size is the whole
## scale) or in the menus (the lobby: the menu's phone factor). `build` is told the levels to show;
## `by_level` has a phone reading build one place for each level, for a place that scrolls.
func _every_reading(
	place: String, shot: String, build: Callable, in_night := true, by_level := false
) -> void:
	var readings: Array[Callable] = [_exact]
	# The sizes a player has: a desktop at the three interface sizes, a phone held sideways.
	for ui_scale in UI_SCALES:
		readings.append(func() -> Reading: return _real(CANVAS, ui_scale))
	if in_night:
		for ui_scale in PHONE_NIGHT_SCALES:
			readings.append(func() -> Reading: return _real(PHONE, ui_scale, true))
			readings.append(func() -> Reading: return _real(PAGE, ui_scale, true))
	else:
		readings.append(func() -> Reading: return _real(PHONE))
		readings.append(func() -> Reading: return _real(PAGE))
	for make: Callable in readings:
		var probe: Reading = make.call()
		var phone := (
			probe.name.begins_with("real_%dx%d" % [PHONE.x, PHONE.y])
			or probe.name.begins_with("real_%dx%d" % [PAGE.x, PAGE.y])
		)
		_dispose(probe)
		# What each place built shows: all the levels, or on a scrolling phone one at a time.
		var groups: Array = [LEVELS]
		if by_level and phone:
			groups = LEVELS.map(func(level: int) -> Array: return [level])
		for group: Array in groups:
			var reading: Reading = make.call()
			var hook: Array = []
			var badges: Array[Badge] = (
				await build.call(reading, hook, group)
				if by_level
				else await build.call(reading, hook)
			)
			await _check(
				reading, badges, place, shot, hook[0] if not hook.is_empty() else Callable()
			)
			_dispose(reading)
			await get_tree().process_frame


## Takes down what a reading built.
func _dispose(reading: Reading) -> void:
	(reading.host.get_parent() if reading.name == "exact" else reading.host).queue_free()


func test_the_tag_over_a_head(_do_skip := _skip(), _skip_reason := SKIP_WHY) -> void:
	await _every_reading(
		"tag over a head",
		"tag",
		func(r: Reading, hook: Array) -> Array[Badge]: return await _tags(r, hook)
	)


func test_the_player_boxes(_do_skip := _skip(), _skip_reason := SKIP_WHY) -> void:
	await _every_reading(
		"player box",
		"box",
		func(r: Reading, _hook: Array) -> Array[Badge]: return await _boxes(r, false)
	)


func test_the_player_boxes_with_a_plate(_do_skip := _skip(), _skip_reason := SKIP_WHY) -> void:
	await _every_reading(
		"player box with a plate",
		"box_plate",
		func(r: Reading, _hook: Array) -> Array[Badge]: return await _boxes(r, true)
	)


func test_the_scoreboard(_do_skip := _skip(), _skip_reason := SKIP_WHY) -> void:
	await _every_reading(
		"scoreboard",
		"board",
		func(r: Reading, _hook: Array) -> Array[Badge]: return await _scoreboard(r, false)
	)


func test_the_scoreboard_with_a_plate(_do_skip := _skip(), _skip_reason := SKIP_WHY) -> void:
	await _every_reading(
		"scoreboard with a plate",
		"board_plate",
		func(r: Reading, _hook: Array) -> Array[Badge]: return await _scoreboard(r, true)
	)


func test_the_end_board(_do_skip := _skip(), _skip_reason := SKIP_WHY) -> void:
	await _every_reading(
		"end board",
		"end",
		func(r: Reading, _hook: Array) -> Array[Badge]: return await _end_board(r, false)
	)


func test_the_end_board_with_a_plate(_do_skip := _skip(), _skip_reason := SKIP_WHY) -> void:
	await _every_reading(
		"end board with a plate",
		"end_plate",
		func(r: Reading, _hook: Array) -> Array[Badge]: return await _end_board(r, true)
	)


func test_the_lobby_seats(_do_skip := _skip(), _skip_reason := SKIP_WHY) -> void:
	await _every_reading(
		"lobby seat",
		"lobby",
		func(r: Reading, _hook: Array, levels: Array) -> Array[Badge]:
			return await _lobby(r, false, levels),
		false,
		true
	)


func test_the_lobby_seats_with_a_plate(_do_skip := _skip(), _skip_reason := SKIP_WHY) -> void:
	await _every_reading(
		"lobby seat with a plate",
		"lobby_plate",
		func(r: Reading, _hook: Array, levels: Array) -> Array[Badge]:
			return await _lobby(r, true, levels),
		false,
		true
	)


## Nothing in a place moves while it is read (#1348). A marquee panel runs a chase of bulbs in real
## time (`UIPanel`: the lit set walks a place every 0.15 s) and the readings take the place's
## picture three times (as it is, with the badges clear, in flat colour), so the bulbs are lit in
## other places in each and a bulb under the digits is read as ink: the schedule's windowed run
## failed `test_the_lobby_seats` that way, on a runner whose frames are not a GPU's. The suite
## holds the chase still (reduced motion, which it keeps) and this checks no panel is running one.
func test_no_panel_chases_its_bulbs_while_a_place_is_read() -> void:
	var reading := _exact()
	await _lobby(reading, false, [3])
	await get_tree().process_frame
	var panels := reading.host.find_children("*", "UIPanel", true, false).filter(
		func(node: Node) -> bool: return (node as UIPanel).variant == UIPanel.Variant.MARQUEE
	)
	assert_int(panels.size()).is_greater(0)  # the lobby has the marquee this is about
	for panel: UIPanel in panels:
		(
			assert_bool(panel.is_processing())
			. override_failure_message(
				"%s chases its bulbs while the pictures are taken" % panel.get_path()
			)
			. is_false()
		)
	_dispose(reading)


func test_the_compact_player_boxes(_do_skip := _skip(), _skip_reason := SKIP_WHY) -> void:
	await _every_reading(
		"compact player box",
		"box_compact",
		func(r: Reading, _hook: Array) -> Array[Badge]: return await _boxes(r, true, PARTY.size())
	)


func test_the_night_report_level_row(_do_skip := _skip(), _skip_reason := SKIP_WHY) -> void:
	await _every_reading(
		"night report",
		"report",
		func(r: Reading, _hook: Array) -> Array[Badge]: return await _night_report(r)
	)
