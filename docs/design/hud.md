# HUD

What a player sees during a night: where each readout sits, what feeds it, and why. The code is
`game/ui/hud/` (scene `hud.tscn`, one script per part); the look follows the [UI look](style.md#ui-look) rules
(flat paper and signs, hard shadows, notched corners, amber and hot orange, two faces) and the tokens of the
`gds_ui` addon. Round, points, fuel and shop numbers are in [Rounds, points and fuel](rounds.md).

## Network-first

The HUD reads one object, `HudState` (plain numbers, strings, arrays and dictionaries; a test checks that it holds no
`Object`). It never sees `GameRules`, a node or a body:

| Fed by | How | Carries |
| --- | --- | --- |
| The rules' events | `hud.feed(events)` / `state.apply_event(event)`, the same dictionaries the server broadcasts | round, zombies left, points, fuel, circuits, players and their down state, **your health** (`player_added`, `player_hurt`, `player_healed`, `player_downed`), purchases, hits and kills, game over |
| A snapshot | `state.load_snapshot(rules.to_dict())` | a late joiner or reconnect, no events replayed: round, phase, break, zombies left and the round's total, every player's points, down state and grenades, your health, the generator. Names are not in the rules, so the ones set before stay |
| The local player's readings | `facing` (a property), `set_ammo`, `set_equipment`, `set_prompt`, `set_area`, `set_markers`, `set_player_name` (`set_health` is for tools and captures) | what the rules do not own: which way you face, the weapon in hand, what is in reach, where the player stands |
| HUD additions to the rules' events | optional `screen_x`, `screen_y` (0 to 1) on `zombie_damaged` to place the damage number at the hit | the client turns a hit point into these; there is no world position in the HUD |

Events for other players change their row in the party list and leave your own readings alone. Unknown events are
ignored, so the rules can grow events without breaking the HUD. A blow is the rules' `player_hurt`: it carries a
`bearing` in the world (radians clockwise from -z), and the damage arc turns it by `facing` (the frame's yaw of the
local player) into the direction on screen.

## Parts

| Part | Where | Shows |
| --- | --- | --- |
| `HudRound` | top left | the round on a row of **reel digits** (a projector drum counter that rolls to the next number), zombies left or the break countdown |
| `HudObjective` | top left, under the round | the area you are in and one line of what to do next (two lines at most) |
| `HudTeam` | top left | one ticket for the other players: name and `UP` or `DOWN` (2 to 4 players; hidden when alone) |
| `HudFuel` | top right | the tank as 20 segments, a percentage or `LOW` or `NO POWER`, one bulb per circuit with its sign's word beside it, in two columns (`SCREEN`, `SNACKS`, `BOOTH`, `BACK LOT`) |
| `HudFeed` | top right, under the tank | what happened on the lot ("RUBY OPENED THE CONCESSION STAND", someone down, generator warnings), then who connected or left; one line each, 560 units wide (wider than the column): a long line shrinks toward 24, then ends in an ellipsis |
| `HudPoints`, `HudHealth` | bottom left | your name and points; a bar of ten ticks, or `DOWN` and what to hope for; one row for the equipment with its count and the grenade count |
| `HudAmmo` | bottom right | magazine as a big numeral, reserve beside it, the weapon name on a coloured bar; hot orange when low |
| `HudBanner` | top centre | a marquee board with chasing bulbs, on the top margin level with the corner cards: `ROUND N`, `ROUND N SURVIVED`, `THE LIGHTS GO OUT`, and an area's name as you enter it (an area never replaces a round banner) |
| `HudBossBar` | top centre, under the banner | while a boss stands on the lot: its name (`THE PROJECTIONIST`, `+1` for more) over a bar that empties with its health, one bar a boss, up to three; hot orange under a quarter |
| `HudPrompt` | bottom centre, between the two cards | a concession-menu card, three lines high: the key at its left, beside it the object, one line on what it does and the price (amber, or hot `NEED 350 POINTS`) |
| `HudGains` | beside the crosshair | "+100 HEADSHOT KILL", a short list that fades oldest first; runs of small hits merge into one row; at most three rows |
| `HudCrosshair` | centre | hit marker (ticks: cream hit, amber headshot, larger red kill) and floating damage numbers, small, nudged apart, at most eight |
| `HudDamage` | full screen | a red arc toward the attacker per blow; a red frame under a third health (pulses; held while down) |
| `HudMarkers` | full screen | objective diamonds with distance, smaller as they get farther; teammates' names at constant size; the important marker pins to the edge with an arrow when off-screen |

The interaction prompt takes its key from the `interact` action in the InputMap (E, gamepad Y), so a rebound key shows
the new key, and the glyph is a square keycap or a round button by the **last device used** (`UIInputMode.gamepad`). It
sinks while the action is held. A refused purchase shakes the card and says why in place of the price.

## Decisions

- **Typeface through a token.** `UITokens.font_display` and `font_text` (null keeps the engine's fallback font) feed
  `display_font()` and `text_font()`; every HUD label and drawn string asks those. The pick in [typography](typography.md)
  (issue #31) drops in by setting two resources; nothing here names a font. Captures load Bungee Inline and Barlow
  Condensed from a folder outside the repository (`--fonts=`). No font file is committed.
- **No compass bar, no minimap.** The lot is one small, lit area seen from a third-person camera; the lit circuits
  already show where to go, and a minimap would add a second picture to read at 720p. The waypoint diamonds carry
  distance and an edge arrow for the one thing that matters (the next door), and teammates get names over their heads.
  Revisit if the map grows past the lot.
- **A reel counter, not tally marks.** The round is a drum counter in the style of a projector's reels (two digits,
  three from round 100); it is the only place the hot red is a big numeral.
- **A part never grows past its band.** The layout test once used short values and the fallback font and passed
  while a real name, a three-digit round or the Marquee face overlapped parts at 1536 x 864. Each part now has a width
  it keeps (`HudStyle.COLUMN` for the side columns, `CARD` for the banner and prompt, `HudAmmo.WIDTH`,
  `HudGains` taking what is left of the screen up to the ammo card) and the text gives way: a number or a name
  shrinks its type toward the 24-unit floor, then ends in an ellipsis (`HudStyle.set_fitted`); a name before a word that
  must survive ("POINTS", "x12") is cut by `HudStyle.trimmed`. A name is kept to 20 characters by the state
  (`HudStyle.NAME_LIMIT`). Vertically the bands are: the right column ends above the gains, the gains above the
  prompt, the prompt on the bottom margin.
- **Ordinary text is never cut; the worst case may be.** The overlap fix (#161) made every part give way with an
  ellipsis, and at 1080p that cut the everyday values (`SCRE... SNAC...`, `PLAYER 1 OPENED THE C...`; #170). Two
  structural fixes, no abbreviations: the generator's words sit beside their bulbs in two columns (half the gauge for a
  word, not a quarter, so `BACK LOT` fits; the card is no taller), and the event rows are 560 units wide, hanging left of
  the column into the empty space under the banner (the banner moved from 10 % of the screen height to the top margin so
  it ends above them at every canvas). Wrapping to two lines was rejected: three events of two lines reach the gains.
  `test_hud_typical_text.gd` holds the line: no ellipsis for the values of an ordinary night at 1080p and 1440p.
- **Caps keep a 28-zombie round readable.** Three gain rows, eight damage numbers, six damage arcs, three events and one
  notice at a time; the oldest goes first.
- **Notices on the right.** Joins and leaves sit under the event list, not at the left edge: with four players, an
  objective and a downed health stack, the left column is full on a 1536 x 864 canvas.
- **Outlined text.** Every label has a dark outline and a hard shadow so it holds on the lit lot and on the dark.
- **Colour means something.** Amber is points and light, hot orange or red is danger and low (round numeral, low
  ammo, no power, a price you cannot pay), cream is plain information.

## Scale

The project stretches the canvas to 1920 x 1080 (and wider or taller for other window shapes); the UI scale setting
divides it (0.8 to 1.25). The HUD lays out in canvas units with anchors, no scale of its own. A test builds the busiest
HUD (four players, you down, a long prompt, a banner, full lists), and the same with the longest content the game allows
(20-character names, round 123, 99,999,999 points, 999 / 9999 ammo, a 23-character weapon, a long prompt and notices),
at every window from 1024 x 768 to 4K at each UI scale, in three typefaces, and checks that every part is inside the
screen and none overlaps another. The smallest text is 24 canvas units: 16 px
at 720p, 12.8 px at 720p with the smallest UI scale.

## Cost

Parts redraw only for what changed. `HudState` marks the topics a change touched (`round`, `team`, `fuel`, `health`,
`ammo`, `points`, `prompt`, `objective`, `markers`), announces them once through `changed`, and a part lists the topics
it reads (`HudPart.topics`); a setter that sets what it already holds announces nothing. `apply_events` announces a
whole batch once (`hold` / `release` do the same for a frame's events and readings), though `event_applied` still comes
once per event for the one-shot treatments. The break countdown wakes the round part once a second, when the number
on screen changes. The party rows are made when a player joins and freed when one leaves; a name or a down state only
rewrites a row. A tick in which a round's 17 zombies die (58 events) takes the HUD about 2 ms headless, down from 41 to
45 ms.

## Motion and reduced motion

Everything time-driven advances by the frame's delta (`advance(delta)` on each part), so a capture or a test replays
exactly. With `UIMotion.reduced`: no reel roll, no banner growth, no rising numbers or popups, no swinging arcs, no
chasing bulbs, no pulsing (the low-health frame and low-fuel tank hold steady); fades and the information stay.

## Tests and captures

`game/tests/ui/test_hud_state.gd` (the mirror, from real rules events; topics; names), `test_hud_snapshot.gd` (a late
joiner against the HUD that saw every event), `test_hud_refresh.gd` (changes announced, nodes made and a time budget for
the break and a kill batch), `test_hud_parts.gd` (every part, the prompt with simulated input and device switching),
`test_hud_typical_text.gd` (the ordinary night's values show in full at 1080p and 1440p, in the fallback face and the
Marquee pair), `test_hud_layout.gd` (sizes, overlap, readability, reduced motion: the busiest HUD and the longest
content the game allows, in the fallback face, a synthetic wide face and, when `refs/fonts` is there, the Marquee
pair, at every canvas). The capture `game/tests/captures/hud_worst_case.tscn` renders the longest content at one canvas
(`-- --out=<png> [--size=1536x864] [--face=fallback|wide|marquee] [--busy]`). The capture
`game/tests/captures/hud_tour.tscn` plays a real `GameRules` night over the drive-in greybox:

```text
godot --path game res://tests/captures/hud_tour.tscn --write-movie out.png --fixed-fps 10 -- --view=concession --fonts=<fonts folder> [--reduced]
```

To record at a window size, put `window/size/window_width_override` and `window_height_override` in an uncommitted
`game/override.cfg`; `--resolution` is ignored by Movie Maker.
