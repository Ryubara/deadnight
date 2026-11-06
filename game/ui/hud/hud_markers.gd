class_name HudMarkers
extends HudPart
## World markers drawn over the view: objective diamonds with their distance, shrinking with it, and
## teammates' names that stay readable at any range. The important marker that is off-screen is
## pinned to the screen edge with an arrow; the others only show while on screen. Fills the HUD.
## The client projects each marker to screen space; this part never sees a game object.

## Diamond half-size at point blank and far away, and the distance where it stops shrinking.
const DIAMOND_NEAR := 24.0
const DIAMOND_FAR := 13.0
const FAR_METRES := 60.0
const EDGE_INSET := 90.0
## What a marker pinned to an edge keeps clear of: the side columns (along the top and the bottom
## edge), and the round card above and the health and ammo cards below (along a side edge).
const SIDE_CLEAR := HudStyle.MARGIN + HudStyle.COLUMN + 48.0
const TOP_CLEAR := 260.0
const BOTTOM_CLEAR := 390.0
const ARROW := 16.0
## The ring of a teammate on the ground.
const DOWNED_RADIUS := 22.0
const DOWNED_WIDTH := 6.0
## Text stays this far inside the screen.
const TEXT_MARGIN := 12.0
## The size of a marker's words at the desktop's scale, which is also the least anywhere.
const LABEL_SIZE := HudStyle.MIN_TEXT
## The width of the dark outline round the words at `LABEL_SIZE`.
const OUTLINE := 7
## How far a marker's shape reaches round its place: a diamond's shadow, and the gap between its
## edge and the arrow that points back to where it really stands.
const SHADOW_REACH := 3.0
const ARROW_GAP := 6.0
## Steps of a canvas unit a marker's place is told apart in: a marker follows the world, so the
## state holds a new float place nearly every frame, and the part is drawn when the picture would
## change by a quarter of a unit (a quarter of a pixel at 1080p), not when a float does (#948).
const PLACE_STEPS := 4.0
## The most columns a draw tries for all the markers it moves.
const MAX_TRIES := 800
## How far past the edge of a card a place that rests against it is put, so that the float noise of
## measuring the marker again where it stands (its box is a hair taller than the model's, 1e-4)
## never counts it as touching the card. A crowded page (the weapon strip's fingertip-sized places,
## #1280) leaves only such places.
const EDGE_EPSILON := 0.05
## How far an objective's words keep from a card of the HUD (the outline of the letters is 3.5).
const CLEAR_GAP := 8.0
## How far a marker that was moved keeps from the others that were, at `LABEL_SIZE`.
const MARKER_GAP := 4.0

## Where each marker is drawn on the last frame: {id: {"at": Vector2, "pinned": bool}}.
var placed: Dictionary = {}
## Where each ally's tag (icon, level, name and what follows) was drawn on the last frame, canvas
## units: {id: Rect2}. Every tag stays inside the screen.
var tags: Dictionary = {}
## What each marker took on the last frame, in this part's units: {id: {"at": where it is drawn,
## "box": the rectangle of its shape, its arrow and its words, "moved": whether it is not on the
## place it points to, "arrow": which way its arrow points (zero for none)}}. A marker whose shape
## or words would be under a card of the HUD is drawn on the nearest place that is under none, with
## an arrow back toward the place it marks (#1218).
var shown: Dictionary = {}
## The parts of a tag with a level, as laid out, for tests and captures (a tag with no level has
## none): {id: {"icon": Rect2, "level": Rect2, "name": Rect2}}.
var tag_parts: Dictionary = {}

## Where each objective's words (its name and distance) were drawn on the last frame, in this
## part's units: {id: Rect2}. They stay out of `keep_clear` (#1192).
var labels: Dictionary = {}
## The cards the HUD keeps in its corners, which a marker's words stay out of: the part cannot see
## the HUD, so `Hud` lists them. A card that moves, grows or goes away redraws the markers.
var keep_clear: Array[Control] = []:
	set(value):
		for card in keep_clear:
			if is_instance_valid(card) and card.item_rect_changed.is_connected(queue_redraw):
				card.item_rect_changed.disconnect(queue_redraw)
				card.visibility_changed.disconnect(queue_redraw)
		keep_clear = value
		for card in keep_clear:
			card.item_rect_changed.connect(queue_redraw)
			card.visibility_changed.connect(queue_redraw)
		queue_redraw()

