# The second map: the small indoor map

Deadnight's second map is small, close-quarters and indoors, built to the hard targets of
[the small-map formula](../research/maps/small-map-formula.md) (measured from Nacht der Untoten) on a floorplan of
our own. The look and its kit are [small map: art and kit](../research/maps/small-map-art.md); the outside seen
through the windows (the drive-in's world in the distance) is #638's; doors, buys and the box are #632's.

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

## Sockets for the kit and for #632

| Node | What it is |
| --- | --- |
| `Start`, `Side`, `UpperA`, `UpperB` | a room each, with `room`, `rect` (x, z, width, depth) and `floor` metadata; walls, floors, pillars, counter, racks and stairs under it |
| `Windows/Window_<id>` | a window or the breach: on the wall's centre line at floor height, +Z into the room; `barricade_id`, `room`, `kind` (`window` or `breach`), `gap` (the wall's gap: 2.0 m wide, 2.2 m tall, 2.4 for the breach). Its frame, sill and the players-only blocker (layer 2, as the boards) are StaticBody3D children the bake never reads |
| `ZombieSpawns/Spawn_<id>` | where the dead of each window rise: 6 to 7 m outside it, `barricade_id` and `room` |
| `Doors` (`LotDoors`) | `Door_Side`, `Stairs_Start`, `Stairs_Side`: `shop_id` (`door_side`, `door_stairs_start`, `door_stairs_side`), `requires` (none), a placeholder `cost` of 450 until #632 puts the price in the shop; one slab each and a stand on each side |
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
