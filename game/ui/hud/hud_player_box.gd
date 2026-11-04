class_name HudPlayerBox
extends Control
## One player's container: `[portrait][points]`. The portrait (`HudPortrait`) sits on the left, the
## points box on its right carries the player's colour (the colour of the seat's armband, the same
## one the player wears in the lot), with the name small at its left and the points at its right.
## A downed player's portrait is dimmed, their box darkened and the name says DOWN.
##
## The two texts share one baseline (the bottom of the numerals' capitals), so a small name and a
## big number read as one line; the numbers of every box end on the same vertical line.

## Height of your own box and of a teammate's; the portrait is a square of that height.
const LOCAL_HEIGHT := 66.0
const OTHER_HEIGHT := 48.0
## A teammate's box once the party is bigger than `HudPoints.COMPACT_FROM`: eight players still
## fit the column on the smallest canvas, with the name and the points set a size smaller.
const COMPACT_HEIGHT := 32.0
## Space between the portrait and the points box, and the box's padding.
const SPLIT := float(HudStyle.SM)
const PADDING := float(HudStyle.MD)
## The seat's colour round the portrait.
const FRAME := 3.0
## The room a name keeps before the number may take the rest (ordinary names fit it; a longer one
## ends in an ellipsis).
const NAME_ROOM := 72.0
## How much of the seat's colour a downed player's box keeps (the rest is the dark ground).
const DOWN_KEEP := 0.3

var player_id := 0
var colour := Color.WHITE
var downed := false
var is_local := false
## The smaller teammate box of a big party (`HudPoints.COMPACT_FROM`).
var compact := false
var portrait := HudPortrait.new()
var name_text: String:
	get:
		return _name.text
var number_text: String:
	get:
		return _number.text
## The colour the name and the number are drawn in.
var ink := Color.BLACK

var _tokens := UITokens.active()
var _shown_seat := -1
var _shown_look: Dictionary = {}
var _name := HudStyle.clip(HudStyle.label("", HudStyle.SMALL, Color.BLACK, false, 1.0))
var _number := HudStyle.clip(HudStyle.label("0", HudStyle.MEDIUM, Color.BLACK, true))


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_number.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	for node in [portrait, _name, _number]:
		add_child(node)
	for label in [_name, _number]:
		# Dark ink on the seat's colour needs no outline or shadow.
		(label as HudLabel).halo_size = 0
		(label as Label).add_theme_color_override(&"font_shadow_color", Color.TRANSPARENT)
	resized.connect(_layout)


## The text colour that reads best on `fill`: the dark ink or the light one, whichever has the
## higher contrast ratio (the red seat takes the light one).
static func ink_for(fill: Color) -> Color:
	var tokens := UITokens.active()
	var dark := tokens.ink_on_accent
	var light := tokens.ink
	return dark if contrast(fill, dark) >= contrast(fill, light) else light


## WCAG contrast ratio of two colours.
static func contrast(a: Color, b: Color) -> float:
	var la := _luminance(a)
	var lb := _luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


static func _luminance(c: Color) -> float:
	return 0.2126 * _linear(c.r) + 0.7152 * _linear(c.g) + 0.0722 * _linear(c.b)


static func _linear(v: float) -> float:
	return v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)


## How wide the number's text is at the size it is drawn, and the size of its label, for tests.
func number_width() -> float:
	return HudStyle.text_width(
		_number.get_theme_font(&"font"), _number.text, _number.get_theme_font_size(&"font_size")
	)


func number_size() -> Vector2:
	return _number.size


## The box's own height.
static func height_for(local: bool, small := false) -> float:
	if local:
		return LOCAL_HEIGHT
	return COMPACT_HEIGHT if small else OTHER_HEIGHT