## The size of the words, canvas units: `LABEL_SIZE`, or what 14 CSS px come to where a finger holds
## the screen and a unit is under 0.7 CSS px (a phone's night: 0.36). `Hud` sets it
## (`MenuScale.text_units`); the icon beside a level and the gaps follow it.
var label_size := LABEL_SIZE:
	set(value):
		value = maxi(value, LABEL_SIZE)
		if value != label_size:
			label_size = value
			queue_redraw()

## What else holds the screen's canvas, which a marker stays out of as it does the cards: the touch
## buttons under a finger (`TouchControls.button_boxes`), in the canvas's units. Set by the screen.
var held: Array[Rect2] = []:
	set(value):
		held = value
		queue_redraw()

## What the last draw was made from (`_key`).
var _drawn_key: Array = []
## What a draw collects: every marker's shapes, their smoothed rings [centre, radius, from, to,
## colour, width] and their words [font, place, text, colour].
var _shapes := HudShapes.new()
var _rings: Array[Array] = []
var _words: Array[Array] = []
## The level icons of a draw [rect, region of the atlas]: all of them before any word.
var _icons: Array[Array] = []
## `keep_clear` as this draw sees it, grown by `CLEAR_GAP`, in this part's units; read by the first
## words that need it (`_cards`), not by a draw with no objective on screen.
var _blocked: Array[Rect2] = []
var _blocked_read := false
## The places tried so far in this draw (`MAX_TRIES`).
var _tries := 0
## What the markers moved off the cards took in this draw: the next to move keeps clear of it.
var _moved: Array[Rect2] = []
## The widths of the words a draw has measured (`_width`).
var _widths := {}


func _ready() -> void:
	resized.connect(queue_redraw)
	texture_filter = LevelIcons.FILTER


func topics() -> Array[StringName]:
	return [HudState.MARKERS]


func refresh() -> void:
	var key := _key()
	if key != _drawn_key:
		_drawn_key = key
		queue_redraw()


## Everything `_draw` reads, as the picture tells it apart: the screen, where each marker stands in
## quarter units, how far it says it is in whole metres, its words and its state.
func _key() -> Array:
	var key: Array = [size, label_size]
	if state == null:
		return key
	var spots := _place_all()
	for marker in state.markers:
		var spot: Dictionary = spots.get(marker["id"], {})
		if spot.is_empty():
			continue
		var at: Vector2 = spot["at"]
		(
			key
			. append(
				[
					marker["id"],
					marker["kind"],
					roundi(at.x * PLACE_STEPS),
					roundi(at.y * PLACE_STEPS),
					spot["pinned"],
					roundi(float(marker.get("distance", 0.0))),
					str(marker.get("label", "")),
					bool(marker.get("downed", false)),
					bool(marker.get("dead", false)),
					int(marker.get("level", 0)),
					int(marker.get("icon", 0)),
					int(marker.get("bleed", 0)),
					roundi(float(marker.get("revive", 0.0)) * 100.0),
				]
			)
		)
	return key


func marker_at(id: StringName) -> Dictionary:
	return _place_all().get(id, {})


