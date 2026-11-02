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

`PrizeCrane` (`game/world/crane/prize_crane.gd`) is built from boxes and spheres, no asset: a red cabinet with a glass
case, a pile of plush prizes, a claw on a gantry, a lit marquee. `CraneView` (`game/gameplay/night/crane_view.gd`)
stands it at the spot the server's frame names, set back 1.5 m from that spot's marker, and the crane is a function of
the frame's `crane` ({spot, stage, left, weapon}), so a late joiner sees the same crane:

- **Spin.** The claw sweeps over the pile, drops, closes and lifts; weapon models cycle above the glass, one every
  0.07 s at first and 0.46 s at the end (the Mystery Box slows the same way). Every prize shows its own model
  (the rifle, the shotgun, the tommy gun that is the `smg`, the flare gun at half the length); a prize added to the
  pool without a model is a plain silhouette until it has one (`PrizeCrane.MODELS`, checked by a test).
- **Grab.** The chosen weapon rises from the claw to the stage and floats, blinking for the last 3 seconds.
- **Breakdown.** A moth-eaten plush (our dud) shows on the stage, sparks fly, the marquee and the light flicker and the
  power goes; the crane then sinks where it stood and rises at the next spot.
  The card at the glass says `OUT OF ORDER: REFUNDED` to everyone while it does (the buyer's `YOUR PRIZE IS COMING`
  is for the dig only), read from the frame's crane stage, so the wire is unchanged.
- **Beam.** A cheap additive cone (a ten-line shader: bright at the foot, fading up, blended additively, no depth
  write) stands over the crane's spot, so the way to it is a column of light in the night.

`tests/captures/crane_tour.tscn` films it from the player's shoulder camera (physics ticks, 60 a second):
`godot --path game res://tests/captures/crane_tour.tscn --fixed-fps 10 --write-movie out.png --quit-after 700`, with
`-- --breakdown` for the breakdown and `-- --beam` for the crane on the open field. `test_crane_view.gd` checks the
placement, the cycling and its slowing, the chosen weapon, the dud and the move without a window. The tour switches
off the real mouse and keys (`local_input`, `capture_mouse`) so a recording never holds the person's cursor.

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
