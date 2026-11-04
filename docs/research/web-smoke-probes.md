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
