class_name CodeKeypad
extends CanvasLayer
## An on-screen keypad for a room code (Deadnight #1183): letters and digits, delete and Join,
## docked to the bottom of the screen while a finger is on the code field. It needs nothing from the
## browser, so a player can enter a code where the system keyboard cannot be made to open (a Discord
## Activity's webview, iOS), and a field that sits under half a phone's screen is lifted above it
## (`KeyboardLift`).
##
## The keys never take the focus: the field keeps it, so a hardware keyboard and Ctrl+V still reach
## the field while the keypad is up. A key edits the field as a keystroke would (`text_changed`
## fires, so the field's own reaction to typing, the upper case, runs). It lives in a canvas layer
## of its own, above the router's: the router's layer is the one lifted.

## Keys per row. The rows are the digits, then the letters in order; the last row has delete and
## Join.
const COLUMNS := 10
const DIGITS := "1234567890"
const LETTERS := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
## The layer above the router's (`UIRouter.LAYER`) and under nothing the game puts over a screen.
const LAYER := 110
## How big the keys are, in the window's own pixels and not in design units: a screen's units are
## 0.36 px on a phone held sideways (the page's 844 x 390 are 1688 x 780 canvas pixels, which is not
## "a phone" to `MenuScale`), and a fixed number of units would give keys a finger cannot hit. A key
## is this share of the window's short side tall, within these bounds (a 780 px window: 78 px, which
## is 39 CSS pixels at the pixel ratio of 2 the page reports).
const KEY_SHARE := 0.1
const KEY_MIN_PX := 56.0
const KEY_MAX_PX := 120.0
const GAP_PX := 8.0
const MARGIN_PX := 14.0
## The keys of a row are at most this share of the window's height each (the four rows with their
## gaps stay under 60 % of it).
const KEY_MAX_SHARE := 0.13
## A key is at most this many times as wide as it is tall.
const KEY_ASPECT := 1.7
## A finger counts as the one that focused the field when it touched this recently (milliseconds).
const TOUCH_WINDOW_MSEC := 600
## The letter's size, as a share of the key's height.
const LABEL_SHARE := 0.5

## Units of the page's height the keypad covers now (0 when none is up): what `KeyboardLift` reads.
static var covering := 0.0

var field: LineEdit
var panel: PanelContainer
var delete_key: UIButton
var join_key: UIButton
## The key's height now, in design units (`layout`).
var key_height := 0.0
var _keys := {}
var _rows: VBoxContainer
var _margin: MarginContainer
var _row_boxes: Array[HBoxContainer] = []
var _tokens := UITokens.active()
var _touched_at := -1000000


## Builds the keypad for `target`: shown when the field takes the focus from a finger, hidden when
## it loses it. The field no longer asks the system keyboard to open: this is its keyboard.
static func attach(target: LineEdit, parent: Node) -> CodeKeypad:
	var keypad := CodeKeypad.new()
	keypad.field = target
	target.virtual_keyboard_enabled = false
	parent.add_child(keypad)
	return keypad


func _ready() -> void:
	layer = LAYER
	visible = false
	panel = PanelContainer.new()
	panel.name = "Keypad"
	# This layer is outside the router's stage, which is where the theme every control reads comes
	# from.
	panel.theme = UIThemeBuilder.build(_tokens)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(panel)
	_margin = MarginContainer.new()
	panel.add_child(_margin)
	var rows := VBoxContainer.new()
	_rows = rows
	rows.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_margin.add_child(rows)
	_add_row(rows, DIGITS)
	_add_row(rows, LETTERS.substr(0, COLUMNS))
	_add_row(rows, LETTERS.substr(COLUMNS, COLUMNS))
	var last := _add_row(rows, LETTERS.substr(2 * COLUMNS))
	delete_key = _key("Delete", 2)
	delete_key.name = "Delete"
	delete_key.pressed.connect(delete_before_caret)
	last.add_child(delete_key)
	join_key = _key("Join", 2)
	join_key.name = "Join"
	join_key.variant = UIButton.Variant.PRIMARY
	join_key.pressed.connect(submit)
	last.add_child(join_key)
	layout()
	get_viewport().size_changed.connect(layout)
	if field != null:
		field.focus_entered.connect(_on_field_focus)
		field.focus_exited.connect(close)
		field.gui_input.connect(_on_field_input)
		field.visibility_changed.connect(_on_field_visibility)
		if field.has_focus():
			_on_field_focus()


func _exit_tree() -> void:
	covering = 0.0


## True while the keypad is up.
func is_open() -> bool:
	return visible


## Opens the keypad when the focus came from a finger (a keyboard or a pad reaching the field types
## on its own). The input mode is not asked: on the web the mouse press a touch makes reaches the
## game before the touch does (`UIInputMode.touch` was false when the field took the focus), so the
## keypad watches for both.
func _on_field_focus() -> void:
	if field.editable and Time.get_ticks_msec() - _touched_at <= TOUCH_WINDOW_MSEC:
		open()


func _input(event: InputEvent) -> void:
	if not is_finger_press(event):
		return
	_touched_at = Time.get_ticks_msec()
	# A finger down anywhere but on the keypad or the field puts the keypad away (it has no Close key).
	if visible and not _on_keypad_or_field(_position_of(event)):
		field.release_focus()
		close()