func _draw() -> void:
	placed = _place_all()
	var font := tokens.text_font(tokens.embolden_display * 0.3, 1.0)
	# All the markers' shapes are one command, then the smoothed rings, then all their words (the
	# outlines, then the letters: two commands, not two a marker): a marker's words can go over
	# another marker's shape that stands under them (#948).
	_shapes = HudShapes.new()
	_rings.clear()
	_words.clear()
	_icons.clear()
	tags.clear()
	tag_parts.clear()
	labels.clear()
	shown.clear()
	_widths.clear()
	_moved.clear()
	_tries = 0
	_blocked_read = false
	for marker in state.markers:
		var spot: Dictionary = placed.get(marker["id"], {})
		if spot.is_empty():
			continue
		if marker["kind"] == &"ally":
			_draw_ally(font, marker, spot)
		else:
			_draw_objective(font, marker, spot)
	_shapes.flush(self)
	for ring: Array in _rings:
		draw_arc(ring[0], ring[1], ring[2], ring[3], 32, ring[4], ring[5], true)
	if not _icons.is_empty():
		var atlas := LevelIcons.atlas()
		for icon: Array in _icons:
			draw_texture_rect_region(atlas, icon[0], icon[1])
	for word: Array in _words:
		draw_string_outline(
			word[0],
			word[1],
			word[2],
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			label_size,
			roundi(OUTLINE * _grown()),
			tokens.shadow
		)
	for word: Array in _words:
		draw_string(word[0], word[1], word[2], HORIZONTAL_ALIGNMENT_LEFT, -1, label_size, word[3])


func _place_all() -> Dictionary:
	var out := {}
	if state == null:
		return out
	for marker in state.markers:
		var norm := Vector2(float(marker["x"]), float(marker["y"]))
		var on_screen := Rect2(0.0, 0.0, 1.0, 1.0).has_point(norm)
		var at := norm * size
		if on_screen:
			out[marker["id"]] = {"at": at, "pinned": false, "target": at}
		elif bool(marker.get("important", false)):
			out[marker["id"]] = {"at": _pin(at), "pinned": true, "target": at}
	return out


## The edge point toward `at` from the screen centre, inset so the marker stays whole, and slid
## along that edge out of the corners, where the HUD's cards stand.
func _pin(at: Vector2) -> Vector2:
	var centre := size * 0.5
	var half := centre - Vector2.ONE * EDGE_INSET
	var offset := at - centre
	if offset == Vector2.ZERO:
		return centre
	var across_x := half.x / maxf(absf(offset.x), 0.001)
	var across_y := half.y / maxf(absf(offset.y), 0.001)
	var pinned := centre + offset * minf(across_x, across_y)
	if across_x < across_y:
		pinned.y = clampf(
			pinned.y, minf(TOP_CLEAR, centre.y), maxf(size.y - BOTTOM_CLEAR, centre.y)
		)
	else:
		pinned.x = clampf(pinned.x, minf(SIDE_CLEAR, centre.x), maxf(size.x - SIDE_CLEAR, centre.x))
	return pinned


func _draw_objective(font: Font, marker: Dictionary, spot: Dictionary) -> void:
	var t := clampf(float(marker["distance"]) / FAR_METRES, 0.0, 1.0)
	var half := lerpf(DIAMOND_NEAR, DIAMOND_FAR, t) * _grown()
	var text := "%d m" % roundi(float(marker["distance"]))
	if str(marker.get("label", "")) != "":
		text = "%s  %s" % [str(marker["label"]).to_upper(), text]
	var pinned: bool = spot["pinned"]
	var box_of := func(place: Vector2, arrowed: bool) -> Rect2:
		return _objective_box(font, text, half, place, arrowed or pinned)
	var at := _settle(spot["at"], box_of)
	var moved := not at.is_equal_approx(spot["at"])
	var diamond := PackedVector2Array(
		[
			at + Vector2(0, -half),
			at + Vector2(half, 0),
			at + Vector2(0, half),
			at + Vector2(-half, 0)
		]
	)
	var drop := Vector2(SHADOW_REACH, SHADOW_REACH) * _grown()
	_shapes.polygon(
		PackedVector2Array(
			[diamond[0] + drop, diamond[1] + drop, diamond[2] + drop, diamond[3] + drop]
		),
		tokens.shadow
	)
	_shapes.polygon(diamond, tokens.accent_bright)
	var inner := half * 0.45
	_shapes.rect(Rect2(at - Vector2.ONE * inner * 0.5, Vector2.ONE * inner), tokens.ink_on_accent)
	var words := _clear_of_cards(_objective_words(font, text, half, at))
	var direction := Vector2.ZERO
	var drawn := Rect2(at, Vector2.ZERO).grow(half + SHADOW_REACH * _grown()).merge(words)
	if pinned or moved:
		direction = (at - size * 0.5).normalized()
		if moved:
			direction = (Vector2(spot["target"]) - at).normalized()
		drawn = drawn.merge(_arrow(at, half, direction, tokens.accent_bright, words))
	if moved:
		_moved.append(drawn.grow(MARKER_GAP * _grown()))
	labels[marker["id"]] = words
	_words.append([font, Vector2(words.position.x, words.end.y), text, tokens.ink])
	shown[marker["id"]] = {"at": at, "box": drawn, "moved": moved, "arrow": direction}


