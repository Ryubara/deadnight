class_name HudChallengeCard
extends HudTicket
## The card of the challenge prompt, in the look of the main menu, "The program": a paper ticket,
## cream with dark ink, notched like the HUD's cards, a tear line of dots down its left edge and
## progress as a punch card, four holes in a row, one more punched at each quarter. Inside: what it
## is (small caps) and the count (large) on one row, the words under it, the holes under those.
## A milestone has a hole for each step of its ladder. A finish punches the last hole and says
## `FINISHED`.

const WIDTH := HudStyle.COLUMN
const HOLE_RADIUS := 6.0
const HOLE_GAP := 26.0
const ROW := 22.0
const CAPTION_SIZE := HudStyle.SMALL
const COUNT_SIZE := HudStyle.MEDIUM
## The tear line: dots down the left edge.
const PERFORATION_GAP := 10.0
const PERFORATION_RADIUS := 2.2
## How much a finish brightens the paper at the flash's peak.
const FLASH_LIGHTEN := 0.4

var caption := HudStyle.label("", CAPTION_SIZE, tokens.ink_on_accent, false, HudStyle.TRACK_CAPTION)
var count := HudStyle.label("", COUNT_SIZE, tokens.hot, true)
var words := HudStyle.wrap(HudStyle.label("", HudStyle.TEXT, tokens.ink_on_accent))

var _row := HBoxContainer.new()
var _holes := Control.new()
var _punched := 0
var _total := 4
## 0 to 1: how far the finish flash has run.
var _flash := 0.0


func _init() -> void:
	super()
	custom_minimum_size.x = WIDTH
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	HudStyle.clip(caption)
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_row.add_child(caption)
	_row.add_child(count)
	body.add_child(_row)
	words.custom_minimum_size.x = WIDTH - float(HudStyle.PAD + HudStyle.PAD_LEFT)
	body.add_child(words)
	_holes.custom_minimum_size.y = ROW
	_holes.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_holes.draw.connect(_draw_holes)
	body.add_child(_holes)
	# Ink on paper: no outline, no shadow under the letters.
	for label in [caption, count, words]:
		label.add_theme_constant_override(&"outline_size", 0)
		label.add_theme_constant_override(&"shadow_offset_y", 0)
		label.add_theme_color_override(&"font_shadow_color", Color(0.0, 0.0, 0.0, 0.0))


## Fills the card from an advance (`ChallengeProfile.apply`'s dictionary).
func show_advance(advance: Dictionary) -> void:
	var rung := int(advance.get("rung", 0))
	HudStyle.set_text(caption, _caption_for(int(advance.get("family", 0)), advance))
	if rung > 0:
		_punched = rung
		_total = int(advance["rungs"])
		HudStyle.set_text(count, "%d" % int(advance["target"]))
	else:
		_total = 4
		_punched = int(advance.get("checkpoint", 0)) / 25
		if advance.get("completed", false):
			_punched = _total
		HudStyle.set_text(count, "%d / %d" % [int(advance["after"]), int(advance["target"])])
	HudStyle.set_wrapped(words, String(advance["text"]), HudStyle.TEXT, words.custom_minimum_size.x)
	_holes.queue_redraw()
	queue_redraw()


## The finish flash, 0 to 1 and back.
func set_flash(value: float) -> void:
	if value != _flash:
		_flash = value
		queue_redraw()


## How many holes are punched and how many there are (for tests and captures).
func holes() -> Vector2i:
	return Vector2i(_punched, _total)


func _caption_for(family: int, advance: Dictionary) -> String:
	if advance.get("completed", false):
		return "FINISHED"
	match family:
		ChallengeDef.Family.MILESTONE:
			return "MILESTONE"
		ChallengeDef.Family.ORDER:
			return "ORDER"
	return "TODAY"


func _draw() -> void:
	var outline := HudStyle.ticket_points(Rect2(Vector2.ZERO, size))
	var shadow := PackedVector2Array()
	for point in outline:
		shadow.append(point + HudStyle.SHADOW)
	draw_colored_polygon(shadow, tokens.shadow)
	draw_colored_polygon(outline, tokens.ink.lerp(Color.WHITE, _flash * FLASH_LIGHTEN))
	var x := HudStyle.STRIPE + 4.0
	var y := HudStyle.NOTCH + 4.0
	while y < size.y - HudStyle.NOTCH:
		draw_circle(Vector2(x, y), PERFORATION_RADIUS, tokens.ink_disabled)
		y += PERFORATION_GAP


func _draw_holes() -> void:
	for i in _total:
		var at := Vector2(HOLE_RADIUS + 2.0 + i * HOLE_GAP, ROW * 0.5)
		if i < _punched:
			_holes.draw_circle(at, HOLE_RADIUS, tokens.bg)
		else:
			_holes.draw_arc(at, HOLE_RADIUS - 1.0, 0.0, TAU, 24, tokens.ink_disabled, 2.0)
