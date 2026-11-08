# Map review: both maps as a level designer

A design review of the drive-in lot and the second map ("the back rooms"), done as a level designer would
([#833](https://github.com/Ryubara/deadnight/issues/833), 2026-11-03). Every area was walked from the player's
shoulder camera and judged against the kit's [map review
checklist](https://ryubara.github.io/gdstudio/engines/godot/map-review/) (built from published level-design
writing, with its sources). Every claim about leaving a map or skipping a door was **proved by moving the real player
body**, not by eye. The findings are ranked by how much they hurt play, each with its issue.

North is up on every plan (the lot's screen is at the top). Metres, x east, z south. Letters on the plans are the
findings below.

## Ranked findings

| Rank | Finding | Where | Issue |
| ---: | --- | --- | --- |
| 1 | **B1.** A player leaves the lot over the plaza's south-west corner: a crate and a small container stacked against the end wall are stairs, and past the wall there is a floor 0.5 m under the lot with no end and no kill volume | lot, plaza (door 2,000) | [#845](https://github.com/Ryubara/deadnight/issues/845) |
| 2 | **B2.** Buying only the concession (350) opens the back lot (1,250): barrels and a dumpster in the midway's west alley are stairs onto the 2.6 m fence | lot, midway to back lot | [#846](https://github.com/Ryubara/deadnight/issues/846) |
| 3 | **A.** The start-room counter on the second map can be jumped onto, and the middle of its top is out of every zombie's reach: ten dead for 40 s landed no blow | second map, hall | [#847](https://github.com/Ryubara/deadnight/issues/847) |
| 4 | **J.** The reach tests and the docs take the jump height (1.1 m) as the most a player climbs; the real body climbs 1.25 m, and no test runs the body at the props beside the walls on either map | both, tests | [#848](https://github.com/Ryubara/deadnight/issues/848) |
| 5 | **C.** Every area but the field has dead spawn points that are bare ground at a fence, with no breach, window or gate; the share of the pool that comes through the field's breaches falls from 100% to 35% as the doors open | lot | [#849](https://github.com/Ryubara/deadnight/issues/849) |
| 6 | **D.** Each of the field's six aprons has a lamp 0.5 m from its spawn (#703): the dead never come out of the dark, and the map page's numbers (31 to 47 m from a lamp) are out of date | lot, field | [#850](https://github.com/Ryubara/deadnight/issues/850) |
| 7 | **E.** The back lot is 30% lit by the field's circuit (the map page says 5%): its identity as the dark area behind the dearest door is gone | lot, back lot | [#851](https://github.com/Ryubara/deadnight/issues/851) |
| 8 | **F.** The back lot's neon sign is a flat orange greybox block, bright with its circuit off | lot, back lot | [#852](https://github.com/Ryubara/deadnight/issues/852) |
| 9 | **G.** The generator, the game's second pillar, reads as a blank olive wall from the yard's gate | lot, yard | [#853](https://github.com/Ryubara/deadnight/issues/853) |
| 10 | **H.** The second map's pendant lamps' haze cones read as solid white columns when the camera is 2 to 3 m from one (upstairs) | second map | [#854](https://github.com/Ryubara/deadnight/issues/854) |
| 11 | **I.** Thin ground: the yard's east third, the plaza, the field's flanks and its south strip hold little to run round or fight from (reworked, [below](#the-thin-ground-reworked-855)) | lot | [#855](https://github.com/Ryubara/deadnight/issues/855) |

Already filed and not repeated: prompts through walls ([#831](https://github.com/Ryubara/deadnight/issues/831); the
audit below gives it the worst places), a sign's glow through walls
([#832](https://github.com/Ryubara/deadnight/issues/832)), lamps lighting the next room
([#841](https://github.com/Ryubara/deadnight/issues/841)), the projector's spot aimed at the road
([#840](https://github.com/Ryubara/deadnight/issues/840)), `upper_b1` with no way in
([#824](https://github.com/Ryubara/deadnight/issues/824)), wall weapons as silhouettes
([#829](https://github.com/Ryubara/deadnight/issues/829)), the prize crane
([#830](https://github.com/Ryubara/deadnight/issues/830)), web night load
([#828](https://github.com/Ryubara/deadnight/issues/828)). Nothing else found by the sweeps below is a bug; what the
sweeps checked and found clean is listed per area.

## How it was done

- **Research first.** The kit page cites the sources (flow and loops, cover and sightlines, encounters, pacing,
  wayfinding, lighting for darkness, collision hygiene). Valve's own Left 4 Dead notes sit behind an anti-bot page and
  were read second-hand.
- **Walked from the camera.** `tests/captures/map_review_tour.gd` plays the real night (no dead, every door open,
  every circuit on) and puts the player at each spot with the shoulder camera behind: 49 spots on the lot, 22 on the
  second map, each also with every circuit off (`--dark`); `--plan` draws the plans; `--chain` captures a chain of
  hops found by the probe.
- **Inventory.** `tools/world/map_inventory.gd` lists every collider, mesh and light of a map scene. Result: every
  drawn thing taller than 0.5 m on both maps has a collider (the only exceptions are the signs above the machines), no
  collider has nothing drawn near it (the lot's 320 m "outskirts" slab aside) and every drawn box and mesh has a
  material (the back lot's sign block is a material, but a flat one: F).
- **Movement.** `tools/world/map_escape_probe.gd` runs the real player body (`PlayerSimulation`, the same rules the
  night ticks) from every ground cell the start can walk to, with the doors in a given state: sprinting at the thing
  ahead and jumping at five moments, walking and jumping, and crouch-walking at it. Where the body settles off the
  walkable ground is a standing place, and it tries again from there, up to five hops. A standing place beyond the
  map, inside a closed area or at 2.4 m and more is a violation. Each reported chain is replayed hop by hop from the
  real floor (`--replay`) and captured (`--chain`) before it is filed. Doors states swept: the lot with none sold,
  with only the concession, with every door but the road, and with all; the second map with none and with all.
- **Reach.** `tools/world/ledge_probe.gd` runs the body at blocks of each height from level ground: the highest it
  gets onto is **1.25 m** (the jump is 1.1 m and the step-up and the capsule's foot add the rest), not 1.3. Every
  design page and test that says "a little over a jump" meant 1.1.
- **Roost check.** `tools/world/roost_probe.gd` puts the player on a spot in a real night, with ten dead chasing for
  40 s.
- **Audit.** `tools/world/map_audit.gd` lists each spawn point (inside a solid, in view of the start, distance to the
  nearest breach and lamp) and, for each shop spot, the standing places within the use reach that have a wall between.
- **Limits.** The sweep is a search, not a proof of absence: 1.5 m (lot) and 0.75 m (second map) launch cells, eight
  headings for ground cells and sixteen from a standing place, jumps at the moments listed, five hops deep. It finds
  what it finds; the fixes should add the test below (J), which pins the cases.

![The lot, top-down, with the findings](maps/review/plan-lot.jpg)

*The lot: dead spawn points (red), shop spots (blue), door slabs (yellow), findings (letters). The red-ringed lamps
inside the six aprons at the top are D.*

## The lot

Seven areas (the screen field, the concession and the midway behind it, the projection booth, the generator yard, the
back lot, the ticket plaza). The layout is a fan of car rows facing the screen, three doors off a central spine, two
side lots and a plaza at the end. The structure works: a safe lit start with a landmark (the SNACKS neon and the
projector beam read from the start apron), purchases that each add somewhere to run, and a hard last lot. Its faults
are at the seams: the walls and the props beside them, and what happens at the spawn points.

| Area | Verdict | Evidence and notes |
| --- | --- | --- |
| Field: start apron and avenue | **Keep.** The best-read place on the lot: the SNACKS neon is the lit landmark at the end of a cleared 35 m avenue, the beam points up behind it, the cars at the sides are low cover with gaps. The start faces the stand | [captures](maps/review/lot-field-1.jpg) f01 to f03 |
| Field: car rows | **Keep.** A fan of 76 cars: loops between the rows, shoulder camera under the roofs as the page says; the dark set stays readable (moon and screen) | f04, f03 dark |
| Field: flanks, south strip | **Thin (I).** Wide dark ground, a few trees, a wreck, a playground frame; the south strip is a 40 m blank wooden fence. The largest empty circle on the field is 7.2 m radius and 0.5% of its ground is more than 6 m from cover, so the field is not too wide; the flanks are just empty. **Reworked (#855):** a row of four wrecks on each flank and two pairs of kerb walls on the strip, each a lap of 44 to 45 m | [captures](maps/review/lot-field-2.jpg) f05 to f10; [#855](maps/review/thin-ground.jpg) |
| Field: aprons and breaches | **Keep the form, fix D.** Six walled aprons, boards across the gaps, readable from the field; each has a lamp 0.5 m from the spawn | f07, f08; plan |
| Concession | **Keep.** Warm, lit, a counter to run round, windows 1.0 to 2.4 m up that nothing can enter (the sweeps landed no body inside from the field in any state) | [captures](maps/review/lot-concession.jpg) c01 to c05 |
| Midway | **Fix B2.** An open 32 by 42 m court, grey tiles, two lamps, two alleys with barrels and dumpsters at their ends; the west alley is the door skip. The spawns at the south corners are bare ground (C) | [captures](maps/review/lot-midway.jpg) m01 to m05 |
| Projection booth | **Keep.** The one roost by design (the ramp, the window over the field, the projector); the camera is against the wall on the ramp (known, the player swaps shoulder). The projector spot lights the plaza through the wall ([#840](https://github.com/Ryubara/deadnight/issues/840)) | [captures](maps/review/lot-booth.jpg) b01 to b05 |
| Generator yard | **Rework G, I.** Four lamps round a cage, 24% lit; the cage from the gate is a blank olive wall with propane tanks, and the east third of the yard is empty ground (only 7% of the yard is solid). **Reworked (#855):** a carton row in the east third, a 41 m lap with container B | [captures](maps/review/lot-yard.jpg) y01 to y06; [#855](maps/review/thin-ground.jpg) |
| Back lot | **Rework E, F.** Six rows of wrecks and a dark mood, but 30% of it is lit by the field's lamps and its one neon is a flat orange block | [captures](maps/review/lot-backlot.jpg) l01 to l04, l03 dark |
| Ticket plaza | **Fix B1, thin I.** The perk machine at the end of the court is a good landmark from the gate; the end wall's south-west corner is the way out; the court is 640 m² with 11% solid; three bare spawn points. **Reworked (#855):** two carton rows in the south half (a lap of 60 m with the booths), and the container by the end wall was a roost, now out of reach | [captures](maps/review/lot-plaza.jpg) p01 to p04; [#855](maps/review/thin-ground.jpg) |

### What the sweeps found on the lot

**B1, the plaza's way out.** With every door open, three hops from the plaza floor: onto the crate at the wall (0.63
m), onto the small container (1.71 m) and a sprint-jump over the corner of the end wall (3.0 m): the player lands 5.8
m beyond the map on the "outskirts" slab, a 320 m floor 0.5 m under the lot. Nothing is there: no zombie path, no kill
volume, no way back. The container's top is 1.29 m under the wall's top and the body reaches 1.25 m from a standing
start, so the margin is thin and the run-up and the wall's corner make up the 0.04 m (the replay lands past the wall
every time). The page's rule ("nothing a player can step up on stands within a jump of a taller block") is kept for
1.1 m and not for the body.

![Chain: the plaza's way out](maps/review/chain-plaza-escape.jpg)

**B2, the back lot's skip.** With only the concession sold, four hops from the midway's west alley: a walk-jump to the
barrels, onto a barrel (0.82 m), onto the dumpster (1.62 m), and a sprint-jump south-west over the 2.6 m midway fence
into the back lot, whose door costs 1,250 and needs the booth. The east alley has no such stair (its barrel is a spill
with no collider, and the dumpster is the only step). No chain reached the yard, the booth or the plaza from the
midway in this state; with every door but the road sold, no chain reached the plaza (see the numbers below).

![Chain: the back lot's skip](maps/review/chain-backlot-skip.jpg)

**Clean:** with none sold, no body entered the concession or any other closed area from the field. The playground's
1.4 m and 2.4 m frames cannot be climbed from the floor (an early run that thought so was started 0.2 m above the
floor; the probe now starts at the solid floor).

**C, D, E, bare spawns and lamps.** The audit of the spawn points:

| Area | Spawn points | Nearest breach | Nearest lamp |
| --- | --- | ---: | ---: |
| Field | six, on the aprons | 4 m | **0.5 m** each |
| Midway | (-14, 36), (14, 36) | 75 m | 4.6 m, 3.0 m |
| Generator yard | (60, -2), (60, 36), (28, 36) | 20 to 67 m | 14 to 19 m |
| Back lot | (-60, -2), (-60, 36), (-30, 36) | 20 to 66 m | 5 to 13 m |
| Plaza | (-14, 50), (13.5, 55), (-13.5, 55) | 87 to 91 m | 15 to 17 m |

None is in view of the start (0 of 8). Past the field the dead appear on open ground at a fence
([captures](maps/review/lot-midway.jpg) sp1; [yard](maps/review/lot-yard-spawns.jpg); [back
lot](maps/review/lot-backlot.jpg) sp4; [plaza](maps/review/lot-plaza.jpg) sp6 and sp7): nothing opens, nothing is
torn, the second map's twelve windows each carry boards, a sill and a shaft of light. The share of the pool at the
breaches by the lot's own report: 100% at the start, 75% with the concession, 55% with the yard, 43% with the back
lot, 35% with the road. The lamp per apron is the maintainer's own placing in #703 (lamps 18 to 23); the map page's
table (back lot 104 m², 5%) and its text (the dead come in 31 to 47 m from a lamp and "arrive out of the dark 25%
faster") are from before that, and the report the page cites now reads: field 33% lit, back lot 580 m² (30%), of which
the field's circuit alone lights 476 m². Whether the apron lamps are right (a lit breach is readable, and the dead
then walk at the round's pace until they leave the pool) is the maintainer's to weigh; the page and the rule have to
say the same thing.

**What the props are for.** Counted per area (collision blockers at least 0.9 m tall are cover; low ones are clutter
you step over): field 31 and 17, concession 5 and 6, midway 12 and 33, booth 2 and 4, yard 12 and 13, back lot 3 and
32, plaza 9 and 7. The back lot is clutter with three pieces of cover besides the wreck rows; the booth is a roost
with two. Every one of them has a material.

### The thin ground, reworked (#855)

The maintainer chose to add loops and cover to the four stretches rather than shrink them. Each new piece is either
taller than the body's reach and narrow or square to its neighbours (a wreck at 1.3 m, a carton stack at 1.40 m: run
round and seen over, never stood on) or low cover a player shoots over (kerb walls at 1.0 m). Nothing a body can stand
on is within a sprint-jump (6 m) of a piece over the reach.

| Stretch | Added | Solid before / after | Ground > 6 m from cover | Largest empty circle | Lap (dead's mesh) |
| --- | --- | ---: | ---: | --- | ---: |
| Field, west flank (x < -45) | a row of four wrecks, x -52, z -25 to -8 | 11.6% / 14.8% | 0.1% / 0.0% | 6.0 / 5.7 m | 44 m |
| Field, east flank (x > 45) | a row of four wrecks, x 53.5, z -24.5 to -7.3; a sofa moved off the row | 7.8% / 11.2% | 0.8% / 0.2% | 6.7 / 6.2 m | 44 m |
| Field, south strip (z -10 to -4) | two pairs of kerb walls (1.0 m) in front of the fence, with a lane behind | 8.4% / 11.6% | 0.0% / 0.0% | 5.8 / 5.1 m | 45 m and 44 m |
| Yard, east third (x > 50) | a row of nine carton stacks, 2.6 m short of container B; tyres moved to the corner | 11.6% / 14.1% | 1.2% / 0.4% | 6.8 / 6.3 m | 41 m |
| Ticket plaza | two rows of four carton stacks across the south half, the machine's line clear between them | 11.6% / 13.2% | 0.1% / 0.0% | 6.2 / 4.5 m | 30 m; 60 m with the booths |

Measured from `map_inventory.gd` (solids 0.45 to 1.9 m, a 0.25 m grid); the laps by `test_lot_loops.gd`, the
shortest lap round each on a walking mesh for the dead's agent. The plaza's booths lap is 52 m, not the page's "about
45". The field as a whole: 26.9% to 27.8% solid, largest circle 7.2 to 6.9 m.

**A roost on the plaza's end wall, found and fixed.** The region sweep (1.0 m cells, depth 4, every door sold) stood
the body on the small container, the container, the dumpster, the machine and the wreck at the end wall, from two
crates and a stack of tyres beside them. A player on the container's back edge, against the wall, took **no blow from
ten dead in 40 s** (`roost_probe.gd` at 2.4 m/s); the machine's top and the small container's took 5. The crates are
loose cartons now and the tyres stand by the booths; `test_plaza_escape.gd` fails on any standing place over the reach
in the plaza, and failed on the old props.

**A wreck climbed at an inside corner.** The first west row ended in a wreck turned across it; the body got onto 1.3 m
from the floor at the inside corner of the two (one sprint-jump), though a lone 1.3 m block is out of reach. The rows
are straight now, and the sweep stands nothing on a row.

**Sweeps** (`map_escape_probe.gd --region`, 1.0 m cells, depth 4), before and after, on the stretches: the field with no
door sold 20,340 and 22,795 hops, nothing over a wall or in a closed area, no wreck row stood on (the one wreck stood on
is the north-east one among the cars, from a car's bonnet, before and after; ten dead landed 5 blows there, so it is no
roost); the yard's east third and the plaza with every door sold 8,940 and 8,800 hops, the junk tops before and none
after. Sixteen ground points beside the fuel tanks are flagged in both: the probe bakes a cylinder as its box, so the
corners of a tank's box read as closed ground. A kerb wall's top is no roost (5 blows in 40 s).

![The thin stretches, before and after, from the player's camera](maps/review/thin-ground.jpg)

**Prompts through walls.** The audit reproduces #831 on the lot: the stand's shotgun plaque (-8.2, -5.6) reaches a
standing place inside the stand 2.3 m away, behind the wall; the grenade rack (11.4, 3.0) one inside the stand at 2.2
m; the rifle plaque (-4, 20.4) one inside the booth at 2.3 m; the booth's Quick Load machine 26 of 87 places; the
plaza's perk machine one outside the end wall. The cranes and the midway, yard and back lot lockers have none. The
list went to #831's owner.

## The second map

A two-storey depot of 585 m²: the hall (start), the side room and two upstairs halves, three links in a ring, twelve
windows. (Since #917 the ground outside is one level, walled into three yards, with the drive-in to the south, the upper
windows open onto a terrace and a gallery the dead climb to, and there are eight entries; the layout, its reasons and
its captures are on [the map's page](../design/smallmap.md#outside-and-windows-917). This review is of the layout before
it.) The formula's tests hold; the map plays well in the camera: warm pendants, plaques you read, machines you can tell
apart, a long lit corridor down the side room. The shoulder camera is tight on the upstairs and at the stair foot (the
arm is pulled in; the known cases). One real fault and one art fault.

![The second map, top-down, with the findings](maps/review/plan-small-ground.jpg)

*The ground floor: dead spawn points (red; each 6 to 7 m outside its window), shop spots (blue), the counter (A).*

![The upper floor, with the findings](maps/review/plan-small-upper.jpg)

*The upper floor (the hall's roof is the lower part of the picture): spawn points on the roof and in the yard to the
north, the pendant lamps whose haze cones are H.*

| Area | Verdict | Evidence and notes |
| --- | --- | --- |
| Hall (start room) | **Fix A.** Lit 90% by its lamps, five windows, a counter to run round: the counter is also a roost | [captures](maps/review/small-hall.jpg) h01 to h06 |
| Side room | **Keep.** A 22 m lit corridor of pillars and racks with the box and the coolers on the north wall; the west end is dim and ends in the breach pocket | [captures](maps/review/small-side.jpg) s01 to s05 |
| Stairs | **Keep.** Two flights of 17 risers, a wall each side | u01, u09 |
| Upstairs, both halves | **Keep, fix H.** 77% and 93% lit; the shop wall of coolers reads at a distance; the pendants' haze cones read as solid white columns up close (H); `upper_b1` has no way in ([#824](https://github.com/Ryubara/deadnight/issues/824)) | [captures](maps/review/small-upstairs.jpg) u02 to u07, [more upstairs captures](maps/review/small-upstairs-2.jpg) |
| Hall's roof and the yard | **Keep.** Dead spawn on the roof and in the yard, each 3 to 7 m from its window; nothing a body reaches goes out | spawns on the plan |

**A, the counter roost.** The hall's counter (5 by 3.5 m, 1.2 m high, "a little over a jump") is climbed from the
floor: 62 standing places on it, from a sprint-jump from the west. The middle of its top is 1.75 m from any edge, and
a zombie's centre cannot come within 0.5 m of the counter (its walking mesh) and swings from 1.4 m: so there. Ten dead
chasing for 40 s: the player at the middle of the top (8, 1.2, 6.25) took **0 blows, health 100**; at the counter's
edge (6.3, 1.2, 5.2) **7 blows, dead**; on the hall floor (8, 0, 11) **7 blows, dead**. The player on the counter
shoots down with nothing able to answer, in the start room, from the first round. The racks (1.2 m, 0.4 m deep) can be
stood on too, and are not a roost (the edge is 0.2 m away).

![The counter from the floor and from its top](maps/review/small-counter-roost.jpg)

**Clean:** the sweeps with every door open found no body beyond the building, in a window, on the hall's roof (a spawn
point there is for the dead) or past the bank. Standing on the coolers, the re-cut bench and the cabinets (1.1 to 1.2
m) is possible and harmless. 4,825 (none) and 15,660 (all) hops.

**Prompts through walls.** The same audit on the second map: the shotgun plaque on the side room's east wall 16 of 74
places, the quick-load cooler 1.2 m from a place behind the wall, the upstairs shotguns, coolers and the cabinet 13 to
17 of about 95 each, the hall's pistol and crowbar plaques 17 of about 95 each, the box 6 of 75.

## Across the two maps

| | The lot | The second map | Verdict |
| --- | --- | --- | --- |
| How the dead come in | six breaches in the field; bare points elsewhere (C) | twelve windows, each with boards, a sill, a shaft | the second map's is the one to follow |
| Shape of an entry | six breaches: a 4 m gap with a 0.9 m sill, jambs and a header, and a players-only blocker (#915; before, a full-height gap that read as a door) | twelve windows, the breach included (a 0.9 m sill, #915) | the same: every barricade is a window, checked by `test_barricade_windows.gd` |
| Light | a generator, six circuits, lamps that cost fuel, pools of light; dark is a mechanic | eight pendants on an always-on circuit; no dark, no generator | by design ([the map's page](../design/smallmap.md#what-the-map-leaves-out)); the second map has no gradient from lit to dark, so its rooms are judged on readability, and they pass |
| Kit and scale | Toon props and greybox walls, 2.4 to 3.0 m fences | the second map's own kit, 3.2 m ceilings | consistent: both read as 1958 brick; plaques, machines and prompt text are the same |
| Reach assumed | 1.1 m (jump) in the test and the page | 1.1 m in the formula and the counter | measured 1.25 m (J) |
| Words on cards | the lot's | the map's own (`MapWords`), tested | fine |
| Use zones (missed by this review, found in play: [#908](https://github.com/Ryubara/deadnight/issues/908)) | 7 overlapping pairs at the old 3.2 m reach; none after the reaches shrank and two posts and the rifle moved | 51 pairs (a locker 1.45 m from `upper_a2`, perks 2.1 to 2.9 m apart); 26 left at the new reaches, listed for [#917](https://github.com/Ryubara/deadnight/issues/917); none since [#994](https://github.com/Ryubara/deadnight/issues/994) (the side room's south-west window dropped, five things moved) | the spacing sweep is a test on both maps ([use reach](use-reach.md#spacing-and-the-press-908)) |

## The reach (J)

The jump is 1.1 m (`PlayerTuning.jump_height`); the step-up is 0.3 m on the ground and does not apply in the air; a
block of 1.25 m is climbed from level ground and one of 1.3 m is not (nine jump moments, four approach distances,
sprint and walk). `test_drive_in_jump_reach.gd` skips a barrier whose top is more than `jump_height` above a platform,
so a rise of 1.1 to 1.25 slips past, and it runs the real body only from the car roofs near the perimeter: the props
beside the walls (containers, crates, dumpsters, barrels) are never tried. The second map has no such test.

A first part of J is done in the review: `tests/player/test_jump_reach.gd` runs the body at blocks of 1.05 to 1.5 m
and fails if the highest it climbs leaves 1.25 m by more than 0.06 m (3 s). The rest (the number as one constant the
lot's test reads, the sweep tests, the map pages) is [#848](https://github.com/Ryubara/deadnight/issues/848).

## Numbers of the sweeps

| Map and doors sold | Hops run | Standing places | Result |
| --- | ---: | ---: | --- |
| Lot, none | 115,045 | 9,560 | nothing inside a closed area or past the walls |
| Lot, the concession | 149,375 | 10,746 | the back lot is entered (B2); nothing else |
| Lot, all but the road | 168,330 | 11,104 | the plaza is not entered |
| Lot, all | 179,815 | 11,325 | past the plaza's wall (B1); the fence tops of B2 |
| Second map, none | 4,825 | 82 | 62 places on the counter (A) |
| Second map, all | 15,660 | 145 | the counter, the coolers and the bench (1.1 to 1.2 m, harmless) |

"Standing places" counts the places a body came to rest off the walkable ground; a hop is one run of 54 ticks and 24
to settle. The sweep is a search: a clean row means it found none, not that none exists.

## The pieces of the walking mesh (#1051)

A path never leaves the piece of the mesh it starts on, so a body on a piece joined to nothing is told every place is
out of reach: the Rookie of #1041 stood so for minutes, and Follow and Hold had nothing to get it off. Measured with
`tools/world/walking_pieces.gd` on every saved mesh, after `NavmeshSplit`, with the real capsule walked from each piece
(`test_walking_mesh_pieces.gd`). Every door open:

| Kind | Lot | Second map | What was done |
| --- | ---: | ---: | --- |
| The map's own ground | 1 | 1 | stays |
| Behind a barricade: a pocket, or a yard outside (a sill of 0.9 m stops a walk with the boards torn) | 14 | 4 | stays, the reason below |
| Outside the perimeter | 1 | 0 | stays: no body gets there |
| Roofs of 35 m2 or more, which no chain of hops from the ground reaches | 4 | 2 | stays: the flood finds no way |
| A scrap the cut left: 1.34 m2 at x -15.25 to -13.75, z 31.0 to 32.25 | 1 | 0 | off the walking mesh |
| An island the bake leaves among the cars: 0.25 m2 at x 34.75 to 35.5, z -31.0 to -30.5 | 1 | 0 | off the walking mesh |
| Tops a body gets to, in one hop or more (bonnets, car roofs, crates): 0.19 to 24.75 m2 | 129 | 0 | off the walking mesh |
| Tops no chain of hops reaches, and hollows inside solid boxes (a body fits and cannot get in) | 56 | 3 | off the walking mesh |

So 207 pieces on the lot before and 20 after, 10 and 7 on the second map; each set of doors adds its shut rooms, all
63 m2 or more.

**The cause of the one in the issue was proved, and it is one of 131.** The two polygons of the scrap join the rest of the
baked mesh by one edge, and that edge belongs to a polygon that crosses the line of the boards of `mid_w` (local x 1.25
to 1.5, z -0.5 to 2.0): the cut takes it and leaves them behind. The east midway's mesh is triangulated otherwise and
leaves nothing. It is the only piece of either map the cut made; the 14 pockets are the far side of their boards. The
other 130 a body can walk or climb off are in the bake itself (the mesh of a top joins nothing because a body gets there
by a jump): on the mesh as it was, a bot set on a bonnet stayed there for 15 s for every order, as it did on the scrap.
The flood runs with every door open; the rooms behind a shut door are the escape sweeps'.

**The fix is in `NavmeshSplit`:** a piece under `LEAST_PIECE` (30 m2) goes with the gaps, on the layer only the dead ask
for, except the largest. A person's path from such a spot then starts on the nearest walking ground, so Roam, Follow and
Hold all walk off it with no code of their own, and #1050's walk back is left for what is not on the mesh at all. The
two ways round were worse: cutting the polygons exactly at the line needs a new vertex in every neighbour and moves the
mesh at all 16 barricades, right up to the boards; giving the cut polygon back puts a walking polygon across the line.
Polygons only leave the walking mesh, so no way across the boards can open; the whole mesh stays, so the dead keep their
paths (compared by length, 440 pairs on the lot and 39 on the second map). Finding the pieces adds about 6 ms on a desktop
to each mesh a door swaps in (12 ms in all).

**Kept with a reason:** the pockets and yards. They are real ground, the dead's way in, and on the second map 600 to 970
m2. A person who jumps a torn sill is out there and walks where they like. A bot jumps only on the third rung of the
stuck ladder, along its way, and its way never crosses a barricade, so it is not reached; `tests/night/test_bot_fence.gd`
holds that a bot sent at one does not stand there. On the lot the far side of `mid_w` and `mid_e` is the plaza, an area
once its door is sold, so "the far side of the boards" is not a rule that could take them off.

## Tools and how to run them

```text
godot --headless --path game -s res://tools/world/map_inventory.gd -- --scene=<scene> --out=<abs>.json
godot --headless --path game -s res://tools/world/map_escape_probe.gd -- --scene=<scene> --start=x,y,z --doors=none|all|<ids> --depth=5 --cell=1.5 --out=<abs>.json
godot --headless --path game -s res://tools/world/map_escape_probe.gd -- <same> --replay=<abs>.json   (one chain, hop by hop)
godot --headless --path game -s res://tools/world/map_audit.gd -- --scene=<scene> --out=<abs>.json
godot --headless --path game -s res://tools/world/ledge_probe.gd
godot --headless --path game -s res://tools/world/walking_pieces.gd -- --png=<abs>.png [--scene=<scene> --meshes=<res>] [--cut-only]
godot --headless --path game res://tools/world/roost_probe.tscn -- --scene=<scene> --at=x,y,z --dead=10 --seconds=40
gds godot -- --path game res://tests/captures/map_review_tour.tscn -- --map=lot|small --out=<folder> [--dark] [--plan] [--chain=<json>]
```

The probes need no window; the tour does (through `gds godot`). The sheets on this page are 4 to 6 of the tour's
frames each.
