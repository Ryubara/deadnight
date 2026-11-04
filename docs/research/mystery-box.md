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
