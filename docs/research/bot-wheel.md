# Bot command wheel

What building the wheel that gives the team's bots an order (#642) taught. The orders and what the bots do with them are
[#641](bots.md); the HUD look is [HUD](../design/hud.md#the-bot-command-wheel); the touch buttons are
[touch controls](../design/touch-controls.md).

## The controls

| Device | Opens | Picks | Gives |
| --- | --- | --- | --- |
| Keyboard and mouse | hold **Q** | move the mouse | let go over an entry |
| Gamepad | hold the **d-pad left** | the **right stick** | let go of the button over an entry |
| Touch | hold the **BOTS** button (right edge, above Melee) | drag from where the thumb landed | lift over an entry |

Follow is up, Roam lower right, Hold lower left. Letting go in the middle (under 0.3 of the reach) or before the wheel
opened (a hold shorter than 0.18 s: a tap) gives nothing. Pausing, or the controls going off under the hold, cancels it.
The view does not turn while the key or button is held: the mouse and the right stick belong to the wheel, a drag from
the BOTS button is not a look.

Moved with it (#642): **shoulder swap is on C** (it was Q), and **crouch is on Ctrl and the pad's B only** (C was a second
crouch key). **Ping** is on Z, the middle mouse button and the pad's d-pad right: the middle button and the pad button
were already in the map from #511; what was missing was the touch control, a PING button on the top edge beside Pause.
`test_input_actions.gd` pins every one of these keys and checks that no two gameplay actions share a pad button.

## The parts

| Part | File | Does |
| --- | --- | --- |
| `BotWheel` | `gameplay/night/bot_wheel.gd` | the model: press, `advance(delta)`, the pointer, `hovered()`, `release()` gives the order or `""`; plain data, no clock, so a test steps it by hand |
| `BotWheelDriver` | `gameplay/night/bot_wheel_driver.gd` | reads the `bot_wheel` action (a key, a pad button and a touch button all press it), feeds the model from the mouse, the right stick and the finger on the BOTS button, locks the view, calls the order, says it on the HUD |
| `HudBotWheel` | `ui/hud/hud_bot_wheel.gd` | the drawing, one of the HUD's full-screen overlays |
| `BotOrderLink` | `gameplay/night/bot_order_link.gd` | the one place the wheel meets `BotOrders` (below) |
| `Player.look_locked` | `gameplay/player/player.gd` | while true neither the mouse nor the right stick turns the view |
| `TouchControls.wheel_offset()` | `ui/touch/touch_controls.gd` | where the finger on the BOTS button is from where it landed |

The driver is a child of the night screen, not of the night: the screen owns the HUD and the touch layer, the night stays
as it was. Its `step(delta)` is the whole frame, so the tests drive it by hand and send the input as events.

## BotOrders

The wheel calls `night.bot_orders.issue(order, issuer_id, at)` (`BotOrders`, #641, `bot_id` left 0: the whole team)
through `BotOrderLink`, with `at` the person's position (Hold holds that spot). It reads the standing order from the
frame with `BotOrders.current(frame)`, and keeps its own last choice until the frame says. The link is a seam on
purpose: `issuer` and `reader` are callables, the tests set a recorder, and a build without `bot_orders` answers `{}`
(nothing sent, nothing shown). An order the link refused (`{}`) leaves the wheel on the order that stood.

## Saved key bindings

There is no key rebinding screen and no saved binding to move over: the `InputMap` is read from `project.godot` alone,
and the settings file holds no keys (`docs/research/settings.md` lists every key it keeps). Someone who played with Q for
the shoulder gets C, and Q for the wheel, from the next start; there is nothing to migrate and nothing to flag. If a
rebind screen is built, the wheel's key and the shoulder's key are what it must clash-check.

## The touch layout is full

The right thumb's corner has no room left on a phone's 540 unit canvas: Fire, Aim, Jump, Reload, Swap, Grenade, Interact
and Melee take it, and Reload's bottom edge is already clipped there (#606). The BOTS button sits in Melee's column on the
far right edge, in the one slot that is on screen and clear of Reload (60 from the edge, 405 up, radius 40).
**Ping sits on the top edge beside Pause** (538 from the safe edge), where the left thumb reaches it between fights,
not in the right thumb's corner. That puts it under the banner and near the middle of a 1168 wide canvas (the HUD
banner shows there for seconds), a compromise a layout editor would remove. `test_touch_layout.gd` tests both
circles against the 1168 by 540 canvas, both hands, clear of every other button.

## Tests

- `tests/night/test_bot_wheel.gd`: the model (sectors, centre, hold time, release, cancel) and the link.
- `tests/ui/test_bot_wheel_input.gd`: the real input, in the real night screen with the driver stepped by hand and the
  orders going to a recorder: Q held, the mouse moved to each entry, Q let go (each order, and the tap, the middle, the
  pause, a refused order); the same on a pad that is not device 0 with the right stick; the same with a finger on the
  BOTS button, a second finger on the stick; the view held still; C swaps the shoulder and Q does not; the ping bindings
  (Z, middle mouse, the pad) and the touch PING button each mark a place in the night.
- `tests/ui/test_hud_bot_wheel.gd`: shown only while open, the tickets and the dial fit every canvas down to 1168 by 540.
- `tests/night/test_input_matrix.gd`: rows for `bot_wheel` and `ping` (their touch controls too).
- Mutations checked: the tap opening the wheel (fails the tap test and the model's), the pause not cancelling (fails the
  pause test), the view lock off (fails the mouse and the stick tests).