## A finger that is already on the field (it kept the focus after Join or Close) brings the keypad
## back.
func _on_field_input(event: InputEvent) -> void:
	if is_finger_press(event) and field.editable:
		_touched_at = Time.get_ticks_msec()
		open()


func _on_keypad_or_field(at: Vector2) -> bool:
	if panel.get_global_rect().has_point(at):
		return true
	return Rect2(field.get_global_transform_with_canvas().origin, field.size).has_point(at)


static func _position_of(event: InputEvent) -> Vector2:
	if event is InputEventScreenTouch:
		return (event as InputEventScreenTouch).position
	return (event as InputEventMouseButton).position


## A finger going down: the touch itself, or the mouse press the engine makes of it (which comes
## first on the web).
static func is_finger_press(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		return (event as InputEventScreenTouch).pressed
	if event is InputEventMouseButton:
		var click := event as InputEventMouseButton
		return click.pressed and click.device == InputEvent.DEVICE_ID_EMULATION
	return false


func _on_field_visibility() -> void:
	if not field.is_visible_in_tree():
		close()


func open() -> void:
	visible = true
	# Docked to the bottom and growing upward, the panel is as tall as its keys need.
	covering = panel.get_combined_minimum_size().y


func close() -> void:
	visible = false
	covering = 0.0


## Types `letter` at the field's caret (over its selection), as a key would: a field that is full
## takes nothing, and `text_changed` is emitted so the field reacts as it does to typing.
func type_letter(letter: String) -> void:
	if field == null or not field.editable:
		return
	if field.has_selection():
		var from := field.get_selection_from_column()
		field.delete_text(from, field.get_selection_to_column())
		field.deselect()
		field.caret_column = from
	if field.max_length > 0 and field.text.length() >= field.max_length:
		return
	field.insert_text_at_caret(letter)
	field.text_changed.emit(field.text)


## Deletes the character before the caret, or the selection.
func delete_before_caret() -> void:
	if field == null or not field.editable:
		return
	if field.has_selection():
		var from := field.get_selection_from_column()
		field.delete_text(from, field.get_selection_to_column())
		field.deselect()
		field.caret_column = from
	elif field.caret_column > 0:
		var at := field.caret_column
		field.delete_text(at - 1, at)
		field.caret_column = at - 1
	else:
		return
	field.text_changed.emit(field.text)


## What Enter does in the field.
func submit() -> void:
	if field != null:
		close()
		field.text_submitted.emit(field.text)


## The key of a letter or digit (for a test and a capture).
func key_for(letter: String) -> UIButton:
	return _keys.get(letter)


func _add_row(rows: VBoxContainer, letters: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row_boxes.append(row)
	rows.add_child(row)
	for letter in letters:
		var key := _key(letter, 1)
		key.name = letter
		key.pressed.connect(type_letter.bind(letter))
		_keys[letter] = key
		row.add_child(key)
	return row


## A key: a button, never taking the focus from the field. `layout` gives it its size.
func _key(text: String, span: int) -> UIButton:
	var key := UIButton.new()
	key.text = text
	key.variant = UIButton.Variant.SECONDARY
	key.focus_mode = Control.FOCUS_NONE
	key.set_meta(&"span", span)
	return key


## Sizes the keys for the window as it is: tall enough for a finger whatever the units are worth.
func layout() -> void:
	layout_for(Vector2(get_window().size), get_viewport().get_visible_rect().size)


## `layout` for a window of `pixels` showing `units` of the design.
func layout_for(pixels: Vector2, units: Vector2) -> void:
	if units.x <= 0.0 or pixels.x <= 0.0:
		return
	var per_unit := pixels.x / units.x
	var key_px := clampf(minf(pixels.x, pixels.y) * KEY_SHARE, KEY_MIN_PX, KEY_MAX_PX)
	# Never so tall that four rows of them are more than the top share of the screen.
	key_height = minf(key_px / per_unit, units.y * KEY_MAX_SHARE)
	# Whole units: the theme's constants are integers, and a rounded-up gap nine times over would push
	# the last key off the screen.
	var gap := maxi(floori(minf(GAP_PX / per_unit, units.x * 0.01)), 1)
	var margin := maxi(floori(minf(MARGIN_PX / per_unit, units.x * 0.02)), 1)
	var width := floorf(
		maxf(
			0.0,
			minf((units.x - 2.0 * margin - gap * (COLUMNS - 1)) / COLUMNS, key_height * KEY_ASPECT)
		)
	)
	for side in ["left", "right", "top", "bottom"]:
		_margin.add_theme_constant_override("margin_" + side, margin)
	_rows.add_theme_constant_override(&"separation", gap)
	for row in _row_boxes:
		row.add_theme_constant_override(&"separation", gap)
	for key: UIButton in find_children("*", "UIButton", true, false):
		var span := int(key.get_meta(&"span", 1))
		key.custom_minimum_size = Vector2(width * span + gap * (span - 1), key_height)
		key.add_theme_font_size_override(&"font_size", roundi(key_height * LABEL_SHARE))
	if visible:
		covering = panel.get_combined_minimum_size().y
