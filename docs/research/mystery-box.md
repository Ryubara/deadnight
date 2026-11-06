# The Mystery Box, and our prize crane

The prize crane is modelled on the Call of Duty Zombies Mystery Box: a gamble for a random weapon that you pay for
up front, watch spin, and may have to take before it fades, and that sometimes breaks and moves. The names, models,
sounds and layouts are ours; this page keeps the numbers worth copying and says how sure each one is.

**Sources and how sure we are.** The big wikis (the Call of Duty and Project Lazarus wikis on Fandom, StrategyWiki)
refused automated reading when this page was written (HTTP 402 and 403), so most numbers come from search snippets of
those pages and from forum and modding threads, and the rest from what players commonly report. Every row says which:
**quoted** has a source in the list below, **reported** is common community knowledge we could not open a page for,
**estimated** is our reading and should be checked with a timed capture of the real thing.

- Modding thread, UGX-Mods, "custom perk, cheaper box and faster spin": the Black Ops 1 script has `cost = 950` in
  `treasure_chest_think()`, and the box's move-up animation is `moveto(..., 3, 2, 0.9)`. It also quotes a
  "Bonfire Sale" mod lasting 30 seconds.
- Project Lazarus wiki, Mystery Box (through a search summary): the chance of the Joker (the teddy bear) depends on how
  many times the box has been used since it last moved.
- Giant Bomb, The Mystery Box (through a search summary): outside the first map, a teddy bear comes out after 6 to 8
  uses and the box relocates.
- Call of Duty Zombies forum, "Mystery box weapon draw chances" (through a search summary): all weapons are equally
  likely, with exceptions such as the ones the player holds.

## What the Mystery Box does

