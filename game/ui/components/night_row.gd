class_name NightRow
extends Button
## One night of the Server Browser as a row you press to go in (`NightEntry`): the map's picture
## faded behind it, the map's name, a badge that says which of the two it is (a lobby WAITING for
## its host, or a night IN PROGRESS with its round), who hosts it and how many bots play, and the
## people on it out of the seats, as a number and as one pip a seat. Drawn here, as the menu's
## tickets are (`MenuItemButton`).
##
## The words never sit on the picture: the picture is the row's ground, darkened by a scrim that is
## nearly solid under the text (`SCRIM_LEFT`), the badge is a chip with its own fill, and the people
## count sits on a dark plate. `scrim_contrast` is the contrast the cream type has with the
## brightest pixel of the map under it, which `test_night_row.gd` holds above 4.5.
##
## The compact form (a phone held sideways, 540 units tall) is a little over a tap target high and
## drops the pips; the badge, the name and the count stay.

const HEIGHT := 116.0
const COMPACT_HEIGHT := 84.0
const STRIPE := 10.0
const PAD := 30.0
const PAD_COMPACT := 24.0
const OUTLINE := 3.0
const TITLE_SIZE := 38
const TITLE_SIZE_COMPACT := 30
const TITLE_SIZE_MIN := 20
const NUMBER_SIZE := 52
const NUMBER_SIZE_COMPACT := 38
const PIP := 8.0
const PIP_STEP := 22.0
const CHIP_PAD := 12.0
## The scrim over the picture: how dark at the text end, and at the far end where the picture shows.
const SCRIM_LEFT := 0.92
const SCRIM_RIGHT := 0.46
## The share of the row's width the name, the badge and the host are written over.
const TEXT_SHARE := 0.6
const SCRIM_COLOUR := Color(0.03, 0.025, 0.045)
## What the people plate is: nearly solid, so the count has a ground of its own.
const PLATE := Color(0.03, 0.025, 0.045, 0.88)
## The row of a full night, and of one the player is busy joining.
const FULL_FADE := 0.55
## The chips: a lobby that waits is amber with dark type, a night in progress red with white.
const WAITING_FILL := Color("ffb347")
const WAITING_INK := Color("1c1612")
const MATCH_FILL := Color("d6392f")
const MATCH_INK := Color.WHITE
const FULL_FILL := Color("8d8574")
const FULL_INK := Color("1c1612")
const HERE_FILL := Color("efe4cb")

var entry: NightEntry:
	set(value):
		entry = value
		accessibility_name = entry.spoken() if entry != null else ""
		queue_redraw()
var compact := false:
	set(value):
		compact = value
		_fit()
		queue_redraw()
## The row is the night the player is in already (they opened the browser from its lobby): a press
## goes back.
var here := false:
	set(value):
		here = value
		queue_redraw()
## The player pressed it and the join is on its way.
var joining := false:
	set(value):
		joining = value
		queue_redraw()


func _init() -> void:
	UiSounds.wire(self)
	flat = true
	focus_mode = Control.FOCUS_ALL
	# Inside a scroll area a drag that starts here reaches it (`UIScroll`); anywhere else the button
	# stops the pointer, as a button does.
	UIScroll.pass_touch_in_scroll(self)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fit()
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	mouse_entered.connect(_on_hover)
	mouse_exited.connect(queue_redraw)
	resized.connect(queue_redraw)


## A row is a ticket of a list; a full night is refused like a placeholder row is.
func ui_sound_role() -> StringName:
	return &"ticket_soon" if entry != null and entry.full and not here else &"ticket"


func _fit() -> void:
	custom_minimum_size = Vector2(0.0, COMPACT_HEIGHT if compact else HEIGHT)


func _on_hover() -> void:
	# Hovering moves the focus, so the pointer and the keyboard never disagree (the menu's rule).
	if not disabled and focus_mode != Control.FOCUS_NONE:
		grab_focus()
	queue_redraw()


## The least contrast the type (`MenuLook.INK`) has anywhere over the part of the row the name, the
## badge and the host are written over (the first `TEXT_SHARE` of its width): each pixel of the
## map's picture, as the scrim covers it at that distance across the row. The row is readable when
## this is at least 4.5 (the written minimum for body text). Compositing is done on the colours, as
## the screen does it.
static func scrim_contrast(info: MapInfo) -> float:
	var texture := info.preview() if info != null else null
	var brightest := 0.0
	if texture == null:
		brightest = _luminance(Color.BLACK)
	else:
		var image := texture.get_image()
		var width := image.get_width()
		var reach := int(width * TEXT_SHARE)
		for y in image.get_height():
			for x in reach:
				var covered := _over(image.get_pixel(x, y), float(x) / float(width))
				brightest = maxf(brightest, _luminance(covered))
	return (_luminance(MenuLook.INK) + 0.05) / (brightest + 0.05)


