# The lot

The drive-in map: seven areas, what opens in what order for how many points, where the dead can be kited, where the
light falls, how the night closes in on it and how it plays for four. The greybox that proves it is
`game/world/drive_in_greybox.tscn`, at true scale (the player capsule is 0.35 m by 1.8 m; see the
[style bible](style.md#scale)). The player is third person, so widths are sized for the shoulder camera, not the
capsule ([Widths and the camera](#widths-and-the-camera)).

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
| Prize crane | one of four places (below); it starts inside the stand, beside the cabinet that was there | `crane_play`: a play, a spin, then a weapon the player lacks that only the buyer can take; it can break down and move | the stand is the first door; a gamble to spend the first thousand on |
| Re-cut bench | the projection booth, in the middle of its floor at `(3.5, 28.2)`, facing the door, spot at `(3.5, 25.9)` | `upgrade_weapon`: re-cuts the weapon in hand ([the re-cut](upgrades.md)) | past the booth's door (750), mid rounds: the first thing the booth is for besides the rifle and the roost |
| Soda fountain | the concession stand, behind the counter at `(8.2, 4.9)`, facing the door, spot at `(8.2, 3.7)` | `tonic_hearty`: more health ([the hearty tonic](upgrades.md#the-hearty-tonic)) | in the first area that opens: a first thing to save for after the shotgun |
| Ammunition lockers (5) | the avenue (field), the stand (its north-east corner), the midway, the yard, the back lot | rounds for the weapon in hand, as many as fit | one in the open from the start, one more in each area that opens, so a fight is never a long walk from rounds |

### The crane's places

The crane stands on one place at a time (`crane.spot` in the rules, a marker with the metadata `crane_spot` here) and
moves when a play breaks it down ([the Mystery Box research](../research/mystery-box.md)). It moves only to a place
whose door is already open (`crane.spot_doors` in the tuning), so it is never somewhere nobody can reach. A light
beam over the current place says where it is.

| Index | Place | Door it needs | Why there |
| ---: | --- | --- | --- |
| 0 | inside the stand, `(-6.4, 5)` | the concession | where it starts; the first thing the first door buys |
| 1 | the midway, `(6, 14)`, on the open ground between the stand and the booth | the concession | a place to run to from the stand, with the booth's rifle wall and a locker near |
| 2 | the field, `(-24, -14)`, clear ground west of the avenue | none | the one place the open field has, so the crane is sometimes out in the dead's path |
| 3 | the yard, `(40, 10)` | the yard | late, with the generator: a reason to go there that is not fuel |

A play can only break down while another place is open to move to. The tests (`test_shop_spots.gd`) hold the markers to
one for each index and to the rules above.

The two machines are `RecutMachine` and `SodaFountain` (`game/world/machines/`), drawn from primitives like the crane
and placed in the greybox over the hidden blocks (`ReCutMachine`, `SodaFountain`) that keep their collision and their
place in the zombies' walking mesh. Each has a spot marker of its own kind (`upgrade`, `perk`); the marker of the
stand's locker moved 3.6 m north so the fountain's spot is farther than a reach from it.

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
  the cars to the dead, a pack's legs are hidden. Crouching is simulated now (capsule 1.2 m, pivot 1.1 m;
  [Player controller](../research/player-controller.md#crouching)) but not yet designed against.
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

| Area | Floor | Lit by the rules, every circuit on | What lights it |
| --- | ---: | ---: | --- |
| Screen field | 5,952 m² | 975 m² (16%) | eight lamp posts and the screen's glow: a strip 21 m wide and 36 m long down the avenue, and a disc at each flank post; the rim is dark |
| Concession | 240 m² | 217 m² (90%) | three warm lights; window spill on the field |
| Midway | 1,104 m² | 373 m² (34%) | two dim lamps and the booth's front light; the alleys dark |
| Booth | 120 m² | 110 m² (92%) | two lights, and the projector beam (the brightest thing on the map) |
| Generator yard | 1,932 m² | 451 m² (23%) | four work lamps and the generator's glow, a block in the middle of the ground: lit while the tank has fuel, and the most to lose |
| Back lot | 1,932 m² | 104 m² (5%) | one flickering neon sign |
| The road | 1,936 m² | 264 m² (14%) | the ticket kiosk, and a wreck's headlights (120 m², the only ground lit with the tank dry) |

"Lit" is the rules' word, not the eye's: ground within 6 m (`LotLamps.LAMP_REACH`) of a lamp whose circuit is on, counted
on a 0.5 m grid over each floor. It is the ground where the dead keep their round's pace, and
`game/tools/lot/lot_report.gd` prints this table and the ones in the two sections below. The glow in the capture above
reaches further than 6 m, so the picture looks lighter than the rule is; the table replaces the shares that were read
off that capture by eye (a third of the field, four fifths of the yard), which the measurement did not bear out.

The dead come in at the field's breaches ([below](#the-fences-breaches)), 31 to 47 m from the nearest lamp: they
arrive out of the dark 25% faster than their round's pace, and under a lit lamp they drop back to it: the light does not
slow the dead, it only withholds the speed-up, which is why every lamp costs fuel
([rounds](rounds.md#why-these-numbers)). When the generator dies the
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

What is solid changes the moment the rules say so; only the drawing moves, with one Tween a board and nothing per frame
(`test_barricade_motion.gd` steps them by hand, `tests/captures/board_motion.tscn` films them):

| | Motion | Numbers |
| --- | --- | --- |
| Torn | a drawn copy of the board (pooled, at most 5 a breach, the board's own mesh, no physics) is flung out of the field toward the one pulling it: up, a turn and a half about its length so it lands flat, one end swung out 20 to 34 degrees, then it sinks into the ground and is gone | rises 0.55 m, lands 1.2 m out, gravity 20 m/s²: down in 0.5 s from the lowest slot, 0.78 s from the top; sinks in 0.22 s |
| Mended | the board's body is in its slot at once; its mesh slides in from the field side swung up about one end (alternate ends board to board, as nailed by hand) and knocks home with a small overshoot | 0.5 m in, 55 degrees, 0.28 s, back-out easing |

A jump of several boards (a late join, a snapshot catching up) moves only the last board that changed; the others snap.
Binding to the rules at the start of a night snaps.

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

The rules decide, the lamps follow. The zombies' lit pace asks `GeneratorState` (`NightWorld.is_lit` ->
`LotLamps.lit_at`: a lamp within 6 m whose circuit is on and whose tank has fuel), never a light node, so a server
that draws nothing agrees with every client. The client's `LotLamps` mirrors `circuit_changed`, `fuel_empty`,
`fuel_restored` and each frame's `fuel`: a circuit that goes off hides its lights and darkens its posts' bulbs; in the
tank's last tenth (`brownout_fraction`) the lights sag and drop out in a flicker that is a function of the frame's
tick and the lamp's number (no clock, no random draw), so a recording and a test see the same lights; at an empty tank
they go out. Only the screen's glow outlasts the generator, at 30% (`afterglow`), and it lights no ground for the
dead. The flicker is only the picture: the lit pace stays whole until the tank is empty.

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
spawn there and they are faster off lit ground; keeps the field's circuit on; and when the tank falls below the low
line puts every other circuit out (in a break) and keeps them out until the tank is back 15 points above it.

### The fuel cans

The generator's tank only goes down, so the lot sells fuel: two **can stands** (`FuelSpots/*`, a crate of red cans with
a yellow band and a FUEL sign in `FuelProps`), each in an area behind its door. A player buys from the spot 1.1 m in
front of a stand, within `fuel_reach` (2 m, less than `use_reach`, so nobody buys through a wall):

| Stand | Where | Needs |
| --- | --- | --- |
| `SpotStand` | inside the concession, behind the counter, on the soda side (2.5, 3.7) | the concession's door |
| `SpotYard` | outside the generator cage's west wall, facing the yard's gate (35.4, 15.9) | the yard's door |

The concession's is where the design put fuel (the stand), the yard's is for the player who has fought to the generator
and finds it dry: the yard is `mains` and goes black with the tank. Each spot is a marker with the shop item
(`metadata/shop_id`, the rules' `fuel_can`) and the door (`metadata/door`); `LotFuel` reads them and the night asks it
which spot is in reach. Using one (`use`) sends `RulesAction.buy` for the item through the night server and the same
prompt path as the doors and the breaker posts; the rules price it (`ShopItem.fuel_offer`: a whole can at 100 + 20 per
round, or only the room left at its share of the price, nothing when the tank is full), and a hand buys at most every
`fuel_interval` (0.5 s). The HUD's card reads `FUEL CAN`, `+25 UNITS OF FUEL` (or `FILLS UP: +10 UNITS`, or `THE TANK IS
FULL`) and the price, and a refill shows the generator's card (`fuel_changed` with a positive delta).

The autopilot (`AutopilotFuel`) goes to the nearest open stand when the tank is at the low line and it can pay for a
can, and buys until the tank is back above 40%.

## A night that closes in

The second pillar. What the night does to the lot as the rounds go by, from the rules' tuning and the measured
greybox (`game/tools/lot/lot_report.gd`).

**The lot itself does not change with the round.** No lamp fails or dims because a round was reached and no breach
moves. The night around it does darken: the world reads the rules' `ambient_for_round` (0.60 falling to 0.15 by round
14, the "Light" column of [the tuning table](rounds.md#the-tuning-table)) and dims its ambient, moon, sky and fog with
it, so the lamps' pools stand out more each round (`NightLight`, see [the night's
environment](../research/night-environment.md#the-night-closes-in-with-the-round)). What also closes in is the
pressure on the same ground, and the tank that feeds its lamps:

| Round | What arrives | Zombies 1p / 4p | Spawn every 1p / 4p | Alive cap 1p / 4p | Pace, lit to dark (m/s) | Generator draw | Doors a solo player can afford |
| ---: | --- | --- | --- | --- | --- | ---: | --- |
| 1 | walkers | 4 / 11 | 3.20 / 1.28 s | 6 / 24 | 1.20 to 1.50 | x1.00 | none (the concession at 2) |
| 4 | the first runner | 9 / 24 | 2.83 / 1.13 s | 8 / 26 | 1.68 to 2.10 | x1.09 | concession, yard |
| 6 | the first crawler | 12 / 34 | 2.61 / 1.04 s | 10 / 28 | 2.00 to 2.50 | x1.15 | and the booth |
| 8 | the first brute | 17 / 46 | 2.40 / 0.96 s | 12 / 30 | 2.32 to 2.90 | x1.21 | and the back lot |
| 10 | Midnight Stampede (runners only) | 21 / 60 | 2.22 / 0.89 s | 13 / 31 | 2.64 to 3.30 | x1.27 | and the road: all five |
| 15 | Double Feature, a boss | 36 / 101 | 1.81 / 0.72 s | 17 / 35 | 3.44 to 4.30 | x1.42 | all |
| 20 | Crawl Space (crawlers only) | 54 / 151 | 1.47 / 0.59 s | 21 / 39 | 4.24 to 5.30 | x1.57 | all |
| 30 | | 101 / 282 | 0.98 / 0.39 s | 28 / 40 | 5.00 to 6.25 | x1.87 | all |

The columns are the rules' functions (`zombies_for_round`, `spawn_interval`, `alive_cap`, `speed_for_round`) and the
fuel tuning's `round_strain`; the doors column is [the affordability column above](#areas-and-opening-order). The pace
is the walker's: dark is x1.25 and never above 6.25. Three things close in: the dead come faster and in greater number,
the doors a player has bought put spawns inside the lot, and the generator burns more fuel for the same lamps.

### What darkens, and in what order

The rounds do not say; the tank and the player do. A circuit goes dark when someone throws its breaker, and all of them
go dark when the tank runs dry. A player choosing what to give up wants the ground each unit of fuel buys:

| Circuit | Lights | Ground it lights | Draw a minute, round 1 / 30 | Ground per unit of draw |
| --- | --- | --- | --- | ---: |
| `screen_lot` | the field's posts and the screen's glow | 969 m² of the field | 3.6 / 6.7 | 269 m² |
| `concession` | the stand, the midway's two lamps | 217 m² in the stand, 206 m² in the midway, 69 m² outside them | 3.0 / 5.6 | 164 m² |
| `booth` | the booth and the projector beam | 110 m² in the booth, 168 m² in the midway | 4.8 / 9.0 | 58 m² |
| `back_lot` | the neon sign, the ticket kiosk | 104 m² in the back lot, 112 m² on the road | 4.2 / 7.9 | 51 m² |
| `mains` | the yard's four work lamps and the generator's glow | 447 m² of the yard | none: the idle draw (1.8 / 3.4) | |
| `battery` | the wreck's headlights | 120 m² of the road | none: not the generator's | |

So the back lot and the booth go dark first, and the field's circuit last, and a team that does it that way keeps most
of the ground it can use. A tank with only the field's circuit on lasts 18.5 minutes of full-rate burn at round 1 and
9.9 at round 30; with every circuit on, 5.7 and 3.1 (the breaks burn half). When it runs low (the last tenth,
`brownout_fraction`) the lamps sag and flicker, and when it is empty every generator lamp is out: the screen keeps an
afterglow for the eye but lights no ground for the rules, the yard goes black, and the road's headlights are the only
lit ground on the lot, 60 m south of the field's fence. Every zombie is then 25% faster, everywhere.

### Where the dead come from as the lot opens

A new door adds its area's spawns to the pool, and a spawn is chosen by an equal roll over the open ones
(`ZombieDirector`, `NightWorld.spawn_points`):

| Area | Spawns | Metres from the nearest lamp | Boards to tear |
| --- | ---: | --- | --- |
| Field (the six aprons) | 6 | 31 to 47 | yes, five at each breach |
| Midway (with the concession) | 2 | 3 and 16 | no |
| Generator yard | 3 | 14 to 21 | no |
| Back lot | 3 | 13 to 38 | no |
| Road | 3 | 15 to 38 | no |

| Doors bought | Spawns in the pool | At the field's breaches |
| --- | ---: | ---: |
| none | 6 | 100% |
| concession | 8 | 75% |
| and the yard (the booth adds none) | 11 | 55% |
| and the back lot | 14 | 43% |
| and the road | 17 | 35% |

So buying a door moves the dead toward the light, and off the boards: a spawn inside an area has nothing to tear, and
it is 3 to 21 m from a lamp where a breach is 31 to 47 m. A team that opens every area has the field's breaches as a
third of the pressure. That is the closing in: the lot opens outward and the dead open with it.

### Proposed, not built

- **Nothing else is proposed.** A lamp that fails at a round, or a breach that moves, would be a new rule on top of a
  tank and a pace that already close in; a four-player capture at rounds 10, 20 and 30 should show whether the curve
  needs it before anyone adds one.

## Played together

The third pillar, for two to four players. The rules' scaling is in [rounds](rounds.md#the-tuning-table); this is what
it means on the ground.

### Where four stand to buy a door

A door opens for everyone and the buyer's points pay for it. The prompt shows within 3.2 m (`use_reach`) of a slab, on
the side the player arrives from, and four capsules abreast need 2.8 m (2 x 0.35 m each), so they fit the 3 m doors with
0.2 m to spare and the open ground in front holds them all in reach. Where each door is, from the greybox:

| Door | Slab | Opening | Nearest lamp of the circuit that serves it | Nearest field breach spawn |
| --- | --- | ---: | --- | ---: |
| Concession (350) | the stand's front, (0, -3.6) | 3 m | 1.6 m (the stand's light): bought in the light | 64 m |
| Generator yard (500) | the gate in the field's south fence, (40, -4) | 4 m | 17 m (the work lamps): bought in the dark | 32 m |
| Booth (750) | the booth's front, (0, 22.2), in the midway | 3 m | 0.1 m (the booth's light) | 79 m |
| Back lot (1250) | the gate in the field's south fence, (-40, -4) | 4 m | 38 m (the neon sign): bought in the dark | 32 m |
| Road (2000) | the plaza's gate, (0, 38) | 4 m | 6.0 m (the kiosk): at the edge of lit | 89 m |

The yard's and the back lot's gates are the odd ones. They stand in the field's far south fence, 30 m from the nearest
field lamp and 32 m from the nearest breach, so buying them is a team move into the dark where the dead are 25% faster,
not an errand for one. The start is no closer to danger: the players spawn 33 to 36 m from the nearest breach.

### Where a downed player can be revived

Not built: the rules only get a downed player up at the end of the round, for a tenth of their points, and have no
revive action yet ([rounds](rounds.md#open-questions)); the balance simulator assumes six seconds. The places to design
it for are the lit ground at least 30 m from every spawn that is open, which is little:

| Pocket | Size | Where | When |
| --- | ---: | --- | --- |
| The avenue | 858 m² | centre (0, -25), the lit strip below the screen | always, while the field's circuit is on |
| The stand | 192 m² | centre (0, 2) | after the concession, while its circuit is on |

There is none in the yard, the booth, the back lot or the road: the yard's door puts three spawns in the safest ground,
14 to 21 m from its lamps. A team that goes deeper than the stand has nowhere to put a downed player down safely.

### How the team shares the loops

A loop under about 40 m is too short for a pack to string out, and each pursuer needs a loop of its own to be led
round. The loops [above](#loops-for-kiting) arrive with the doors: only the car rows and the counter's 45 m before the
yard, then two loops of 110 m and 50 m with it. Four players can split across two loops from the yard, which they can
afford at round 5 (one player at round 4), and have none to spare for the first four rounds, when the dead number 11 to
24 for them: the early rounds are fought on the avenue and the rows, with the breaches' boards as the only wall.

### One player to four

| Round | Zombies 1p / 2p / 4p | Each player's share 1p / 2p / 4p | Spawn every 1p / 2p / 4p | Alive cap 1p / 2p / 4p |
| ---: | --- | --- | --- | --- |
| 1 | 4 / 6 / 11 | 4.0 / 3.0 / 2.8 | 3.20 / 2.13 / 1.28 s | 6 / 12 / 24 |
| 10 | 21 / 34 / 60 | 21 / 17 / 15 | 2.22 / 1.48 / 0.89 s | 13 / 19 / 31 |
| 20 | 54 / 86 / 151 | 54 / 43 / 38 | 1.47 / 0.98 / 0.59 s | 21 / 27 / 39 |
| 30 | 101 / 161 / 282 | 101 / 81 / 71 | 0.98 / 0.65 / 0.39 s | 28 / 34 / 40 |

Four face 2.8 times the dead of one, each of them faces 30% fewer, and they come 2.5 times as fast, through six breaches
(one and a half each). The four-player cap is the solo cap plus 18 and stops at 40 from round 21,
the ceiling of the lot ([zombies](zombies.md#crowd-budget), decided in #315: it was 46, six more than the lot ever stood).

### Is the lot too empty for four?

The numbers do not say so. The field's 5,952 m² has 76 cars on 650 m² of it, and the ground that matters is its lit
975 m²: 244 m² a head for four, a room 16 m on a side each. The four-player alive cap of 24 to 40 over the field is one
dead to 150 to 250 m², but they come through six gaps to the same strip. The yard and the back lot, at 1,932 m² each, are
twice the lit pool and 23% and 5% lit: a team of four there is at the edge of a flickering sign, which is the late
night's intent. Nobody has watched four players on it with the shoulder camera, so this is a reading of numbers and not
a verdict: a four-player capture (bots in a `Night` of four) at rounds 1, 10 and 20 is the evidence still owed.

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
| `Lighting` | the night's `WorldEnvironment` (sky, fog, ambient) and the moon; the numbers are constants in the generator, the round dims them (`NightLight`) |
| `*/Lamps` | the lights of an area, `metadata/circuit` naming the circuit they hang on ([above](#which-lamps-hang-on-which-circuit)); `LotLamps` reads them |
| `FuelSpots`, `FuelProps` | the fuel can spots (`metadata/shop_id`, `metadata/door`; [above](#the-fuel-cans)) and the crates, cans and signs; `LotFuel` reads the spots |
| `Switches` | the breaker posts (`metadata/circuit`, and `metadata/door` for the area's shop door; [above](#the-breaker-posts)); `LotSwitches` reads them |

The drive-in's own props (speaker posts, the counter, popcorn machine and menu board, the projector, the ticket booths
and the marquee, the screen's frame, picnic tables, trash cans) are placed by `tools/world/drivein_props.py`. A speaker
post stands in front of every other parked car's nose, towards the screen, never on a gap between cars nor within 1.4 m
of the line the shoulder camera takes through one nor within 1.5 m of a lamp post; a prop that replaces a greybox block
(the counter, projector, kiosks, screen frame) keeps that block's collision box exactly.

`game/world/drive_in/` holds the parts (`car.tscn`, `lamp_post.tscn`, `lot_lamps.gd`), the capture rig and
`camera_probe.gd` (the player's camera rig as a function: arm sweep plus shoulder). The scene is written by `tools/world/build_greybox.py`
(run it from the repository root and commit what it writes; the run must leave `git diff` empty), so a layout change is
a change to a constant or coordinate there, not hand edits to a 380-node scene. A change to any collision box also
needs the zombies' navigation meshes baked again (`tools/world/bake_lot_navmeshes.gd`, see
[the zombies](../research/zombies.md#the-meshes-are-baked-ahead-of-time-335)); a test fails until it is.
`game/tests/world/` checks:

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
- the fuel cans: a spot per stand, each selling a shop fuel item behind a shop door, on its area's ground, clear of the
  doors and posts, walkable with every door open (`test_lot_fuel.gd`); in a night the prompt, the purchase, a dry tank
  refilled with the lamps and the dead's speed following, the held key, a full tank, a poor player, the HUD card and the
  generator's card (`tests/night/test_night_fuel.gd`); the rules' offer (`tests/rules/test_fuel_refill.gd`);
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
| Field | the 76 parked cars: the lot's own 1950s sedan (`car.tscn`, five paints picked from where each car stands, never random); the four wrecks on the flanks; ten trees on the flanks and beside the screen; junk against the perimeter fence (tyres, sofas, a skip, pipes, drums); barriers on the north fence beyond the last car; low junk on the south strip; litter in the aisles |
| Midway | a dumpster at the end of each alley, cartons where crate stack A was, a small container where B was, cones at the road gate |
| Generator yard | two pairs of containers where A and B were, six drums in two touching rows where the drum row was, cartons and pallets, two gas bottles on the generator cage's north wall, a water tank and tyres on the east fence; pipes on the north fence, a skip by the fuel tanks, hoardings and drums on the south fence, crates on the cage's south wall, a tree, litter |
| Back lot | the wreck rows are the kit's Broken Car (`wreck.tscn`); tyres, debris, a spilt drum |
| Road | the two wrecks are Broken Cars (the battery headlights sit at the west one's front); barriers and cones before the roadblock; crates by the kiosks; queue barriers to the kiosks, a tree in each of the plaza's north corners, street lights on its side walls (models only, no light); hoardings at the road's west end, junk on its north verge, a skip, cones on the centre line |

Rules the placement keeps, all checked by the world tests:

- **Solid props are CSG.** The zombies' mesh is baked only from CSG shapes with collision (`navmesh_baker.gd`), so a
  prop that blocks has a hidden `CSGBox3D` or `CSGCylinder3D` with `use_collision`; a hidden CSG root still collides
  and bakes. A `StaticBody3D` would be solid for the player and invisible to the dead.
- **Clutter has no collision**: cones, pallets, planks, debris, papers, signs, a lone carton, a spilt drum, a gas can,
  the street lights. It never closes a path or makes a slot. A tree is solid only at its trunk (0.3 m, 2.4 m tall).
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
- What the road is for: the end of the night, an escape, or just the last door.
- Whether the door prices should scale with the party. They do not (a four-player team earns a little less a head
  and buys the yard a round later: [the affordability column](#areas-and-opening-order)), and the balance report has
  not asked for it.
