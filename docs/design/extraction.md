# Extraction

**A proposal for the maintainer's approval (#1056). Nothing on this page is built.** A night can be won: each map has a
kill quota and a chain of steps of its own, and with both met the team calls a helicopter and leaves. The numbers here
were measured with the real player body, real bots and real nights (`game/tests/captures/extraction_probe.tscn`), and
each one says how.

The maintainer's ask, 2026-11-04: every map has a quota and a set of steps, unique to that map, that must be done
before the team can extract. The players are an elite military unit that a helicopter drops off to clear out the dead
and fix up the area before they extract. The map's steps must not be too easy, and are expanded if they are. Before
that, he pointed out that players would get bored of a night that has no way to win at all.

## What I need from you

Each point below is a choice with a recommendation; the build waits for your answers.

| # | Choice | Recommended | Where |
| ---: | --- | --- | --- |
| 1 | The quota's size and how it scales | 200 kills on the lot and 100 on the back rooms for one player, up 60% a player, the same at every count modifier | [The quota](#the-quota) |
| 2 | The tally stops at each stage until the steps are done | Yes | [The quota](#the-quota) |
| 3 | The lot's chain | *Light the LZ*, seven stages | [The lot](#the-lot-light-the-lz) |
| 4 | The back rooms' chain | *Raise the roof*, six stages | [The back rooms](#the-back-rooms-raise-the-roof) |
| 5 | How extraction plays | Hold a ring for 90 s, then a rope | [Extraction itself](#extraction-itself) |
| 6 | A downed player, a late joiner, after the rope | Carried if in the ring; a late joiner wins but the frame needs the last stages; the night ends, and the lobby keeps *No extraction* | [Downed, late and leaving](#downed-late-and-leaving) |
| 7 | What a win pays and unlocks | 300 XP, 500 more the first time on each map, one frame a map and one for a harder win | [What a win pays](#what-a-win-pays) |

**The result in one line: the chains are not too easy; the lot is proven winnable, and the back rooms only at double
health.**

| Veteran bots, real nights, wins at the final rules | The lot | The back rooms |
| --- | --- | --- |
| Solo | 1 of 9 | 0 of 9, best stage 6 of 6 |
| Two | 1 of 3 | 0 of 3, best stage 6 of 6 |
| Four | 2 of 9 | 0 of 9, best stage 6 of 6; 1 of 1 at double health at count x1 |

Four Regular bots won 0 of 6, reaching stage 6 of 7 on the lot and 5 of 6 on the back rooms. Bots are not people, and
three nights a cell is a sketch: read these as "it can be done", not as win rates. Bots do not kite, and the tool sends
one bot at a time to each job with no escort, so a person should do better. Nothing here proves **the back rooms at x5**
or **solo at x5** on either map: the bots die in rounds 2 to 4, as they do with no chain at all. See [what was not
proven](#what-was-not-proven).

## What "too easy" means

The worry is the point of this page, so the test was written before the chains were. A chain is too easy when any of
these holds:

| # | Test | How it is run | Passes when |
| ---: | --- | --- | --- |
| 1 | **The floor** | The real player body (`PlayerSimulation`, through `NightServer.apply`), sprinting, every door sold, no dead at all, half a tank and every board down | One body needs 5 minutes or more, and four need 3.5 or more: a team shares the work but cannot share the clocks |
| 2 | **The stall** | A real night in which, from round 8, the team keeps one dead alive so the round never ends and no more of its dead come: the classic way to do a chore in peace | The chain cannot be finished in the quiet |
| 3 | **The night** | Real bots from round 1, earning every door, with the dead that come | Most of the time spent on the chain has a dead within 10 m, it costs downs, and it runs across many rounds |
| 4 | **The farm** | The same nights: kills before the steps | Kills made ahead of the steps bank nothing |

### What the maps have, as they stand, is too easy

Before anything was added, the chains were first built only from what each map has, the way the issue suggests: fill
the tank, throw the three breakers, start the projector on the lot; board the windows and use a radio on the back
rooms. One body in an empty night:

| Chain (nothing added) | Steps done in | With the helicopter's wait |
| ---: | ---: | ---: |
| The lot | 53 s | 121 s |
| The back rooms | 24 s | 86 s |

Under a minute of steps, and every press could be made in the lull of a stalled round. Everything below is the
expansion the maintainer asked for.

## The quota

**The team shares one tally, and it does not run ahead of the steps.**

The quota is the team's kills, by anyone on the team, bots included.

**Choice 1, the size.**

```text
quota = base x (1 + 0.6 x (players - 1))
```

The 0.6 is the rounds' own `count_per_extra_player`, so the quota grows as the dead do.

| Players | The lot (base 200) | The back rooms (base 100) |
| ---: | ---: | ---: |
| 1 | 200 | 100 |
| 2 | 320 | 160 |
| 4 | 560 | 280 |
| 8 | 1,040 | 520 |

On the shipped table, 200 kills is the whole count through round 13 for one player, and 560 the same for four. On the
back rooms both figures fall in round 10: the map's nights are shorter, so its quota is too.

**The count modifier does not raise it.** The kills a team makes before it falls do not grow with the count, so a higher
quota only moves the win past where nights end:

| Kills before the night ended, no chain, 3 nights of Regular bots | x1 | x2 | x5 |
| --- | ---: | ---: | ---: |
| The lot, four | 288 to 543 | 383 to 488 | 492 to 644 |
| The lot, solo | 103 to 183 | 10 to 37 | 12 to 75 |
| The back rooms, four | 53 to 301 | 133 to 296 | 94 to 104 |
| The back rooms, solo | 18 to 105 | 22 to 73 | 23 to 28 |

| Option | At x5, four players, the lot | For | Against |
| --- | ---: | --- | --- |
| **Flat (recommended)** | 560 | A modifier is danger, and it already pays in kills a minute. The same kills arrive in fewer rounds | A x5 win is short: the one measured took 15 minutes against 22 to 24 |
| With the cube root of the count | 958 | Reads fairly on paper | Measured: four veterans ended on 575, 314 and 958 of 958 (the last won) |
| With the count | 2,800 | Simple | Out of anyone's reach |

The quota is set when the night starts and rises by the same rule when a player joins. It never falls when one leaves:
the tally is already earned.

**Choice 2, the tally stops at each stage.** Each stage has a tier, a share of the quota. The tally stops at the next
tier until the steps of the stage before it are done.

| Option | What it does | For | Against |
| --- | --- | --- | --- |
| **Stops at a tier (recommended)** | Kills past the tier count for nothing yet: the card says *Finish the step to clear further* | The steps and the kills stay together to the end, and a farm banks nothing. Four veterans on the lot at x1 made 697 to 794 kills for a tally of 560, and at x5 one team made 1,417 for 252 | A team can feel held back, so the card has to say why |
| Kills and steps apart | Any order | Simple to read | A team farms the quota at a choke, then does the steps with the map empty |

The tiers also close the old trick of keeping one dead alive to work in peace: no dead, no kills, and the tally stops
the chain ([the stall](#how-it-was-measured)).

## The lot: Light the LZ

The pilot will not put down on a dark lot. The team restarts the generator, runs power back out to the lot, gets the
projector working and puts a signal on the big screen that can be seen for miles, then marks the avenue, the one long
clear strip of ground on the map, as a landing zone. It is built on what the lot already has (the generator, the fuel,
the circuits, the doors, the booth and the avenue) and it is a chain of **distance, fuel and light**: every door has to
be bought, and the work crosses the whole lot.

![The lot's chain on the plan](extraction-lot.png)

Stages open in order; the steps of a stage can be done in any order and at once. *Noise* is the dead a step calls when
it starts, as a share of the round's own count, so it scales with the round, the players and the modifier. A loud step
in a break ends the break.

| Stage | Tier | The step | Work | Behind | Noise | Built on | New |
| ---: | ---: | --- | ---: | --- | ---: | --- | --- |
| 1 | 0 | Restart the generator, and fill the tank | 20 s, then cans | Yard door | 25% | Generator, fuel | The service job |
| 2 | 15% | Three breakers: stand, booth, back lot | 10 s each | Booth and back lot doors | 15% each | The posts and circuits | A press becomes a 10 s job |
| 3 | 30% | The load test: every circuit on, tank not dry | 45 s, starts over if dry | | 25% | Circuits, fuel | The clock |
| 4 | 45% | Carry the lamp from the plaza's wreck and the reel from the back office to the projector | 5 s to lift, 5 s to fit | Road and back lot doors | 25% each | The booth | Two loads |
| 5 | 60% | Roll the film: the signal lights the screen | 75 s, gun down | Booth door | 50% | Projector, screen | The clock, the signal |
| 6 | 80% | Four flares down the avenue | 5 s each | | 25% once | The avenue | Flares |
| 7 | 100% | Call the bird, hold the ring on the avenue | 90 s, guns up | | 50% | The avenue | The hold |

Hands are full on a carry: no shot, no sprint. **A blow knocks the load out of the hands**, where it lies with a marker
until someone lifts it again, in a second. (The first rule was that a dead within 3.5 m made the carrier put it down: by
round 12 one always is, and small teams rarely got the lamp to the booth.)

The chain needs every door, because the road door needs the back lot's and that needs the booth's: 4,850 points in all.
That is the map's own opening order, so the chain and the doors pull the same way, and the points compete with guns and
tonics.

| Step, 21 nights | Nights it opened | Finished | Minutes (median) | Downs while open |
| --- | ---: | ---: | ---: | ---: |
| Generator, tank | 20 | 18 | 0.4 | 2 |
| Breakers | 17 or 18 | all | 0.3 each | 0 |
| Load test | 17 | 15 | 0.8 | 9 |
| The reel | 15 | 11 | 0.7 | 11 |
| **The lamp** | 14 | 8 | **2.9** | **21** |
| Roll the film | 8 | 6 | 1.8 | 11 |
| Flares | 6 | 6 | 0.3 to 0.6 each | 1 each |
| The hold | 6 | 4 | 1.6 | 6 |

A down counts for every step open at the time. The first three stages are easy on purpose: they come while a team is
learning the night, and the chain's first beat should be won. The lamp is the crux, and six of the fourteen nights that
reached it ended before it arrived; it took from 33 s to 280 s of walking. The load test costs little by itself: its
downs are the round that happened to be running while it counted.

The captures, from the player's camera, lit and with the circuits off: the generator, the projector, the avenue and the
back office read (the office only with its circuit on, which stage 2 has seen to). **The wreck in the plaza does not**:
it stands in the dark in both, so the lamp needs a light of its own or nobody will read it as the place (P9).

## The back rooms: Raise the roof

The depot has no power and nothing that shows from the air, and a helicopter cannot land in its walled yards. The team
seals the building to buy time, gets the depot's old radio working off a truck battery, strings an aerial, calls the
bird in, then blows the wall out onto the hall's flat roof and holds it until the rope comes down. It is built on what
this map has (the windows, the floors, the ring of links, the terrace) and it is a chain of **contact**: nothing is far,
every leg passes a window, and the last stand is outside, on a roof the dead already know the way to.

![The back rooms' chain on the plan](extraction-back-rooms.png)

| Stage | Tier | The step | Work | Behind | Noise | Built on | New |
| ---: | ---: | --- | ---: | --- | ---: | --- | --- |
| 1 | 0 | Seal the building: all six windows at three boards or more at once | 5 s held | All three links | none | Windows, boards | The state to hold |
| 2 | 15% | Carry the battery from the hall and the set from the side room up to the radio | 5 s to lift, 5 s to fit | The links | 25% each | The ring | Two loads |
| 3 | 35% | String the aerial: the two ends, upstairs | 12 s each | The stairs | 15% each | The upper floor | The aerial |
| 4 | 60% | Call it in on the radio | 90 s, gun down | The stairs | 50% | | The clock |
| 5 | 80% | Charge the south wall: it blows the window out onto the terrace | 30 s | The stairs | 50% | Window `upper_a2` | The blown wall |
| 6 | 100% | Hold the roof, the terrace, until the rope comes | 90 s, guns up | | 50% | The terrace | The hold |

The seal is the map's own step, and it needed tuning: at five boards all three x5 nights ended on it. Three boards got
14 of the 17 teams that opened it past it, in 1.3 minutes (median). At x5 nights still end there. Once done it holds
nothing up: the windows are free to fall again.

| Step, 22 nights | Nights it opened | Finished | Minutes (median) | Downs while open |
| --- | ---: | ---: | ---: | ---: |
| Seal | 17 | 14 | 1.3 | 17 |
| Battery, set | 14 | 14 | 0.3 and 0.5 | 2 each |
| The aerial | 14 | 12 | 0.3 each | 5 each |
| **The call** | 11 | 7 | **2.3** | **27** |
| The charges | 7 | 4 | 0.7 | 5 |
| **The hold** | 4 | 1 | 1.5 | 9 |

The counts take in the one night at double health, the only one to finish the hold. The call is the crux: 90 s with the
gun down, in a room with a window. The roof is the hardest place in either chain: three nights at real health reached it
and none left.

The captures: the radio's corner, the hall, the side room and the south wall all read, and all are lit. The **terrace is
the darkest place either chain uses**, its deck almost black (P11). Since the last stand is there, it needs light: the
bird's searchlight, and flares of its own. The lamps of this map have no circuit, so its dimmest state and its lit one
are the same frame.

**This one is a layout change.** The blown wall gives the roof a way into the building. Before it lands, the map's
review runs again on every door state: the escape sweep (P14), the roost probe (P15) and the openings' table (P19). The
measured holds crossed the wall by a short teleport of the tool, because the walking mesh has no way through it yet.

## Extraction itself

**Choice 5, how it plays.** With the chain done and the tally at the quota, a player calls the bird with a press at the
last step: the team can reload and spread out first, then start the clock when it is ready. (The tool starts it at once,
so a person's hold starts better than the measured one.)

| Option | What it does | For | Against |
| --- | --- | --- | --- |
| **Hold a ring, then the rope (recommended)** | 90 s inside a ring (12 m on the avenue, 7 m on the terrace), with half a round's dead called in. The clock pauses with nobody in the ring. At zero the rope comes, and everyone in the ring leaves | The last stand the night has been building to, and one clear place to run to | A team stands in one place at the end of a night of moving, so the ring has to be big enough to run in |
| A timer | The bird lands after a clock, wherever the team is | Nothing to build | No shape: the end plays like any other minute |
| One at a time | The rope lifts one player each 15 s | The last player alone is a great moment | Long for four, and a slow player can lose a night's win to who got on first |

**The hold's noise, one number for every team:** half a round's dead. A whole round's ended every small team's hold in
the first nights. It is a share of the round, so it scales by itself.

| Holds at the final rules, veteran bots | Reached | Finished | Downs |
| --- | ---: | ---: | ---: |
| The lot (three by a team of four, two solo, one by two) | 6 | 4 | 6 |
| The back rooms | 3 | 0 | 8 |
| The back rooms, four at double health | 1 | 1 | 1 |

Bots are held on one spot by their order and cannot run the ring, so a person's hold should go better. If everyone falls
during the hold, the night is lost as it is today, and the report says how near it was: *The bird was 12 s out*.

## What the team sees and hears

The chain uses the homes the game already has, and nothing stays on the screen that is not changing (the maintainer's
rule: panels for slow progress appear on change and leave).

| What | Where | Notes |
| --- | --- | --- |
| The next step, in words | `HudObjective`, top left: one line, *Restart the generator* | The card exists; a stage with several steps says how many are left |
| Where to go | `HudMarkers`: the objective diamond, the distance and the edge arrow | Each step in reach of the team has a marker; a dropped load has one too |
| The tally | A card beside the round: `AREA CLEARED 168 / 560`, shown when it moves after a pause and when a tier fills, then gone | When it stops at a tier it says why: *Finish the step to clear further* |
| A step done | `HudBanner`, one line, and a soldier's line for everyone (the voice source is #252) | *Generator's running*, *Power's out to the lot*, a pilot's voice for the call |
| The world answers | The map changes, not only the HUD | The lot's lamps come on area by area, the screen lights with the signal, the flares burn down the avenue. In the back rooms the boards are the read, then the radio's chatter, then the wall goes |
| Noise | A loud step's dead come by the openings, as any dead do | The spawn rule (a walk from behind an opening) does not change: a surge is more of the round, never a pop |
| The bird | The sound and the model of #1057 | Heard far off at the call, closer through the hold, its searchlight on the ground for the last 30 s |

The steps can be done by anyone, and only bots need teaching: a bot will not start a step by itself, so a solo player's
bots and an all-bot night need the claim rule the bots already use for the back rooms' links (the nearest free bot takes
the job).

## Downed, late and leaving

**Choice D1, a downed player at the rope.** The rule that decides how the last 30 seconds feel.

| Option | What it does | For | Against |
| --- | --- | --- | --- |
| **Carried (recommended)** | Everyone inside the ring when the rope comes leaves, up or down; a player who bled out and anyone outside the ring does not | The team's last act is getting a friend into the ring, and a revive in the last seconds is the best moment the night can have | A downed player does nothing for the last seconds, as today |
| Up only | Only players on their feet leave | Harsher, and the revive still matters | A body a metre from the rope when the clock ends loses the whole night to bad luck |
| All of the team | Anyone alive anywhere is pulled out | Nobody is left behind | The hold stops asking anything of the players: nothing to fight for |

**Choice D2, a player left behind.** A win is a player's, not the room's: a player left behind has not extracted. With
**Carried** that takes bleeding out or staying outside on purpose. Recommended: they watch the end of the night and get
the night's XP without the win's. A team that all dies during the hold loses the night as it does today, and keeps
everything but the win: the report says how near they came (see below).

**Choice D3, a late joiner.** The join rule does not change ([the lobby](lobby.md)): a newcomer comes in by the drop
of #1057, into the tally and the step the team is on.

| Option | What it does | For | Against |
| --- | --- | --- | --- |
| **Win on the rope, the frame for the last stage (recommended)** | Anyone who leaves on the rope has won and is paid for it; the map's frame needs the player to have been in the night since the stage before the last | A friend who joins for the end is welcome and is paid; the rare frame still means something | Two rules to explain, one line each on the report |
| One rule: on the rope wins all | Simple | Nothing to explain | Waiting in a lobby for the last minute of a stranger's night buys the frame |
| Present for half the quota | Strict | Nothing is bought | A friend joining at round 12 is punished for it |

**Choice D4, a player who leaves or drops.** The tally and the steps are the team's, so nothing is lost when a player
goes. Recommended: a load they carried drops where they stood and keeps its marker. A player who drops and rejoins is
the same player (the seat comes back as it does today).

**Choice D5, after extraction.**

| Option | What it does | For | Against |
| --- | --- | --- | --- |
| **The night ends, with a win (recommended)** | The rope ends the night for everyone in it. The end of a night (#973) plays with the helicopter in the first angle and a win's title | A win is an ending: the thing the maintainer asked for. No new state in the server | A team on a great run stops there |
| The team votes to stay on | At the call, the team may choose to stay; the steps are spent and the rounds go on | The people who wanted endless still have it in the same night | A second ending to design; a win is not an ending any more |
| Endless stays as a lobby setting | The lobby keeps a *No extraction* setting: tonight's game, unchanged | The endless night is not taken away, and it costs almost nothing to keep | One more setting; XP per night differs a little |

Recommended together: the night ends at the rope, **and** the lobby keeps *No extraction*, off by default. A team can
also simply not call the bird: the steps are not forced on anyone, and the night goes on until they fall.

## How long a winning night should take

| A night | Rounds | Minutes |
| --- | ---: | ---: |
| Today, four Regular bots, no chain, the lot | 10 to 13 | 14 to 18 |
| Today, the simulator's average four (with menus) | 14.8 | 16 |
| Today, the simulator's strong four (with menus) | 20.7 | 25 |
| **A win on the lot, four veterans** | 13 and 14 | **22 and 24** |
| A win on the lot, two veterans | 13 | 22 |
| A win on the lot, one veteran at x2 | 10 | 22 |
| A win on the back rooms, four veterans at double health | 12 | 14 |

A win takes about as long as a strong team's night does today. The chain's own minimum, with no dead at all, is about a
quarter to a third of that:

| The least it can take: real bodies, no dead, doors open, half a tank, boards down | One | Two | Four |
| --- | ---: | ---: | ---: |
| The lot | 403 s | 333 s | 303 s |
| The back rooms | 303 s | 268 s | 265 s |

**How many people:** one can do every step. Four save 100 s on the lot and 38 s on the back rooms, since the clocks
cannot be shared.

## What a win pays

**Choice 7, XP.** The chain takes time, so unless the win pays, a winning night pays less an hour than dying does today.
On the design's lines a seat in a win on the lot gets about 530 XP: 20 a round reached, about 1 a kill, 15% for the
rest. That night takes about 26 minutes with its menus, so about 1,220 XP an hour against 1,740 to 2,320 for today's
nights.

| Option | A win pays | XP an hour on the lot | For | Against |
| --- | --- | ---: | --- | --- |
| **300, and 500 the first time on each map (recommended)** | 300 XP each win; once per map, 500 more | About 1,900 | A win brings the night up to the going rate and does not outrun it; the first win is about one top level | A short win on the back rooms pays more an hour (about 2,700). It is rare, and the cap holds it |
| Scaled by the modifier | 300, 450, 600 at x1, x2, x5 | About 1,900 and up | Pays the brave | A first win at x5 goes past the 1,500 XP cap, so the cap needs a rule |
| None | The night's own XP | About 1,220 | No new line | Winning costs a player XP an hour, the wrong way round |

All of it sits inside the 1,500 XP a night of [progression](progression.md): 530 + 300 + 500 is 1,330. These are worked
from the design's lines and the kills above, not played.

**The frames (#1072).** A frame is shown only to those who did it, so it should stay rare but not impossible.

| Option | What it gives | For | Against |
| --- | --- | --- | --- |
| **One frame a map, and a second for a harder win (recommended)** | Any win gives the map's frame. A win solo with no bots, or at x5, gives its second | One sentence each; the hard frame is what a good team plays for | A second art job on each map |
| One a map | Any win | Least work | Nothing to chase after the first win |
| One for each modifier | Three a map | Many goals | Six frames, and a plate cannot say much more than two can |

A win with bots filling seats counts. By D3, the frame needs the player in the night from the stage before the last.

## The build, once approved

Split into issues only after the maintainer has answered the choices above; none is filed yet. In order:

1. **The chain's rules.** `ExtractionChain`, a resource per map: stages, steps, tiers and the tally that stops at a
   tier, in the rules with no node, and in the snapshot for a late joiner. The tests port from `extraction_probe.gd`.
2. **The steps' four kinds in the world.** Work at a place, carry, every window sealed, the circuits' load test;
   markers, prompts and the use-sight and spacing tests of each place, on both maps.
3. **The noise.** A step's dead as more of the round, through the openings, and the break it ends.
4. **Extraction itself.** The call, the ring, the hold and the rope; D1 and D2; a win in `game_over`'s place, with the
   end of a night's title and first angle.
5. **The lot's dressing:** the lamp in the plaza's wreck, the reel in the back office, the flares, the screen's signal.
6. **The back rooms' dressing:** the battery, the radio, the aerial's two ends, the wall and the blown opening. This one
   is a layout change: the roof gains a way into the building, so the escape sweep, the roost probe and the opening
   table run again on every door state before it lands (the map's review, P14, P15 and P19).
7. **The HUD and the sound.** The tally card, the objective lines, the banners; the bird's approach (with #1057), the
   step lines (with #252).
8. **The bots.** Claiming a step by distance, carrying, standing a ring, and a soak of four bots that reaches the rope.
9. **The win in the numbers.** XP (#1058's table), the night report's line (#1068), the frames (#1072), telemetry, and
   the simulator's model of a chain so the numbers below can be retuned from real nights.

## How it was measured

The tool is `game/tests/captures/extraction_probe.tscn`, with the chains as data in `extraction_chains.gd`. Nothing of
it ships (`tests/*` is out of the export). It runs the real server in a real night: real bodies, real bots, real doors
bought with real points, real boards through the real `use` press. What it conducts is what does not exist yet: it sends
a bot with the same `HOLD` order a person gives, keeps its trigger up while it works, and adds a step's noise to the
round's plan.

The tests were set before the chains were written:

| Test | Passes when | Result |
| --- | --- | --- |
| 1. The floor | One body 300 s or more, four 210 s or more | **Passes:** 403 and 303 s on the lot, 303 and 265 s on the back rooms |
| 2. The stall | The chain cannot be finished in the quiet | **Passes:** after 30 minutes the lot stood at stage 3 of 7 kept alive from round 8 (tally 186 of 560) and stage 4 from round 12 (336); the back rooms at stage 3 of 6 from round 8 (144 of 280) and stage 4 from round 9 (213) |
| 3. The night | Most of the chain's time has a dead within 10 m, it costs downs and crosses many rounds | **Mostly.** Four veterans on the back rooms 57 to 66%, on the lot at x1 67%; the lot's other cells 37 to 52%, since a chain of distance has quiet walks, and the four Regular bots 36 and 41%. Every win ran from round 6 or earlier to round 10 or later |
| 4. The farm | Kills ahead of the steps bank nothing | **Passes:** the tally held at every tier |

In the stall from round 12 one bot stopped short with the lamp and I did not chase why. It does not change the result:
the same stall under the earlier rules finished the lamp and the film and stopped at 374, short of the 448 the next
stage needs.

### The nights

Three nights a cell, seeds 1 to 3, shipped health, the final rules. Veteran bots, and four Regular bots in the last
rows:

| Map | Team | Count | Won | Stage reached | Minutes | Round | Kills | Downs | Chain time with a dead near |
| --- | ---: | --- | ---: | --- | --- | --- | --- | --- | ---: |
| The lot | 1 | x1 | 0 of 3 | 4, 4, 4 of 7 | 15.3, 14.6, 16.7 | 10, 10, 10 | 117, 130, 128 | 1, 1, 1 | 38% |
| The lot | 1 | x2 | 1 of 3 | 7, 7, 4 of 7 | 17.2, 22.0, 13.5 | 9, 10, 7 | 208, 254, 127 | 1, 0, 1 | 52% |
| The lot | 1 | x5 | 0 of 3 | 1, 1, 1 of 7 | 2.3, 5.4, 3.9 | 2, 4, 3 | 27, 96, 64 | 1, 1, 1 | 45% |
| The lot | 2 | x1 | 1 of 3 | 7, 4, 4 of 7 | 22.1, 15.2, 17.7 | 13, 11, 11 | 399, 242, 234 | 2, 2, 2 | 44% |
| The lot | 4 | x1 | 2 of 3 | 7, 7, 7 of 7 | 24.4, 22.3, 23.6 | 14, 13, 14 | 794, 697, 779 | 11, 0, 4 | 67% |
| The lot | 4 | x2 | 0 of 3 | 2, 3, 5 of 7 | 13.7, 20.7, 17.9 | 10, 13, 10 | 597, 1132, 705 | 5, 8, 6 | 37% |
| The lot | 4 | x5 | 0 of 3 | 3, 5, 4 of 7 | 24.2, 13.9, 12.3 | 9, 6, 6 | 1417, 781, 675 | 8, 6, 6 | 49% |
| The back rooms | 1 | x1 | 0 of 3 | 5, 6, 5 of 6 | 9.3, 10.6, 8.8 | 10, 10, 10 | 119, 130, 119 | 1, 1, 1 | 61% |
| The back rooms | 1 | x2 | 0 of 3 | 3, 1, 3 of 6 | 3.3, 2.6, 6.4 | 4, 4, 6 | 46, 39, 89 | 1, 1, 1 | 37% |
| The back rooms | 1 | x5 | 0 of 3 | 1, 1, 1 of 6 | 0.9, 1.3, 2.1 | 2, 2, 3 | 29, 31, 67 | 1, 1, 1 | 0% |
| The back rooms | 2 | x1 | 0 of 3 | 1, 5, 6 of 6 | 10.0, 9.8, 12.5 | 11, 10, 11 | 214, 206, 264 | 3, 2, 3 | 57% |
| The back rooms | 4 | x1 | 0 of 3 | 4, 4, 6 of 6 | 10.8, 9.3, 11.9 | 10, 9, 11 | 353, 290, 445 | 8, 5, 8 | 57% |
| The back rooms | 4 | x2 | 0 of 3 | 4, 4, 3 of 6 | 6.3, 8.9, 6.2 | 6, 8, 6 | 261, 473, 245 | 7, 9, 6 | 66% |
| The back rooms | 4 | x5 | 0 of 3 | 1, 1, 1 of 6 | 2.3, 4.7, 2.4 | 2, 4, 3 | 113, 329, 199 | 4, 9, 5 | 62% |
| The lot | 4 Regular | x1 | 0 of 3 | 6, 2, 4 of 7 | 19.9, 15.9, 22.4 | 13, 11, 14 | 604, 408, 680 | 12, 8, 17 | 41% |
| The back rooms | 4 Regular | x1 | 0 of 3 | 5, 1, 5 of 6 | 10.2, 2.1, 11.8 | 10, 4, 11 | 353, 53, 416 | 6, 4, 15 | 36% |

*Stage reached* is the stage open when the night ended: on the lot, 7 of 7 is the hold.

The chain grew in four steps, each from what a run showed:

| Chain | What changed | Why |
| --- | --- | --- |
| v1 | The maps as they stand | 53 s and 24 s of steps: too easy |
| v2 | The chains on this page, with a five-board seal and a quota that rose with the count | Reached the last stages on the lot; stopped at the seal at x5 on the back rooms |
| v3 | Seal at three boards, longer call and charges, a flat quota, the back rooms' base at 100 | The back rooms reached their roof |
| v4 | A blow drops a load; the hold calls half a round | Small teams rarely carried the lamp, and no small team survived the hold |

Three nights is noise: four veterans on the lot at x5 won 1 of 3 under each of v2 and v3, and 0 of 3 under the easier
v4.

### What was not proven

- **The back rooms at x5, and solo at x5 on both maps.** Bots die in rounds 2 to 4 with or without a chain. The rules
  allow a win; no run shows one. At x5 the lot's four reached stage 5 of 7.
- **A win on the back rooms at real health.** Four veterans won once at double health, in 13.9 minutes. If the first
  real nights say the same, the first things to move are the base (100 to 80) and then the call (90 s to 60).
- **People.** Everything here is bots, and the chain is conducted, not played. The quota, the tiers and the clocks are
  one table, and the first real nights retune it.
- **XP.** Worked from the design's lines, not measured in a report.
- **New props.** No step's place has its prop yet. The places pass the spacing check against every shop, door, window
  and switch on their floor (P10), save the charges, which stand at the window they blow on purpose. Use-sight, the
  phone and a prop's height against the reach (P13) come with the build.

### To run it again

```text
godot --headless --path game res://tests/captures/extraction_probe.tscn -- \
  --map=drive_in --chain=v4 --mode=night --bots=4 --count=1 --seed=1 --profile=veteran --quota=560 --out=<file>
```

`--map=small_indoor` for the back rooms; `--mode=floor`, `stall` or `base`. The chain's places on camera:
`map_review_tour.tscn` with `--spot=name:x:y:z:yaw:pitch`.
