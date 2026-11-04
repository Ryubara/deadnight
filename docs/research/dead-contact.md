# The player and the dead

How a player's body meets the dead (issue #914): the maintainer, playing round 12 at 3x with three bots, said the player
"shouldn't be able to run through zombies, but should also be able to nudge zombies out of the way if they run against
them enough". Code: `game/gameplay/player/dead_*.gd`, `ZombieSim.nudge`; tests: `game/tests/player/test_dead_block.gd`,
`test_dead_shove.gd`, `game/tests/net/test_dead_online.gd`; measurements: `game/tests/captures/dead_variants.gd`,
`dead_walk.gd`, `dead_cost.gd`, `bots_soak.gd --dead=...`.

## Why there was no collision

The dead are not physics bodies (`docs/research/zombies.md`, "No physics bodies"): `ZombieSim` keeps each one as plain
data, so 40 of them cost under a millisecond and the server stays deterministic and node-free, and they are shot at
through analytic hit zones. A player's `CharacterBody3D` is stopped by layers `WORLD` and `BOARDS` only (`player.tscn`,
mask 3); nothing in the physics world is a zombie, so `move_and_slide` could never meet one. It was not a decision about
play: no issue, design page or lesson says the player may pass through the dead (searched), and the one deliberate "no
collision" rule, players through each other (#760, `PhysicsLayers.BODY`), is a different thing. It fell out of "the dead
are data".

## What comparable games do

The public record is thin (no engine source, no numbers), so this is what could be read, and nothing here is a measured
value of ours.

