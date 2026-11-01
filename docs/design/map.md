# The lot

The drive-in map: seven areas, what opens in what order for how many points, where the dead can be kited, where the
light falls. The greybox that proves it is `game/world/drive_in_greybox.tscn`, at true scale (the player capsule is
0.35 m by 1.8 m; see the [style bible](style.md#scale)). The player is third person, so widths are sized for the
shoulder camera, not the capsule ([Widths and the camera](#widths-and-the-camera)).

The layout is our own. The genre's map-flow principles were studied for understanding only: a first area that is
safe to learn in, doors that show what they will open before they are bought, every purchased area adding a loop,
and no area whose only way on is back through the last.

![The lot, top-down, evenly lit](map-plan.png)

North is up, the screen at the top. The numbers are the opening order; the red slabs are the purchase doors, with
their cost.

## Areas and opening order

The prices are the shop's: each door is a shop item in the rules' tuning (`default_tuning.tres`, see
[rounds](rounds.md#the-tuning-table)), and the generator reads price and prerequisite from it, so the economy has one
source. A test fails when the scene and the tuning disagree.

| Plan | Area | Shop item | Cost | Needs | Affordable (round, 1 / 2 / 4 players)* |
| --- | --- | --- | ---: | --- | --- |
| 1 | Screen field | start | free | - | - |
| 2 | Concession stand, then the midway behind it | `door_concession` | 350 | field | 2 / 3 / 3 |
| 5 | Generator yard | `door_yard` | 500 | concession | 4 / 4 / 5 |
| 4 | Projection booth | `door_booth` | 750 | concession | 6 / 6 / 7 |
| 6 | Back lot | `door_back_lot` | 1250 | booth | 8 / 9 / 9 |
| 7 | The road | `door_road` | 2000 | back lot | 10 / 12 / 12 |

\* The first round at whose end one player's points, half of them spent on doors (the rest buys weapons, fuel and
tonics), cover the running total of every door so far. Counted: about 85 points a zombie, a per-player share of every
zombie of the rounds so far (`zombies_for_round` in `default_tuning.tres`, rounds.md has the curve). Not counted: the
200 starting points and the round bonus, so this is the plan's pace with no help. `test_door_affordability.gd`
recomputes the column from the tuning and fails when it drifts. Rounds.md spends everything and counts the starting
points and the bonus, so its numbers differ.

Where this departs from the [overview](index.md): the generator yard opens before the booth and the back lot, not
with them. Light is the first pillar, and the generator's starter tank has to be refuelled (fuel is bought at the
concession) before it runs dry, which this plan puts around round 3 to 4.

`Plan` is the number on the plan above; the table is in opening order.

Rules the greybox is built to:

- **A bought door is gone in the world and in the zombie navigation.** `LotDoors` (a script on `Doors`) follows the
  rules' `door_opened` and frees the door's slabs and label; `DoorNavigation` then rebakes the zombies' mesh, which
  is baked from the slabs. How, and why not links: [zombies research](../research/zombies.md#doors).

- **Every area is entered only through its door.** A door is a group of slabs (`Doors/Door_*`), one slab for each way
  into the area, and one purchase removes them all. The yard and the back lot each have two ways in (a gate in the
  field's south fence and a link from the midway), so each has one door with two slabs; nothing else leads in.
- **The order is the shop's.** The greybox cannot stop someone who bought the yard from walking field, yard, link,
  midway: both sides of the link are inside the yard's door. What stops it is that the shop will not sell a door
  before its prerequisite (`requires`, also metadata on the door group), so the concession is always sold first. The
  opening-order test sells each of the nine sets of doors the shop can have sold through the rules (so `LotDoors`
  opens them, the game's own path), bakes a navigation mesh for the player's body and checks that every sample point
  (three or more) of the reachable areas is reached, and that no way towards any point of a closed area's whole
  footprint (a grid four metres apart, and the samples) enters it: the field, plus the stand and midway once the
  concession is sold, plus each sold door's area.
- **Nobody leaves by jumping.** The player jumps 1.1 m and a car roof is 1.65 m, so a jump from a roof lifts the feet
  to 2.75 m: the outer walls (the field's north, west and east fences, the yard's east and the back lot's west) are
  3.0 m, `PERIMETER_H` in the generator, up from 2.4 m. The fences between the field and the yard and back lot stay
  2.4 m: nothing reachable stands within a jump of them, and a door's slab is 2.6 m. The road's end is 1.6 m by
  design and nothing reachable stands beside it. `test_drive_in_jump_reach.gd` bakes the walking mesh with the jump
  as its climb for each door still closed (and what needs it), finds the platforms a player can reach, checks that no
  closed slab, closed area's wall, field fence or perimeter wall has its top within a jump of one, and runs the real
  player body (`PlayerSimulation`, sprinting and jumping) from the middle and edges of every car roof near a perimeter
  wall. Before the change the body cleared the north fence from a roof (feet at 2.70 m over a 2.40 m top).
- Zombies spawn only in open areas, and always in the field.
- Every purchased area adds at least one loop, so buying a door always buys somewhere to run.

## Shop spots

Besides the doors, the lot sells at fixed spots: the markers of `ShopSpots` in the greybox, each with a `kind` and a
`shop_id`, read by `NightWorld.shop_spots()`. A player in reach (3.2 m, `NightTuning.use_reach`) of one is offered what
it sells on the prompt card and buys with `interact`, the same press as a door; a door in reach wins, then the nearest
spot with something to sell. What a spot offers comes from the rules' tuning, so the price is never in the scene (the
plaque only names the weapon).

| Spot | Where | Sells | Why there |
| --- | --- | --- | --- |
| Shotgun, on the wall | the concession's front wall, field side, left of the door | `weapon_shotgun`; once owned, its rounds | in the open before any door: the first weapon a player can save for, bought under the dead's eyes |
| Rifle, on the wall | the booth's front wall, midway side | `weapon_rifle`; once owned, its rounds | past the concession: the long gun waits for the middle rounds and the player who has opened the lot |
| Prize crane | inside the stand, beside the cabinet that was there | `crane_play`, a weapon the player lacks, until the pool is empty | the stand is the first door; a gamble to spend the first thousand on |
| Ammunition lockers (5) | the avenue (field), the stand, the midway, the yard, the back lot | rounds for the weapon in hand, as many as fit | one in the open from the start, one more in each area that opens, so a fight is never a long walk from rounds |

A locker never sells the crowbar anything (it never runs dry). The tests (`test_shop_spots.gd`) hold every spot to a
real shop item, to the lot, and farther than a reach from every door slab and from every spot of another kind, so one
press never means two things. The lockers are a green crate with a yellow band, the wall weapons an amber plaque, all
lit by their own colour so they read in the dark (captures in the pull request).

## Widths and the camera

The first draft sized passages for the 0.7 m capsule and a 1.7 m first-person eye. The player is over the shoulder
(`PlayerTuning`: pivot 1.55 m up, spring arm 2.8 m with a 0.25 m sphere, camera 0.75 m to one side). The arm is swept
straight back from the pivot, and the shoulder offset is applied after the sweep, so the camera is not collision
tested sideways: in a narrow place it ends up inside the wall. A passage therefore needs the shoulder offset plus a
little air on each side, `2 x (0.75 + 0.1) = 1.7 m`, so every passage the camera must go through is at least 1.8 m.

| Passage | First draft | Now | Why |
| --- | --- | --- | --- |
| Gaps between cars | 1.4 m | 1.8 m | the 1.4 m gap put the camera in the car's glass at cabin height (measured: every car gap probe failed) |
| Rear exits of the stand, the generator cage's openings | 1.8 m | 2.0 m | 1.8 m only just clears; the camera sits 0.05 m from the jamb |
| Booth ramp | 1.6 m | 2.0 m | the camera cleared it (a wall on one side, an edge on the other); the real fault was the landing, which sat at the foot of the ramp, 3.75 m up, and cut the arm to 0.98 m. It is now at the top. Widened so the ramp is as wide as the other passages; the camera on the wall-side shoulder is still only 0.25 m off the wall, so the player swaps shoulder |
| Doors and gates | 3 to 4 m | unchanged | pass with room to spare |

A zombie is about the player's width (0.7 m), so two come through 1.4 m side by side: **nothing on the map is single
file**. The earlier claims ("a pack does not fit a 1.4 m gap", "the ramp is one at a time") were wrong for a capsule
too. The car rows are a funnel that spreads a pack two across, not a wall; the booth is a roost because of the climb
and the one way up, not because of the ramp's width. The ramp's east side is open on purpose: jumping off the edge is
a 3.6 m drop into the booth, a way down that costs health once fall damage exists (not yet). Everywhere the camera
has to pass, the test sweeps it (`game/tests/world/test_drive_in_camera.gd`, from the `CameraProbes` markers the
generator writes), and a navigation agent as wide as the shoulder camera must reach every area
(`test_drive_in_opening_order.gd`).

Where the arm shortens (the generator cage, which is 2.4 m deep between its opening and the generator; the ramp's
foot, 2.3 m from the north wall) the spring arm pulls the camera in: that is the arm doing its job, not clipping.

## Choke points

| Where | Width | What it does |
| --- | --- | --- |
| Concession front door | 3 m | the first door; the dead queue on the field side |
| Yard gate, back lot gate, road gate | 4 m | two zombies abreast with room; a good place to hold, a bad place to stand |
| Concession rear exits | 2.0 m | two abreast; the stand empties into the midway at a trickle, not a flood |
| Midway links to the yard and back lot | 4.5 m | the joints of the two long loops, each with its own door slab |
| Gaps between cars | 1.8 m | the camera fits; a pair of zombies fits; the rows are a funnel, not a wall |
| Booth ramp | 2.0 m | two abreast, a 25 degree climb; the roost's one way up |

## Loops for kiting

| Loop | Length | Opens with |
| --- | --- | --- |
| Round the concession counter | about 45 m | the concession |
| Concession, midway, yard, field | about 110 m | the yard |
| Concession, midway, back lot, field | about 120 m | the back lot |
| Round the generator cage (open on two sides) | about 50 m | the yard |
| Round the booth | about 85 m | the booth |
| Back lot's wreck lanes | three of 30 to 40 m | the back lot |
| Car rows: aisle to aisle behind a row | 20 to 60 m | the start |

A loop under about 40 m is too short for a pack to string out; the counter loop is the exception, for one player
buying time. Two loops share the concession, so a team splits across them and the stand is never a dead end. The
only dead ends are deliberate: the midway's two alleys (6 m by 12 m, dark, for ambushes) and the booth's upper room.

## Sight lines

- **The avenue** (x = 0, 35 m of cleared ground from the apron to the stand): the longest clear line, lit. The first
  rounds are shot down it.
- **The field's flanks**: open ground beyond the outer rows, with the playground and the picnic shelter as the only
  cover. The dead are seen coming from far off, but only the head and shoulders show over the cars.
- **Behind the car rows**: cars are 1.65 m tall. The shoulder camera at a level view sits 1.55 m up, below a roof, so
  it looks through the gaps, not over the cars; tilted down about 8 degrees (the arm swings the camera up by
  `2.8 x sin(pitch)`) it clears the roofs and sees the aisle behind. A standing player's head and shoulders show above
  the cars to the dead, a pack's legs are hidden. Crouching (carried by the controller, not simulated yet) is not
  designed against until it exists.
- **The booth window** looks 70 m down the field at the screen and over the stand's roof. Nothing there is lit but the
  projector, so the roost sees the whole night and is seen by none of it.
- **The stand's windows** let light out onto the field, and let the dead see in; they are 2.2 m wide with a 1 m sill.
- Everywhere else sight lines are short: the midway, the yard and the back lot are broken by crates, containers and
  wrecks, so the dead arrive from around corners.

## Light and dark

The generator powers every `powered_light` (a node group): the field's lamps, the stand and booth, the yard, the
projector beam, the neon in the back lot. The moon is dim and blue, so unlit ground is dark, not black.

![Where the lights fall](map-lights.png)

| Area | Lit (by eye, from the capture) | What lights it |
| --- | --- | --- |
| Screen field | the avenue and the apron, about a third | eight lamp posts and the screen's glow; the rim is dark |
| Concession | all inside | three warm lights; window spill on the field |
| Midway | a fifth | two dim lamps; the alleys dark |
| Booth | inside | two lights, and the projector beam (the brightest thing on the map) |
| Generator yard | four fifths | four work lamps and the generator's glow: the safest ground, and the most to lose |
| Back lot | a tenth | one flickering neon sign |
| The road | a fifth | the ticket kiosk, and a wreck's headlights |

The dead come in at the field's breaches (`Breach*`), 30 to 40 m from the nearest lamp: they arrive out of the dark
and are slowed when they reach the light, which is the design. When the generator dies the lamps go with it: the
field is dark but for the screen, the yard goes black, and the only fuel is across the lot.

## The greybox

`game/world/drive_in_greybox.tscn`: CSG boxes, one flat colour per area, one script (on `Doors`). Metres, Y up,
x east, z south; the screen is at z = -48 and the road at z = 52 to 64.

| Node | Holds |
| --- | --- |
| `Field`, `Concession`, `Midway`, `ProjectionBooth`, `GeneratorYard`, `BackLot`, `Road` | an area: ground, walls, props, `Lamps`, `ZombieSpawns`, a hidden `Label` |
| `Field/PlayerSpawns` | four markers on the apron below the screen |
| `Doors` | the `LotDoors` script: `bind(rules)` opens a door when the rules sell it; signal `door_opened(door_id)` |
| `Doors/Door_*` | the five purchase doors: a group of slabs (one per way into the area) and a price label, with `metadata/cost`, `shop_id` and `requires`, written from the shop's tuning. `LotDoors.open` frees them; free `Doors` to walk everywhere (a test) |
| `CameraProbes` | markers at every narrow place, facing the way a player walks through; the camera test sweeps the shoulder camera from them |
| `Lighting` | the night environment and the moon |

`game/world/drive_in/` holds the parts (`car.tscn`, `lamp_post.tscn`), the capture rig and `camera_probe.gd` (the
player's camera rig as a function: arm sweep plus shoulder). The scene is written by `tools/world/build_greybox.py`
(run it from the repository root and commit what it writes; the run must leave `git diff` empty), so a layout change is
a change to a constant or coordinate there, not hand edits to a 380-node scene. `game/tests/world/` checks:

- the areas and that the doors' prices and prerequisites equal the shop's (`test_drive_in_greybox.gd`);
- reachability: a navigation mesh baked per set of sold doors, each area reached only through its door
  (`test_drive_in_opening_order.gd`, with a negative control), and that an agent as wide as the shoulder camera still
  reaches every area; the doors themselves (`test_lot_doors.gd`); jumps (`test_drive_in_jump_reach.gd`); and the
  affordability column above (`test_door_affordability.gd`);
- the camera: the arm and the shoulder camera swept through every probe, both ways, both shoulders
  (`test_drive_in_camera.gd`), with a negative control that a 1.4 m gap between cars is caught.

To capture: `capture_rig.tscn` takes `-- --view=top|night_top|start|concession|concession_in|booth|yard|backlot|plaza`,
or `--view=tp:<probe>` for the shoulder camera at a probe (`--offset`, `--turn`, `--side`, `--y`, `--doors=closed`,
`--flood`; see the script's header).

## Not yet decided

- The ramps: drive-in rows sit on shallow berms so rear cars see over front ones. The greybox is flat; berms are
  dressing, and a 0.3 m step needs the player controller's step height first.
- "Spawn only in open areas" needs the rules code: `ZombieDirector` is given its spawn points and does not ask which
  areas are open yet.
- What the road is for: the end of the night, an escape, or just the last door.
- Solo scaling of the door costs, which belongs in the round economy (the affordability table above shows one, two
  and four players at the same prices).
