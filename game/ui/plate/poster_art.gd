class_name PosterArt
extends Control
## A poster set's poster at whatever size it is given: `PosterCompose.shapes` scaled to the control
## (one command, `HudShapes`), the title printed on it when `titled`, and a cover over each panel
## the player has not uncovered yet: a solid tile, so nothing of the picture or the title shows
## through, with its number. A cover stays inside the poster's frame (the frame is one piece at
## 0 and at 6 panels) and leaves a hairline of the picture between it and the next one. The
## shapes are built when the set or the size changes; uncovering a panel only redraws the covers.

## How much darker than the poster's dark a cover is, and how much of the light its number has.
const COVER_DARKEN := 0.45
const COVER_GAP_DARKEN := 0.75
const NUMBER_ALPHA := 0.8
## The gap between two covers, in design units.
const COVER_GAP := 1.5
## The number on a cover: its size as a share of the panel's height.
const NUMBER_SIZE := 0.42

## The set on show (null: nothing is drawn).
var poster: PosterSet:
	set(value):
		poster = value
		_dirty = true
		queue_redraw()
## The panels uncovered (0 to 5).
var uncovered: Array[int] = []:
	set(value):
		uncovered = value
		queue_redraw()
## Print the title and number the covers: off for a thumbnail too small to read.
var titled := true:
	set(value):
		titled = value
		queue_redraw()

var _built: Array[Dictionary] = []
var _built_size := Vector2.ZERO
var _dirty := true


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true


## A control that shows `set` `width` units across, the poster's proportions.
static func make(
	poster_set: PosterSet, width: float, panels: Array[int], print_title := true
) -> PosterArt:
	var art := PosterArt.new()
	art.custom_minimum_size = Vector2(width, width * PosterCompose.SIZE.y / PosterCompose.SIZE.x)
	art.size = art.custom_minimum_size
	art.titled = print_title
	art.poster = poster_set
	art.uncovered = panels
	return art


## How many shapes the poster is drawn from, for tests (0 for none).
func shape_count() -> int:
	_build()
	return _built.size()


## How many units of this control one unit of the design space is.
func factor() -> float:
	return size.x / PosterCompose.SIZE.x


func _build() -> void:
	if not _dirty and _built_size == size:
		return
	_built.clear()
	_dirty = false
	_built_size = size
	if poster == null or size.x < 1.0:
		return
	var unit := factor()
	for item in PosterCompose.shapes(poster):
		var points := PackedVector2Array()
		for point in item["p"] as PackedVector2Array:
			points.append(point * unit)
		_built.append({"p": points, "c": PlatePalettes.colour(poster.palette, item["r"])})


func _draw() -> void:
	_build()
	if _built.is_empty():
		return
	var shapes := HudShapes.new()
	for item in _built:
		shapes.polygon(item["p"], item["c"])
	shapes.flush(self)
	var unit := factor()
	var font := get_theme_font(&"font", &"Label")
	if titled:
		_print_title(font, unit)
	# The covers come after the print, so a covered panel hides the title under it.
	for index in PosterSet.PANELS:
		if not uncovered.has(index):
			_cover(index, font, unit)


func _print_title(text_font: Font, unit: float) -> void:
	for line: Dictionary in PosterCompose.print_lines(poster):
		var font: Font = UITokens.active().font_display if line["display"] else text_font
		var text: String = line["text"]
		var wanted := maxi(int(float(line["size"]) * unit), 6)
		var width := float(line["room"]) * unit
		var px := HudStyle.fit_size(font, text, wanted, width, 6)
		var ink := PlatePalettes.colour(poster.palette, line["role"])
		var span := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		var at := Vector2(float(line["centre"]) * unit - span * 0.5, float(line["baseline"]) * unit)
		draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, ink)


## Where the cover of panel `index` lies: the panel, kept inside the frame and a gap from the
## neighbours.
func cover_rect(index: int) -> Rect2:
	var unit := factor()
	var panel := PosterCompose.panel_rect(index)
	var frame := PosterCompose.FRAME
	var gap := COVER_GAP * 0.5
	var column := index % PosterSet.COLUMNS
	var row := index / PosterSet.COLUMNS
	var left := frame if column == 0 else panel.position.x + gap
	var right := (
		PosterCompose.SIZE.x - frame if column == PosterSet.COLUMNS - 1 else panel.end.x - gap
	)
	var top := frame if row == 0 else panel.position.y + gap
	var bottom := PosterCompose.SIZE.y - frame if row == PosterSet.ROWS - 1 else panel.end.y - gap
	return Rect2(Vector2(left, top) * unit, Vector2(right - left, bottom - top) * unit)


func _cover(index: int, font: Font, unit: float) -> void:
	var rect := cover_rect(index)
	var dark := PlatePalettes.colour(poster.palette, PlateShapes.Role.DARK)
	# The gap between two covers is the dark of the poster, not a sliver of its picture.
	var frame := PosterCompose.FRAME * unit
	var inside := Rect2(Vector2.ONE * frame, size - Vector2.ONE * 2.0 * frame)
	draw_rect(rect.grow(COVER_GAP * unit).intersection(inside), dark.darkened(COVER_GAP_DARKEN))
	draw_rect(rect, dark.darkened(COVER_DARKEN))
	if not titled:
		return
	var px := maxi(int(PosterCompose.PANEL.y * unit * NUMBER_SIZE), 8)
	var text := str(index + 1)
	var span := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px)
	var ink := Color(PlatePalettes.colour(poster.palette, PlateShapes.Role.LIGHT), NUMBER_ALPHA)
	var at := (
		rect.position
		+ Vector2(
			(rect.size.x - span.x) * 0.5,
			(rect.size.y + font.get_ascent(px) - font.get_descent(px)) * 0.5
		)
	)
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, ink)