| Part | The Mystery Box | How sure |
| --- | --- | --- |
| Cost | 950 points a play | quoted (script), and the figure every guide gives |
| Spin | The lid opens and weapon models cycle above it for about 4 to 5 seconds, quick at first, slowing down until one stops | estimated (the length), reported (the slowing) |
| Grab window | The chosen weapon floats above the box for about 12 seconds, sinking slowly; if nobody takes it, it is gone and the box closes. No refund | reported, estimated (12 s) |
| Pool | A fixed list of weapons, all about equally likely; a weapon the player already holds is skipped; the same weapon does not come twice in a row; "wonder" weapons are rarer or limited | reported |
| Leaving ("teddy") | A teddy bear appears instead of a weapon. There are guaranteed uses after a move, then a rising chance. By uses since the last move: 0 to 3 never; 4 to 7 about 15%; 8 to 11 about 30%; 12 or more about 50%. One source says the bear shows after 6 to 8 uses | quoted (the table, from a summary; the 6 to 8 is another source's reading of the same rule) |
| Refund | When the bear shows, the price comes back | reported |
| Relocation | The bear "dances", the box flies away and lands at another location of the map; only locations in rooms the players have opened are used | reported |
| Marking | A pillar of light (blue-white) stands over the active box so it can be seen from far away; a box that is not active is not lit | reported |
| Co-op | One box for everyone, one play at a time; the buyer sees the weapon and takes it. Behaviour for the other players differs by title | estimated; we decided it ourselves below |
| Fire Sale | A timed event (about 30 seconds): the price falls to 10, every box location shows a box at once, and the bear cannot appear | reported, estimated (the 30 s) |

## What we copied, and what we changed

Everything is in `CraneTuning` (`game/gameplay/rules/crane_tuning.gd`) and the shop item `crane_play`, in
`default_tuning.tres`; the code holds no number.

| Part | Our crane | Why it differs |
| --- | --- | --- |
| Cost | 550, tuned with the balance simulator (see [the price](#the-price)) | Our points are earned at a different rate (a round pays 350 to 3,500, a wall shotgun costs 900) |
| Spin | 4.5 s (`spin_seconds`) | The middle of the reported range |
| Grab window | 12 s (`grab_seconds`), only the buyer can take it | We chose buyer-only for every title's sake: the prompt of anyone else says so |
| Pool | shotgun 4, rifle 3, SMG 2, flare gun 1, baseball bat 0.5, fire axe 0.5, revolver 1, crowbar 1 (an open question for the maintainer, #410) (`pool`, `pool_weights`), minus what the buyer carries (two weapons, #410: the revolver and the crowbar are in it for a player who gave them up) | We have six prizes, not forty: the flare gun plays the part of the rare wonder weapon and the two melee weapons are rarer still. Equal odds would make the crane a free shotgun-or-rifle choice. Every weapon the start and the wall do not give is in it. The balance simulator cannot see a melee prize: it fights with a firearm while any has rounds and resupplies before it runs dry, so a bat or axe draw is a wasted play for it (even with their damage set to 100000 the simulated nights are identical, the bench in this branch). At weight 1 each the average solo median round fell from 14 to 8 (out of its 10 to 14 range); at 0.5 it stays 14 to 15 on two seed sets. The gate therefore bounds the melee weights, not their strength, (those figures are from before the carry). The simulator models the two-weapon carry of #410 since: its players give up the weakest weapon only for one worth 1.5 times more, and the average solo median round fell from 14 to 8 to 10 with it until the stampede was cut from 140% to 110% of the count, which brought the gate back. The bat and axe are cut strong (150 and 167 a second against the crowbar's 82) by design reasoning, for a slot that a firearm could have had ([the roster](../design/weapons.md#the-roster)) |
| Leaving | Never in the first 3 plays at a spot (`safe_plays`), then 15% for four plays, 30% for four, then 50% (`leave_chances`) | The Mystery Box's table, as quoted. We have four places, not a whole map, and a night is shorter, so it is a place to watch, not a promise |
| Breakdown | The crane "breaks down": a moth-eaten plush shows (our dud), sparks, a power-down; the price is refunded in full (`refund_fraction`); 4 s later it is gone (`breakdown_seconds`) | Original dud prize and effect in place of the bear |
| Relocation | One of the other spots whose door is open (`spot_doors`); with no other open spot a play cannot break down | The Mystery Box only moves to opened rooms |
| Marking | A light beam, a cheap additive cone, over the crane's current spot | Same job, our look |
| Fire Sale | Not modelled | An event system the game does not have yet; see the issue list in the pull request |

### The spots

Four places, in `docs/design/map.md` ([shop spots](../design/map.md#shop-spots)): the stand (start), the midway, the
open field and the yard. The stand and the midway are behind the concession door, the yard behind its own, the field
needs none. The crane starts in the stand.

### The events

The rules announce every step (the list with fields is in `game_rules.gd`, and the audio and visuals hook on these):
`purchase_made` and `points_changed` on the play, `crane_spin_started`, then either `crane_prize_ready` followed by
`crane_prize_taken` or `crane_prize_lost`, or `crane_breakdown` (with the refund as a `points_changed` of reason
`refund`) followed by `crane_moved`. A take by anyone else is answered with `crane_take_denied`. The snapshot version
is 8.

### The price

See the section "The crane's price" in [the balance simulator](balance-simulator.md): the cost is the one number
the simulator chose.

## How it looks and how to film it

`PrizeCrane` (`game/world/crane/prize_crane.gd`) is built from boxes in code like the lot's other machines, with the
weapons' own models in it: a red cabinet, a glass case of tiny weapons, a claw on a gantry, the **prize bay** over the
case (a lit board behind a framed opening) and a lit marquee. `CraneView` (`game/gameplay/night/crane_view.gd`) stands
it at the spot the server's frame names, set back 1.5 m from that spot's marker, and the crane is a function of the
frame's `crane` ({spot, stage, left, weapon}), so a late joiner sees the same crane. The cabinet is a drawing with no
collision; the wall is `CraneBlock` (`game/gameplay/night/crane_block.gd`) in the world both a server and a client
build, moved by `crane_moved` and by the frame, so the two bodies stop at the same place (#748). The rework of #830
changed the look only: the stages, timings, cycling, blink, dud and the server's state are as they were.

- **The case.** A tiny model of every prize in the pool lies in it, from each weapon's far level (`<model>_far.glb`
  beside the model its hold file names, `holds/<id>.tres`), at half its length in the hands (0.24 to 0.56 m), side on to
  the glass and heaped on a cream floor that rises 0.22 m to the back. Every prize lies there once, then the pool again
  while the case has room (20) and triangles to spare (6,000); a weapon added to the pool with its hold file is in the
  case with no edit, and one without a model yet lies there as a plain dark stand-in. All of them are merged into **one
  mesh with the weapons' palette** (`weapons_palette.png`, the copy with every cell), so the case is one draw call and
  adds no shader: the shipped pool's 9 prizes make 20 tiny models, 5,352 triangles, under the 6,912 of the 48 plush
  spheres they replaced (48 draw calls), and the 17 planned would each lie there at least once. A test builds the case
  from a pool of every weapon with a hold file (12 today: the shipped 9 and #822's three, not prizes yet) and holds
  each one in it, in one mesh, under the plush's triangles. The warm-up's crane and
  the night's share the merged mesh through the engine's resource cache.
- **Spin.** The claw sweeps over the heap, drops, closes and lifts; the weapons cycle on the board inside the bay, one
  every 0.07 s at first and 0.46 s at the end, and the board's light beats with them.
- **Grab.** The board slides out of the front toward the player in 0.7 s (from 0.42 m to 1.12 m in front of the
  cabinet's middle, a small bump as it stops) with the chosen weapon on it, side on, muzzle to the player's right,
  at its length in the hands times 1.1 (0.7 to 1.2 m), turning 7 degrees either way at most so it is never seen end
  on. It blinks, with the board, for the last 3 seconds; after the window the board goes back in, empty.
- **Breakdown.** The board slides out with a moth-eaten plush (our dud) on it, sparks fly from the bay, the marquee and
  the light flicker and the power goes; the crane then sinks where it stood and rises at the next spot.
  The card at the glass says `OUT OF ORDER: REFUNDED` to everyone while it does (the buyer's `YOUR PRIZE IS COMING`
  is for the dig only), read from the frame's crane stage, so the wire is unchanged.
- **Beam.** A cheap additive cone (a ten-line shader: bright at the foot, fading up, blended additively, no depth
  write) stands over the crane's spot from the top of the marquee, so the way to it is a column of light in the night.
  It rises to the first solid over the crane and no further (#911): the cone was a fixed 36 m, and the depth test
  only hides what lies behind a surface from the camera, so from a floor or a roof over the crane the column came out
  of the slab (the concession's roof, the second map's upper floor). `CraneView` casts one ray up from the marquee
  (`PrizeCrane.beam_length_over`, world layer) when it puts the crane at a spot, and `set_beam_length` shortens the same
  cone (same taper, one uniform `cut`, a fade over the last 1.5 m, or 0.6 of a shorter beam). A crane under a ceiling
  3.2 m high has a 0.39 m beam: a glow on the marquee. No ray runs in a frame, and no mesh, light or program is added.
  `tests/world/test_crane_beam.gd` casts the same ray from every crane spot of both maps and checks that nothing solid
  stands inside the beam and that a solid ends it; `tests/captures/box_beam_views.tscn` shoots every spot from the floor
  in front, from the first solid over it and from across the lot.

### Why the prize comes out at eye height (#830)

The prize used to float on a stage 3.25 m up, over the marquee, turning about its upright axis in front of the foot
of the beam. From the shoulder camera of a player on the crane's marker (0.8 m from the glass, where the use prompt
is) that stage was at the top edge of the frame, half of every turn showed the weapon end on, and the beam's brightest
part washed it out; the Soldier's body covers the middle of the machine below its head. It had only been filmed from
1.6 m back and 1.2 m aside with the camera pitched down to frame the whole machine.

The board's middle is at 1.95 m and its bottom at 1.72 m: over the Soldier's hair (0.36 m over the `Head` bone) as the
camera sees it from the marker, so the body never covers the prize, and well inside the frame. At grab height
(1.35 m) the head covers 79 to 98 % of every prize. `test_crane_view.gd` measures it on a 1920 x 1080 view of the
player's resting camera on the marker: every prize whole on the screen, at least 10 % of its width (the revolver 13.9 %,
the long guns 20 to 24 %) and at most 10 % of it behind the body (0 % for all eight).

| From the player's view | Before (stage) | After (board) |
| --- | --- | --- |
| Where the prize is, desktop, on the marker | the top edge of the frame, cut by it | the upper middle, whole |
| Turning | a full turn every 7 s (end on twice) | 7 degrees either way |
| Behind it | the beam's foot (additive, the brightest) | a lit cream board: a dark weapon on a light card |
| Crane draw calls / triangles at rest (bench) | 67 / 13,300 | 18 / 6,300 |
| ... in the grab window / the breakdown | 69 / 14,400; 78 / 167,000 | 20 / 7,300; 29 / 8,900 |

The breakdown's 167,000 triangles were its 36 sparks, each a default `SphereMesh` (64 x 32, 4,000 triangles); a
spark is now a small box. The numbers are `tests/captures/crane_cost_bench.tscn` (the crane alone before a camera,
less the same frame without it), run windowed through `gds godot`. The night's load (the warm-up stage, three runs
of each, alternated) was 5,446 to 6,121 ms on `main` and 5,317 to 6,039 ms with the rework: no change beyond the
noise; building the crane takes 52 to 64 ms the first time and 18 to 20 ms with its models cached.

### Filming it

`tests/captures/crane_prize_view.tscn` takes one screenshot from the player's own shoulder camera for every weapon of
the pool as it comes out, the cycling and the dud, standing where a player stands: `--stand=marker` (on the marker),
`back` (1.6 m back, the edge of the reach), `side` (1.3 m aside) or `case` (looking down into the case); `--phone`
draws the touch controls (run it at 2340 x 1080). `tests/captures/crane_tour.tscn` films a whole play from the
shoulder camera (physics ticks, 60 a second): `godot --path game res://tests/captures/crane_tour.tscn --fixed-fps 10
--write-movie out.png --quit-after 700`, with `-- --breakdown` for the breakdown and `-- --beam` for the crane on the
open field. Both switch off the real mouse and keys (`local_input`, `capture_mouse`) so a recording never holds the
person's cursor. `test_crane_view.gd` checks the placement, the cycling and its slowing, the chosen weapon, the dud,
the move, the case's tiny models and the prize on the screen without a window.

## The bot

The autopilot buys a play when the crane stands where it is, a prize is left that the bot lacks and the points cover
the price with ammunition money to spare, waits at the glass through the dig and presses use on the held-out prize
(`Autopilot`, `_waiting_on_crane`). `test_autopilot_night.gd` plays the whole path with no hand action but the points:
walk to the crane on the field, `crane_spin_started`, `crane_prize_ready`, `crane_prize_taken`, the weapon in its
arms.

### The hosted bots at the crane (#1322)

The maintainer, playing: "the bots will use the prize pick (mystery box), but they'll never actually pick up the weapon.
They'll just keep rolling it until eventually leaving." Counted in a real night (`bots_crane_soak.tscn`: four hosted bots
alone in the lot, 15 game minutes, seeds 1 to 4, two at the shipped health and two at five times it, so 16 bot-nights),
on `main` before the fix:

| | Plays | Prizes held out | Taken | Left on the glass | Points into plays |
| --- | --- | --- | --- | --- | --- |
| Before, all bots | 51 | 46 | 12 (26%) | 34 | 28,050 |
| Before, the Rookie (a pistol and a free hand) | 16 | 14 | 2 | 12 | 8,800 |
| After, all bots | 21 | 19 | 14 (74%) | 5 | 11,550 |
| After, the Rookie | 11 | 9 | 4 | 5 | 6,050 |

Where it broke, in the order of how many offers it cost:

- **The decision to take is not the decision to buy** (32 of the 34). The bot paid when *any one* of the seventeen
  prizes was worth taking (`BotEconomy._crane`) and then took the one it was dealt only when that one beat what it
  would give up by `WeaponWorth.REPLACE_GAIN` (1.5). A Rookie with the pistol only takes 7 of the 17 prizes against a
  round-3 walker's health (half the draw by weight) and 3 against round 5's (a quarter). The draw is blind, so most
  plays were dealt a prize the bot's own rule leaves on the glass, and nothing remembered a miss: it paid again at
  once. The bot now pays only when the weighted share of the draw it would take (`BotEconomy.crane_odds`, the weights
  `ShopItem.roll` draws by) is at least `BotProfile.crane_min_odds` (0.25), and lets the prize go at most once a round
  with the weapons it carries (`BotBeliefs.pass_crane`, set by the `crane_prize_lost` event). The bot still weighs a
  prize as before (`worth_taking`, `weighs_by_round`): what changed is that it no longer pays for a hand it expects to
  refuse. Rolls: the number of plays a bot may make is not capped; it is the odds, one miss a round and the box's own
  breakdown.
- **The wait never walked back** (1 of the 34, and every shove). The old wait kept the bot "at the glass" by
  setting a note, not a goal, so a bot a teammate's walk pushed 3 m off (the press reaches 1.5 m,
  `NightTuning.spot_reach`) stood out of reach through the 12 seconds the prize floated, with an empty card. The wait
  now sets the stand and the facing whenever the card is not the crane's (`BotCraneWait`).
  `test_bot_crane.gd` puts the bot 3.5 m off during the dig and checks the card is down, then that it takes the prize.
- **Left for something else** (1 of the 34, and 1 of the 5 after): a bot that is not clear of the dead
  (`BotShop.clear_from`) runs no errand, and a bot that goes to a revive is 60 m away, while the prize floats for 12 s
  whatever the fight is. That is the bot's own choice and is unchanged.

Not the cause, checked: the use press and the guard (every offer a bot wants was taken within the second it showed;
the `replace_settle` of #908 is 0.4 s and the bot presses each think); the bot's reach when it is at its stand (the
card was up for the whole window in 22 of the 32 prizes it declined, and each of the 12 prizes it wanted while in
reach of the glass was taken within two seconds of showing); the use-sites test of #1244 (a bound of the same reaches the
spot offers use: with it merged the three tests of `test_bot_crane.gd` give the same results as without); and the
retune of #1023 (it raised the odds a little: a pistol-only Rookie's share of takeable prizes at round 3 / 5 / 8 went
from 0.43 / 0.17 / 0.39 to 0.50 / 0.24 / 0.54). The rule is older: the free hand weighed by the round is #827
(2026-11-03), the 1.5 margin #566 (2026-11-02), the buy-on-any-prize rule #271 (2026-11-01), and the simulator's
shoppers (`NightSim._crane_can_pay_off`) bought on any prize too, so the model wasted plays in the same way: they follow
the same rule since #1331 ([below](#the-simulators-shoppers-at-the-crane-1331)).

The soak's medians (`tools/bots/soak_report.py`, one Godot process of five nights a chunk, roam, the simulator's
numbers from 60 nights each; the first row of every pair is `main`, the second the fix):

| Cell | Nights (seeds) | Median round | Sim median | Kolmogorov | Spend ratio (sim) | Nights that broke a gate |
| --- | --- | ---: | ---: | ---: | --- | ---: |
| rookie x2, `main` | 10 (1 to 10) | 6 | 5 | 0.38 | 0.67 (0.71) | 0 |
| rookie x2, fix | 10 (1 to 10) | 9 | 5 | 0.68 | 0.68 (0.71) | 0 |
| rookie x2, `main` | 20 (11 to 30) | 7 | 5 | 0.48 | 0.65 (0.71) | 0 |
| rookie x2, fix | 20 (11 to 30) | 6 | 5 | 0.33 | 0.67 (0.71) | 0 |
| regular x2, `main` | 10 (1 to 10) | 12 | 15 | 0.55 | 0.55 (0.75) | 3 |
| regular x2, fix | 10 (1 to 10) | 11 | 15 | 0.35 | 0.66 (0.75) | 2 |
| veteran x2, `main` | 10 (1 to 10) | 13 | 16 | 0.57 | 0.60 (0.71) | 0 |
| veteran x2, fix | 10 (1 to 10) | 16 | 16 | 0.38 | 0.69 (0.71) | 1 |

Ten nights do not rank the fix: the Rookie's median read 6 against 9 on the first ten seeds and 7 against 6 on the next
twenty. What the fix changes for certain is the points a bot spends on the crane (about 1,000 less a bot-night in the
crane soak, which go to the other things on its list: the spend ratio of the regular and veteran cells rose by about
0.1). So the cells of `bots-nightly` that read bot strength (the median within 1.5 of the simulator, the Kolmogorov
distance under 0.2, the spend ratio within 0.20 of the simulator's) can move by a round either way and the spend ratio
by a tenth. The simulator's shoppers were not touched by #1330; they follow the rule since #1331
([below](#the-simulators-shoppers-at-the-crane-1331)). The gates that read the bots'
behaviour (the engine error, stuck and idle gates, the far-from-the-person gate) are not moved: the walk back to the
glass is a note of `crane`, which `SoakWatch.ERRAND_NOTES` counts as an errand.

A person's crane is the rules' and is untouched: the change is in `gameplay/bots/` only.

### The simulator's shoppers at the crane (#1331)

After #1330 the bots paid for a play only at 25% odds, and the simulator's shoppers (the model the crane's price was
tuned against, [the balance simulator](balance-simulator.md#the-cranes-price)) still paid on any one prize worth
taking. The parity reads of `bots-nightly` (#767, #772) set a bot cell beside the simulator's, so the two now spent
differently. The simulator uses the bots' rule, from one place:

- `CraneOdds` (`gameplay/bots/crane_odds.gd`): `share` is the weight of the prizes the shopper lacks and would take over
  the weight of all it lacks (the weights `ShopItem.roll` draws by), `worth_playing` is "some chance, and at least the
  minimum share" and `MIN_SHARE` (0.25) is the default of `BotProfile.crane_min_odds` and of the new
  `SimSkill.crane_min_odds`. `BotEconomy.crane_odds` and `NightSim._crane_share` both call `share`, the first with its
  `worth_taking`, the second with `_worth_taking` (the same `WeaponWorth` test: the weapon beats the weakest carried by
  1.5 times, a free hand against the quick melee).
- `CranePass` (`gameplay/bots/crane_pass.gd`): the round and the weapons carried when a prize was left on the glass.
  `BotBeliefs.pass_crane` keeps one, each `NightSim.SimPlayer` keeps one, and a shopper plays no more in that round
  with those hands. A prize the simulator's shopper does not take (`_play_crane`: it does not beat the weakest weapon)
  is the pass; the model never leaves a prize it wants.
- Not shared, and why: the pool. The simulator takes the ray gun and the freeze gun out of the draw
  (`NightSim.UNMODELLED`, #788), so its shoppers draw among 15 prizes and the bots among 17; the shares are over the
  pool each one plays. The simulator's shoppers are also always at the glass, so there is no walk, wait or reach.
- `test_sim_crane_shopper.gd`: the simulator's share of the draw equals the bots' on a grid of rounds and hands (it
  fails when the two drift apart), a play at a slim chance is not paid for, a pass ends the plays of a round until the
  round or the hands change.

Before and after, the simulator's cells the parity batch reads, plus the balance gate's other cells: 2,000 simulated
nights a cell (two independent sets of 1,000, seeds from 1 and from 5001; the nightly reads 300), the same seeds before
and after, the tree frozen for the run. The mean round has the standard error of 2,000 nights in brackets:

| Sim cell | Median round | Mean round (se) | Spend ratio | Plays a player-night | Share of earnings into the crane |
| --- | --- | --- | --- | --- | --- |
| weak x1 | 5 to 5 | 5.57 (0.06) to 5.61 (0.06) | 0.693 to 0.679 | 2.17 to 2.01 | 0.250 to 0.226 |
| weak x2 | 5 to 5 | 6.20 (0.05) to 6.32 (0.06) | 0.712 to 0.704 | 2.33 to 2.18 | 0.291 to 0.258 |
| weak x4 | 5 to 5 | 6.64 (0.06) to 6.83 (0.06) | 0.723 to 0.717 | 1.69 to 1.63 | 0.214 to 0.191 |
| average x1 | 12 to 12 | 11.39 (0.09) to 11.36 (0.09) | 0.678 to 0.658 | 3.52 to 2.80 | 0.107 to 0.086 |
| average x2 | 14 to 15 | 13.10 (0.06) to 13.39 (0.06) | 0.737 to 0.729 | 3.60 to 2.65 | 0.117 to 0.083 |
| average x4 | 16 to 16 | 15.12 (0.06) to 15.52 (0.05) | 0.796 to 0.788 | 2.68 to 1.93 | 0.077 to 0.052 |
| strong x1 | 18 to 18 | 16.54 (0.09) to 16.64 (0.09) | 0.653 to 0.635 | 3.95 to 2.96 | 0.060 to 0.044 |
| strong x2 | 19 to 19 | 18.96 (0.06) to 19.16 (0.05) | 0.706 to 0.690 | 3.83 to 2.73 | 0.058 to 0.040 |
| strong x4 | 21 to 21 | 20.77 (0.04) to 20.82 (0.03) | 0.700 to 0.685 | 2.62 to 1.88 | 0.038 to 0.027 |
| average x8 | 17 to 18 | 16.85 (0.05) to 17.14 (0.04) | 0.806 to 0.797 | 1.48 to 1.11 | 0.038 to 0.027 |

- **The medians hardly move; the means rise a little.** One median moves a whole round (average x2, 14 to 15) and one
  more at the top (average x8, 17 to 18). The mean round rises in 9 of 10 cells and by more than two standard errors of
  the difference in five: average x4 +0.40 (5.0 standard errors), average x8 +0.28 (4.3), average x2 +0.29 (3.2),
  strong x2 +0.20 (2.6), weak x4 +0.19 (2.3); the rest are within it (average x1 is -0.02). A player who keeps the
  points of the plays it no longer makes buys the rest of the list sooner. Nothing leaves its range in `BalanceTargets`:
  the gate's own cells, 60 nights from seed 4000 (what `test_balance_targets.gd` reads), read weak 5, average solo 10,
  average x2 15, average x4 16, average x8 16 to 17, strong solo 17, as before but for the last, one round up.
- **The plays fall by a fifth to three tenths** in the average and strong cells (average solo 3.5 to 2.8 a player-night,
  strong solo 4.0 to 3.0) and by 3 to 8% for the weak shopper. The share
  of earnings that goes into the crane falls by 0.011 to 0.035 and the spend ratio by 0.006 to 0.020 in every cell: the
  points of the plays not made are kept.
- The price of the crane (550) is not touched, and nothing here asks for it: no gate cell comes closer to an edge by it
  (strong solo, 17 of 19 at the gate's seeds, 18 at 2,000 nights, did not move). A retune is the maintainer's.

Against the bots (`bots_soak.tscn`, `soak_report.py`, roam, seeds 1 to 20: **20 nights a cell**, 180 bot-nights, with
`main` after #1330; the bots are the same before and after this change, so one run serves both columns). The Kolmogorov
distance of 20 nights against a simulator cell has a 5% noise of 0.30 by itself, so a cell crossing 0.2 on this table
says nothing; the 100-night nightly is the read for that. The simulator's medians here are capped at round 16, as the
nightly reads them (the table above is not):

| Cell | Bot nights | Bot median (mean) | Sim median before / after | Sim mean (se) before / after | Kolmogorov before / after | Bots' spend ratio | Sim before / after | Crane share: bots / sim before / sim after | Parity read before / after |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| rookie x1 (sim weak) | 20 | 6 (5.7) | 5 / 5 | 5.57+-0.06 / 5.61+-0.06 | 0.20 / 0.20 | 0.77 | 0.69 / 0.68 | 0.273 / 0.250 / 0.226 | off / off |
| rookie x2 (sim weak) | 20 | 7 (7.4) | 5 / 5 | 6.20+-0.05 / 6.32+-0.06 | 0.47 / 0.47 | 0.68 | 0.71 / 0.70 | 0.254 / 0.291 / 0.258 | off / off |
| rookie x4 (sim weak) | 20 | 5 (6.0) | 5 / 5 | 6.64+-0.06 / 6.83+-0.06 | 0.18 / 0.22 | 0.46 | 0.72 / 0.72 | 0.196 / 0.214 / 0.191 | ok / off |
| regular x1 (sim average) | 20 | 10 (10.9) | 12 / 12 | 11.36+-0.09 / 11.33+-0.09 | 0.15 / 0.15 | 0.74 | 0.68 / 0.66 | 0.078 / 0.107 / 0.086 | off / off |
| regular x2 (sim average) | 20 | 12 (12.3) | 14 / 15 | 13.02+-0.06 / 13.27+-0.06 | 0.22 / 0.27 | 0.66 | 0.74 / 0.73 | 0.052 / 0.117 / 0.083 | off / off |
| regular x4 (sim average) | 20 | 11 (11.3) | 16 / 16 | 14.66+-0.05 / 14.95+-0.04 | 0.63 / 0.68 | 0.55 | 0.80 / 0.79 | 0.043 / 0.077 / 0.052 | off / off |
| veteran x1 (sim strong) | 20 | 16 (13.6) | 16 / 16 | 14.54+-0.06 / 14.54+-0.06 | 0.22 / 0.23 | 0.72 | 0.65 / 0.63 | 0.062 / 0.060 / 0.044 | off / off |
| veteran x2 (sim strong) | 20 | 16 (14.0) | 16 / 16 | 15.73+-0.02 / 15.78+-0.02 | 0.35 / 0.37 | 0.72 | 0.71 / 0.69 | 0.046 / 0.058 / 0.040 | off / off |
| veteran x4 (sim strong) | 20 | 16 (15.9) | 16 / 16 | 15.97+-0.01 / 15.97+-0.01 | 0.05 / 0.05 | 0.73 | 0.70 / 0.68 | 0.027 / 0.038 / 0.027 | ok / ok |

- The crane's share of what the bot earns is closer to the simulator's in 7 of 9 cells (bots / simulator before / after:
  regular x2 0.052 / 0.117 / 0.083, rookie x2 0.254 / 0.291 / 0.258, regular x1 0.078 / 0.107 / 0.086) and further in 2
  (rookie x1, veteran x1: a bot that spends 0.27 and 0.06 against a simulator that now spends 0.23 and 0.04).
- The total spend ratio is not the crane's: the simulator's moved toward the bots' in 3 cells (rookie x2, regular x2,
  regular x4), stayed in 1 (rookie x4) and moved away in 5, by 0.02 at most, in the cells where the bots already spend
  more than the simulator (rookie x1, regular x1, the three veteran cells). The spend gate (within 0.20) fails for
  rookie x4 (the bots spend 0.46 against 0.72) and regular x4 (0.55 against 0.80), before and after.
- What the parity reads still show is not the crane: the Regular's median is 2 to 5 rounds under the simulator's
  average player at x2 and x4 (12 against 15, 11 against 16), as it was; it is the bots' own strength, left to the
  issues on the bots.
- The pass is all the memory the model has: a shopper dealt a prize it left plays no more that round with those hands,
  and one that won plays again when its list says so (the weak list has two plays). The bots' pass also covers a prize
  they wanted and missed (the reach, a fight); the model's never does, so a bot can still play less than the model in
  a night of fights.

## Open

- Time the real thing in a capture to replace every **estimated** above (spin length, cycle speeds, the window).
- Fire Sale: a second event on the same rules (price 10, every spot at once, no breakdown) once the game has timed
  events.
- Whether the other players should be able to take a prize the buyer left for the last seconds (some titles allow it).

## The first roll was always the shotgun (#685)

Players said the crane gave the shotgun first too often and not every weapon. The pool held all eight weapons and the
draw is fair: over 10,000 first rolls of a buyer who carries the revolver (seven prizes, weights 4, 3, 2, 1, 0.5, 0.5,
1 of 12) the shares were shotgun 33.0 to 33.7%, rifle 24.8 to 25.4, SMG 16.6 to 16.7, flare gun 8.4 to 8.6, bat 3.8 to
3.9, axe 3.9 to 4.3, crowbar 8.3 to 8.6, for seeds 0 to 9999 and for random ones. The cause was the seed: a solo night
always started from `Night.SEED` (1958), whose crane draws, for that buyer, are shotgun, rifle, SMG, rifle, flare gun,
shotgun, SMG, flare gun. Every person's first play gave the shotgun, and the bat, the axe and the crowbar did not come
in their first eight. A solo night now starts from a fresh seed (the game server always did). What stays: the weights
give the shotgun a third of first rolls, the highest share; that is the balance choice above, not a bug.
