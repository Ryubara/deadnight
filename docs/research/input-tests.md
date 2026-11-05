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
- **The weapon slot keys** (#682): rows `weapon_slot_1` to `_3` (keys 1, 2, 3), keyboard only (`KEYBOARD_ONLY` is exempt
  from the pad-binding rule and the pad loop; the phone taps the weapon's place on the HUD, #1280, so the touch loop
  presses the place's centre: the row's control is the place's action). A slot key shows nothing when its weapon
  is in hand, so `_prepare` puts the other weapon in hand first; the third slot has nobody to pick with two weapons
  carried, so its row proves only that the key reaches the command.
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
- **A held action outlives its suite (#1220).** A CI shard runs its suites one after another in one process, and
  `Input.action_press` stays down until something releases it. `test_level_tags_online` held the scoreboard key
  (`_hold_boards`) and never let it go; the next HUD suite to run in the shard saw a scoreboard (`Hud._process` reads
  the key every frame), and `test_hud_refresh` counted 43 nodes made by the board rebuilding on the break's tick
  (the heading row, four player rows of nine nodes and the cards). It passed alone and in pairs with the suite
  before it, and failed only when a shard split put the two in one process with nothing between that releases the key.
  Release in `after_test` (never only at the end of a test: a failed assert skips the end), and
  `tests/core/test_input_left_clean.gd` fails a suite that presses an action in a function that does not release and
  has no hook that does. To see which node a count is made of, print `node_added`'s path and class.
- **A server chosen and never taken hangs the next solo night (#1220).** `NightScreen.join_url` (with `join_ticket`,
  `join_map`, `join_as_bot`) is a static a lobby's Start fills and a night takes once when it opens. A suite that
  stubs `LobbyScreen.opener` and calls Start fills it and no night takes it, so the next suite's solo night (the
  first test of `test_night_menu`) joins a server that is not there: "Socket error: 111", no `ready_to_play`, and
  the test runs into GdUnit's five minute limit while the rest of its suite passes. A suite that fills it clears it in
  `after_test`; a suite that opens a solo night calls `RouterFixture.forget_join()` first. `forget_join` also drops
  `return_lobby` and `return_api`, which a night takes the same way.
- **What the orders that hung were (#1220, #1212, #1234).** #1212's `godot (6)` ran `test_lobby_private`,
  `test_map_picker`, `test_menu_grips`, `test_menu_news`, `test_night_menu`: the first test of `test_night_menu` timed
  out at 5 minutes after one line, "Socket error: 111", the leaked join above (`test_lobby_private` was the leaker; the
  same order with its cleanup removed and `test_night_menu`'s too hangs on the first test within 150 s, with the cleanup
  alone it passes in 1 s). The pair `test_menu_grips`, `test_night_menu` passes by itself (13 of 13 in every run,
  headless and in a window): `test_menu_grips` leaves nothing. A windowed session has one more cause of the same
  symptom, the minimized window (`WindowFixture`, #1211), which `test_night_menu` handles in `before()`.
- **Finding what a suite leaves for the next.** A throwaway probe suite (never committed) between each two suites of a
  real shard order (`tools/ci_test_shards.py --shard N`) prints what changed since the last probe: every public
  `static var` of the game's classes (`Script.get` reads a static; `get_script_property_list` does not list them), the engine's
  globals, the root's children and the held actions. All nine shards of the tree of #1212 (75 suites each, 116 in the
  last) ran green in their order with a probe after each suite (headless, 6 600 cases in all, only the renderer-reading
  cases skipped). What it found, besides `join_url` (never left set at any suite boundary once `test_lobby_private`
  cleans up): `join_map` and `return_lobby`/`return_api` left by `test_server_browser_screen_online`,
  `test_lobby_preview`, `test_lobby_screen`, `test_lobby_settings_reach_the_night` and `test_lobby_private` (all call
  `RouterFixture.forget_join()` in `after_test` now; a solo night takes them at its start in any case, so they did not
  hang one); `ui_tab_prev`, `ui_tab_next` (`test_settings_layout`), `ui_accept` (`test_stagger_in`) and `ui_cancel`
  (`test_menu_shell`) left held, `NightArrival.shown` set by `test_arrival_night` and `test_night_screen_end`, and
  `TouchMode.device_is_touch` by `test_lobby_framed_fit`. The held actions and `NightArrival.shown` are fixed in #1254
  (below), the touch flag in #1253, the join statics in #1212.

## Finding what a suite leaves for the next

A CI shard runs its suites in one process, in the order GdUnit lists them, so anything a suite sets and does not undo
is read by the suite after it. Nothing fails until an order puts a reader there (#1220), so look for the leftovers
before they fail (#1254).

- **The probe.** A throwaway suite (never committed) with one test that waits a frame and prints what is left:
  `InputFixture.held()` (every action that is down, however it was pressed), `Input.is_mouse_button_pressed` for the
  three buttons, and the public statics a suite is known to set (`NightArrival.shown`, `TouchMode.device_is_touch`,
  `NightScreen.join_url`). Run it between the suites in one process: GdUnit takes several `-a` arguments and runs
  them in the order given, so `-a res://tests/ui/test_x.gd -a res://tests/core/test_probe.gd -a ...` puts the probe
  after every suite. The line it prints after a suite is what that suite left. GdUnit drops a suite named twice, so
  give each probe its own copy (`test_zz_probe1.gd`, `test_zz_probe2.gd`, ...) and have it print the suite before it.
  For a whole shard, take the order from `python3 tools/ci_test_shards.py --root game --shard N`, the one CI uses.
- **Read frames, not the call.** `Input.parse_input_event` only buffers: `Input.is_action_pressed` is still `false`
  in the same frame and turns `true` at the next frame's flush (or at `Input.flush_buffered_events()`). The probe
  waits one frame, and a release made in the same frame as the press comes first and the press lands after it.
  `InputFixture.release_all()` flushes first and then releases every action that is down; call it first in
  `after_test`. It works for `Input.action_press`, an `InputEventAction` and a key event alike (probed on Godot 4.7).
- **The check in the repository.** `tests/core/test_input_left_clean.gd` reads the suites' text and fails a function
  that presses (`Input.action_press`, or `parse_input_event` with `pressed = true`) with no release in it and no
  `after_test`/`after` that releases (`Input.action_release` or `InputFixture.release_all`; a node's
  `pressed = false` in a hook does not count). It was red on `test_settings_layout` (`ui_tab_next`/`ui_tab_prev`),
  `test_stagger_in` (`ui_accept`) and `test_menu_shell` (`ui_cancel`) before their hooks, which the older
  `Input.action_press`-only scan never saw. `test_no_action_is_held_when_this_suite_runs` only reads: it fails when
  the suite before it in the process left an action down, and it never releases (a check that releases would hide the
  leak it exists to find).
- **Statics have no scan yet.** A static a suite sets (`NightArrival.shown` after a night with the drop) is undone by
  the suite's own `after_test` (`NightArrival.reset()`); find the others with the probe. The probe over all nine
  shards (#1254) found `NightArrival.shown` left by `test_arrival_night`, `test_night_screen_end` and
  `test_night_crosshair` (all reset now), no action held after any suite once the three UI suites above release, and
  `TouchMode.device_is_touch` left by `test_lobby_framed_fit` (fixed in #1253, #1251).
