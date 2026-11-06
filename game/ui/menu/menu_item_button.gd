class_name MenuItemButton
extends Button
## A row of a menu list as a ticket: cream paper with a half-round notch in each side, the title in
## ink, a line under it, and an amber outline while it has the focus or the pointer. The primary
## ticket is red with white type. Drawn here, not themed: the plain button's own text is off, so
## the title is the only text. Used by the Play, Shop and More panels.

const PAD := 26.0
const NOTCH := 11.0
const PERF_FROM_RIGHT := 96.0
const OUTLINE := 3.0

var title := "":
	set(value):
		title = value
		accessibility_name = value
		queue_redraw()
var subtitle := "":
	set(value):
		subtitle = value
		queue_redraw()
## The first row of a list, drawn larger and in red.
var primary := false:
	set(value):
		primary = value
		_fit()
		queue_redraw()
## A row that cannot be used yet (a placeholder): drawn on shaded paper, still focusable so a
## keyboard can read it.
var placeholder := false:
	set(value):
		placeholder = value
		queue_redraw()
## The right-hand note (a count, "coming", a price).
var note := "":
	set(value):
		note = value
		queue_redraw()
## Whether the right end is an "admit one" stub behind a perforation (the three ways to start).
var admit := false:
	set(value):
		admit = value
		queue_redraw()

var _width := 560.0


func _init() -> void:
	UiSounds.wire(self)
	flat = true
	focus_mode = Control.FOCUS_ALL
	# Inside a scroll area a drag that starts here reaches it (`UIScroll`); anywhere else the button
	# stops the pointer, as a button does.
	UIScroll.pass_touch_in_scroll(self)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_fit()
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	mouse_entered.connect(_on_hover)
	mouse_exited.connect(queue_redraw)
	resized.connect(queue_redraw)


## What kind of ticket this is, for the menu's sounds: a way to start is torn and punched, a row
## that is not there yet is refused, any other is punched.
func ui_sound_role() -> StringName:
	if placeholder:
		return &"ticket_soon"
	return &"ticket_start" if admit else &"ticket"


## Sets the width the row asks for.
func set_width(width: float) -> void:
	_width = width
	_fit()


func _fit() -> void:
	custom_minimum_size = Vector2(_width, 96.0 if primary else 72.0)


func _on_hover() -> void:
	# Hovering moves the focus, so the pointer and the keyboard never disagree.
	if not disabled and focus_mode != Control.FOCUS_NONE:
		grab_focus()
	queue_redraw()


func _draw() -> void:
	var lit := has_focus() or is_hovered()
	var paper := MenuLook.RED if primary else MenuLook.PAPER
	var shade := MenuLook.RED.darkened(0.25) if primary else MenuLook.PAPER_SHADE
	if placeholder:
		paper = MenuLook.PAPER_SHADE
		shade = MenuLook.PAPER_RULE
	if lit:
		paper = paper.lightened(0.06)
	var perf := size.x - PERF_FROM_RIGHT if admit else -1.0
	MenuLook.draw_ticket(self, size, paper, shade, NOTCH, perf)
	if lit:
		draw_rect(Rect2(Vector2.ZERO, size), MenuLook.AMBER, false, OUTLINE)
	var ink := Color.WHITE if primary else MenuLook.PAPER_INK
	var muted := Color(1.0, 1.0, 1.0, 0.82) if primary else MenuLook.PAPER_MUTED
	if placeholder:
		ink = MenuLook.PAPER_MUTED
	var tokens := UITokens.active()
	var title_size := MenuLook.SIZE_ITEM if primary else MenuLook.SIZE_TITLE
	var has_sub := subtitle != "" and primary
	var top := size.y * 0.5 + title_size * 0.35
	if has_sub:
		top = 12.0 + title_size * 0.8
	var right_room := (PERF_FROM_RIGHT if admit else 0.0) + 40.0
	draw_string(
		tokens.font_display,
		Vector2(PAD, top),
		title.to_upper(),
		HORIZONTAL_ALIGNMENT_LEFT,
		size.x - PAD - right_room - _note_width(),
		title_size,
		ink
	)
	var small: Font = tokens.font_text
	if has_sub:
		draw_string(
			small,
			Vector2(PAD, size.y - 14.0),
			subtitle,
			HORIZONTAL_ALIGNMENT_LEFT,
			size.x - PAD - right_room,
			MenuLook.SIZE_CAPTION,
			muted
		)
	elif subtitle != "":
		var sub_width := (
			small.get_string_size(subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, MenuLook.SIZE_CAPTION).x
		)
		draw_string(
			small,
			Vector2(size.x - right_room - sub_width, size.y * 0.5 + MenuLook.SIZE_CAPTION * 0.35),
			subtitle,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			MenuLook.SIZE_CAPTION,
			muted
		)
	if note != "":
		draw_string(
			MenuLook.wide_font(),
			Vector2(
				size.x - PAD - _note_width() + 24.0, size.y * 0.5 + MenuLook.SIZE_CAPTION * 0.35
			),
			note.to_upper(),
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			MenuLook.SIZE_CAPTION,
			MenuLook.RED if not placeholder else muted
		)
	if admit:
		var stub := MenuLook.wide_font()
		var line_height := 22.0
		var middle := size.y * 0.5
		for index in 2:
			var word := "ADMIT" if index == 0 else "ONE"
			var word_width := stub.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
			draw_string(
				stub,
				Vector2(
					size.x - PERF_FROM_RIGHT * 0.5 - word_width * 0.5,
					middle - 2.0 + index * line_height
				),
				word,
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				16,
				muted
			)


func _note_width() -> float:
	if note == "":
		return 0.0
	return (
		(
			MenuLook
			. wide_font()
			. get_string_size(note.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, MenuLook.SIZE_CAPTION)
			. x
		)
		+ 24.0
	)