## The words of an objective: under its diamond, or over it when the screen ends there.
func _objective_words(font: Font, text: String, half: float, at: Vector2) -> Rect2:
	var baseline := at + Vector2(0.0, half + label_size + 8.0)
	if baseline.y > size.y - TEXT_MARGIN:
		baseline.y = at.y - half - 8.0
	return _on_screen(_words_rect(font, text, baseline))


## Everything an objective draws when its diamond is on `at`: the diamond with its shadow (and the
## arrow beside it when `arrowed`) and the words.
func _objective_box(font: Font, text: String, half: float, at: Vector2, arrowed: bool) -> Rect2:
	var reach := half + (ARROW + ARROW_GAP if arrowed else SHADOW_REACH) * _grown()
	return Rect2(at, Vector2.ZERO).grow(reach).merge(_objective_words(font, text, half, at))


## An arrow of the marker's colour beside its shape (`reach` from `at`), pointing along
## `direction`: toward the edge an off-screen marker is pinned to, or toward the place a marker that
## was moved off a card really stands. It stands on the side of the shape that `direction` faces, or
## else on a flank of the shape or under or over it: the first side where it is not over the
## marker's own words or tag (`avoid`), a card or a marker moved before it (else the first where it
## is not over the words). Gives the rectangle it takes.
func _arrow(at: Vector2, reach: float, direction: Vector2, colour: Color, avoid: Rect2) -> Rect2:
	var flank := Vector2(1.0 if direction.x >= 0.0 else -1.0, 0.0)
	var points := PackedVector2Array()
	var box := Rect2()
	for anchor: Vector2 in [direction, flank, -flank, Vector2.DOWN, Vector2.UP]:
		var corners := _arrow_points(at, reach, anchor, direction)
		var corners_box := Rect2(corners[0], Vector2.ZERO).expand(corners[1]).expand(corners[2])
		if corners_box.intersects(avoid):
			continue
		if points.is_empty():
			points = corners
			box = corners_box
		if not _touches(corners_box, true):
			points = corners
			box = corners_box
			break
	if points.is_empty():
		points = _arrow_points(at, reach, flank, direction)
		box = Rect2(points[0], Vector2.ZERO).expand(points[1]).expand(points[2])
	_shapes.polygon(points, colour)
	return box


## The three corners of an arrow that points along `direction` from the side of the shape that
## `anchor` faces: the tip, then the two corners of its base.
func _arrow_points(
	at: Vector2, reach: float, anchor: Vector2, direction: Vector2
) -> PackedVector2Array:
	var grown := _grown()
	var base := at + anchor * (reach + ARROW_GAP * grown)
	var side := direction.orthogonal() * ARROW * grown * 0.6
	return PackedVector2Array([base + direction * ARROW * grown, base + side, base - side])


func _draw_ally(font: Font, marker: Dictionary, spot: Dictionary) -> void:
	var box_of := func(place: Vector2, arrowed: bool) -> Rect2:
		return _ally_box(font, marker, place, arrowed)
	var at := _settle(spot["at"], box_of)
	var moved := not at.is_equal_approx(spot["at"])
	var colour := tokens.accent_bright
	if bool(marker.get("downed", false)):
		colour = _downed_colour(marker)
		_draw_downed(font, marker, at)
	else:
		var grown := _grown()
		var tip := at + Vector2(0.0, -10.0) * grown
		_shapes.polygon(
			PackedVector2Array(
				[
					tip + Vector2(0, 14) * grown,
					tip + Vector2(-10, 0) * grown,
					tip + Vector2(10, 0) * grown
				]
			),
			tokens.accent
		)
		_tag(font, marker, _ally_baseline(font, marker, at), colour)
	var direction := Vector2.ZERO
	var drawn := _ally_box(font, marker, at, false)
	if moved:
		direction = (Vector2(spot["target"]) - at).normalized()
		drawn = drawn.merge(_arrow(at, _ally_reach(marker), direction, colour, tags[marker["id"]]))
		_moved.append(drawn.grow(MARKER_GAP * _grown()))
	shown[marker["id"]] = {"at": at, "box": drawn, "moved": moved, "arrow": direction}


