class_name HudPlayerBox
extends Control
## One player's container: `[portrait][points]`. The portrait (`HudPortrait`) sits on the left, the
## points box on its right carries the player's colour (the colour of the seat's armband, the same
## one the player wears in the lot), with the name small at its left and the points at its right. A
## downed player's portrait is dimmed, their box darkened and the name says DOWN.
##
## A player with a level shows the badge of `LevelTag` before the name: icon, the level right beside
## it, a little padding, then the name (a bot, or a viewer who turned levels off, shows the name
## alone). In any of the three sizes the name gives way first, ending in an ellipsis; the badge and
## the points are never cut. The badge is one block at the left of the points box, so whatever comes
## to sit behind the box later has its place at the box's left edge.
##
## A calling card sits behind the whole points box (`CardArt`, cut to the box's ticket shape). The
## points stay on the colour of the seat's armband, on a tab that runs in from the right edge
## (`HudPointsTab`), exactly as they are with no card; the level and the name sit on a strip of the
## same colour (`HudNameTab`) just as long as they are, so each glyph is on the colour its ink was
## chosen for, whatever the card is and at whatever size the box is drawn: an outline of the seat's
## colour (the first version, #1070) was a ring a pixel wide in a night on a phone and the words
## blurred into the card (#1189). The card shows round the strip and under the icon. An emblem
## follows the name, like the badge before it takes room from the points when those are long. A
## frame (#1071) is a border run just inside the box's outline, over the card and the tabs and under
## the words (`FrameArt`): it changes no layout. A bot or a seat with no card, emblem or frame draws
## none of them, and the box is what it was.
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
## Where the card's picture sits, as a share of the card's width: left of the points.
const CARD_PICTURE_AT := 0.54
## How far the strip behind the words reaches past the first and the last of them.
const NAME_TAB_PAD := 4.0
## The words' strokes are a unit and a half to two units thick; where a unit is less than this many
## pixels (a phone in a night: 0.36) they are under a pixel and no pixel is wholly ink, so the type
## is made heavier by `THIN_BOLD` (the face's own embolden, on top of the HUD's) until it is not.
const THIN_BELOW := 0.6
const THIN_BOLD := 0.9
## The contrast the words keep with the seat's colour (WCAG AA for text), a card or none.
const MIN_CONTRAST := 4.5
## What the word DOWN keeps against the dark of a downed seat's box: a letter a pixel wide is never
## wholly ink, so a word needs the headroom (the seat-coloured words have 5.6 to 14.9).
const DOWN_CONTRAST := 7.5
## A downed player's card is darkened by this much.
const CARD_DOWN := 0.55
## An emblem's side, as a share of the box's height (never more than the level icon).
const EMBLEM_SHARE := 0.4

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
## The level and icon shown, `Vector2i(level, icon)`; zero for none.
var shown_level := Vector2i.ZERO
## Where the icon, the level and the name sit in the box on the last layout, box coordinates, for
## tests: {"icon": Rect2, "level": Rect2, "name": Rect2}; empty without a level.
var badge_parts: Dictionary = {}
## The calling card, the emblem and the frame on show (`&""` for none).
var shown_card: StringName = &""
var shown_emblem: StringName = &""
var shown_frame: StringName = &""
## Whether the type is the heavier one (`THIN_BOLD`).
var _thin := false
## The pixels a unit was when the type was last chosen.
var _unit := -1.0

var _tokens := UITokens.active()
var _shown_seat := -1
var _shown_look: Dictionary = {}
var _name := HudStyle.clip(HudStyle.label("", HudStyle.SMALL, Color.BLACK, false, 1.0))
var _number := HudStyle.clip(HudStyle.label("0", HudStyle.MEDIUM, Color.BLACK, true))
var _card := CardArt.new()
var _tab := HudPointsTab.new()
var _name_tab := HudNameTab.new()
var _emblem := EmblemArt.new()
var _frame := FrameArt.new()
var _icon := LevelTag.icon_rect(1)
var _level := HudStyle.clip(HudStyle.label("", HudStyle.SMALL, Color.BLACK, false, 1.0))


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_number.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_icon.visible = false
	_level.visible = false
	_emblem.visible = false
	_tab.visible = false
	_name_tab.visible = false
	_card.motif_at = CARD_PICTURE_AT
	_frame.visible = false
	for node in [_card, _tab, _name_tab, _frame, portrait, _icon, _level, _name, _emblem, _number]:
		add_child(node)
	for label in [_name, _level, _number]:
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


