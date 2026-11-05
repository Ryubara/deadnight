# Phone audit: every action, every element, a verdict

The audit behind the phone's controls (#1275). The maintainer, 2026-11-05: "we're still treating the users as if
they're playing the desktop version but just with touch controls", and "I don't like that every button acts like an
individual keybind that has its own button, it bloats the screen and it's super confusing." The reasons and the sources
are in [mobile controls](../research/mobile-controls.md#the-audit-1275); what the layer does today is
[touch controls](touch-controls.md). Read on the real page (844 x 390 and 667 x 375 CSS px, ratio 2, touch mode)
after the pull requests #1281, #1283 and #1284 had landed.

**The rule behind every verdict.** The right thumb holds Fire and looks, so it gets what a fight needs and nothing
else: Fire, Aim, Jump, Crouch, Reload (the maintainer's list), and one contextual button at a time. The left thumb
walks and has the stick. What the screen already shows is made tappable before a control is added: the HUD's own
places press the game's actions (`HudSlots.touch_zones`, `TouchControls.zones`). A control that is only there because a
desktop key is, is dropped or folded into something already on screen. A verdict is **KEEP**, **TAP** (the element that
already shows it takes the touch), **CONTEXT** (a button that shows only when it applies, as Interact does),
**CONVERT** (a gesture or a state in place of the key) or **DROP** (a duplicate).

## Every action of the input map

| Action (desktop key) | Home on a phone | Verdict | Built by |
| --- | --- | --- | --- |
| `move_*` (WASD), `sprint` (Shift) | the floating stick, sprint past its rim | KEEP | #1276 |
| `look_*`, the mouse | a drag on free ground, or from any right button | KEEP | #1283 |
| `fire` (left button) | Fire, the ring's centre | KEEP | #1283 |
| `aim` (right button) | Aim, held with auto-fire on, a toggle off | KEEP | #1283, #1281 |
| `jump` (Space) | Jump | KEEP | #1283 |
| `crouch` (Ctrl) | Crouch, a toggle | KEEP | #1283 |
| `reload` (R) | Reload, next to Fire; auto reload at 0 makes it rare | KEEP | #1283, #1278 |
| `interact` (E) | the Interact button, only at something to use | KEEP, CONTEXT | #1283 |
| `swap_weapon` (F), `weapon_slot_1..3` | a tap on a weapon of the HUD's strip | TAP | #1284 |
| `throw_grenade` (G), `toss_grenade` (H) | press and hold the strip's grenade place | TAP | #1284 |
| `quick_melee` (V) | **Strike**: a button that shows only while a dead is within reach | CONTEXT | #1285 |
| `bot_wheel` (Q, hold and drag) | a tag at the inner end of the weapon strip showing the order; a tap gives the next | TAP | #1286 (done) |
| `scoreboard` (Tab, held) | a finger held on the players' column | TAP | #1287 |
| `swap_shoulder` (C) | a double tap on free ground | CONVERT | #1288 |
| `ping` (Z, middle button) | one small button under Pause, clear of it | KEEP | #1289 (spacing) |
| `pause` (Esc) | the one control on the top edge, beside the round card | KEEP | here (nothing near it) |
| `ui_accept`, `ui_cancel`, `ui_tab_*` | taps on buttons and tabs, which already work | KEEP | - |

After this the phone has Fire, Aim, Jump, Crouch, Reload, Strike and Interact (the last two only when they apply),
Pause and Ping, and the stick. Gone from the glass: Swap, Grenade (#1284), Side, Melee, Bots, Scoreboard. Nothing needs
a keyboard.

### Why each home

- **Melee.** Quick melee is a real verb here (a blow with whatever is in hand, no weapon needed in a slot; bots use it
  at arm's length). It cannot stay a permanent circle: the maintainer's list leaves it out and the ring round Fire is
  full. Call of Duty: Mobile shows its knife only when an enemy is within striking distance
  ([Activision](https://blog.activision.com/call-of-duty/2019-10/Getting-a-Grip-on-the-Call-of-Duty-Mobile-Controls)),
  which costs no screen the rest of the time. Home: the place Swap left (575 left and 340 up of the corner, 21 mm from
  Fire), beside Reload, clear of Interact's. Shown while a dead is within `quick_melee`'s reach on the client's view.
  Not tested for comfort: a thumb has to leave Fire for it, as it does for Reload.
- **Bot orders.** The standing order showed for two seconds in the feed after a change and nowhere else, so a player
  could not read it. A tag (shown only when the room has bots) says it and takes the touch: a tap gives the next of
  Follow, Roam, Hold. Three orders are a cycle, not a wheel; the wheel (hold and drag) stays for the keyboard and the
  pad, and the touch layer's wheel finger goes. Built in #1286, at the inner end of the weapon strip and not in the
  column's cards: the stick's resting ring crosses the cards, and a tag a fingertip high and 14 CSS px wide in words
  reaches 8 units into the ring between the points and the health at 1.0 (54 at 0.8) and is still in its rows above
  the points, where the strip's row is under it and costs the column no height.
- **Scoreboard.** The players' column is the scoreboard's short form (points, names). A finger held on it shows the
  ticket, as Tab does, and lifting hides it: the same `scoreboard` action, so nothing else forks.
- **Shoulder.** A fight verb that is rare (a corner, a wall): a double tap on free ground. Two taps in a row are never a
  look, so the first adds no delay to anything.
- **Ping.** The one verb with no element that already shows it. A tap on the reticle would be one gesture fewer, but a
  look surface fires it by accident (a player review of Apex Legends Mobile reports pings made by mistake on touch,
  from a search summary, not read on the page), so it stays a button: one small circle, under Pause with the room two
  fingers need between them (the two are 27 CSS px apart today).
- **Pause** stays: the one control every player looks for in the same place.

## Every element of a night, on a phone

| Element | Verdict | Note |
| --- | --- | --- |
| Round card, objective, banner, marquee, boss bar, popup lane | KEEP | read-outs |
| Generator card, feed, notices | KEEP | the bot order notice says the bots' state (`BOTS: HOLDING POSITION`) |
| Players' column | TAP | holds the scoreboard |
| Bot chips, perk badges, challenge ticket, gains, markers | KEEP | read-outs |
| Standing order of the bots | new read-out, TAP | the tag (#1286, done: `HudBotOrder` in the strip's row) |
| Health card | KEEP, grenade count dropped | done here: the strip shows `x3` beside the weapons; the card said it too |
| Weapon strip | TAP | #1284 |
| Ammo card | KEEP, read-out | not a Reload target: one job, one control |
| Prompt card | KEEP, **no key** | done here: the keycap or tap mark held 64 units and pointed at nothing |
| Bot wheel overlay | KEEP for keyboard and pad | |
| Scoreboard ticket | KEEP | opened by the column |
| First-run hints | KEEP, extend | add Strike, the tag (done, #1286: "TAP TO ORDER BOTS"), the double tap when each exists |
| Rotate prompt, pause card, end board | KEEP | already tap targets |

## Key hints a phone shows

- The prompt card's key: gone on a phone (done here, `HudPrompt.touch_layout`). The card used to follow "a finger was
  the last input", which a capture from a script never sets; it follows the touch layer now.
- The menu hint bar (`MenuHints`): none on touch (`UIInputMode.touch`), already.
- The settings' Controls tab names the mouse ("Mouse sensitivity", "Push the mouse forward to look down") and is the
  only place the phone's look sensitivity and invert-Y live: a phone shows mouse words for its own look. Convert
  (#1290): the Touch tab holds "Look sensitivity" and "Invert vertical look" on a phone, with no mouse words.

## What the review found

| Finding | Where it stands |
| --- | --- |
| Key hints reserve 64 units on a phone | Fixed here: 48 for the mark and 16 for the gap go to the prompt's words |
| "BOTS: HOLD HERE" at the top right | Fixed here: the notices say the state (`BOTS: FOLLOWING YOU`, `ROAMING`, `HOLDING POSITION`). A ping's own `HOLD HERE` stays: it is what a ping says |
| Touch tab: descriptions cut with "...", `1.00x` against the scrollbar | #1290 (copy that fits, a gap for the bar, a test that no hint is cut, the look settings on the Touch tab) |
| Six markers before two meet at 667 x 375, 1.0 | Clearing the right side wins it all back: see below |
| Pause and Ping 27 CSS px apart | Moves with the Ping verdict (#1289) |

### Markers if the right side is cleared

The 667 x 375 page (1334 x 750 window, ratio 2), the busiest HUD, a banner, a prompt and a level card up: the most
markers (one on each card, three of them diamonds, or one) that none meet another or a card or a button, measured with
`test_hud_marker_cards.gd`'s helpers (10 is the most tried). "Today" is main after #1283, every circle; "cleared" keeps
Fire, Reload, Aim, Jump, Crouch and Pause only.

| Interface size | Diamonds | Today | Today with Interact up | Cleared | Cleared with Interact up |
| --- | --- | --- | --- | --- | --- |
| 0.8 | 3 | 10+ | 10+ | 10+ | 10+ |
| 1.0 | 3 | 8 | **6** | 10+ | 10+ |
| 1.0 | 1 | 10+ | 10+ | 10+ | 10+ |
| 1.25 | 3 | 3 | 3 | 5 | 5 |
| 1.25 | 1 | 4 | 4 | 8 | 7 |

The six is the Interact button being up (without it the page holds eight). The right side cleared gives all of it back
at 1.0 and more than doubles the page at 1.25, whose limit then is the cards. One Strike circle is added back only
while a dead is in reach; the issue that builds it repeats this table with it up.

### Markers with the bots' tag (#1286)

The same page and the same measure, on the branch of #1286: main after #1284's strip (a place a fingertip high and the
right thumb's ring) and #1291, with one body of the eight a bot, so the tag stands at the strip's end. "No bot" is the
same HUD with no tag. The tag is in the strip's row, under the stick's ring, so it takes nothing from the cards: the
numbers do not move, and `CROWDED_HOLDS` (6) and `SMALLEST_HOLDS` (4) stand. With the Interact button up the numbers
are the same ones in this measure. The 8 of the table above is 6 here: `CROWDED_HOLDS` names the cause, the strip a
fingertip high (#1280) with the right thumb's ring (#1277).

| Interface size | Diamonds | No bot | With the tag |
| --- | --- | --- | --- |
| 0.8 | 3 | 10+ | 10+ |
| 1.0 | 3 | 6 | **6** |
| 1.0 | 1 | 10+ | 10+ |
| 1.25 | 3 | 3 | 3 |
| 1.25 | 1 | 5 | 5 |

The 844 x 390 page holds 10+ at every size and with or without the tag. A tag in the column's cards would have taken a
fingertip's height from the column, which is why it is in the strip's row.