func _downed_colour(marker: Dictionary) -> Color:
	return tokens.ink_muted if bool(marker.get("dead", false)) else tokens.danger


## How far a teammate's shape reaches from its place.
func _ally_reach(marker: Dictionary) -> float:
	return (DOWNED_RADIUS + 4.0 if bool(marker.get("downed", false)) else 14.0) * _grown()


## Where the baseline of a teammate's tag is: over the shape that is on `at`, or under it when the
## tag would be cut by the top of the screen (#1230).
func _ally_baseline(font: Font, marker: Dictionary, at: Vector2) -> Vector2:
	var grown := _grown()
	var downed := bool(marker.get("downed", false))
	var over := at + Vector2(0.0, -DOWNED_RADIUS - 10.0 if downed else -20.0) * grown
	var tag := _tag_geometry(font, marker, over)
	if Rect2(tag["box"]).position.y >= TEXT_MARGIN:
		return over
	var below := at.y + (DOWNED_RADIUS + 6.0 if downed else 12.0) * grown
	return Vector2(at.x, below + maxf(LevelTag.ICON * grown, label_size))


## Everything a teammate draws when it is on `at`: the pointer or the ring (and the arrow beside it
## when `arrowed`) and the tag.
func _ally_box(font: Font, marker: Dictionary, at: Vector2, arrowed: bool) -> Rect2:
	var reach := _ally_reach(marker)
	var grown := _grown()
	var shape := Rect2(at.x - 10.0 * grown, at.y - 10.0 * grown, 20.0 * grown, 14.0 * grown)
	if arrowed:
		shape = Rect2(at, Vector2.ZERO).grow(reach + (ARROW + ARROW_GAP) * grown)
	elif bool(marker.get("downed", false)):
		shape = Rect2(at, Vector2.ZERO).grow(reach)
	return shape.merge(_tag_geometry(font, marker, _ally_baseline(font, marker, at))["box"])


## A teammate on the ground: a red marker with their name and the seconds they have left, and a ring
## that fills while somebody holds the revive on them. Bled out, it says so and carries no clock.
func _draw_downed(font: Font, marker: Dictionary, at: Vector2) -> void:
	var dead := bool(marker.get("dead", false))
	var colour := _downed_colour(marker)
	var grown := _grown()
	var radius := DOWNED_RADIUS * grown
	var width := DOWNED_WIDTH * grown
	_shapes.circle(at, radius + 4.0 * grown, Color(tokens.shadow, 0.6))
	_rings.append([at, radius, 0.0, TAU, Color(colour, 0.35), width])
	var progress := float(marker.get("revive", 0.0))
	if progress > 0.0:
		_rings.append(
			[
				at,
				radius,
				-PI * 0.5,
				-PI * 0.5 + TAU * clampf(progress, 0.0, 1.0),
				tokens.accent_bright,
				width
			]
		)
	elif not dead:
		_rings.append([at, radius, -PI * 0.5, PI * 1.5, colour, width * 0.5])
	# A cross, the mark of someone who needs a hand.
	var arm := radius * 0.45
	_shapes.line(at + Vector2(-arm, 0.0), at + Vector2(arm, 0.0), colour, 4.0 * grown)
	_shapes.line(at + Vector2(0.0, -arm), at + Vector2(0.0, arm), colour, 4.0 * grown)
	_tag(font, marker, _ally_baseline(font, marker, at), colour)


