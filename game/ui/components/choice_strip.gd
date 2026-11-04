class_name ChoiceStrip
extends Control
## A row of choices drawn side by side: colour swatches, or text chips when an entry has no colour.
## One control for the whole row: it takes focus once, left and right (the d-pad, the stick, the
## arrow keys) move along it, and a click picks a chip.
##
## A locked entry is drawn greyed with a padlock and can be looked at (the cursor goes to it, the
## screen shows how to get it) but not chosen: `blocked` fires instead of `chosen`.
##
## Entries are Dictionaries: `label`, `colour` (a Color; leave out for a text chip), `locked`
## (bool) and `hint` (text for the screen's caption).

## The cursor landed on an unlocked entry and it is now the chosen one.
signal chosen(index: int)
## The cursor landed on, or the player pressed accept or clicked on, a locked entry.
signal blocked(index: int)
## The cursor moved (whether or not the entry can be chosen).
signal cursor_moved(index: int)

## Size of a swatch and the gap between chips; a palette longer than `LONG` uses the compact pair.
const SWATCH := 44.0
const GAP := 8.0
const SWATCH_COMPACT := 28.0
const GAP_COMPACT := 4.0
const LONG := 8
const CHIP_PADDING := 20.0

var entries: Array[Dictionary] = []:
	set(value):
		entries = value
		_cursor = clampi(_cursor, 0, maxi(entries.size() - 1, 0))
		selected = clampi(selected, 0, maxi(entries.size() - 1, 0))
		update_minimum_size()
		queue_redraw()
## The chosen entry.
var selected := 0
## The entry the cursor is on: the chosen one, or a locked one being looked at.
var cursor := 0:
	get:
		return _cursor

var _tokens := UITokens.active()
var _cursor := 0
var _ring: UIFocusRing
var _fill := StyleBoxFlat.new()


func _init() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_ring = UIFocusRing.new(_tokens, _tokens.radius_md)
	_fill.anti_aliasing = true
	_fill.set_corner_radius_all(_tokens.radius_md)
	_fill.set_border_width_all(_tokens.border)


func ui_sound_role() -> StringName:
	return &"choice_strip"


func _ready() -> void:
	focus_entered.connect(UIAudio.play.bind(&"focus", self))
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)


## Chooses `index` without a signal (the screen putting the strip in step with its look).
func select(index: int) -> void:
	selected = clampi(index, 0, maxi(entries.size() - 1, 0))
	_cursor = selected
	queue_redraw()


## Moves the cursor by `delta` (no wrap) and chooses the entry it lands on if it is unlocked.
func step(delta: int) -> void:
	move_to(clampi(_cursor + delta, 0, maxi(entries.size() - 1, 0)))


## Puts the cursor on `index`: chooses it when it is unlocked, else announces it as blocked.
func move_to(index: int) -> void:
	if index < 0 or index >= entries.size():
		return
	var moved := index != _cursor
	_cursor = index
	if moved:
		UIAudio.play(&"select", self)
		cursor_moved.emit(index)
	if entries[index].get("locked", false):
		blocked.emit(index)
	elif index != selected or moved:
		selected = index
		chosen.emit(index)
	queue_redraw()


func _swatch() -> float:
	return SWATCH if entries.size() <= LONG else SWATCH_COMPACT


func _gap() -> float:
	return GAP if entries.size() <= LONG else GAP_COMPACT


func _get_minimum_size() -> Vector2:
	var width := 0.0
	for i in entries.size():
		width += _chip_width(i) + (_gap() if i > 0 else 0.0)
	return Vector2(width, _tokens.control_height)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var click := event as InputEventMouseButton
		if click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
			var hit := index_at(click.position)
			if hit >= 0:
				grab_focus()
				move_to(hit)
				if entries[hit].get("locked", false):
					UIMotion.shake(self)
			accept_event()
	elif event.is_action_pressed(&"ui_left"):
		step(-1)
		accept_event()
	elif event.is_action_pressed(&"ui_right"):
		step(1)
		accept_event()
	elif event.is_action_pressed(&"ui_accept"):
		if entries[_cursor].get("locked", false):
			blocked.emit(_cursor)
			UIMotion.shake(self)
		accept_event()


## The entry under `point` (in this control's space), or -1.
func index_at(point: Vector2) -> int:
	for i in entries.size():
		if chip_rect(i).has_point(point):
			return i
	return -1


## Where entry `index` is drawn, in this control's space.
func chip_rect(index: int) -> Rect2:
	var x := 0.0
	for i in index:
		x += _chip_width(i) + _gap()
	return Rect2(x, (size.y - _swatch()) * 0.5, _chip_width(index), _swatch())


func _chip_width(index: int) -> float:
	var entry := entries[index]
	if entry.has("colour"):
		return _swatch()
	var font := get_theme_font(&"font", &"UIOptionSelector")
	var font_size := get_theme_font_size(&"font_size", &"UIOptionSelector")
	return (
		font.get_string_size(entry["label"], HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
		+ 2.0 * CHIP_PADDING
	)


func _draw() -> void:
	var font := get_theme_font(&"font", &"UIOptionSelector")
	var font_size := get_theme_font_size(&"font_size", &"UIOptionSelector")
	var focused := has_focus() and not UIInputMode.pointer
	for i in entries.size():
		var rect := chip_rect(i)
		var entry := entries[i]
		var locked: bool = entry.get("locked", false)
		var chosen_now := i == selected
		if entry.has("colour"):
			var colour: Color = entry["colour"]
			_fill.bg_color = _greyed(colour) if locked else colour
		else:
			_fill.bg_color = _tokens.surface_raised
		_fill.border_color = _tokens.accent_bright if chosen_now else _tokens.outline
		_fill.set_border_width_all(_tokens.border + (2 if chosen_now else 0))
		draw_style_box(_fill, rect)
		if not entry.has("colour"):
			var ink := _tokens.ink_disabled if locked else _tokens.ink
			var baseline := (
				rect.position.y
				+ (rect.size.y + font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
			)
			draw_string(
				font,
				Vector2(rect.position.x + CHIP_PADDING, baseline),
				entry["label"],
				HORIZONTAL_ALIGNMENT_LEFT,
				-1.0,
				font_size,
				ink
			)
		if locked:
			_draw_padlock(rect)
		if focused and i == _cursor:
			_ring.draw(self, rect, 1.0)


func _greyed(colour: Color) -> Color:
	var grey := colour.get_luminance() * 0.6 + 0.1
	return Color(grey, grey, grey).lerp(_tokens.surface_raised, 0.35)


func _draw_padlock(rect: Rect2) -> void:
	var centre := rect.get_center()
	var colour := _tokens.ink
	var body := Rect2(centre + Vector2(-8.0, -1.0), Vector2(16.0, 12.0))
	draw_rect(body.grow(1.5), _tokens.bg)
	draw_rect(body, colour)
	draw_arc(centre + Vector2(0.0, -1.0), 5.5, PI, TAU, 12, colour, 2.5, true)