## Fills the box from one entry of the party (`HudState.team`).
func show_player(id: int, member: Dictionary, local: bool, small := false) -> void:
	player_id = id
	is_local = local
	compact = small and not local
	downed = bool(member["downed"])
	var seat := int(member.get("seat", 0))
	colour = LookCatalog.armband_colour(seat)
	ink = ink_for(fill())
	custom_minimum_size = Vector2(HudStyle.COLUMN, height_for(local, compact))
	# A points change comes here every kill: what did not change is left alone (a portrait builds
	# a look and its key, a colour override tells the label to lay itself out again).
	var look_data: Dictionary = member.get("look", {})
	if seat != _shown_seat or look_data != _shown_look:
		_shown_seat = seat
		_shown_look = look_data
		portrait.show_look(look_data, seat)
	portrait.downed = downed
	_set_colour(_name, _tokens.danger if downed else ink)
	_set_colour(_number, ink)
	var tag := "DEAD" if bool(member["dead"]) else "DOWN"
	HudStyle.set_text(_name, tag if downed else HudState.name_of(member))
	HudStyle.set_fitted(
		_number,
		str(member["points"]),
		HudStyle.POINTS if local else (HudStyle.TEXT if compact else HudStyle.MEDIUM),
		_box().size.x - 2.0 * PADDING - NAME_ROOM,
		HudStyle.MIN_TEXT
	)
	_layout()
	queue_redraw()


## Sets a label's text colour when it is not already that.
func _set_colour(label: Label, value: Color) -> void:
	if label.get_theme_color(&"font_color") != value:
		label.add_theme_color_override(&"font_color", value)


## The fill of the points box: the seat's colour, or a dark one of it while down.
func fill() -> Color:
	return colour.lerp(_tokens.bg, 1.0 - DOWN_KEEP) if downed else colour


## The points box: its rectangle, right of the portrait.
func _box() -> Rect2:
	var h := height_for(is_local, compact)
	var left := h + SPLIT
	return Rect2(left, 0.0, maxf(size.x, custom_minimum_size.x) - left, h)


func _layout() -> void:
	var box := _box()
	portrait.position = Vector2.ONE * FRAME
	portrait.size = Vector2.ONE * (box.size.y - 2.0 * FRAME)
	var number_font := _number.get_theme_font(&"font")
	var number_px := _number.get_theme_font_size(&"font_size")
	var name_font := _name.get_theme_font(&"font")
	var name_px := _name.get_theme_font_size(&"font_size")
	# One baseline for both: the numerals' capitals centred in the box.
	var baseline := (
		box.size.y * 0.5
		+ (number_font.get_ascent(number_px) - number_font.get_descent(number_px)) * 0.5
	)
	var wide := HudStyle.text_width(number_font, _number.text, number_px) + 2.0
	_number.size = Vector2(minf(wide, box.size.x - 2.0 * PADDING - NAME_ROOM), _line(_number))
	_number.position = Vector2(
		box.end.x - PADDING - _number.size.x, baseline - number_font.get_ascent(number_px)
	)
	var name_left := box.position.x + PADDING
	_name.size = Vector2(
		maxf(_number.position.x - name_left - float(HudStyle.SM), 0.0), _line(_name)
	)
	_name.position = Vector2(name_left, baseline - name_font.get_ascent(name_px))


## A label's own line height.
func _line(label: Label) -> float:
	return label.get_minimum_size().y


func _draw() -> void:
	var box := _box()
	var shade := HudStyle.SHADOW * 0.6
	var outline := HudStyle.ticket_points(box, HudStyle.NOTCH * 0.6)
	var shadow := PackedVector2Array()
	for point in outline:
		shadow.append(point + shade)
	# One command for the four shapes (`HudShapes`).
	var shapes := HudShapes.new()
	shapes.polygon(shadow, _tokens.shadow)
	shapes.rect(Rect2(shade, Vector2.ONE * box.size.y), _tokens.shadow)
	shapes.polygon(outline, fill())
	shapes.rect(Rect2(Vector2.ZERO, Vector2.ONE * box.size.y), fill())
	shapes.flush(self)