## `colour` as it is when it reads on `ground` at `target` to one, else pulled toward white until it
## does: the red of DOWN on the dark a downed seat's box is (2.1 to 1 before, #1189).
static func legible(colour: Color, ground: Color, target: float) -> Color:
	var pulled := colour
	var step := 0.0
	while step < 1.0 and contrast(pulled, ground) < target:
		step += 0.05
		pulled = colour.lerp(Color.WHITE, step)
	return pulled


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


## The x where the number ends, box coordinates: the same in every box of a size, whatever sits
## before the name.
func number_right() -> float:
	return _number.position.x + _number.size.x


## Where the name starts and ends, box coordinates.
func name_rect() -> Rect2:
	return Rect2(_name.position, _name.size)


## The box's own height.
static func height_for(local: bool, small := false) -> float:
	if local:
		return LOCAL_HEIGHT
	return COMPACT_HEIGHT if small else OTHER_HEIGHT


## Fills the box from one entry of the party (`HudState.team`).
## `level` is `Vector2i(level, icon)` as the viewer is to see it (`HudState.level_of`); `plate` is
## the calling card, emblem and frame (`HudState.plate_of`).
func show_player(
	id: int, member: Dictionary, local: bool, small := false, level := Vector2i.ZERO, plate := {}
) -> void:
	player_id = id
	is_local = local
	compact = small and not local
	shown_level = level if level.x > 0 else Vector2i.ZERO
	shown_card = StringName(plate.get("card", &""))
	shown_emblem = StringName(plate.get("emblem", &""))
	shown_frame = StringName(plate.get("frame", &""))
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
	_sync_weight()
	_set_colour(_name, legible(_tokens.danger, fill(), DOWN_CONTRAST) if downed else ink)
	_set_colour(_number, ink)
	_set_colour(_level, ink)
	_icon.visible = shown_level.x > 0
	_level.visible = shown_level.x > 0
	if shown_level.x > 0:
		LevelTag.set_icon(_icon, shown_level.y)
		HudStyle.set_text(_level, str(shown_level.x))
	_icon.modulate.a = 0.55 if downed else 1.0
	_show_plate()
	var tag := "DEAD" if bool(member["dead"]) else "DOWN"
	HudStyle.set_text(_name, tag if downed else HudState.name_of(member))
	HudStyle.set_fitted(
		_number,
		str(member["points"]),
		HudStyle.POINTS if local else (HudStyle.TEXT if compact else HudStyle.MEDIUM),
		_box().size.x - 2.0 * PADDING - NAME_ROOM - _taken(),
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


## What the badge and the gap before the name take from the box's line; nothing without a level.
func _badge_taken() -> float:
	if shown_level.x < 1:
		return 0.0
	var font := _name.get_theme_font(&"font")
	return LevelTag.taken(LevelTag.level_room(font, _name.get_theme_font_size(&"font_size")))


## What the tab's lean takes from the name's room: nothing without a card.
func _tab_taken() -> float:
	return HudPointsTab.SLANT if shown_card != &"" else 0.0


## What the emblem takes from the line after the name: its side and a gap; nothing without one.
func _emblem_taken() -> float:
	return _emblem_side() + float(HudStyle.SM) if shown_emblem != &"" else 0.0


func _emblem_side() -> float:
	return minf(LevelTag.ICON, roundf(_box().size.y * EMBLEM_SHARE))


## Everything before and after the name that the points make room for.
func _taken() -> float:
	return _badge_taken() + _emblem_taken()


## Puts the card and the emblem on show; what did not change is left alone (a card rebuilds its
## shapes, and this runs at every kill).
func _show_plate() -> void:
	if _card.card_id != shown_card:
		_card.card_id = shown_card
	var carded := shown_card != &""
	_tab.visible = carded
	_tab.colour = fill()
	_name_tab.visible = carded
	_name_tab.colour = fill()
	for label in [_name, _level]:
		(label as HudLabel).halo_size = 0
	_emblem.rim = fill() if carded else Color(0, 0, 0, 0)
	var darkened := CARD_DOWN if downed else 0.0
	if not is_equal_approx(_card.dim, darkened):
		_card.dim = darkened
		_emblem.dim = darkened
	if _emblem.emblem_id != shown_emblem:
		_emblem.emblem_id = shown_emblem
	_emblem.visible = shown_emblem != &""
	if _frame.frame_id != shown_frame:
		_frame.frame_id = shown_frame
	if not is_equal_approx(_frame.dim, darkened):
		_frame.dim = darkened
	_frame.visible = shown_frame != &""


## Makes the type heavier where a unit is under `THIN_BELOW` of a pixel, and as it was elsewhere.
func _sync_weight() -> void:
	if not is_inside_tree():
		return
	var unit := get_viewport().get_final_transform().get_scale().x
	if not is_equal_approx(unit, _unit):
		_unit = unit
		set_thin(unit < THIN_BELOW)


## The heavier type of a screen where a unit is a fraction of a pixel (`THIN_BOLD`), or the HUD's
## own.
func set_thin(thin: bool) -> void:
	if thin == _thin:
		return
	_thin = thin
	var extra := THIN_BOLD if thin else 0.0
	var plain := _tokens.embolden_display
	for label in [_name, _level]:
		label.add_theme_font_override(&"font", _tokens.text_font(plain * 0.3 + extra, 1.0))
	_number.add_theme_font_override(&"font", _tokens.display_font(plain * 0.5 + extra))
	_layout()


func _layout() -> void:
	_sync_weight()
	var box := _box()
	_card.position = box.position
	_frame.position = box.position
	if _card.size != box.size:
		_card.size = box.size
		_frame.size = box.size
		var outline := HudStyle.ticket_points(Rect2(Vector2.ZERO, box.size), HudStyle.NOTCH * 0.6)
		_card.clip = outline
		_frame.outline = outline
	portrait.position = Vector2.ONE * FRAME
	portrait.size = Vector2.ONE * (box.size.y - 2.0 * FRAME)
	var number_font := _number.get_theme_font(&"font")
	var number_px := _number.get_theme_font_size(&"font_size")
	var name_font := _name.get_theme_font(&"font")
	var name_px := _name.get_theme_font_size(&"font_size")
	# One baseline for both: the numerals' capitals centred in the box, on a whole unit (a label
	# drawn from half a unit sets its glyphs at a whole one, and the icon beside the level follows
	# the digits where they are drawn).
	var baseline := roundf(
		(
			box.size.y * 0.5
			+ (number_font.get_ascent(number_px) - number_font.get_descent(number_px)) * 0.5
		)
	)
	var wide := HudStyle.text_width(number_font, _number.text, number_px) + 2.0
	_number.size = Vector2(
		minf(wide, box.size.x - 2.0 * PADDING - NAME_ROOM - _taken()), _line(_number)
	)
	_number.position = Vector2(
		box.end.x - PADDING - _number.size.x, baseline - number_font.get_ascent(number_px)
	)
	var name_left := box.position.x + PADDING
	badge_parts = {}
	if shown_level.x > 0:
		var room := LevelTag.level_room(name_font, name_px)
		# The icon's body is centred on the digits' ink, which sit on the name's baseline.
		var icon := Rect2(
			name_left,
			LevelTag.icon_top(LevelTag.digits_centre(name_font, name_px, baseline), shown_level.y),
			LevelTag.ICON,
			LevelTag.ICON
		)
		_icon.position = icon.position
		_icon.size = icon.size
		var level_at := icon.end.x + LevelTag.ICON_GAP
		_level.size = Vector2(room, _line(_level))
		_level.position = Vector2(level_at, baseline - name_font.get_ascent(name_px))
		name_left = level_at + room + LevelTag.NAME_GAP
		badge_parts = {"icon": icon, "level": Rect2(_level.position, _level.size)}
	_name.size = Vector2(
		maxf(
			_number.position.x - name_left - float(HudStyle.SM) - _emblem_taken() - _tab_taken(),
			0.0
		),
		_line(_name)
	)
	_name.position = Vector2(name_left, baseline - name_font.get_ascent(name_px))
	# The emblem follows the name's text, or the end of its room when the name is cut.
	var side := _emblem_side()
	_emblem.size = Vector2.ONE * side
	var text_end := minf(HudStyle.text_width(name_font, _name.text, name_px), _name.size.x)
	_emblem.position = Vector2(
		name_left + text_end + float(HudStyle.SM), box.position.y + (box.size.y - side) * 0.5
	)
	_place_name_tab(box, name_left, text_end)
	_tab.place(box, _number.position.x - float(HudStyle.SM) - HudPointsTab.SLANT)

	if shown_level.x > 0:
		badge_parts["name"] = Rect2(_name.position, _name.size)


## The strip behind the level and the name: from just before the level (or the name without one) to
## just after the name's text, the line's height and a little, in the box's middle.
func _place_name_tab(box: Rect2, name_left: float, text_end: float) -> void:
	if shown_card == &"":
		return
	var left := name_left
	if badge_parts.has("level"):
		left = (badge_parts["level"] as Rect2).position.x
	left -= NAME_TAB_PAD
	var right := name_left + text_end + NAME_TAB_PAD + HudNameTab.SLANT * 0.5
	var height := minf(
		_line(_name) + 2.0 * float(HudStyle.XS), box.size.y - 2.0 * float(HudStyle.XS)
	)
	_name_tab.place(Rect2(left, box.position.y + (box.size.y - height) * 0.5, right - left, height))


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
