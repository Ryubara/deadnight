class_name MenuNav
extends RefCounted
## How a key, a pad button or a touch moves between the menu's tabs, as one pure function, so a
## test can send every device's event and the menu reads them all the same way.

## Keys: Q and E step back and forward; Ctrl+Tab and Ctrl+Shift+Tab do the same.
const PREVIOUS_KEY := KEY_Q
const NEXT_KEY := KEY_E
## Pad: the bumpers.
const PREVIOUS_BUTTON := JOY_BUTTON_LEFT_SHOULDER
const NEXT_BUTTON := JOY_BUTTON_RIGHT_SHOULDER
## A sideways drag of the stage this far (in design units) with a finger turns the soldier; a drag
## on the tab bar this far changes tab.
const SWIPE_UNITS := 120.0


## -1 or +1 when `event` asks for the previous or next tab, 0 when it asks for neither. Releases,
## key repeats and keys with another modifier held are not asks.
static func tab_step(event: InputEvent) -> int:
	if event is InputEventKey:
		var key := event as InputEventKey
		if not key.pressed or key.echo:
			return 0
		var plain := not (key.ctrl_pressed or key.alt_pressed or key.meta_pressed)
		if plain and key.keycode == PREVIOUS_KEY and not key.shift_pressed:
			return -1
		if plain and key.keycode == NEXT_KEY and not key.shift_pressed:
			return 1
		if key.ctrl_pressed and key.keycode == KEY_TAB:
			return -1 if key.shift_pressed else 1
		return 0
	if event is InputEventJoypadButton:
		var pad := event as InputEventJoypadButton
		if not pad.pressed:
			return 0
		if pad.button_index == PREVIOUS_BUTTON:
			return -1
		if pad.button_index == NEXT_BUTTON:
			return 1
	return 0


## The place a number reads at: "1,850" for a thousand and over.
static func grouped(value: int) -> String:
	var text := str(absi(value))
	var out := ""
	while text.length() > 3:
		out = "," + text.substr(text.length() - 3) + out
		text = text.substr(0, text.length() - 3)
	return ("-" if value < 0 else "") + text + out


## "3/5", "1,850/3,000".
static func fraction_text(have: int, need: int) -> String:
	return "%s/%s" % [grouped(have), grouped(need)]
