# The lot

The drive-in map: seven areas, what opens in what order for how many points, where the dead can be kited, where the
light falls. The greybox that proves it is `game/world/drive_in_greybox.tscn`, at true scale (the player capsule is
0.35 m by 1.8 m; see the [style bible](style.md#scale)). The player is third person, so widths are sized for the
shoulder camera, not the capsule ([Widths and the camera](#widths-and-the-camera)).

The layout is our own. The genre's map-flow principles were studied for understanding only: a first area that is
safe to learn in, doors that show what they will open before they are bought, every purchased area adding a loop,
and no area whose only way on is back through the last.

![The lot, top-down, evenly lit](map-plan.png)

North is up, the screen at the top. The numbers are the opening order; the yellow roller shutters are the purchase
doors, with their cost. The boards across the field's six breaches are wood, and the roadblock at the town end of the
road is a concrete block, not a door.

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

The night's look is the `Lighting` node: a near-black blue sky with stars and a moon hanging over the screen, fog
that thickens past 25 m, a dim cool ambient and a cool moon light, so the screen is the brightest thing on the lot and
the lamps are the warm pools in it ([night environment](../research/night-environment.md)).

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

The dead come in at the field's breaches ([below](#the-fences-breaches)), 30 to 40 m from the nearest lamp: they
arrive out of the dark and are slowed when they reach the light, which is the design. When the generator dies the
lamps go with it: the field is dark but for the screen, the yard goes black, and the only fuel is across the lot.

## The fence's breaches

The dead come in at six gaps in the field's fence, 4 m wide: two in the west fence, two in the east, two in the north
(`Field/BreachNW`, `NE`, `W`, `E`, `N`, `N2`, the ids in the rules' tuning). Outside each gap is a walled apron 8 m
deep and 12 m wide, closed on three sides (nobody walks off the map through a torn fence), where the dead appear out
of the dark: the field's zombie spawns stand on the aprons, not in the field.

Across each gap are five boards (a `Barricade` node, `world/drive_in/barricade.gd`, with a `Board` per child). The
boards follow the rules' `board_torn` and `board_repaired`, one at a time from the top down and back up from the
bottom, and while they stand they are solid for players and nothing else: they sit on their own physics layer, so
shots, grenades and the camera pass them (a zombie at the boards can be shot), and they are not part of the
navigation mesh, which keeps the gap open, so the dead's way in is a path and what holds them is the simulation. A
player puts boards back from the field side only, within reach of the middle of the gap.

### Which lamps hang on which circuit

Each `Lamps` group carries `metadata/circuit`, and every light below it takes that circuit. Four are the generator's
(`circuit_drain` in the fuel tuning, the HUD's `SCREEN`, `SNACKS`, `BOOTH`, `BACK LOT`); two are not.

| Circuit | Lamps |
| --- | --- |
| `screen_lot` (on at the start) | the field's eight lamp posts, the screen's glow |
| `concession` | the stand's three interior lights, the midway's two lamps |
| `booth` | the projector beam, the booth's two lights |
| `back_lot` | the neon sign, the ticket kiosk on the road |
| `mains` | the yard's four work lamps and the generator's glow: wired straight to the generator with no switch, so lit while the tank has fuel and black when it is dry |
| `battery` | the wreck's headlights on the road: not the generator's, they burn all night |

The rules decide, the lamps follow. The zombies' slowdown asks `GeneratorState` (`NightWorld.is_lit` ->
`LotLamps.lit_at`: a lamp within 6 m whose circuit is on and whose tank has fuel), never a light node, so a server
that draws nothing agrees with every client. The client's `LotLamps` mirrors `circuit_changed`, `fuel_empty`,
`fuel_restored` and each frame's `fuel`: a circuit that goes off hides its lights and darkens its posts' bulbs; in the
tank's last tenth (`brownout_fraction`) the lights sag and drop out in a flicker that is a function of the frame's
tick and the lamp's number (no clock, no random draw), so a recording and a test see the same lights; at an empty tank
they go out. Only the screen's glow outlasts the generator, at 30% (`afterglow`), and it lights no ground for the
dead. The flicker is only the picture: the slowdown stays whole until the tank is empty.

![The lot from above: the start, every circuit on, a dry tank](map-circuits.png)

Left to right: the night's start (the field and the yard lit), every circuit on, the tank dry.

### The breaker posts

A circuit is switched at a post (`CircuitSwitch`, under `Switches`, one per switchable circuit; `mains` and `battery`
have none). A post stands where its area's door is bought from, on the side the player arrives on, so a bought area
is lit by walking to the wall beside the door, and clear of the door's slabs (a door in reach takes the prompt):

| Circuit | Post | Lights |
| --- | --- | --- |
| `screen_lot` | behind the players' spawns, in the avenue below the screen | the field (no door guards it) |
| `concession` | the stand's front wall, 8.5 m east of its door, on the field side | the stand and the midway behind it |
| `booth` | the booth's north wall, 4.6 m east of its door, on the midway side | the booth |
| `back_lot` | the field's south fence, 4.5 m east of the back lot's gate | the back lot |

Using one (`use`, within `use_reach` of the post) sends `RulesAction.set_circuit` with the opposite of how the circuit
stands; the rules answer with `circuit_changed` and the lamps, the post and the HUD follow. The HUD's card names the
lights and what they do to the tank (`CONCESSION LIGHTS: OFF`, `COSTS 3% FUEL A MINUTE`, from the circuit's draw in the
fuel tuning), and the post shows the circuit: the lever's tip up and a green lamp for on, the tip down and a dull red
lamp for off. A hand throws a breaker at most every `switch_interval` (0.5 s), so a held key does not flicker the
lights. A circuit can be thrown with the tank dry: it lights when fuel comes. The post's lamp is an emissive surface,
never a `powered_light`, so a post is no lamp of the lot.

The autopilot (`AutopilotSwitches`) lights the circuit of an area as soon as its door is bought, because the dead now
spawn there and lit ground slows them; keeps the field's circuit on; and when the tank falls below the low line puts
every other circuit out (in a break) and keeps them out until the tank is back 15 points above it.

## The greybox

`game/world/drive_in_greybox.tscn`: CSG boxes, one script (on `Doors`). Metres, Y up, x east, z south; the screen is
at z = -48 and the road at z = 52 to 64. Each surface has a material from `game/assets/lot/` (asphalt, gravel,
concrete, planks, corrugated sheet, blocks, diner tiles, the doors' shutters: [style bible](style.md#lot-surfaces)),
and the field's stalls have painted lines.

| Node | Holds |
| --- | --- |
| `Field`, `Concession`, `Midway`, `ProjectionBooth`, `GeneratorYard`, `BackLot`, `Road` | an area: ground, walls, props, `Lamps`, `ZombieSpawns`, a hidden `Label` |
| `Field/Breach*`, `Field/Apron*` | a breach's boards (a `Barricade` with `metadata/barricade_id`) and the walled apron outside it; each field spawn marker carries the `barricade_id` of the breach it lies outside |
| `Field/PlayerSpawns` | four markers on the apron below the screen |
| `Doors` | the `LotDoors` script: `bind(rules)` opens a door when the rules sell it; signal `door_opened(door_id)` |
| `Field/ParkingLines`, `Road/RoadDashes` | the painted lines between the stalls and down the road: one `MultiMesh` each, no collision |
| `Doors/Door_*` | the five purchase doors: a group of slabs (one per way into the area) and a price label, with `metadata/cost`, `shop_id` and `requires`, written from the shop's tuning. `LotDoors.open` frees them; free `Doors` to walk everywhere (a test) |
| `CameraProbes` | markers at every narrow place, facing the way a player walks through; the camera test sweeps the shoulder camera from them |
| `Lighting` | the night's `WorldEnvironment` (sky, fog, ambient) and the moon; the numbers are constants in the generator |
| `*/Lamps` | the lights of an area, `metadata/circuit` naming the circuit they hang on ([above](#which-lamps-hang-on-which-circuit)); `LotLamps` reads them |
| `Switches` | the breaker posts (`metadata/circuit`, and `metadata/door` for the area's shop door; [above](#the-breaker-posts)); `LotSwitches` reads them |

The drive-in's own props (speaker posts, the counter, popcorn machine and menu board, the projector, the ticket booths
and the marquee, the screen's frame, picnic tables, trash cans) are placed by `tools/world/drivein_props.py`. A speaker
post stands in front of every other parked car's nose, towards the screen, never on a gap between cars nor within 1.4 m
of the line the shoulder camera takes through one nor within 1.5 m of a lamp post; a prop that replaces a greybox block
(the counter, projector, kiosks, screen frame) keeps that block's collision box exactly.

`game/world/drive_in/` holds the parts (`car.tscn`, `lamp_post.tscn`, `lot_lamps.gd`), the capture rig and
`camera_probe.gd` (the player's camera rig as a function: arm sweep plus shoulder). The scene is written by `tools/world/build_greybox.py`
(run it from the repository root and commit what it writes; the run must leave `git diff` empty), so a layout change is
a change to a constant or coordinate there, not hand edits to a 380-node scene. `game/tests/world/` checks:

- the areas and that the doors' prices and prerequisites equal the shop's (`test_drive_in_greybox.gd`);
- reachability: a navigation mesh baked per set of sold doors, each area reached only through its door
  (`test_drive_in_opening_order.gd`, with a negative control), and that an agent as wide as the shoulder camera still
  reaches every area; the doors themselves (`test_lot_doors.gd`); jumps (`test_drive_in_jump_reach.gd`); and the
  affordability column above (`test_door_affordability.gd`);
- the lamps: each on a known circuit, ground lit only by a circuit that is on and a tank with fuel, the flicker
  (`test_lot_lamps.gd`, and in a whole night with the dead's speed, `tests/night/test_night_lamps.gd`);
- the breaker posts: one per generator circuit, each naming its door, clear of every door's slabs, showing the
  circuit (`test_lot_switches.gd`); in a night the prompt, the throw, the held key, a downed player, a dry tank and
  the HUD (`tests/night/test_night_switches.gd`);
- the camera: the arm and the shoulder camera swept through every probe, both ways, both shoulders
  (`test_drive_in_camera.gd`), with a negative control that a 1.4 m gap between cars is caught.

To capture: `capture_rig.tscn` takes `-- --view=top|night_top|start|concession|concession_in|booth|yard|backlot|plaza|road`,
or `--view=tp:<probe>` for the shoulder camera at a probe (`--offset`, `--turn`, `--side`, `--y`, `--doors=closed`,
`--flood`; see the script's header).

### Props

The lot is dressed with the starting kit's props (the Quaternius Toon Shooter Game Kit, CC0), brought in by
`tools/blender/build_props.py` (scale 0.8, one shared palette, [style](style.md#props)) and placed by
`tools/world/lot_props.py`, which the generator calls: each area's props go under `<Area>/Dressing`, from the
`DRESSING` table there, and each prop is a scene in `world/drive_in/props/` (the model, plus a hidden CSG block of its
size where it stands in the way).

| Where | What |
| --- | --- |
| Field | the 76 parked cars: the lot's own 1950s sedan (`car.tscn`, five paints picked from where each car stands, never random); the four wrecks on the flanks; a broken pallet by the playground, cones by the shelter |
| Midway | a dumpster at the end of each alley, cartons where crate stack A was, a small container where B was, cones at the road gate |
| Generator yard | two pairs of containers where A and B were, six drums in two touching rows where the drum row was, cartons and pallets, two gas bottles on the generator cage's north wall, a water tank and tyres on the east fence |
| Back lot | the wreck rows are the kit's Broken Car (`wreck.tscn`); tyres, debris, a spilt drum |
| Road | the two wrecks are Broken Cars (the battery headlights sit at the west one's front); barriers and cones before the roadblock; crates by the kiosks |

Rules the placement keeps, all checked by the world tests:

- **Solid props are CSG.** The zombies' mesh is baked only from CSG shapes with collision (`navmesh_baker.gd`), so a
  prop that blocks has a hidden `CSGBox3D` or `CSGCylinder3D` with `use_collision`; a hidden CSG root still collides
  and bakes. A `StaticBody3D` would be solid for the player and invisible to the dead.
- **Clutter has no collision**: cones, pallets, planks, debris, a lone carton, a spilt drum, a gas can. It never closes
  a path or makes a slot.
- **No stairs out.** A prop a player can jump onto (a crate 0.63 m, a drum 0.82 m, tyres 0.87 m, a barrier 0.5 m) is
  kept away from anything taller and from low walls: a barrier by the road's 1.6 m end walls, or a climbable wreck
  beside them, failed `test_drive_in_jump_reach.gd`. The wreck's block is one box 1.3 m tall (no step at the bonnet),
  so it cannot be climbed from the ground.
- **No slots.** Props stand against a wall or touch each other, or leave at least a passage's width: nothing on the
  map is single file, and no prop stands in a door, a breach or its apron, a camera passage or a shop spot.

Capture views for the props, at the player's eye height (`--view=`): `yard_drums`, `yard_east`, `backlot_rows`,
`road_block`, `alley`, `midway_court`.

## Not yet decided

- The ramps: drive-in rows sit on shallow berms so rear cars see over front ones. The greybox is flat; berms are
  dressing, and a 0.3 m step needs the player controller's step height first.
- "Spawn only in open areas" needs the rules code: `ZombieDirector` is given its spawn points and does not ask which
  areas are open yet.
- What the road is for: the end of the night, an escape, or just the last door.
- Solo scaling of the door costs, which belongs in the round economy (the affordability table above shows one, two
  and four players at the same prices).