- **Left 4 Dead** (Valve): the infected are bots with "local avoidance" and "mob flocking" on top of reactive path
  following, "collision resolution" lives in their locomotion, and the way out of a crowd is the **shove**, which makes
  room and does no damage; L4D2 added melee fatigue so it cannot be held for ever ([Booth, "The AI Systems of Left 4
  Dead"](https://www.readkong.com/page/the-ai-systems-of-left-4-dead-michael-booth-valve-9664541); [shove and
  fatigue](https://left4dead.fandom.com/wiki/Melee)). The infected are in the way, and a button clears them.
- **Vermintide / Darktide** (Fatshark): a slot system "moves enemies to slots around players to space them out, simulate
  collision, and help with performance" ([Darktide 101 dev blog](https://forums.fatsharkgames.com/t/darktide-101-enemy-design-and-prototyping-dev-blog/98452)),
  and players describe the push as what you need "if you want to move through a horde" (Steam discussion, not an
  official source). The crowd is held off the body by where it is allowed to stand, and the push moves it.
- **Killing Floor, Call of Duty Zombies, Back 4 Blood, World War Z, Dying Light**: searched, nothing public on whether and
  how the common dead stop the body; the visible pattern is that all of them make the player pay for being surrounded
  and give a way out (a shove, a sprint, a perk, killing).

What we took from it: the dead stop the body; the way out is a deliberate act that costs time (the shove), not a
property of the crowd; and the crowd keeps its own spacing (our separation push already is the slot system's job).

## What was built

- **The body is stopped in the movement function both machines run** (`PlayerSimulation` calls `DeadBlock.apply` after
  the slide). Each living zombie is a circle of 0.4 m on the ground (the body's own 0.35 m is added); a body that ended
  inside one is put back on its edge and loses the speed it had into it, so it slides round the zombie like a post.
  One-way: the body is never allowed nearer than it began the tick and never pushed out of an overlap, so a
  prediction that is a few centimetres off never fights the reconciler. A body above a zombie's head (a car roof, 1.4 m)
  or under a ramp it stands on (1 m) is not touched. The correction goes through `move_and_collide`, so a wall wins.
- **The same positions on both machines.** A client fills the body's field from the frame it draws (`DeadSnapshot.of_entries`
  from the decoded entries); the server keeps the dead's places of the last 18 ticks in the frame's centimetres and fills
  each body's field from the frame its command names (`view_step`, the one the lag compensation uses for shots). A
  tuning switch `dead_as_seen` turns it off to compare.
- **The push is the server's alone** (`DeadShove`, `ZombieSim.nudge`). The body reports what it touched and how hard the
  stick pushed into each zombie; a push held `hold_seconds` makes the zombie yield at `shove_speed`, **across** the
  player's way (80 percent sideways, to the side it leans to, by its id when dead ahead). The client does not predict the
  zombie's move: it sees it in a later frame, and the body is held by the same frame the server used meanwhile. A wall
  ahead of the yielding zombie (a ray) stops it and it rolls to the side instead; a zombie that is rising, dying or at
  its boards is not moved; a boss gives 30 percent.
- **Bots** (`BotLegs._avoid_dead`) walk round a zombie their way brushes within 1 m of its middle and slow as it comes
  near, on the side the way already leans (by seat when it is dead ahead); the retreat steering already flees from the dead.

## The variants and the numbers

All numbers are game time; every row is the real simulation (`PlayerSimulation`, `ZombieSim`, the lot's walls). The
variants differ only in how a push moves a zombie, since the block itself is the same:

| variant | rule |
| --- | --- |
| hard | blocked, no push moves anything |
| timed | blocked; after 0.6 s of push the zombie goes at 1 m/s straight away from the body |
| wade | blocked; the zombie goes at once, at 35 percent of the speed the stick pushes at |
| ramp | blocked; after 0.3 s the zombie goes from 0.3 to 2 m/s over 1.5 s, slower with the crowd behind it |
| timed, sideways | as timed, 80 percent of the yield across the player's way (**chosen**) |

**Time to get through** (`dead_variants.gd`: the body pushes straight on, never steers, from dead centre, running;
sprint is within 0.2 s; seconds, and in brackets the seconds before the first zombie moved 0.3 m; "stuck" is not through
in 20 s). One, two touching, a block of 12 (3 across, 4 deep, 3 m in front), a ring of 8 at 1.1 m and of 10 at 0.95 m
round the body (out 3 m):

| scenario | hard | timed | wade | ramp | timed, sideways | ramp, sideways | wade, sideways |
| --- | --- | --- | --- | --- | --- | --- | --- |
| one | stuck | 3.2 (1.3) | 2.2 (0.6) | 3.0 (1.1) | **1.6 (1.2)** | 1.4 (1.1) | 0.9 (0.5) |
| two | stuck | 1.9 (1.4) | 1.3 (0.8) | 1.8 (1.3) | **1.7 (1.3)** | 1.6 (1.2) | 1.1 (0.8) |
| block of 12 | stuck | stuck (1.4) | 11.9 (0.7) | stuck (1.7) | **5.9 (1.3)** | 6.3 (1.6) | 3.1 (0.6) |
| ring of 8 | stuck | 4.2 (1.1) | 3.0 (0.4) | 4.0 (1.2) | **1.9 (1.1)** | 2.0 (1.2) | 1.2 (0.3) |
| ring of 10 | stuck | 3.3 (0.8) | 2.0 (0.4) | 3.0 (0.8) | **2.2 (0.9)** | 2.4 (1.0) | 1.4 (0.3) |

One zombie 0.25 m off the line is passed in 0.8 s by every variant, the body slides round it: the block only holds a
player who runs into the middle of one, which is the case that has to be answered. With the block off (`enabled =
false`) the same body walks through the dead at its own pace.

**Real nights** (`dead_walk.gd`: a stand-in person at seat 1 runs laps of 150 m round the lot's open ground, a
straight run along the navigation path, sprinting, never shooting, steering round nothing, in a night three bots
fight; 6 nights of 6 game minutes, rounds 1 to 6; the bots walk round the dead):

| dead | downs | blows / damage taken | held by a zombie (share of the time) | held 2 s or more (trapped) | longest hold |
| --- | --- | --- | --- | --- | --- |
| off (before) | 0 | 7 / 105 | 0 | 0 | 0 |
| hard (no push) | 13 | 103 / 1633 | 1.6 percent | 5 | 5.1 s |
| timed, straight away | 10 | 111 / 1722 | 1.0 percent | 1 | 2.1 s |
| timed, sideways (**chosen**) | 11 | 108 / 1752 | 0.9 percent | 0 | 1.1 s |
| wade, sideways | 11 | 106 / 1663 | 0.1 percent | 0 | 0.6 s |

A runner who never fights is downed about twice a night once the dead stop him and never when they do not: that is the
change doing what was asked, and the cost of a hard block for a person who runs into the dead; every variant pays it
alike. The number the variants differ in is "trapped": with no push a walker was held 5 times for 2 s or more and up
to 5.1 s; with the chosen push, never more than 1.1 s. (The stand-in's own "stalled" count is left out: it ran while it
was downed and while it stood wedged on a car's corner with no zombie near, see the lesson in the kit.)

**Bots alone** (`bots_soak.gd`, 4 regular bots, 3 nights each, up to round 9, seeds 1 to 3, same seeds; the bots
before they walked round the dead, A, and after, C):

| dead | rounds | downs | damage taken | held (share) | longest hold |
| --- | --- | --- | --- | --- | --- |
| off, A | 9, 9, 9 | 5 | 1161 | 0 | 0 |
| timed (straight yield), A | 9, 9, 9 | 6 | 1536 | 0.02 percent | 0.8 s |
| off, C | 9, 9, 9 | 5 | 1400 | 0 | 0 |
| timed (straight yield), C | 9, 9, 9 | 5 | 1279 | 0.04 percent | 1.1 s |
| timed, sideways (**chosen**), C | 9, 9, 9 | 6 | 1261 | 0.04 percent | 1.1 s |

The bots barely meet the dead at these rounds (they shoot and back away) and the rounds they reach are the same; the
damage they take moves with the seed more than with the rule (1161 and 1400 for the same code with the dead off). The
bots' walking round the dead is for the corners, and a test holds it.

**No rubber band online** (`test_dead_online.gd`: a client through a link with 60 ms each way and 10 ms of jitter
sprints at a zombie that walks to meet it; the largest correction the reconciler asked for in a run, 8 runs, median;
metres): no zombie 0.29; the dead as the client drew them **0.27**; the dead as they stand now on the server 0.58. A
sprint's own start costs 0.2 to 0.5 m of corrections on this link whatever is ahead; the dead as seen add nothing to it.
The body ends at the server's place to 2 cm (0.001 to 0.03 m settled).

**Cost per dead** (`dead_cost.gd`, desktop, a machine shared with other work, 3000 ticks a row, microseconds a 60 Hz
tick; four bodies, 40 dead, a quarter of them within 3 m of the bodies): the snapshot of the dead's places 32, filling
the four fields 21, stopping the four bodies 14, counting the pushes 8: **75 µs a server tick at the 40 cap**, 0.45
percent of a tick, about 1.9 µs a dead; one body and 40 dead, 36 + 9 + 6 + 3. The four bodies' own movement is 438 µs
a tick. On a client: 25 µs a tick at 40 dead (the snapshot from the decoded entries and the fill). Nothing is spent
when `enabled` is off, and the dead farther than 3 m from a body are never looked at by the block.

## The choice

**Timed, sideways: blocked, a push held 0.6 s makes the zombie roll out of the way at 1 m/s.** Why:

- It is what was asked. A body is stopped dead by the dead; run against one for a moment and it gives way. A single one
  dead ahead costs 1.6 s (0.3 s of that is the walk to it), a ring of eight 1.9 s: long enough to feel, short enough to
  leave. Wade moves a zombie after 0.4 to 0.6 s and slows the body to a third: that is running through them, slower.
- Nobody is held for good: a walker was held at most 1.1 s in real nights (5.1 s with no push), the block of twelve
  gives in 5.9 s, and a zombie with a wall behind it rolls to the side.
- It is the simplest rule that passes every row: two numbers (hold, speed) and the direction. Ramp has more knobs and no
  better row; its crowd drag leaves a block of twelve stuck. The other variants stay in `DeadContactTuning` (`policy`) so
  these tables can be made again.
- The sideways roll is what made the numbers: pushing a zombie straight ahead leads it along in front of the player at
  1 m/s (3.2 s to pass one) and jams a block (stuck).

## Left alone

- Players through each other stay a pass-through (#760); only the dead stop a body.
- The dead are not stopped by the player: a zombie walks to 1.4 m (`reach`) of its target and stands, so it never walks
  into a still body. A body that runs into one is stopped at 0.75 m, inside the swing's reach, so running into the
  dead is being in their reach, which the table above counts (damage).
- Balance: the simulator does not model the body being stopped. The bots' rounds are the same with the dead on; if a
  person's nights end sooner because running through the dead no longer works, that is the intent of #914.
- The tuning is in `dead_contact_tuning_default.tres` (hold, speed, radius, lateral share, boss share).
