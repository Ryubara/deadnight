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

## A faint vertical line over the plates (#1249)

Cause: the film overlay's scratch (`film_grain.gdshader`): a line 1.6 px wide at a fresh random x three times a second,
about a third of those times, over 65% of the rows, drawn over everything the router shows. Never in a layout, which is
why it sat at one screen x over several controls and moved between captures. Seen with `phone_layout.py --section line`
(Settings shot 40 times, 0.1 to 0.2 s apart; `--with numpy --with pillow`): `column_line.py` takes the median of the
shots (the screen without the film), subtracts it from each shot and reads, for each column, how far it stands over
columns x-3 and x+3 (the smaller of the two, so a panel's step edge reads 0). A panel's own hairline border is a ridge,
so one shot alone reads it as a line (x = 36 in every shot): measure a series. Web export, Chrome 156 headless
(SwiftShader), shots with a column of at least +3 levels on at least half the rows:

| page | main | scratch removed |
| --- | --- | --- |
| phone, ratio 3 (1688 x 780 canvas, 2532 x 1170 shot) | 8 of 40, +10 to +14 | 0 of 40 |
| phone, ratio 2 (1688 x 780 shot) | 9 of 40 | 0 of 40 |
| desktop 1280 x 720 | 4 of 40 | 0 of 40 |

The median screens of main and of the fix differ by 0.4 levels on average (99% of the pixels by 2 or less), so the
plates look the same. The scratch is removed, not hidden on a phone: a desktop shows it too.
