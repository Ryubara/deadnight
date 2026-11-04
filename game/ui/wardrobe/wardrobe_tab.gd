class_name WardrobeTab
extends Button
## One tab of the wardrobe's strip (Body, Hair, Headwear...): the menu's own tab, smaller. The
## active one is a stub of paper with its name in ink, the others are cream on the dark; the focus
## and the pointer outline it in amber. A tab is a button, so the keyboard and the pad walk the
## strip as they walk the menu's.

const PADDING := 12.0
const PADDING_COMPACT := 10.0
const TYPE := 25
const TYPE_COMPACT := 24
const HEIGHT := 56.0

## The tab's id (`CustomizeScreen.TABS`).
var key: StringName = &""
var active := false:
	set(value):
		active = value
		queue_redraw()
var compact := false

var _type_size := TYPE
var _padding := PADDING


func _init(tab_key: StringName, label: String, small := false) -> void:
	UiSounds.wire(self)
	key = tab_key
	text = ""
	compact = small
	_type_size = TYPE_COMPACT if small else TYPE
	_padding = PADDING_COMPACT if small else PADDING
	flat = true
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	accessibility_name = label
	name = label
	set_meta(&"label", label)
	var width := MenuLook.wide_font().get_string_size(
		label.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, _type_size
	)
	custom_minimum_size = Vector2(
		width.x + _padding * 2.0, maxf(HEIGHT, MenuLook.TAP_TARGET if small else 0.0)
	)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)


func ui_sound_role() -> StringName:
	return &"tab"


func label() -> String:
	return get_meta(&"label")


func _draw() -> void:
	var lit := has_focus() or is_hovered()
	if active:
		MenuLook.draw_ticket(self, size, MenuLook.PAPER, MenuLook.PAPER_SHADE, 6.0)
	var colour := (
		MenuLook.PAPER_INK if active else (MenuLook.INK if lit else MenuLook.INK.darkened(0.12))
	)
	var font := MenuLook.wide_font()
	var baseline := (size.y + font.get_ascent(_type_size) - font.get_descent(_type_size)) * 0.5
	draw_string(
		font,
		Vector2(_padding, baseline),
		label().to_upper(),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		_type_size,
		colour
	)
	if (has_focus() and not UIInputMode.pointer) or (lit and not active):
		draw_rect(Rect2(Vector2.ZERO, size), Color(MenuLook.AMBER, 0.8), false, 3.0)
