# Web smoke probes find a control by name

The browser probes in `tools/web_smoke/` drive the game with the same keys and taps a player uses and read what the
game publishes as `window.deadnight` (`game/core/web_probe.gd`). A probe that counts key presses breaks silently when
a screen gains a control (#715 put the bot skill in the Bots row; #741 and #743 followed).

## How a probe walks

- The game publishes `focus`: the name of the control that has the keyboard (the nearest named node, so a button's
  inner control reads as the button). The Play screen and the room lobby share `MatchSettingsPanel`, whose controls
  are named by their setting key: `count_multiplier`, `perk_limit`, `max_alive`, `break_seconds`, `bots`,
  `bot_skill`; a map card is named by its map id (`drive_in`); the Play screen's buttons are `Start`, `Reset` and
  `Back`.
- `smoke.focus_control(page, wanted, key)` presses `key` until `focus` is `wanted`, at most `smoke.FOCUS_TRIES`
  presses, and raises `TimeoutError` naming the wanted control, the one reached and every control passed.
- `smoke.step_value(page, wanted, key, times)` presses a value key and checks the focus was on `wanted` before and
  after, so a key that moved the focus is an error, not a wrong setting.
- Taps use `spots` (`<key>:x,y` and `<key>:end:x,y`, fractions of the window), looked up by the same control names.
  `bots:end` is the bot count's next arrow and `bot_skill:end` the skill's: the two selectors share one row, so a spot
  taken from the row's control hit the skill's arrow.

## Order of the walk

The focus links decide, not the picture. On the Play screen Up from `Start` reaches `bot_skill`, then `bots`, then
`break_seconds`, `max_alive`, `perk_limit`, `count_multiplier` and the map cards (the perk limit shares the intensity's
row, #913); Down from `break_seconds` lands on `bot_skill`
(the nearer selector), so `bots` is reached going up. Walk up from Start and come back to `Start` going down.

## Adding a control

Name it (a setting's key, or the name a button already has in the lobby) and a probe needs no change. A test
(`test_web_probe.gd`) fails when a Play-screen control stops publishing its name. Run `solo_settings.py`,
`camera_owner.py` and `map_picker.py` through `gds quiet` on a web export before opening the pull request.

`lobby.py` (the host's rules) walks by the same names but needs a deployed backend and no CI job runs it: it was
changed from its count of presses without a local run.

## The probes are off in a player's page (#935)

`window.deadnight` is read by the browser tests, not by the game, and the judder, view and pad probes read it over
the JavaScript bridge in every frame (a property read, and a new `Array` for the pads). They are added only when the
page asks (`WebProbe.asked`): `?probe` (or `?probe=flash`) in the address, `window.deadnight_probe` set before the game
starts, or a profile run (`window.deadnight_bench`). A probe that reads `viewRows`, `frames`, `pad_count` or
`pause_presses` opens its page through `smoke.probing(url)`; the pad probe lists the pads on
`Input.joy_connection_changed`, not every frame. The snapshot (`WebProbe.snapshot`, four times a second) is built only
when the page asks (#983), so **every** probe that reads `window.deadnight` needs the page to ask: a build served by
`smoke.serve` (and `smoke.Quiet`, which the lobby and room probes use, and `activity.py`'s server) gets
`window.deadnight_probe=true` in its head by itself; a deployed URL goes through `smoke.probing(url)`, or has `probe` in
the query it builds. A page that must stay plain passes `smoke.serve(folder, probing=False)`.

`tools/web_smoke/bridge_calls.py` counts the bridge's traffic of the plain menu and a plain autopilot night (counting
proxies for `create_object`, a wrapped `eval`) and fails the web job above `--max-per-second` (1: a plain page
publishes nothing and makes no evals, #983); `--probe` shows the
probes' own traffic. The picture it saves of each page is for a reader, taken after the count, so it waits
120 s and, when a night on the runner's software renderer still does not answer, is left out and noted in the report
(`screenshot`), never a failed job (#1235: one run in seven stalled the night's shot past Playwright's 30 s;
the other six took 161 to 187 s for the whole step). `heap_soak.py --plain` soaks the page a player opens.
Numbers: `docs/research/web-heap.md`.

`tools/web_smoke/arrival_web.py` plays the helicopter drop of a player's arrival (#1057): Solo from the menu on either map
(`--map`), a phone-sized page (`--size 844x390`), a skip (`--skip`), or a late join to a game server of this machine with
a bot in the night (`--late --godot <the pinned Godot>`); it counts the WebGL calls through the show and after it
(`smoke.trace`) and fails on a console error, a show that never began or ended, or a HUD that did not give way. A page that
asks for the probes does not play the show unless it has `?arrival` (`--unasked` checks that it does not). Numbers:
[the arrival](arrival.md).

## Which scale a page runs at, and the ruler (#1197)

`phone_layout.py` walks the menu screens in Chromium as a phone (or `--desktop`, or `--iframe` for the Activity's frame)
and prints, from `window.deadnight` (`layout`, `phone`, `ui_audit`), the page in CSS px, the canvas, the content scale
factor, the canvas in units and the smallest text and tap target in CSS px. It fails under 14 and 44. Sections: `tour`,
`turn` (upright and back, a tablet page, a covering screen), `night` (a night entered and left). Details and numbers:
[phone-page-scale.md](phone-page-scale.md).

## The phone probes, run together on one export (#1317)

CI runs no browser probe, so each pull request of the phone rework ran only the probes it knew of, on its own base, and
four were stale when the whole rework was on main. Run the lot on one export of main, under `gds quiet`, after a change
that moves the touch layer, the HUD's places or the menu's scale. All take `<web folder> <out folder>` first:

| Probe | Pages | Notes |
| --- | --- | --- |
| `phone_layout.py` | `--size 844x390`, `--size 667x375` | `--section tour,browser,lobby,turn,night`; the floors (14 and 44 CSS px) are the phone's, a tablet page is the desktop's |
| `phone_drag.py`, `phone_view.py` (`--night`, `--iframe`) | its own sizes | |
| `touch_right_side.py` | `--page 844x390`, `--page 667x375` | the page is `WxH` here, the others take `844` or `667` |
| `touch_weapon_places.py`, `touch_ping_place.py`, `touch_double_tap.py`, `touch_bot_tag.py`, `touch_strike.py`, `round_card_phone.py`, `night_taps.py` | `--page 844`, `--page 667` | |
| `touch_scoreboard.py` | `--page`, and `--bots 3`, `--bots 7` | a room with bots takes room the solo night does not |
| `touch_sprint.py` | both sizes in one run | |
| `players_column_phone.py`, `challenge_card_phone.py` | `--pages 844,667` | take a Godot and a work folder, export their own copy (delete it after) |
| `touch_look.py`, `touch_look_smooth.py`, `touch_grenade_look.py` | older sizes | not in the rework's list; they pass on main |
| `touch_melee.py`, `touch_assist.py` | 844 x 390 | bench scenes that export their own copy (delete it after); both fail on main, not yet read to the end (#1320) |

Two traps found by that run. `touch_hits` and `touch_buttons` list every circle of the layout, the contextual Interact
and Strike too, drawn or not: a probe that presses "every button" must skip them unless they are up (`touch_strike` for
Strike), or it holds a button that is not there. A finger for the stick must land on free ground (the stick's side,
above the weapon strip, right of the players' column): a finger on the column is the scoreboard's and starts no stick.
The marker capacity of a page (the audit's tables) is measured by the helpers of `test_hud_marker_cards.gd` over counts
of 1 to 10, see [the touch audit](../design/touch-audit.md#markers-on-main-after-the-rework-1317).
