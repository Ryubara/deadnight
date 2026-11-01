# Gamepad devices in the InputMap

Found while making repair hold-to-repeat (#297): the gamepad events saved in `project.godot` answered only the first
pad.

- An `InputEventJoypadButton` or `InputEventJoypadMotion` in the InputMap carries a `device`. Godot 4.7 matches it
  exactly: an event with `device` 0 answers pad 0 only, so pad 1 (a second pad, or the first one after it was unplugged
  and plugged back in, when Godot hands out a new id) presses nothing. `-1` answers every pad.
- The project stored `"device":0` on all 20 of its pad events (10 buttons, 10 axes). They are `-1` now; the keyboard and
  mouse events are untouched. Checked with `InputMap.event_is_action` for pads 0, 1 and 3
  (`game/tests/night/test_human_controller_use.gd`).
- When adding an action in the editor's Input Map, pick "All Devices" for the pad event, or the file gets a `0` again.
- The same goes for anything that fakes input: a test or the touch layer presses the action itself
  (`Input.action_press`), which has no device at all and works either way.
