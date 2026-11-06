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
| `BotWheelDriver` | `gameplay/night/bot_wheel_driver.gd` | reads the `bot_wheel` action (a key and a pad button press it), feeds the model from the mouse and the right stick, locks the view, calls the order; on a phone it also reads `bot_order_next` (a tap on the HUD's tag) and gives the order after the one that stands; says the bots' state on the HUD once the frame shows it changed |
| `HudBotWheel` | `ui/hud/hud_bot_wheel.gd` | the drawing, one of the HUD's full-screen overlays |
| `BotOrderLink` | `gameplay/night/bot_order_link.gd` | the one place the wheel meets `BotOrders` (below) |
| `Player.look_locked` | `gameplay/player/player.gd` | while true neither the mouse nor the right stick turns the view |
| `HudBotOrder` | `ui/hud/hud_bot_order.gd` | the phone's tag of the standing order (#1286): a word in the order's colour, at the inner end of the weapon strip (`HudSlots.bot_tag`), only while the room has a bot; its box is a zone the touch layer presses as `bot_order_next` |

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
  pause, a refused order); the same on a pad that is not device 0 with the right stick; the view held still; C swaps
  the shoulder and Q does not; the ping bindings (Z, middle mouse, the pad) and the touch PING button each mark a place
  in the night. A tap on the tag gives Hold, Follow, Roam in turn, the feed says the state once the order stands, a
  refused order changes nothing and says nothing, a tap while paused gives nothing then or later, and a finger on the tag
  never starts the stick or a look. `tests/ui/touch/test_touch_bot_tag.gd`: the tag on both phone pages, three interface
  sizes and both hands (a fingertip high and wide, on the screen, clear of the buttons, the stick's ring, the places and
  the cards), its word and colour, the first-run hint, and that it keeps its taps under another place.
- `tests/ui/test_hud_bot_wheel.gd`: shown only while open, the tickets and the dial fit every canvas down to 1168 by 540.
- `tests/night/test_input_matrix.gd`: rows for `bot_wheel` and `ping`, and for `bot_order_next` (touch only: the tag).
- Mutations checked: the tap opening the wheel (fails the tap test and the model's), the pause not cancelling (fails the
  pause test), the view lock off (fails the mouse and the stick tests).

## Proof in a browser and in a window

`tools/web_smoke/bot_wheel.py` exports the bench scene (`tests/captures/bot_wheel_bench.tscn`: the game's own night screen,
the orders going to a recorder) and drives it in headless Chrome: a held Q and the mouse, a virtual standard-mapping pad
(button 14, the right stick), and `Input.dispatchTouchEvent` with a second finger on the stick, right hand and left hand.
All three orders come out of each device, a tap gives none, the view turns 0.000 rad under the wheel and the PING button
marks a place; every button lies inside an 844 by 390 page. The phone's tag is proved on the real page by
`tools/web_smoke/touch_bot_tag.py` (below). Windowed captures of the same bench (`--mode=desktop|pad`) are on the pull
request.

- **A touch lift names the finger that lifted.** `Input.dispatchTouchEvent` with `touchEnd` takes the points that were
  *lifted*, not the ones still down: the probe's first version lifted the stick and left the wheel's finger down, and the
  order came out one drag late. The wheel itself was right.
- **A bench published nothing in a release export** because it asked a node it had not set yet (the touch layer) and a
  release template prints no script error. The bench guards it and prints its first publication.
- **Measure the view from the moment the wheel opens.** The probe moved the mouse to the middle before each hold, and
  that move turned the view as it always does: 2.1 rad "under the wheel".

## The phone's tag (#1286)

The wheel is a keyboard idea on glass (hold, drag, release; a button on the far right edge, always on). A phone has the
tag instead: the standing order in a word and a colour, a tap for the next of Follow, Roam, Hold. What was learned:

- **Why it stands beside the weapons and not in the column's cards.** The issue asked for a tag in the players'
  column. Two measures, in this order:
    1. On the stick's first ring (`STICK_REST`, 330 units in and 390 up, radius 105, which crossed the column's cards) a
       tag a fingertip high and 14 CSS px wide in words could not stand between the points and the health cards or above
       the points clear of the ring: 8 units into it at 1.0 and 54 at 0.8 (the word is 168 to 207 units wide, the ring
       started 225 units from the edge). #1294 then moved the ring beside the column, so a column tag no longer meets it.
    2. A tag in the column makes the column a fingertip taller (128 units at 1.0), and the challenge card, which stands
       at 0.36 of the screen's height, lands over it: measured on the HUD with the touch layout, the card is over the tag
       at 667 x 375 at 1.25 with 2 and 4 players, and at 1920 x 1080 and 2337 x 1080 with 4 and 8 players, where
       without the tag it is clear for up to 4 players there (it is over the points with 8 players, with or without
       the tag, a fault that was already there). The marker capacity does not move either way (below).
  The strip's row is under the ring and takes no column height, and it is where the left thumb already taps the weapons.
  `HudBotOrder` is its own part: moving it into the column later means making it in `Hud` instead of `HudSlots` and
  moving the challenge card's top.
- **The order's word has to read at a glance, in a corner the film darkens.** The first capture read dim, about
  like an empty weapon slot. The cause is the film's vignette (`film_grain.gdshader`, 0.62) over the whole screen,
  which takes the bottom-left corner, where the strip stands, to about 0.6 of its brightness (the ammo card's number
  in the other corner measures the same): cream `ink` (244, 234, 210) renders as (148, 142, 128). Measured on the
  844 x 390 captures (the brightest pixels of the word against the ticket, rendered): ROAM 6.0, FOLLOW 4.2, HOLD 3.3
  (the first HOLD, the token `hot` itself, was 5.3 against the ticket before the film and 3.6 while a finger lit it).
  Done: the word is 1.35 times the caption (`HudBotOrder.WORD_SCALE`, the ticket grows to hold two lines), HOLD is `hot`
  lightened by 0.35 so every order's colour keeps 7 : 1 against the ticket and 4.5 : 1 lit
  (`test_the_word_of_the_order_is_larger_than_its_caption_and_keeps_its_contrast`). Not done: under the vignette
  HOLD and FOLLOW stay under 4.5 in the corner, because no red-orange lighter than that stays red-orange; the word,
  its size and the stripe say the order too, and the film's strength is the whole game's, not this tag's.
- **A refused order is invisible to the client until the frame says so.** The client's own link refuses only what cannot
  be sent (an unknown order, a position that is not finite); the server also refuses a second order inside
  `BotOrders.GAP` (0.5 s), answering with `bot_order_refused`, which nothing on the client reads. The driver therefore
  says the bots' state when the frame's order *changes* (`BotWheel.NOTICES`), not when it sends: two quick taps used to
  be able to say two different things for one order. The tag shows the frame's order (`HudState.bot_order`), never a guess.
- **The notices say the state.** `BOTS: FOLLOWING YOU`, `ROAMING`, `HOLDING POSITION` (it was `BOTS: HOLD HERE`, which
  reads as an instruction to the bots to hold *this spot*, where the order is to stay where they stand when it is given).
- **A new input action needs a row in `test_input_matrix.gd`.** `bot_order_next` has no key and no pad button; the matrix
  has `TOUCH_ONLY` for it, exempt from the key, mouse and pad loops and proved through the real layer.
- **A hint stands where a prompt may stand.** The tag's label stands in the bottom row, where the prompt card is, so it
  waits while a prompt is up (`TouchHints`).

`tools/web_smoke/touch_bot_tag.py` proves it on the real page (844 x 390 and 667 x 375 CSS px, ratio 2, touch mode, both
hands, a room of three bots, then none): the size, the side, the hint, the three taps, two taps inside the half second,
a finger dragged off the tag.
