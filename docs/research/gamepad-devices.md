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

## Start did nothing in a night (#494)

The maintainer pressed Start on a controller and the night did not pause. The `pause` action was bound right
(Esc, and button 6 on every device) and a test pressed it on pad 0 and on pad 3; both passed.

- **Cause:** `project.godot` also binds Start (button 6) to `ui_accept`. `UIRouter._input` spends the first focus key
  (an arrow, `ui_accept`) on giving the top screen its focus whenever nothing has focus, and marks it handled. A
  running night has no focused control, so every Start was spent there and never reached `_unhandled_input`, where the
  player and the night screen read `pause`. The A button is also `ui_accept` and was eaten the same way, which nobody
  saw: the jump is polled with `Input`, not read from an event.
- **Evidence:** in a headless run with a spy on `_unhandled_input`, Start reached it 0 times in two presses and the
  focus stayed null, while Esc reached it and paused. In the web build with a virtual pad
  (`tools/web_smoke/pad_pause.py`, a standard-mapping pad, Start is button 9) the engine listed the pad, saw Start go
  down and the `pause` action with it (`pad_start_presses` and `pause_presses`, 1 each), and the night went on. The
  earlier tests passed because Esc paused first: that put the Resume button in focus, and Start then pressed it.
- **Fix:** a screen says whether it wants the focus key (`UIScreen.wants_focus_key()`); `NightScreen` says no while
  its overlay is down, so a live night gets its keys.
- **A second hole behind it:** after Start paused and Start resumed, the player waited for a pointer lock, and a browser
  gives the lock to a click or a key, never to a gamepad button: a player on a pad had no controls at all. Only the
  mouse's look and click now wait for the lock (`Player.mouse_enabled()`, `trigger_held()`); a pad plays without it.
- **Rule:** an action that shares a button with a `ui_*` action (Start is `ui_accept`, B is `ui_cancel`, A is both
  `ui_accept` and jump) is tested as the first press on the live screen, not after another key put the screen in
  its menu state. `test_input_matrix.gd` presses every pause event first and again.
