# HUD

What a player sees during a night: where each readout sits, what feeds it, and why. The code is
`game/ui/hud/` (scene `hud.tscn`, one script per part); the look follows the [UI look](style.md#ui-look) rules
(flat paper and signs, hard shadows, notched corners, amber and hot orange, two faces) and the tokens of the
`gds_ui` addon. Round, points, fuel and shop numbers are in [Rounds, points and fuel](rounds.md).

A left-handed touch layout mirrors the corner columns (`Hud.mirrored`, set by the night screen): round and objective swap
with the fuel, event and notice lists, points and health with ammo, so the buttons that flip sides still miss every card
([touch controls](touch-controls.md#left-handed-layout)). Parts in the middle stay.

## Network-first

The HUD reads one object, `HudState` (plain numbers, strings, arrays and dictionaries; a test checks that it holds no
`Object`). It never sees `GameRules`, a node or a body:

| Fed by | How | Carries |
| --- | --- | --- |
| The weapons' events | the same `apply_event`, for `weapon_equipped`, `shot_fired`, `reload_started`, `reload_finished`, `ammo_added` (`HudLoadout.EVENTS`; the binding forwards these and no other weapon event) | the ammo card and the equipment slot: the weapon in hand, its magazine and reserve as the events carry them, whether it is reloading, and the weapon put away last |
| The frame's weapons | `HudLoadout.sync`, every frame, from the local player's `weapon`, `ammo`, `reserve`, `reloading` and `arms` | the same readings, as the server holds them: rounds that came by any road (a locker, a wall buy of a weapon already carried, a pickup) show on the tick they arrive, and a HUD that joined late needs no replay. The frame wins over the events; matching it announces nothing |
| The rules' events | `hud.feed(events)` / `state.apply_event(event)`, the same dictionaries the server broadcasts | round, zombies left, points, fuel, circuits, players and their down state, **your health** (`player_added`, `player_hurt`, `player_healed`, `player_downed`), purchases, hits and kills, game over |
| A snapshot | `state.load_snapshot(rules.to_dict())` | a late joiner or reconnect, no events replayed: round, phase, break, zombies left and the round's total, every player's points, down state and grenades, your health, the generator, the special round running and the bosses on the lot with their health (a boss whose spawn event was already in flight is not counted twice). Names, seats and looks are not in the rules, so the ones set before stay |
| The local player's readings | `facing` (a property; `set_ammo` and `set_equipment` are for tools and captures, the weapons' events and the frame fill them), `set_prompt`, `set_area`, `set_markers` (the night fills it every frame, `NightMarkers`), `set_player_name` (`set_health` is for tools and captures) | what the rules do not own: which way you face, what is in reach, where the player stands |
| HUD additions to the rules' events | optional `world` (a `Vector3`) on `zombie_damaged`, or `screen_x`, `screen_y` (0 to 1) | the night's binding adds `world` (the zombie, lifted to the head or the chest); the crosshair draws the number over that point through its `projector` every frame, so it stays on the wound while the camera turns and hides while the point is behind the lens. `screen_x`/`screen_y` place a number once, for tools |

The ammo card and the weapon slots are the local player's only: another player's `ammo_added`, shot or reload leaves
them alone (a teammate's rounds are not shown anywhere).

Events for other players change their container (points, down state) and leave your own readings alone. Unknown events are
ignored, so the rules can grow events without breaking the HUD. A blow is the rules' `player_hurt`: it carries a
`bearing` in the world (radians clockwise from -z), and the damage arc turns it by `facing` (the frame's yaw of the
local player) into the direction on screen.

## Parts

| Part | Where | Shows |
| --- | --- | --- |
| `HudRound` | top left | the round on a row of **reel digits** (a projector drum counter that rolls to the next number), zombies left or the break countdown |
| `HudObjective` | top left, under the round | a card with the area you are in and one line of what to do next (two lines at most) |
| `HudFuel` | top right, **only for a moment** | the generator card: the tank as 20 segments, a percentage or `LOW` or `NO POWER`, one bulb per circuit with its sign's word beside it, in two columns (`SCREEN`, `SNACKS`, `BOOTH`, `BACK LOT`). Slides down into the column and fades in when the night makes progress at the generator, holds 4 s, leaves (see below) |
| `HudFeed` | top right, under the generator card (at the top while it is away) | what happened on the lot ("RUBY OPENED THE CONCESSION STAND", someone down, generator warnings), then who joined or left; one line each, 480 units wide (wider than the column), ending on the cards' right text line: a long line shrinks toward 20, then ends in an ellipsis (a cleared special round adds `DOUBLE FEATURE CLEARED  +440 EACH`) |
| `HudPoints` | bottom left | **a container per player**, `[portrait][points]` (see below), you first, then the others by id; a player with a level shows **icon, level, name** in the points box ([the order](progression.md#the-level-over-a-head)), a bot the name alone |
| `HudHealth` | bottom left, under the players | a card: `HEALTH n` and the grenade count on one row, a bar of ten ticks (or `DOWN` and what to hope for). The weapon put away used to be named under the bar; the slot strip shows it now, one home for what is carried |
| `HudPerks` | bottom left, **beside the health card** (right of it; left of it for a left hand), its bottom level with the card's | one small badge for each perk the player has (the machine's emblem on its colour), two to a row, rows going up; hidden with none, empty after a down that takes the perks ([see below](#the-perk-badges)) |
| `HudSlots` | bottom right, **above the ammo card**, as wide as it (with the touch controls up: bottom left, under the health card, as wide as it) | the weapons carried, by slot ([see below](#the-weapon-slots)) |
| `HudAmmo` | bottom right | magazine as a big numeral, reserve beside it on the same baseline, the weapon name on a coloured bar; hot orange when low; `RELOADING` while a reload runs; `--` for a weapon with no ammunition (the crowbar) |
| `HudBanner` | top centre | a marquee board with chasing bulbs, on the top margin level with the corner cards: `ROUND N`, `ROUND N SURVIVED`, `THE LIGHTS GO OUT`, and an area's name as you enter it (an area never replaces a round banner). A special round starts with its name (`DOUBLE FEATURE`) over what it brings (`THE HEADLINER ARRIVES`, `2 HEADLINERS ARRIVE`, `ONLY RUNNERS`); clearing one puts `DOUBLE FEATURE CLEARED  +440` under `ROUND 5 SURVIVED`; a late joiner into one sees its banner once |
| `HudMarquee` | top centre, under the banner | in the break before a special round, `COMING UP - ROUND 5 - IN 24` over the round's name in big letters that flicker like a failing neon sign (steady with reduced motion) over what it brings, between two rows of bulbs (the banner's); gone as the round starts. A HUD that joins in the break reads it from the schedule |
| `HudBossBar` | top centre, under the banner | while a boss stands on the lot: its name (`THE PROJECTIONIST`, `+1` for more) over a bar that empties with its health, one bar a boss, up to three; hot orange under a quarter |
| `HudPrompt` | bottom centre, between the two cards | a concession-menu card as high as its words need (a long name or line wraps, never cut; it grows upward): the key at its left, beside it the object, one line on what it does and the price (amber, or hot `NEED 350 POINTS`) |
| `HudChallenge` | left edge, a third of the way down | a paper ticket that says a challenge moved a step (a quarter mark, a finish, a milestone step): the kind in small caps, the count, the words, four punch-card holes (one more punched at each quarter). One at a time, in from the edge, held about 2.4 s, out; see [the prompt](progression.md#the-progress-prompt-in-the-night) |
| `PopupLane` | top centre, **under** the banner, the marquee and the boss bar (it slides to follow them) | the cards of the progression, live, from the server's events: a level card (icon, the level beside it, `LEVEL UP`, the next unlock and its holes), a tier card, an unlock card, a finished challenge; three at most, never over the crosshair or any other part ([popups](progression.md#popups-motion-and-sound), [how it is built](../research/popup-lane.md)) |
| `HudGains` | beside the crosshair | "+100 HEADSHOT KILL", a short list that fades oldest first; runs of small hits merge into one row; at most three rows; rows slide into their slots (see Decisions) |
| `HudReticle` | centre | the reticle (see Decisions): four short ticks round a gap and a dot, cream with a dark edge, static and small; hidden under the pause card and while you are down |
| `HudCrosshair` | centre, over the reticle | hit marker (ticks: cream hit, amber headshot, larger red kill) and floating damage numbers, small, nudged apart, at most eight |
| `HudDamage` | full screen | a red arc toward the attacker per blow; a red frame under a third health (pulses; held while down) |
| `HudMarkers` | full screen | objective diamonds with distance, smaller as they get farther; teammates' names at constant size; the important marker pins to the edge with an arrow when off-screen; a marker that would be under a card (those of the corners and, while they are up, the banner, the prompt and the popup cards) or a touch button is moved to the nearest clear place with an arrow back to where it points; a teammate's tag at the top edge goes under its pointer; on a phone's page the words and the shapes grow to read at 14 CSS px (the desktop's scale does not change) |

The interaction prompt takes its key from the `interact` action in the InputMap (E, gamepad Y), so a rebound key shows
the new key. The glyph follows the **last device used**: a square keycap, a round gamepad button
(`UIInputMode.gamepad`) or, after a touch, a round tap mark with no letter (`UIInputMode.touch`,
[touch controls](touch-controls.md#first-run-and-key-hints)). It sinks while the action is held. A refused purchase
shakes the card and says why in place of the price. The breach's card
says "HOLD TO NAIL BOARDS UP": holding the button keeps putting boards back
([rules](rounds.md#the-fences-boards)).

## The perk badges

`HudPerks` shows the perks the local player has (#707): a `HudPerkBadge` for each drink, **the machine's emblem drawn
flat in the machine's glow on a dark ground of its colour** (two bullets, the revolver drum, three racked guns, the
cross in its ring, the bolt, the soda fountain's heart), so the picture bought at the machine is the picture read,
with no word. The frame's `perks` bits are all it reads (`PerkEffects.mask_tonics` in `NightHudBinding._on_frame`
makes `HudState.perks`), so a purchase adds a badge and a down that takes the perks takes the badges: nothing is
remembered on the client. They stand in the shop's order, two to a row (a player has four at most), rows going up from
the card's bottom: 112 units wide at most, so they fit between the health card and the prompt on the smallest canvas
(1536 x 864). `Hud._place_perks` puts them by the card's rectangle once the layout has settled, so they follow it when
the touch controls bring the slot strip under it, when the safe area moves it, and for a left hand (on the card's
left). Each badge is 52 units, 43 pixels at 720p and UI scale 1.25.

## The weapon slots

Two numbered places (`HudSlots`, a `HudSlotCell` each; three when the perk that carries a third weapon is in, #687: the
places are `HudState.slot_count`, the cells share the card's width) show what is carried: the **silhouette** of each
weapon with the **number of the key that takes it in hand** (`1`, `2`, `3`). The one in hand is the lit place: amber
paper, dark ink; the one put away is cream on dark paper; an empty place is its number alone, dim. No rounds here: the
ammo card is their one home. A player reads "what do I have, which is in my hand" in half a second, and the key is on
the card.

- **The order is the server's.** `arms` in the frame lists the weapons in slot order (`CombatServer` keeps a loadout in
  its slots' order); the HUD reads it (`HudLoadout.sync`) and the events alone fill the same order. A weapon bought with
  full hands sits in the slot of the weapon it replaces, so the numbers never trade places.
- **The silhouettes are the models.** `WeaponSilhouettes` draws each weapon's own glb (the one the Soldier holds, from its
  hold file) from the side with every surface flat white into a transparent texture, once, the first time it is
  needed; the part tints it. A new weapon model has its silhouette with its hold file. Sizes follow the weapons' lengths
  (never under 58 percent of the longest) so a pistol reads as a pistol; a club that stands on its end in the model is
  laid along the width, its long side from the grip pointing right like a barrel.
- **On a phone the strip moves** under the health card (`Hud.touch_layout`, set when the touch layer comes up): the
  bottom right corner is the right thumb's (Fire and Melee sit exactly where the strip would). A left hand flips the
  column and the strip with it.
- **Keys:** `1` and `2` (and `3`) pick that slot's weapon; the slot in hand and an empty slot do nothing; the swap
  button (F, the pad's d-pad up, the touch SWAP) goes on to the next one ([weapons](weapons.md#carrying-weapons)).

## Players' points

Each player in the lot has a container: a square **portrait** on the left and the **points box** on its right, in the
colour of the player's seat (`LookCatalog.armband_colour`: red, cyan, yellow, green, orange, violet, pink, white: eight
seats, eight colours; the colour of the armband they wear in the lot, so the colour on the HUD and on the arm is one).
The box carries the name small at its left and the points at its right, on one baseline; the number takes the dark or
the light ink, whichever has the better contrast on the seat's colour (at least 4.5, a test checks all eight). Your own
container is first and larger (66 units high, a teammate's 48), the others follow by player id; one to eight are shown,
a row made when a player joins and freed when they leave. With more than four players the teammates' boxes are the
**compact** size (`HudPlayerBox.COMPACT_HEIGHT`, 32 units, the name and the points one size smaller,
`HudPoints.COMPACT_FROM`), so a party of eight stands in the height of about five boxes of the old size: 66 + 7 x 32 +
the gaps is 296 units, and the left column still ends under the health card on the smallest canvas (1536 x 864) with
the challenge prompt between it and the round card. A downed player's portrait dims, their box darkens and the name
says `DOWN`. There is no party ticket any more: the containers are the party list.

The portrait is the Soldier as the player wears it, a head-and-shoulders render of the game's own model
(`CharacterAssembler`, the assembler the wardrobe and the lot use) in a tiny 3D world of its own, drawn once and then left
alone (`UPDATE_ONCE`), so it costs nothing after its first frame. The state holds each player's `seat` and `look` as plain
data (the look as `CharacterLook.to_dict`); a join gives the lowest free seat, as the server does, and a `player_look`
event (`player_id`, `seat`, `look`) replaces it. Until a client sends looks, the seat's own preset shows.

## The scoreboard

Hold **Tab** (the pad's **Back / Select** button; on a phone a small button under Pause) and a ticket comes up over the
middle of the night; let go and it leaves. One row per player in the night, in seat order on every screen:
`[armband][name][kills][downs][revives][points][ping]`, with the round and the night's clock above (`TIME 12:34`, hours
after the first). A downed player's name goes red and says `(DOWN)`, one who bled out `(DEAD)`; your own row has a faint
wash. **Ping** is a column only when some player has one (a night over a link), and each ping reads good, fair or bad in
ink, accent and red. **REVIVES** counts the teammates a player pulled up by hand ([Revives](#revives)); getting up
when a round ends is nobody's revive (see [Scoreboard](../research/scoreboard.md)). Every number is the server's,
never counted on the client.

It is `HudScoreboard`, a part like the others, drawn last and not part of any column; it takes no space while hidden. It
is held by the `scoreboard` input action, which the key, the pad and the touch button all press, so the HUD polls the
action instead of listening for one kind of event. A pause menu or the result switches it off
(`Hud.scoreboard_enabled`).

## The bot command wheel

Holding Q (the pad's d-pad left, the touch BOTS button) opens `HudBotWheel` over the middle of the screen: three
tickets, **Follow** on top, **Roam** lower right and **Hold** lower left, a dial in the middle, a flat dim behind. The
pointer (the mouse's motion, the right stick, a finger's drag) lights one ticket; letting go over it gives the team's bots
that order, letting go over the dial or tapping the key gives none. The ticket of the order that stands is marked NOW,
and the HUD's notice list says the new order for a moment after a change (`BOTS: HOLD HERE`). It is a screen-sized
overlay (`Hud.screen_overlays`), so it stays on the middle of the screen whatever the safe area is, takes no room while
closed and is not in a column. The model, the driver and what was learned are in [Bot wheel](../research/bot-wheel.md).

## Revives

What a player reads when someone is down (the rules are in [Revive](revive.md)). Every number is the server's: the frame
carries each player's `bleed`, `revive` (the hold's progress), `reviver`, `self_revive` (seconds left of the revive
perk's own, 0 for none) and `dead`, and `HudState.team` keeps them
(`set_player_revive`), so every screen shows the same ring.

| Where | What | Part |
| --- | --- | --- |
| Over the view, a little under the reticle | **The ring** (`HudRevive`). The reviver: a ring filling as the hold goes on, the seconds left inside, `REVIVING <NAME>` under it. The downed player: the bleed-out clock as a red ring draining, the seconds inside, `BLEEDING OUT`, and over it the teammate's ring filling while they are pulled up (`<NAME> IS PULLING YOU UP`). With the revive perk getting you up alone the clock stands still, so the ring is the perk's own count instead: it fills, the seconds left inside, `GETTING YOURSELF UP` under it. Bled out: `YOU BLED OUT`, `BACK NEXT ROUND`. Nothing for a player who is up and not reviving | `HudRevive` |
| Health card, bottom left | While down: `DOWN` and `BLEEDING OUT 32 S`, or `GETTING YOURSELF UP 3 S` (the revive perk, alone), or `BEING PULLED UP`, or `DEAD` and `BACK NEXT ROUND` | `HudHealth` |
| Prompt card, bottom middle | `REVIVE <NAME>`, `HOLD TO PULL THEM UP: 32 S LEFT`; it comes before a door or a shop | `HudPrompt` |
| Over a downed teammate | A red ring with a cross, their name and the seconds they have left (`DEAD` once they bled out), the hold's ring filling over it; pinned to the screen edge with the other important markers while they are alive, so you know who is bleeding and where | `HudMarkers` |
| Player boxes, left | `DOWN`, or `DEAD`; the portrait dims | `HudPlayerBox` |
| Feed, top right | `RUBY REVIVED PAUL`, `PAUL BLED OUT` (a round's end: `PAUL IS BACK UP`) | `HudFeed` |
| Scoreboard | A REVIVES column | `HudScoreboard` |

A grenade's blast is named in the feed (#805): on the hurt player's own screen `YOUR OWN GRENADE HIT YOU  -42` or
`MOE'S GRENADE HIT YOU  -42` (a blast that does not down them, from `player_hurt`'s `harm` and `by_id`), and on every
screen a down by one reads `RUBY BLEW THEMSELVES UP` or `MOE WAS BLOWN UP BY RUBY'S GRENADE` instead of `IS DOWN`. The red
arc points at the blast as for any blow. [The rule](weapons.md#blast-on-players).

Names come from one place, `HudState.team[id]["name"]` (the prompt, the ring, the feed, the markers and the scoreboard all
read it), so a replicated display name (#485) shows everywhere once it fills that field.

## The generator card

The generator card is not always on. `HudFuel.is_progress` is the rule: fuel added (`fuel_changed` with a positive
`delta`), a circuit switched (`circuit_changed`, either way) and the warnings (`fuel_low`, `fuel_empty`, `fuel_restored`)
show it; the fuel the generator burns, kills and every other event do not, and a snapshot never does. More progress
within the hold keeps it up for a whole hold more. It slides down from above its slot while it fades in (0.3 s), holds
(4 s) and fades and slides out (0.5 s); the feed under it follows its height, so nothing overlaps. With reduced motion it
fades without sliding. A new step of the generator's quest (the circuit switches, #206) adds its event to
`HudFuel.SHOW_EVENTS`. `advance(delta)` moves it, so tests and captures step it by hand.

## Decisions

- **One grid.** Cards share a left edge (the margin, 36 units), a right edge, the gap between stacked parts (`GAP`, 6) and
  the text lines inside a card: text starts `PAD_LEFT` (20) from a card's left edge and ends `PAD` (12) from its right,
  so the round, objective, health and generator cards and the feed rows share two vertical lines. Numbers that sit
  beside smaller text share its baseline (the magazine and the reserve; a name and its points), set from the font's own
  ascent and descent, so another typeface keeps them. The top margin carries the round card, the generator card and the
  banner; the bottom margin the health card, the prompt and the ammo card. A test measures all of it
  (`test_hud_grid.gd`).
- **Smaller.** Every length is the first draft's times `HudStyle.UNIT` (0.75); type is stepped down less so it stays
  readable: 84 for the magazine, 44 for your points, 32 for a teammate's, 24 text, 20 for captions and the floor
  (`MIN_TEXT`: 20 px at 1080p, 13 px at 720p, 10.7 px at 720p with the smallest UI scale). The side columns are 316
  units (16 % of 1920), the ammo card 250, the banner and the prompt 420. Spacing comes from `HudStyle` (`XS`, `SM`,
  `MD`, `LG`), not the menu tokens. Resembling Cold War Zombies' HUD is fine (the maintainer's decision); the look stays
  ours.

- **Typeface through a token.** `UITokens.font_display` and `font_text` (null keeps the engine's fallback font) feed
  `display_font()` and `text_font()`; every HUD label and drawn string asks those. The game's tokens set Bungee Inline
  and Barlow Condensed ([typography](typography.md), issue #11), so the HUD, the menus and the sign share one pair;
  nothing here names a font. The files are committed under `game/assets/fonts` with their licences.
- **No compass bar, no minimap.** The lot is one small, lit area seen from a third-person camera; the lit circuits
  already show where to go, and a minimap would add a second picture to read at 720p. The waypoint diamonds carry
  distance and an edge arrow for the one thing that matters (the next door), and teammates get names over their heads.
  Revisit if the map grows past the lot.
- **A reel counter, not tally marks.** The round is a drum counter in the style of a projector's reels (two digits,
  three from round 100); it is the only place the hot red is a big numeral.
- **The reticle (#300).** A small static mark where the shots go, drawn by `HudReticle` over the middle of the screen:
  four ticks 9 units long and 3 wide round a 7-unit gap, and a 3-unit dot, in the light ink (`tokens.ink`, 92 %)
  with a 1.5-unit dark edge on every shape so it holds on the lit pools and on the dark. About 32 units across, 3 % of
  the 1080-unit canvas height (22 px at 720p). The maintainer asked for "very simple, inspired from games like Call of
  Duty, static and small", so it does not bloom with movement or fire, does not change colour over a zombie and is
  not an animation; the one thing it shows is the camera ray, which is where `AimResolver` sends the shot, so it
  stays at the centre whatever the shoulder offset or the aim zoom do. The hit markers are the
  *diagonal* ticks (starting 9 units out) and sit between the reticle's, so the two never overprint. Lengths are canvas
  units: it scales with the window and the UI scale like every other part (a test reads the viewport's stretch). It
  is shown **while aiming too**: the aim view has no reticle of its own, and hiding the only mark where the shots go
  at the moment of precision would be wrong. It is hidden under every card the night screen shows (Joining,
  Paused, the result: `_show_overlay` calls `set_shown`) and shown again by `_hide_overlay`, the one way a card goes,
  together with the scoreboard and the touch controls (#517: a joined night once ran with none of them). It is also
  hidden while you are down. Every number is on `ReticleStyle` (`ui/hud/reticle_style.tres`, also the *Reticle Style*
  property of the `Hud` node): arm length, gap, thickness, outline, dot size (0 for none), tint and opacity, with
  ranges in the inspector.
- **A part never grows past its band.** The layout test once used short values and the fallback font and passed
  while a real name, a three-digit round or the Marquee face overlapped parts at 1536 x 864. Each part now has a width
  it keeps (`HudStyle.COLUMN` for the side columns, `CARD` for the banner and prompt, `HudAmmo.WIDTH`,
  `HudGains` taking what is left of the screen up to the ammo card) and the text gives way: a number or a name
  shrinks its type toward the 20-unit floor, then ends in an ellipsis (`HudStyle.set_fitted`); a name before a word that
  must survive ("POINTS", "x12") is cut by `HudStyle.trimmed`. A name is kept to 20 characters by the state
  (`HudStyle.NAME_LIMIT`). Vertically the bands are: the right column ends above the gains, the gains above the
  prompt, the prompt on the bottom margin.
- **Ordinary text is never cut; the worst case may be.** The overlap fix (#161) made every part give way with an
  ellipsis, and at 1080p that cut the everyday values (`SCRE... SNAC...`, `PLAYER 1 OPENED THE C...`; #170). Two
  structural fixes, no abbreviations: the generator's words sit beside their bulbs in two columns (half the gauge for a
  word, not a quarter, so `BACK LOT` fits; the card is no taller), and the event rows are 480 units wide, hanging left of
  the column into the empty space under the banner (the banner moved from 10 % of the screen height to the top margin so
  it ends above them at every canvas). Wrapping to two lines was rejected: three events of two lines reach the gains.
  `test_hud_typical_text.gd` holds the line: no ellipsis for the values of an ordinary night at 1080p and 1440p.
- **Lines slide, they never jump.** The point gains and the two feed lists stack their rows in a `HudRowStack`: every
  row has a slot under the rows above it, and each frame it covers the same fraction of its distance to the slot
  (95% in 0.18 s, whatever the frame rate), so when a line above expires, or the cap drops one, the lines below slide
  up instead of teleporting. A new line starts a row below its slot (never above the row before it, so lines arriving
  in one frame cannot overlap) and fades in as it rises. The height the stack reports eases too, so the notices under
  the event list follow. It is the view's motion: `advance(delta)` steps it with the fade (tests and captures pass the
  seconds), `HudState` knows nothing of it, and with reduced motion every line is in its slot at once.
- **The challenge prompt sits where nothing else does (#399).** The left edge, a third of the way down, is the one
  free band: the
  round column ends above it, the players' column starts below it, the reticle, gains and prompt are in the middle and
  at the bottom. It does not mirror for a left hand (the corner buttons are at the bottom). It is a paper ticket, not a
  dark card, on purpose: it is rare, so it may be the one light thing at the edge, and it matches the main menu's
  "The program". `HudChallenge` reads `challenge_advanced` events like every part; `ChallengeHudLink` makes them from the
  night's challenges. A layout test puts it on the busiest HUD at every canvas, mirrored or not, beside the crosshair's
  clear box (`test_hud_challenge.gd`).
- **Caps keep a 28-zombie round readable.** Three gain rows, eight damage numbers, six damage arcs, three events and one
  notice at a time; the oldest goes first.
- **Notices on the right.** Joins and leaves sit under the event list, not at the left edge: with eight players, an
  objective and a downed health stack, the left column is full on a 1536 x 864 canvas.
- **Outlined text.** Every label has a dark outline and a hard shadow so it holds on the lit lot and on the dark.
- **Colour means something.** Amber is points and light, hot orange or red is danger and low (round numeral, low
  ammo, no power, a price you cannot pay), cream is plain information.

## Scale

The project stretches the canvas to 1920 x 1080 (and wider or taller for other window shapes); the UI scale setting
divides it (0.8 to 1.25). The HUD lays out in canvas units with anchors; `HudStyle.UNIT` is the one number that sizes
it against the first draft. A test builds the busiest
HUD (eight players, you down, a long prompt, a banner, full lists), and the same with the longest content the game allows
(20-character names, round 123, 99,999,999 points, 999 / 9999 ammo, a 23-character weapon, a long prompt and notices),
at every window from 1024 x 768 to 4K at each UI scale, in three typefaces, and checks that every part is inside the
screen and none overlaps another. The smallest text is 20 canvas units: 13 px
at 720p, 10.7 px at 720p with the smallest UI scale.

## Cost

Parts redraw only for what changed. `HudState` marks the topics a change touched (`round`, `team`, `fuel`, `health`,
`ammo`, `points`, `prompt`, `objective`, `markers`), announces them once through `changed`, and a part lists the topics
it reads (`HudPart.topics`); a setter that sets what it already holds announces nothing. `apply_events` announces a
whole batch once (`hold` / `release` do the same for a frame's events and readings), though `event_applied` still comes
once per event for the one-shot treatments. The break countdown wakes the round part once a second, when the number
on screen changes. The player containers are made when a player joins and freed when one leaves; a name, points or a
down state only rewrites a box, and a portrait is drawn once. A tick in which a round's 17 zombies die (58 events)
takes the HUD about 2 ms headless, down from 41 to 45 ms.

## Motion and reduced motion

Everything time-driven advances by the frame's delta (`advance(delta)` on each part), so a capture or a test replays
exactly. With `UIMotion.reduced`: no reel roll, no banner growth, no rising numbers or popups, no swinging arcs, no
chasing bulbs, no pulsing (the low-health frame and low-fuel tank hold steady); fades and the information stay.

## Tests and captures

`game/tests/ui/test_hud_state.gd` (the mirror, from real rules events; topics; names), `test_hud_special.gd` (the
marquee, the banner, the reward line and a late joiner into a special round), `test_hud_snapshot.gd` (a late joiner
against the HUD that saw every event), `test_hud_refresh.gd` (changes announced, nodes made and a time budget for
the break and a kill batch), `test_hud_parts.gd` (every part, the prompt with simulated input and device switching),
`test_hud_players.gd` (a container per player, one to eight: colours, local first, down, the portrait),
`test_hud_reticle.gd` (the reticle: present, centred, small, scaled by the viewport stretch, hidden under a menu or
while down, editable), `test_hud_generator_panel.gd` (when the card shows and its stepped timing),
`test_hud_grid.gd` (the grid, measured at every canvas: shared edges, gaps, text lines, no label leaving its part),
`test_hud_typical_text.gd` (the ordinary night's values show in full at 1080p and 1440p, in the fallback face and the
Marquee pair), `test_hud_layout.gd` (sizes, overlap, readability, reduced motion: the busiest HUD and the longest
content the game allows, in the fallback face, a synthetic wide face and the Marquee pair the game ships, at every
canvas). The capture `game/tests/captures/hud_worst_case.tscn` renders the longest content at one canvas
(`-- --out=<png> [--size=1536x864] [--face=fallback|wide|marquee] [--busy|--night] [--quiet] [--players=N]
[--window=WxH]`: `--window` renders at that many pixels with the canvas stretched, so
`--size=1920x1080 --window=1280x720` is a 720p window). The capture
`game/tests/captures/hud_tour.tscn` plays a real `GameRules` night over the drive-in greybox:

```text
godot --path game res://tests/captures/hud_tour.tscn --write-movie out.png --fixed-fps 10 -- --view=concession [--reduced]
```

To record at a window size, put `window/size/window_width_override` and `window_height_override` in an uncommitted
`game/override.cfg`; `--resolution` is ignored by Movie Maker.