## What follows a teammate's name: the clock of a body on the ground.
func _tail(marker: Dictionary) -> String:
	if not bool(marker.get("downed", false)):
		return ""
	return "  DEAD" if bool(marker.get("dead", false)) else "  %d S" % int(marker.get("bleed", 0))


## Where the parts of a teammate's tag go, centred on `baseline_centre`: the icon, the level right
## beside it and then the name, in the order and with the gaps of `LevelTag` (grown with the words),
## when the marker has a level (0 for none: a bot, or the viewer turned levels off), else the name
## alone as it always was, centred the same way. The whole tag is kept inside the screen like any
## other text. Read by the draw and by the search for a place clear of the cards.
func _tag_geometry(font: Font, marker: Dictionary, baseline_centre: Vector2) -> Dictionary:
	var who := str(marker.get("label", "")).to_upper() + _tail(marker)
	var level := int(marker.get("level", 0))
	if level < 1:
		return {"box": _words_rect(font, who, baseline_centre), "who": who, "level": 0}
	var grown := _grown()
	var icon_side := LevelTag.ICON * grown
	var level_width := _width(font, str(level))
	var name_width := _width(font, who)
	var total := (
		icon_side + LevelTag.ICON_GAP * grown + level_width + LevelTag.NAME_GAP * grown + name_width
	)
	var left := clampf(
		baseline_centre.x - total * 0.5,
		TEXT_MARGIN,
		maxf(size.x - TEXT_MARGIN - total, TEXT_MARGIN)
	)
	# The icon's body is centred on the digits' ink, as the font draws them on this baseline.
	var icon_level := int(marker.get("icon", level))
	var icon_top := LevelTag.icon_top(
		LevelTag.digits_centre(font, label_size, baseline_centre.y), icon_level, icon_side
	)
	var top := minf(icon_top, baseline_centre.y - label_size)
	return {
		"box": Rect2(left, top, total, maxf(icon_side, label_size)),
		"who": who,
		"level": level,
		"icon_level": icon_level,
		"icon": Rect2(left, icon_top, icon_side, icon_side),
		"level_width": level_width,
		"name_width": name_width,
	}


## A teammate's tag, centred on `baseline_centre` (`_tag_geometry`); its place is told in `tags`
## and `tag_parts`.
func _tag(font: Font, marker: Dictionary, baseline_centre: Vector2, colour: Color) -> void:
	var tag := _tag_geometry(font, marker, baseline_centre)
	tags[marker["id"]] = tag["box"]
	if int(tag["level"]) < 1:
		_text(font, tag["who"], baseline_centre, colour)
		return
	var grown := _grown()
	var icon: Rect2 = tag["icon"]
	_icons.append([icon, LevelIcons.region(int(tag["icon_level"]))])
	var level_at := icon.end.x + LevelTag.ICON_GAP * grown
	var name_at := level_at + float(tag["level_width"]) + LevelTag.NAME_GAP * grown
	_words.append([font, Vector2(level_at, baseline_centre.y), str(tag["level"]), tokens.ink])
	_words.append([font, Vector2(name_at, baseline_centre.y), tag["who"], colour])
	tag_parts[marker["id"]] = {
		"icon": icon,
		"level":
		Rect2(level_at, baseline_centre.y - label_size, float(tag["level_width"]), label_size),
		"name":
		Rect2(name_at, baseline_centre.y - label_size, float(tag["name_width"]), label_size),
	}


## How much bigger than at the desktop's scale the words are.
func _grown() -> float:
	return float(label_size) / LABEL_SIZE


## `at`, or when what a marker draws there (`box_of(at, arrowed)`: its rectangle, with the arrow
## beside its shape when `arrowed`) is under a card of the HUD, the nearest place where it is under
## none (#1218, #1230): clear of the markers already moved too when there is a place for that, else
## of the cards only. A screen with no such place keeps the marker where it was.
func _settle(at: Vector2, box_of: Callable) -> Vector2:
	if not _touches(box_of.call(at, false)):
		return at
	for apart in [true, false]:
		var best := _nearest_clear(at, box_of, apart)
		if best.is_finite():
			return best
	return at