## The scrim's alpha at `share` of the row's width (0 left, 1 right): a straight line from
## `SCRIM_LEFT` to `SCRIM_RIGHT`.
static func scrim_alpha_at(share: float) -> float:
	return lerpf(SCRIM_LEFT, SCRIM_RIGHT, clampf(share, 0.0, 1.0))


## A picture's colour under the scrim at `share` of the row's width.
static func _over(pixel: Color, share: float) -> Color:
	return pixel.lerp(SCRIM_COLOUR, scrim_alpha_at(share))


## Relative luminance of a colour (WCAG), in the 0..1 range.
static func _luminance(colour: Color) -> float:
	return 0.2126 * _linear(colour.r) + 0.7152 * _linear(colour.g) + 0.0722 * _linear(colour.b)


static func _linear(channel: float) -> float:
	return channel / 12.92 if channel <= 0.03928 else pow((channel + 0.055) / 1.055, 2.4)


func _draw() -> void:
	if entry == null:
		return
	var tokens := UITokens.active()
	var lit := has_focus() or is_hovered()
	var dim := FULL_FADE if entry.full and not here else 1.0
	if joining:
		dim = 0.7
	var whole := Rect2(Vector2.ZERO, size)
	draw_rect(whole, MenuLook.HOLE)
	_draw_picture(whole, dim)
	_draw_scrim(whole, dim)
	_draw_stripe(dim)
	var pad := PAD_COMPACT if compact else PAD
	var left := STRIPE + pad
	var plate_width := _plate_width()
	var room := size.x - left - plate_width - pad * 2.0
	var info := entry.map()
	var fitted := _title_size()
	var ink := Color(MenuLook.INK, dim)
	draw_string(
		tokens.font_display,
		Vector2(left, size.y * (0.38 if compact else 0.4)),
		info.title.to_upper(),
		HORIZONTAL_ALIGNMENT_LEFT,
		room,
		fitted,
		ink
	)
	var line := size.y * (0.78 if compact else 0.76)
	var chip_end := _draw_chip(left, line, dim)
	_draw_facts(chip_end + CHIP_PAD, line, room - (chip_end - left), dim)
	_draw_plate(plate_width, dim)
	if lit:
		draw_rect(whole.grow(-OUTLINE * 0.5), MenuLook.AMBER, false, OUTLINE)


## The picture, cover-fitted to the row: the whole row's ground.
func _draw_picture(whole: Rect2, dim: float) -> void:
	var texture := entry.map().preview()
	if texture == null:
		return
	var source := texture.get_size()
	var wanted := whole.size.x / whole.size.y
	var crop := Rect2(Vector2.ZERO, source)
	if source.x / source.y > wanted:
		crop.size.x = source.y * wanted
		crop.position.x = (source.x - crop.size.x) * 0.5
	else:
		crop.size.y = source.x / wanted
		crop.position.y = (source.y - crop.size.y) * 0.5
	draw_texture_rect_region(texture, whole, crop, Color(1.0, 1.0, 1.0, dim))


## The picture faded: dark at the text end, letting the map through at the far end.
func _draw_scrim(whole: Rect2, dim: float) -> void:
	var left := Color(SCRIM_COLOUR, SCRIM_LEFT)
	var right := Color(SCRIM_COLOUR, SCRIM_RIGHT)
	if dim < 1.0:
		left = Color(SCRIM_COLOUR, lerpf(1.0, SCRIM_LEFT, dim))
		right = Color(SCRIM_COLOUR, lerpf(1.0, SCRIM_RIGHT, dim))
	draw_polygon(
		PackedVector2Array(
			[whole.position, Vector2(whole.end.x, 0.0), whole.end, Vector2(0.0, whole.end.y)]
		),
		PackedColorArray([left, right, right, left])
	)


## The stripe at the left edge says the kind at a distance: amber waits, red is on.
func _draw_stripe(dim: float) -> void:
	var colour := _chip_fill()
	draw_rect(Rect2(0.0, 0.0, STRIPE, size.y), Color(colour, dim))


func _chip_fill() -> Color:
	if here:
		return HERE_FILL
	if entry.full:
		return FULL_FILL
	return MATCH_FILL if entry.is_match() else WAITING_FILL


func _chip_ink() -> Color:
	if here:
		return WAITING_INK
	if entry.full:
		return FULL_INK
	return MATCH_INK if entry.is_match() else WAITING_INK


## The chip with the badge word and, for a night in progress, the round; its right edge.
func _draw_chip(left: float, baseline: float, dim: float) -> float:
	var font := MenuLook.wide_font()
	var text := chip_text()
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, MenuLook.SIZE_CAPTION).x
	var chip_height := MenuLook.SIZE_CAPTION + 14.0
	var rect := Rect2(
		Vector2(left, baseline - MenuLook.SIZE_CAPTION - 4.0),
		Vector2(width + CHIP_PAD * 2.0, chip_height)
	)
	draw_rect(rect, Color(_chip_fill(), dim))
	draw_string(
		font,
		Vector2(rect.position.x + CHIP_PAD, baseline),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		MenuLook.SIZE_CAPTION,
		Color(_chip_ink(), dim)
	)
	return rect.end.x


