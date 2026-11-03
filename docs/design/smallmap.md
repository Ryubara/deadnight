# The second map: the small indoor map

Deadnight's second map is small, close-quarters and indoors, built to the hard targets of
[the small-map formula](../research/maps/small-map-formula.md) (measured from Nacht der Untoten) on a floorplan of
our own. The look and its kit are [small map: art and kit](../research/maps/small-map-art.md); the outside seen
through the windows (the drive-in's world in the distance) is #638's; the links, windows, buys and the box are
[Playing it](#playing-it-links-windows-buys-and-the-box) below (#632).

The greybox is `game/world/smallmap/smallmap_greybox.tscn`, written by `tools/world/build_smallmap_greybox.py`
(run it from the repository root; a rerun leaves the scene unchanged). It is its own scene: the map picker (#624)
wires it into the night later. Its walls, floors and ceilings already wear the kit's shell materials (#633); the
kit's modelled pieces (`game/world/smallmap/fixtures/`) go into its sockets later.

![The greybox from above: the ground floor, and the upper floor with the ring's lap in yellow](smallmap-plan.png)

## The layout

A two-storey depot of 1958 cut into a bank: its back (north) wall is underground on the ground floor, and the upper
floor's back windows open onto the bank's top. Metres, x east, z south.

| Room | Where (inside the walls) | What it is |
| --- | --- | --- |
| Start room | 16 x 14.5 m | the loading hall: a counter of 5 x 3.5 m on four pillars to run round, 5 windows (2 south, 3 east), the players' start south of the counter |
| Side room | 22 x 7.5 m, along the hall's north side and 6 m past it to the west | the rewind room: a row of four pillars joined by film racks to run round, 2 windows south and a breach in the west end onto a dead-end pocket |
| Upstairs | over the side room (22 x 7.6 m) and over the hall's north strip (16 x 4.5 m) | two halves joined by an opening with no door; 2 windows north onto the bank, 2 south onto the hall's roof |

The links: the door between the hall and the rewind room at the hall's north-east corner, and one stair in each
ground room along its north wall, each rising east into the half above it. Every link costs the same (#632 sets the
price); none needs another, so the team picks the order, and the third closes the ring.

Three sketches were tried against the targets before building (the formula fixes the graph: two ground rooms, an
upper floor over both, three links in a ring, so every layout is a box or an L):

| Sketch | The side room | Fails |
| --- | --- | --- |
| A | beside the hall, the door in the middle of its long side | sight lines of about 30 m through the door, corner to corner (row 10: 24 m at most) |
| B | off the hall's end, the door in its end wall | 36 m along its axis through the door |
| C (built) | along the hall's north side and 6 m past its west end, the door where they overlap at the hall's north-east corner | nothing: the longest line is 23 m |

The counter and the racks are solid to a little over a jump (1.2 m), so a loop round them is a loop, and they leave
the view over them open.

## Measured against the formula

`SmallMapMeasure` (`game/tests/world/smallmap/`) measures the scene; `test_smallmap_formula.gd` fails a row out of
its tolerance, and `smallmap_report.gd` prints this table:

```text
godot --headless --path game -s res://tests/world/smallmap/smallmap_report.gd
```

| # | Target | Measured | Tolerance | Holds |
| ---: | --- | --- | --- | --- |
| 1 | Total floor inside, all links open | 584.6 m² | 540 to 660 m² | yes |
| 2 | Floors | 2 | exactly 2 | yes |
| 3 | Rooms (upstairs in two halves joined by an opening) | 3 | exactly 3 | yes |
| 4 | Start room floor | 205.2 m² | 188 to 230 m² | yes |
| 5 | Side room floor | 150.8 m² | 138 to 168 m² | yes |
| 6 | Upstairs floor, the largest (halves 66 and 162 m²) | 227.7 m² | 197 to 241 m² | yes |
| 7 | Side room width (22 x 7.5 m, 2.93 widths long) | 7.5 m | 6 to 8 m | yes |
| 8 | Loop round the start room's counter and pillars | 29.0 m | 25 to 36 m | yes |
| 9 | Ceiling, floor to ceiling in every room | 3.20 m | 3 to 3.6 m | yes |
| 10 | Longest sight line indoors at eye height | 23.0 m | 16 to 24 m | yes |
| 11 | Paid links, each joining two rooms | 3 | exactly 3 | yes |
| 12 | One ring, closed only by the third link | yes | exact | yes |
| 13 | The ring's lap | 68.1 m | 48 to 72 m | yes |
| 14 | Loop round the side room's rack row | 31.2 m | 25 to 36 m | yes |
| 15 | Windows start / side (one a breach) / upstairs (both halves) | 5 / 3 / 4 | exact | yes |
| 16 | Directions to watch start / side / upstairs | 3 / 3 / 2 | exact | yes |
| 17 | Players' start to the nearest window | 5.2 m | 4 to 7 m | yes |
| 18 | A window's spawn outside it (and only its room reached) | 6.0 to 7.0 m | 5 to 15 m | yes |
| 19 | Stairs, one from each ground room, rising 3.4 m | 2 | exactly 2 | yes |
| 27 | Narrowest camera passage (doors 2.0 m) | 1.9 m | at least 1.8 m | yes |
| 28 | Camera probes at every door, stair and corner, the lens never in a wall | 15 probes, 1980 samples | exact | yes |
| 29 | No names, writing or props from Nacht der Untoten | 0 | exact | yes |

How each is measured:

- **Areas** (rows 1, 4 to 6): a navigation mesh with no agent radius and 0.05 m cells (the floor a body stands on),
  baked with every window's gap plugged so it is the inside only; the polygons joined to the players' start; each
  counted to the room whose rectangle holds its middle on its floor (a stair's lower half to its ground room, its
  upper half upstairs). The counter's top and the space under a stair are not reached, so they do not count.
- **Links, ring and loops** (rows 3, 8, 11 to 14): the zombies' mesh (the night's sizes) for each of the eight sets of
  sold links, windows plugged: which room middles reach which. The lap and the loops are paths along the mesh through
  the markers in `Measure/`.
- **Windows and spawns** (rows 15 to 18): the sockets in `Windows/` by the room they open into; each spawn walks into
  its own room and no other with the links shut and the windows open (each room's windows open onto ground of their
  own outside, so the dead never go round from one room to another outside).
- **Ceilings and sight lines** (rows 9, 10): rays from about 870 standing points (every room's edge every 0.5 m and
  inside every metre) at eye height (1.55 m), against walls, frames and the windows' blockers; and up from the floor.
- **The camera** (rows 27, 28): the width across each probe at four heights, and the shoulder camera swept through
  each probe both ways, both shoulders, level, up and down (`CameraProbe`, the player's tuning).

The measures are checked on shapes whose answer is known (`test_smallmap_measure.gd`: a 10 x 10 m room, a 1.4 m gap,
a corridor that squeezes the shoulder camera, a line through a wall).

## Walking it

`test_smallmap_walk.gd` walks three real player bodies (`PlayerSimulation`) from goal to goal along the zombies' mesh
for 90 s and runs a body and a jump at every window from inside. The long run is the move soak:

```text
godot --headless --path game res://tests/captures/smallmap_move_soak.tscn -- --minutes=20 --bodies=4 --seed=1
```

Four bodies for 20 game minutes (44 s of wall time): 1242 legs, all 1242 reached, 21.9 km walked, no second stuck, no
tick outside the building. The bodies are on a physics layer of their own: in a first run, two that met head-on on a
2 m stair stood on each other for 36 s, which is a steering question (the bots' meeting rule), not the map's.

## Playing it: links, windows, buys and the box

The map plays by the lot's rules table with an **overlay** of its own (`MapTuning`,
`game/world/smallmap/smallmap_tuning.tres`, laid over a copy of `default_tuning.tres` by `MapTuning.apply`): what the
maps share (rounds, points, health, the dead, ammunition) stays in one place, and the map holds only what it
changes. The scene names its overlay in `metadata/tuning`, and `test_smallmap_economy.gd` fails when the scene's
markers and the overlay disagree. The night, a seated night and the balance simulator (`--map=small_indoor`) all lay
it over the table the same way (`NightWorld.rules_for`).

### The links

Three links, one price **P = 450**, 2.25 times the 200 starting points (Nacht: 2.0). By the lot's affordability count
(one player, half the points on doors) 450 opens one link at round 3, two at round 4 and three at round 5, each
within a round (formula rows 20 and 21); `test_smallmap_economy.gd` recomputes it from the tuning and fails a price
outside 400 to 475. None needs another (`requires` is empty): the team picks the order, and the third closes the ring.
A link is bought like a lot door: stand by its slab, press use, pay; the slab goes and the walking mesh of the new set
is swapped in. A stair's slab sits at the foot, so it is bought from below or from its own flight, never from the floor
above (a press reaches only what is on its floor: `NightWorld.on_level`). Each link also opens the dead's windows of the
rooms it leads to (`metadata/opens`): the side room's three for the door, the upstairs' four for the first stair, both
for the stair between the side room and the upstairs. The hall's five are open from the start.

A link's card speaks in the map's own words, not the lot's: `MapWords` (`smallmap_tuning.tres`, `words`) names each link
("Side room door", "Hall stairs", "Side room stairs"), says what it opens ("Opens the side room"), and calls a breach a
boarded window. The card, the marker over the link and the feed's line all read it (`NightHudBinding.door_name`); the
lot has no `MapWords` and keeps the HUD's defaults. `test_hud_link_words.gd` fails when a link has no words or a card of
the map names the lot (#697).

### The windows

The twelve windows are `Barricade`s of five boards each (`Windows/Window_<id>/Boards`, the rules'
`BarricadeTuning.ids`), with the kit's 1.5 m boards (so a mended board swings about 0.75 m, `Barricade.board_half`, not
the fence breaches' 2.05). The dead rise 6 to 7 m outside a window, walk to its boards and tear them off one by one
(1.2 s a board, as on the lot), then come in, up to the floor the window is on (the upper windows open onto the bank and
the hall's roof at the upper floor's height). A player puts a board back for points, as at the lot's fence; the
players-only blocker in the opening keeps everyone in whatever the boards do (the sill is 0.9 m, a jump is 1.1 m).
`test_smallmap_windows.gd` runs a night of 24 at once and fails unless every one of the twelve is torn and walked
through, to the room it opens into and the height it is at.

### The shop (formula rows 22 to 25)

| Where | What | Price | Ratio to P |
| --- | --- | ---: | ---: |
| Hall, west wall | Revolver (back in the pool once given up) | 90 | 0.2 |
| Hall, west wall | Crowbar | 270 | 0.6 |
| Side room, east and north walls | Pump shotgun, Tommy gun | 540 each | 1.2 |
| Upstairs, four walls | Baseball bat | 540 | 1.2 |
| | Flare gun | 630 | 1.4 |
| | Fire axe | 720 | 1.6 |
| | Pump shotgun (a second wall of it) | 540 | 1.2 |
| Upstairs, the cabinet (over the side room) | Hunting rifle | 675 | 1.5 |
| Side room, north wall: the box (our crane) | a random gun you lack | 425 | 0.94 |
| An ammunition locker in each room and one more upstairs | rounds for the weapon in hand | the shared table's | |

Prices climb room by room as the formula asks, each within 10% of its ratio (`test_smallmap_economy.gd`). Eight
weapons make nine places, so the shotgun hangs on two walls (same price, different rooms): the wall of a weapon already
carried sells its rounds. The box has **one place and never moves**: its `leave_chances` are empty, so no play breaks
it down; it needs no link (the walls around it are the side room's). The prizes are the lot's (the shotgun heaviest).
At most **24 dead stand at once**, whatever the round and the party (`alive_cap`, on a desktop and in the browser).

### What the map leaves out

Nacht has no perks, no upgrade and no power, and so far neither has this map: no generator, breaker post, fuel can,
tonic or re-cut bench (the tank never drains, there are no circuits, and the lamps hang on the `battery` circuit that
is always lit so the dead keep their lit pace under them). Whether any of it comes to this map is the **maintainer's**
decision (formula rows 25 and 30); this is the formula's default, in force until it is answered, and adding any of it
back is one more row in this overlay plus its marker in the scene.

### Floors for the dead

The dead were flat before this map: a zombie kept the height it spawned at, struck at the flat distance and weighed
players by it. On a map that declares a storey (`metadata/storey`) `ZombieSim` now follows the walking mesh up and down
its stairs (its path points less the baker's 0.35 m lift), weighs a player on another floor by three metres of walking
a metre of height, and swings only at a target within half a storey in height and with no wall between them (a ray at
1.3 m, over the counter and the racks; on a stair beside a wall the dead had struck through it). A press reaches only
the doors, spots and boards on the player's floor. The lot (storey 0) is untouched; `test_zombie_storeys.gd` holds both.

### What a night reads from a map scene

`MapLayout` reads the scene once: the lot's `<Area>/ZombieSpawns` and `Field/PlayerSpawns`, or this map's flat
`ZombieSpawns` (each marker's `room`) and `PlayerSpawns`; the root's `metadata/start_areas`, `storey`, `navmeshes`
(the saved meshes) and `tuning`; each door's `opens`. The picker (#624) wires the scene in; the tests and captures give
it to the night with `Night.scene` or `SeatedNight`'s `scene`.

### Bots on the map

The bots were written for 100 m of open ground: no errand while a dead one is within 12 m, a lull to shop in only when
a quarter of the round is left, and every profile's list names the lot's doors. On a 600 m² map the dead are always
near, so the overlay gives them their own numbers (`bot_clear_from` 5 m, `bot_calm_share` 0.6, `bot_hurt_share` 0 and
its own `bot_shopping` list: the first link, the shotgun, the Tommy gun, the first stair, the rifle, the second stair, the
box). The numbers are in the overlay, not in the bots, and the lot's are unchanged.

### Proof

`tests/captures/smallmap_bot_night.tscn` plays a night of hosted bots to a round and prints the numbers (`--bots`,
`--rounds`, `--seed`, `--open=all` to sell the links first, `--trace`); the numbers and what they showed are
[the research page](../research/maps/small-map-play.md). In seven long nights (one bot, four bots, and four with every
link sold first) **round 10 was reached in all seven and cleared in five**; the first link was bought in round 1, the
first stair by round 3, all twelve windows were torn, and the most dead at once was 22. `test_smallmap_bot_night.gd`
plays a short night of one and of four in the tests; `test_smallmap_economy.gd`, `_links.gd`, `_buys.gd` and
`_windows.gd` pin rows 20 to 26 and every link, buy and window; the shoulder-camera captures are on the pull request.

## Sockets for the kit and for the night

| Node | What it is |
| --- | --- |
| `Start`, `Side`, `UpperA`, `UpperB` | a room each, with `room`, `rect` (x, z, width, depth) and `floor` metadata; walls, floors, pillars, counter, racks and stairs under it |
| `Windows/Window_<id>` | a window or the breach: on the wall's centre line at floor height, +Z into the room; `barricade_id`, `room`, `kind` (`window` or `breach`), `gap` (the wall's gap: 2.0 m wide, 2.2 m tall, 2.4 for the breach). Its frame, sill and the players-only blocker (layer 2, as the boards) are StaticBody3D children the bake never reads. Its `Boards` child is the `Barricade` (five `window_board` slots, `board_half` 0.75) |
| `ZombieSpawns/Spawn_<id>` | where the dead of each window rise: 6 to 7 m outside it, `barricade_id` and `room` |
| `Doors` (`LotDoors`) | `Door_Side`, `Stairs_Start`, `Stairs_Side`: `shop_id` (`door_side`, `door_stairs_start`, `door_stairs_side`), `requires` (none), `cost` (read from the map's tuning when the scene is written), `opens` (the rooms whose dead may rise once it is open); one slab each and a stand on each side |
| `ShopSpots`, `ShopProps` | the markers a player buys from (`kind` `wall`, `crane` or `ammo`, `shop_id`, `room`; the cabinet also `cabinet`, the box `crane_spot` 0) and their plaques, signs, crates and cabinet: none of it is CSG, so the walking mesh does not change |
| `PlayerSpawns`, `CameraProbes`, `Measure` | the players' start; the camera's narrow places; the ring's and loops' markers and each room's middle |
| `Ceilings`, `Roof`, `Outside` | the slabs, the roof, and the ground outside (yards, the bank, the breach's pocket): #638 dresses `Outside` |

The zombies' meshes for the eight sets are saved in `game/world/smallmap/smallmap_navmeshes.res` (`LotNavmeshes`);
bake them again after the geometry changes:

```text
godot --headless --path game -s res://tools/world/bake_lot_navmeshes.gd -- \
  --scene=res://world/smallmap/smallmap_greybox.tscn --out=res://world/smallmap/smallmap_navmeshes.res
```

## Where it parts from the kit page

The formula's rows win where the two sister pages disagree; the kit (#633, #634) follows these numbers on this map:

- **The storey is 3.4 m** (3.2 m clear and a 0.2 m slab), not 3.0: row 9 asks 3.0 to 3.6 m of ceiling and row 19 a
  rise of 3.3 to 4.0 m. The kit's 2.8 m wall modules take a 0.4 m band on top; a stair is 17 risers of 0.2 m on 0.3 m
  treads (the kit's pitch, two steps more).
- **The door and the upstairs opening are 2.0 m wide, the stairs 2.0 m** (the kit's wide opening), not 1.4: row 27
  asks every camera passage 1.8 m and doors 2.0 m. The windows keep the kit's 1.2 x 1.3 m opening; their 2 m module is
  the gap in the wall the walking mesh sees.