## The nearest place to `at` where what a marker draws (with an arrow) is under no card (and
## clear of the markers already moved when `apart`), or `Vector2.INF` when there is none or the draw
## has tried as many columns as it may (`MAX_TRIES`: a screen that has no room for a marker costs a
## few milliseconds, not a hitch).
##
## A marker's rectangle that is clear can be slid left, then up, until it rests on the edge of a
## card or of the screen, so a place exists only if one exists with its left edge on the right of a
## card, or on the left of one, or against a side of the screen: those columns are tried, the
## nearest to `at` first, and in each the nearest place up or down that no card is in (`_clear_y`).
## Once a place is found a column that is no nearer is not looked at.
func _nearest_clear(at: Vector2, box_of: Callable, apart: bool) -> Vector2:
	# The rectangle is measured in the middle of the screen, where nothing keeps it inside: it is
	# the same wherever it stands with all of it on the screen.
	var middle := size * 0.5
	var model: Rect2 = box_of.call(middle, true)
	var offset := model.position - middle
	var start := at + offset
	var obstacles: Array[Rect2] = _cards().duplicate()
	if apart:
		obstacles.append_array(_moved)
	var best := Vector2.INF
	var best_cost := INF
	for x in _lines(start.x, model.size.x, TEXT_MARGIN, size.x, obstacles, true):
		var across := (x - start.x) * (x - start.x)
		if across >= best_cost or _tries >= MAX_TRIES:
			break
		_tries += 1
		var y := _clear_y(x, start.y, model.size, obstacles)
		var cost := across + (y - start.y) * (y - start.y)
		if is_finite(y) and cost < best_cost:
			# The place found is looked at as it is drawn.
			var spot := Vector2(x, y) - offset
			if not _touches(box_of.call(spot, true), apart):
				best = spot
				best_cost = cost
	return best


## The nearest `y` to `want` where a rectangle of `extent` whose left edge is on `x` meets none of
## `obstacles` and is on the screen, or INF when there is none.
func _clear_y(x: float, want: float, extent: Vector2, obstacles: Array[Rect2]) -> float:
	var low := TEXT_MARGIN
	var high := maxf(size.y - TEXT_MARGIN - extent.y, low)
	# The `y` a rectangle meets an obstacle at lie between these two, as `(from, to)`.
	var blocks: Array[Vector2] = []
	var tries: Array[float] = [clampf(want, low, high), low, high]
	for rect in obstacles:
		if rect.position.x < x + extent.x and rect.end.x > x:
			blocks.append(Vector2(rect.position.y - extent.y, rect.end.y))
			tries.append(clampf(rect.end.y + EDGE_EPSILON, low, high))
			tries.append(clampf(rect.position.y - extent.y - EDGE_EPSILON, low, high))
	var found := INF
	for y in tries:
		if absf(y - want) >= absf(found - want):
			continue
		var free := true
		for block in blocks:
			if y > block.x and y < block.y:
				free = false
				break
		if free:
			found = y
	return found


## The places along one axis a rectangle of `length` (that stands at `start` now) is tried at: where
## it rests against the screen (`margin` in from its edges), on either side of every obstacle and
## where it is, those that keep it on the screen, the nearest to `start` first. `along_x` is whether
## the axis is x.
func _lines(
	start: float,
	length: float,
	margin: float,
	extent: float,
	obstacles: Array[Rect2],
	along_x: bool
) -> Array[float]:
	var high := maxf(extent - margin - length, margin)
	var found: Array[float] = []
	for line: float in [clampf(start, margin, high), margin, high]:
		if not found.has(line):
			found.append(line)
	for rect in obstacles:
		var edges: Array[float] = []
		if along_x:
			edges = [rect.end.x + EDGE_EPSILON, rect.position.x - length - EDGE_EPSILON]
		else:
			edges = [rect.end.y + EDGE_EPSILON, rect.position.y - length - EDGE_EPSILON]
		for edge in edges:
			var line := clampf(edge, margin, high)
			if not found.has(line):
				found.append(line)
	found.sort_custom(
		func(one: float, other: float) -> bool: return absf(one - start) < absf(other - start)
	)
	return found


