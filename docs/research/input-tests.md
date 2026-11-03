# Input tests

How we prove a control does something in the night, on every device, so an input change cannot silently drop an
action. The matrix is `game/tests/night/test_input_matrix.gd`; the grenade's own path is
`game/tests/night/test_night_grenades.gd`.

## Why it exists

The grenade key did nothing in the night for a month (#351). Every link had its own test: the action existed, the
player sampled it into `PlayerCommand.throw_over`, the grenade server took actions in the range. Nothing pressed the
key in a night and looked at the night, and the one missing link (the night never made the actions) sat between
tests. The same hole is open for any action.

## What the matrix does

- One row per gameplay action in the input map, with the touch control that presses it. A new action in the map fails
  `test_every_action_has_a_row` until it has a row, so a control cannot be added unproven.
- For each device (keyboard and mouse, a gamepad that is not device 0, the touch layer) every bound event is sent the
  way hardware sends it (`Input.parse_input_event` of a copy of the map's own event, so a changed binding is the one
  tested), held for 24 ticks of a real night through `HumanController`, and two things are asserted: the right field of
  the night's `NightCommand` was set, and the night shows the effect (a shot, a reload, a weapon swap, a pin, the
  shoulder flipped, the view turned, the body running the move).
- **An action with a cooldown needs ticks between its bindings.** The quick melee (`V`, the mouse's back button,
  the d-pad's down; #411) refuses a press made inside its 0.6 s, so the matrix lets 40 ticks pass after each binding
  of it (`_after`), and the row sits before the grenades: an arm that is still throwing one refuses the blow.
- **The bot wheel and the ping** have rows too (#642): `bot_wheel` (Q, the d-pad left, the BOTS touch button) and `ping`
  (Z, the middle mouse button, the d-pad right, the PING touch button). The night reads the ping key as its own edge
  (`HumanController.ping_pressed`, once a tick beside `command`), so the matrix reads both each tick the way
  `Night._human_command` does (`_tick_command`); a second binding of a ping would otherwise find the first one's edge
  still held. What the wheel does with a hold is `tests/ui/test_bot_wheel_input.gd` ([bot wheel](bot-wheel.md)).
- Pause belongs to the screen: the real night screen is entered and each device's pause event must toggle it.
- Touch is real touches on the real layer (`TouchFixture`); the interact button is only there with a prompt, so the
  test sets one.
- Mutation check: with `_throw_grenades` removed from `NightServer.step`, the matrix fails on all three devices for
  `throw_grenade`, and on the keyboard and the pad for `toss_grenade`.

## Facts that cost time

- **Device ids are not what they were.** Godot 4.7 gives a new `InputEventKey` device 16 and a mouse button 32 (a
  pad is 0, and `-1` in the map means every pad). An event with device 0 and a key code matches nothing, so a test that
  sets `device = 0` for a keyboard silently presses nothing. Copy the map's event and change only what you mean to.
- **Events fed outside `step` are lost.** `NightServer` collects the rules' events into an outbox that each `apply`
  and `step` empties; a test that calls `rules.apply(...)` itself (`skip_break`) changes the rules without the client
  hearing, and a HUD under it shows the old number. Let the night run its own intro (`rounds.intro_seconds`) instead.
- **A movement row cannot ask for distance.** The player spawns by a fence and cars; moving back can be a wall.
  The row asks that the body ran the command (`last_command.move`).
- **The look stick moves the rig on frames, not ticks**; the matrix awaits a few `process_frame`s before reading yaw.
- **Two touch layers answer one touch.** The night screen has its own; a second one in the tree would toggle pause
  twice. `TouchFixture.attach` drives the screen's own.
