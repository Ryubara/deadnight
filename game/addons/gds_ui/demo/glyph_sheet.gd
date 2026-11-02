class_name GlyphSheet
extends UIScreen
## Every button glyph the addon draws, side by side: the keyboard and mouse, then a pad of each
## family (a lettered one, a PlayStation one, a Nintendo one). The last row is live: a key-hint
## line whose glyphs follow the device the player used last.

const KEYS := [KEY_E, KEY_SPACE, KEY_SHIFT, KEY_ESCAPE, KEY_ENTER, KEY_TAB, KEY_F1, KEY_UP]
const MOUSE := [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_WHEEL_UP]
const BUTTONS := [
	JOY_BUTTON_A,
	JOY_BUTTON_B,
	JOY_BUTTON_X,
	JOY_BUTTON_Y,
	JOY_BUTTON_LEFT_SHOULDER,
	JOY_BUTTON_RIGHT_SHOULDER,
	JOY_BUTTON_DPAD_UP,
	JOY_BUTTON_DPAD_DOWN,
	JOY_BUTTON_DPAD_LEFT,
	JOY_BUTTON_DPAD_RIGHT,
	JOY_BUTTON_LEFT_STICK,
	JOY_BUTTON_RIGHT_STICK,
	JOY_BUTTON_START,
	JOY_BUTTON_BACK,
]
const AXES := [
	JOY_AXIS_TRIGGER_LEFT,
	JOY_AXIS_TRIGGER_RIGHT,
	JOY_AXIS_LEFT_X,
	JOY_AXIS_RIGHT_X,
]
const FAMILY_NAMES := ["Generic pad", "PlayStation pad", "Nintendo pad"]

var glyphs: Array[UIGlyph] = []
var hints: Array[UIHint] = []


func _ready() -> void:
	super._ready()
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in [&"margin_left", &"margin_right", &"margin_top", &"margin_bottom"]:
		margin.add_theme_constant_override(side, _tokens.space_xl)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override(&"separation", _tokens.space_md)
	margin.add_child(root)
	root.add_child(_label("Button prompts", UILabel.Style.TITLE))
	root.add_child(_label("KEYBOARD AND MOUSE", UILabel.Style.OVERLINE))
	root.add_child(_keyboard_row())
	for family in UIInputMode.Family.size():
		root.add_child(_label(FAMILY_NAMES[family].to_upper(), UILabel.Style.OVERLINE))
		root.add_child(_pad_row(family))
	root.add_child(_label("LIVE: FOLLOWS THE DEVICE YOU USE", UILabel.Style.OVERLINE))
	root.add_child(_hint_row())


func _keyboard_row() -> Control:
	var row := _row()
	for code: Key in KEYS:
		var key := InputEventKey.new()
		key.physical_keycode = code
		row.add_child(_glyph(key, UIGlyph.Device.KEYBOARD, UIInputMode.Family.GENERIC))
	for button: MouseButton in MOUSE:
		var click := InputEventMouseButton.new()
		click.button_index = button
		row.add_child(_glyph(click, UIGlyph.Device.KEYBOARD, UIInputMode.Family.GENERIC))
	# One held down, to show the sink.
	var held := InputEventKey.new()
	held.physical_keycode = KEY_E
	var pressed := _glyph(held, UIGlyph.Device.KEYBOARD, UIInputMode.Family.GENERIC)
	pressed.preview_pressed = true
	row.add_child(pressed)
	return row


func _pad_row(family: int) -> Control:
	var row := _row()
	for index: JoyButton in BUTTONS:
		if family == UIInputMode.Family.NINTENDO and index > JOY_BUTTON_RIGHT_SHOULDER:
			break
		var press := InputEventJoypadButton.new()
		press.button_index = index
		row.add_child(_glyph(press, UIGlyph.Device.GAMEPAD, family))
	if family != UIInputMode.Family.NINTENDO:
		for axis: JoyAxis in AXES:
			var motion := InputEventJoypadMotion.new()
			motion.axis = axis
			motion.axis_value = 1.0
			row.add_child(_glyph(motion, UIGlyph.Device.GAMEPAD, family))
	return row


func _hint_row() -> Control:
	var row := _row()
	for entry in [[&"ui_accept", "Select"], [&"ui_cancel", "Back"], [&"ui_down", "Move"]]:
		var hint := UIHint.new()
		hint.action = entry[0]
		hint.text = entry[1]
		hints.append(hint)
		row.add_child(hint)
	return row


func _row() -> HFlowContainer:
	var row := HFlowContainer.new()
	row.add_theme_constant_override(&"h_separation", _tokens.space_md)
	row.add_theme_constant_override(&"v_separation", _tokens.space_sm)
	return row


func _glyph(binding: InputEvent, device: UIGlyph.Device, family: int) -> UIGlyph:
	var glyph := UIGlyph.new()
	glyph.event = binding
	glyph.device = device
	glyph.family = family
	glyphs.append(glyph)
	return glyph


func _label(text: String, style: UILabel.Style) -> UILabel:
	var label := UILabel.new()
	label.text = text
	label.style = style
	return label
