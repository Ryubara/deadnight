class_name MapCard
extends Button
## One map of the picker as a ticket, drawn the way the menu's tickets are (`MenuItemButton`,
## `MenuLook.draw_ticket`): cream paper with a notch in each side and a perforated stub that holds
## the preview picture, the map's name in the display face and its size and player count under it.
## The map that is chosen is outlined in red and says SELECTED; the one with the focus or the
## pointer is outlined in amber, like every ticket of the menu. A map that is not built yet is on
## shaded paper with a hatched stub, a padlock and a COMING SOON stamp: it takes the focus (a
## keyboard can read it) but a press chooses nothing (`MapPicker` says `blocked`).
##
## The compact form (a phone held sideways, two cards to a row) has no picture and is a little over
## a tap target high: the name, the size and the players on three short lines, and a red check in
## the corner for the chosen map in place of the word.

const NOTCH := 11.0
const OUTLINE := 3.0
const PAD := 20.0
const PAD_COMPACT := 14.0
## The size of a card on the desktop: the picture is 16:9 with the paper's margin round it.
const HEIGHT := 104.0
const PICTURE := Vector2(150.0, 84.4)
## A phone's card, a little over the tap target so the three lines fit.
const COMPACT_HEIGHT := 74.0
const COMPACT_CAPTION := 20
const TITLE_SIZE := 28
const TITLE_SIZE_MIN := 18
const STAMP_TILT := -0.14

var info: MapInfo:
	set(value):
		info = value
		accessibility_name = _spoken()
		queue_redraw()
var selected := false:
	set(value):
		selected = value
		accessibility_name = _spoken()
		queue_redraw()
var compact := false:
	set(value):
		compact = value
		_fit()
		queue_redraw()

var _width := 440.0


func _init() -> void:
	flat = true
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_fit()
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	mouse_entered.connect(_on_hover)
	mouse_exited.connect(queue_redraw)
	resized.connect(queue_redraw)


func _ready() -> void:
	focus_entered.connect(UIAudio.play.bind(&"focus"))


## True for a map that cannot be chosen yet.
func is_locked() -> bool:
	return info == null or not info.is_playable()


## The width the card asks for.
func set_width(width: float) -> void:
	_width = width
	_fit()


## What a screen reader says for the card.
func _spoken() -> String:
	if info == null:
		return ""
	var state := "coming soon" if is_locked() else ("selected" if selected else "")
	return "%s, %s%s" % [info.title, info.facts_text(), ", " + state if state != "" else ""]


func _fit() -> void:
	custom_minimum_size = Vector2(_width, COMPACT_HEIGHT if compact else HEIGHT)


func _on_hover() -> void:
	# Hovering moves the focus, so the pointer and the keyboard never disagree (the menu's rule).
	if not disabled and focus_mode != Control.FOCUS_NONE:
		grab_focus()
	queue_redraw()


func _draw() -> void:
	if info == null:
		return
	var locked := is_locked()
	var lit := has_focus() or is_hovered()
	var paper := MenuLook.PAPER_SHADE if locked else MenuLook.PAPER
	var shade := MenuLook.PAPER_RULE if locked else MenuLook.PAPER_SHADE
	if lit:
		paper = paper.lightened(0.06)
	var text_left := PAD_COMPACT if compact else PAD + PICTURE.x + PAD
	MenuLook.draw_ticket(self, size, paper, shade, NOTCH, -1.0 if compact else text_left - 10.0)
	if not compact:
		_draw_picture(Rect2(Vector2(PAD, (size.y - PICTURE.y) * 0.5), PICTURE), locked)
	_draw_text(text_left, locked)
	if lit:
		_outline(MenuLook.AMBER)
	elif selected:
		_outline(MenuLook.RED)


func _outline(colour: Color) -> void:
	draw_rect(Rect2(Vector2.ZERO, size).grow(-OUTLINE * 0.5), colour, false, OUTLINE)


func _draw_text(left: float, locked: bool) -> void:
	var ink := MenuLook.PAPER_MUTED if locked else MenuLook.PAPER_INK
	if compact:
		_draw_compact_text(left, locked, ink)
		return
	var tokens := UITokens.active()
	var muted := MenuLook.PAPER_MUTED
	var room := size.x - left - PAD
	var title := info.title.to_upper()
	var small: Font = tokens.font_text
	var tag := "" if (not selected or locked) else "SELECTED"
	var title_size := _fit_size(tokens.font_display, title, room, TITLE_SIZE, TITLE_SIZE_MIN)
	draw_string(
		tokens.font_display,
		Vector2(left, 38.0),
		title,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		title_size,
		ink
	)
	var lines: Array[String] = [info.size_text(), info.players_text()]
	for index in lines.size():
		draw_string(
			small,
			Vector2(left, 68.0 + index * 26.0),
			lines[index],
			HORIZONTAL_ALIGNMENT_LEFT,
			room,
			MenuLook.SIZE_CAPTION,
			muted
		)
	_draw_tag(tag, 68.0)