## `words` where it stays out of the HUD's cards (#1192). Unmoved when it touches none, else the
## nearest place on the screen that touches none: slid along its line against the edge of a card, up
## to the edge above or below a card, and once more from there when that meets another card. A
## screen with no such place keeps the words where they were.
func _clear_of_cards(words: Rect2) -> Rect2:
	if not _touches(words):
		return words
	var best := words
	var best_cost := INF
	var round_one: Array[Rect2] = _slid(words)
	var tries: Array[Rect2] = round_one.duplicate()
	for step in round_one:
		if _touches(step):
			tries.append_array(_slid(step))
	for candidate in tries:
		if _touches(candidate):
			continue
		var cost := candidate.get_center().distance_squared_to(words.get_center())
		if cost < best_cost:
			best = candidate
			best_cost = cost
	return best


## Whether `words` meets a card.
func _touches(words: Rect2, apart := false) -> bool:
	for card in _cards():
		if words.intersects(card):
			return true
	if apart:
		for taken in _moved:
			if words.intersects(taken):
				return true
	return false


## `words` moved to each side of every card (left, right, above, below) and kept on the screen.
func _slid(words: Rect2) -> Array[Rect2]:
	var moved: Array[Rect2] = []
	for card in _cards():
		for at: Vector2 in [
			Vector2(card.end.x, words.position.y),
			Vector2(card.position.x - words.size.x, words.position.y),
			Vector2(words.position.x, card.position.y - words.size.y),
			Vector2(words.position.x, card.end.y),
		]:
			var kept := _on_screen(Rect2(at, words.size))
			if not moved.has(kept):
				moved.append(kept)
	return moved


## `words` pulled inside the screen, `TEXT_MARGIN` from its edges.
func _on_screen(words: Rect2) -> Rect2:
	var x := clampf(
		words.position.x, TEXT_MARGIN, maxf(size.x - TEXT_MARGIN - words.size.x, TEXT_MARGIN)
	)
	var y := clampf(
		words.position.y, TEXT_MARGIN, maxf(size.y - TEXT_MARGIN - words.size.y, TEXT_MARGIN)
	)
	return Rect2(x, y, words.size.x, words.size.y)


## The shown cards of `keep_clear`, grown by `CLEAR_GAP`, in this part's units, as this draw has
## them.
func _cards() -> Array[Rect2]:
	if not _blocked_read:
		_blocked = _keep_clear_rects()
		_blocked_read = true
	return _blocked


func _keep_clear_rects() -> Array[Rect2]:
	var found: Array[Rect2] = []
	var origin := get_global_rect().position
	for card in keep_clear:
		if is_instance_valid(card) and card.is_visible_in_tree() and card.size != Vector2.ZERO:
			var rect := card.get_global_rect()
			found.append(Rect2(rect.position - origin, rect.size).grow(CLEAR_GAP))
	for box in held:
		found.append(Rect2(box.position - origin, box.size).grow(CLEAR_GAP))
	return found


## How wide `text` is, shaped once a draw: a marker is laid out again for every place tried.
func _width(font: Font, text: String) -> float:
	if not _widths.has(text):
		_widths[text] = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, label_size).x
	return _widths[text]


## Where `_text` puts `text`: the box of its letters.
func _words_rect(font: Font, text: String, baseline_centre: Vector2) -> Rect2:
	var width := _width(font, text)
	var left := clampf(
		baseline_centre.x - width * 0.5,
		TEXT_MARGIN,
		maxf(size.x - TEXT_MARGIN - width, TEXT_MARGIN)
	)
	return Rect2(left, baseline_centre.y - label_size, width, label_size)


## Centred text with a dark outline, so it holds on a lit or dark ground: kept for the end of the
## draw.
func _text(font: Font, text: String, baseline_centre: Vector2, colour: Color) -> void:
	var width := _width(font, text)
	var at := baseline_centre - Vector2(width * 0.5, 0.0)
	at.x = clampf(at.x, TEXT_MARGIN, maxf(size.x - TEXT_MARGIN - width, TEXT_MARGIN))
	_words.append([font, at, text, colour])