## The words on the chip: which kind of night it is (and the round of one in progress), or what the
## row is doing now.
func chip_text() -> String:
	if entry == null:
		return ""
	if joining:
		return "JOINING..."
	if here:
		return "YOUR NIGHT"
	var text := entry.badge_text()
	if entry.is_match() and entry.round_number > 0 and not entry.full:
		text += "  ROUND %d" % entry.round_number
	return text


## Who hosts and how many bots, after the chip, in the cream type (cut to the room that is left).
func _draw_facts(left: float, baseline: float, room: float, dim: float) -> void:
	var parts: Array[String] = []
	if entry.host_name != "":
		parts.append(entry.host_name)
	if entry.bots > 0:
		parts.append(entry.bots_text())
	if parts.is_empty() or room < 40.0:
		return
	draw_string(
		UITokens.active().font_text,
		Vector2(left, baseline),
		"  ·  ".join(parts),
		HORIZONTAL_ALIGNMENT_LEFT,
		room,
		MenuLook.SIZE_CAPTION,
		Color(MenuLook.INK, dim)
	)


## The size, in units, the map's name is drawn at: the row's own, cut down until the name fits the
## room it has (never under `TITLE_SIZE_MIN`).
func _title_size() -> int:
	var pad := PAD_COMPACT if compact else PAD
	var room := size.x - STRIPE - pad * 3.0 - _plate_width()
	var start := TITLE_SIZE_COMPACT if compact else TITLE_SIZE
	return _fit_size(UITokens.active().font_display, entry.map().title.to_upper(), room, start)


## The sizes, in units, of every word the row draws: the name, the badge, the host, the count and
## its seats. The words are drawn, not theme text, so `UiAudit` asks for them here.
func drawn_text_sizes() -> Array[int]:
	if entry == null:
		return []
	return [
		_title_size(),
		MenuLook.SIZE_CAPTION,
		MenuLook.SIZE_CAPTION,
		NUMBER_SIZE_COMPACT if compact else NUMBER_SIZE,
		MenuLook.SIZE_BODY,
	]


func _plate_width() -> float:
	if compact:
		return 120.0
	return maxf(entry.max_players * PIP_STEP, 120.0) + 40.0


## The people: a plate with the count and a pip a seat.
func _draw_plate(width: float, dim: float) -> void:
	var tokens := UITokens.active()
	var right := size.x - 14.0
	var rect := Rect2(Vector2(right - width, 12.0), Vector2(width, size.y - 24.0))
	draw_rect(rect, Color(PLATE, PLATE.a * dim))
	var number_size := NUMBER_SIZE_COMPACT if compact else NUMBER_SIZE
	var count := str(entry.players)
	var seats := "/%d" % entry.max_players
	var number_width := (
		tokens.font_display.get_string_size(count, HORIZONTAL_ALIGNMENT_LEFT, -1, number_size).x
	)
	var seats_size := MenuLook.SIZE_BODY
	var seats_width := (
		tokens.font_text.get_string_size(seats, HORIZONTAL_ALIGNMENT_LEFT, -1, seats_size).x
	)
	var start := rect.position.x + (rect.size.x - number_width - seats_width) * 0.5
	var base := rect.position.y + (rect.size.y * (0.62 if compact else 0.56))
	draw_string(
		tokens.font_display,
		Vector2(start, base),
		count,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		number_size,
		Color(MenuLook.INK, dim)
	)
	draw_string(
		tokens.font_text,
		Vector2(start + number_width + 2.0, base),
		seats,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		seats_size,
		Color(MenuLook.INK, dim)
	)
	if compact:
		return
	var pips_width := (entry.max_players - 1) * PIP_STEP
	var pip_start := rect.position.x + (rect.size.x - pips_width) * 0.5
	var pip_y := rect.end.y - 18.0
	for seat in entry.max_players:
		var at := Vector2(pip_start + seat * PIP_STEP, pip_y)
		if seat < entry.players:
			draw_circle(at, PIP * 0.5 + 1.0, Color(MenuLook.INK, dim))
		else:
			draw_arc(at, PIP * 0.5, 0.0, TAU, 14, Color(MenuLook.INK, 0.6 * dim), 1.5, true)


## The largest size from `start` down to `TITLE_SIZE_MIN` at which `text` fits `room`.
static func _fit_size(font: Font, text: String, room: float, start: int) -> int:
	var now := start
	while now > TITLE_SIZE_MIN:
		if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, now).x <= room:
			return now
		now -= 1
	return TITLE_SIZE_MIN