## The compact card: the name (it leaves room for the check), then the size and the players.
func _draw_compact_text(left: float, locked: bool, ink: Color) -> void:
	var tokens := UITokens.active()
	var small: Font = tokens.font_text
	var room := size.x - left - PAD_COMPACT
	var title := info.title.to_upper()
	var title_room := room - (24.0 if selected and not locked else 0.0)
	var title_size := _fit_size(tokens.font_display, title, title_room, 22, 16)
	draw_string(
		tokens.font_display,
		Vector2(left, 27.0),
		title,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		title_size,
		ink
	)
	var lines: Array[String] = [info.size_text(), info.players_text()]
	if locked:
		lines = ["Coming soon", info.size_text()]
	for index in lines.size():
		draw_string(
			small,
			Vector2(left, 49.0 + index * 20.0),
			lines[index],
			HORIZONTAL_ALIGNMENT_LEFT,
			room,
			COMPACT_CAPTION,
			MenuLook.PAPER_MUTED
		)
	if selected and not locked:
		var at := Vector2(size.x - PAD_COMPACT - 9.0, 20.0)
		draw_circle(at, 10.0, MenuLook.RED)
		draw_polyline(
			PackedVector2Array(
				[at + Vector2(-4.5, 0.5), at + Vector2(-1.0, 4.0), at + Vector2(5.0, -3.5)]
			),
			Color.WHITE,
			2.2,
			true
		)


## The word that says the card is the chosen one, at the right edge of a line of facts.
func _draw_tag(tag: String, baseline: float) -> void:
	if tag == "":
		return
	var width := _wide_width(tag, MenuLook.SIZE_CAPTION)
	draw_string(
		MenuLook.wide_font(),
		Vector2(size.x - PAD - width, baseline),
		tag,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		MenuLook.SIZE_CAPTION,
		MenuLook.RED
	)


## The stub: the preview, or for a map that is not built the night's dark with a hatch, a padlock
## and a COMING SOON stamp.
func _draw_picture(rect: Rect2, locked: bool) -> void:
	var texture := info.preview()
	if texture != null and not locked:
		draw_texture_rect(texture, rect, false)
		draw_rect(rect, MenuLook.PAPER_INK, false, 1.0)
		return
	draw_rect(rect, MenuLook.HOLE)
	var hatch := Color(1.0, 1.0, 1.0, 0.07)
	var step := 12.0
	var offset := -rect.size.y
	while offset < rect.size.x:
		var from := Vector2(rect.position.x + offset, rect.end.y)
		var to := Vector2(rect.position.x + offset + rect.size.y, rect.position.y)
		var clipped := _clip_to(rect, from, to)
		if clipped.size() == 2:
			draw_line(clipped[0], clipped[1], hatch, 2.0)
		offset += step
	_draw_padlock(rect.get_center() + Vector2(0.0, -10.0))
	_draw_stamp(rect.get_center() + Vector2(0.0, 22.0))
	draw_rect(rect, MenuLook.PAPER_INK, false, 1.0)


func _draw_padlock(at: Vector2) -> void:
	var colour := MenuLook.MUTED
	var body := Rect2(at + Vector2(-11.0, -2.0), Vector2(22.0, 16.0))
	draw_arc(at + Vector2(0.0, -4.0), 8.0, PI, TAU, 16, colour, 3.0, true)
	draw_rect(body, colour)
	draw_circle(body.get_center(), 2.4, MenuLook.HOLE)


func _draw_stamp(at: Vector2) -> void:
	var font := MenuLook.wide_font()
	var text := "COMING SOON"
	var text_size := 17
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size).x
	draw_set_transform(at, STAMP_TILT, Vector2.ONE)
	var box := Rect2(Vector2(-width * 0.5 - 8.0, -15.0), Vector2(width + 16.0, 24.0))
	draw_rect(box, Color(MenuLook.RED, 0.9))
	draw_string(
		font,
		Vector2(-width * 0.5, 3.0),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		text_size,
		Color.WHITE
	)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The part of the line `from`..`to` inside `rect` (two points), or none.
static func _clip_to(rect: Rect2, from: Vector2, to: Vector2) -> PackedVector2Array:
	var direction := to - from
	var low := 0.0
	var high := 1.0
	for axis in 2:
		var start := from[axis]
		var delta := direction[axis]
		var box_low := rect.position[axis]
		var box_high := rect.end[axis]
		if is_zero_approx(delta):
			if start < box_low or start > box_high:
				return PackedVector2Array()
			continue
		var t0 := (box_low - start) / delta
		var t1 := (box_high - start) / delta
		low = maxf(low, minf(t0, t1))
		high = minf(high, maxf(t0, t1))
	if low >= high:
		return PackedVector2Array()
	return PackedVector2Array([from + direction * low, from + direction * high])


static func _wide_width(text: String, font_size: int) -> float:
	return MenuLook.wide_font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x


## The largest size from `start` down to `floor` at which `text` fits `room` (the floor when none).
static func _fit_size(font: Font, text: String, room: float, start: int, floor_size: int) -> int:
	var size_now := start
	while size_now > floor_size:
		if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_now).x <= room:
			return size_now
		size_now -= 1
	return floor_size
