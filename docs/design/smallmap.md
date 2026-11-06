# The second map: the small indoor map

Deadnight's second map is small, close-quarters and indoors, built to the hard targets of
[the small-map formula](../research/maps/small-map-formula.md) (measured from Nacht der Untoten) on a floorplan of
our own. The look and its kit are [small map: art and kit](../research/maps/small-map-art.md); the outside seen
through the windows (the drive-in's world in the distance) is #638's; the links, windows, buys and the box are
[Playing it](#playing-it-links-windows-buys-and-the-box) below (#632). The outside, the windows and the perks' alcoves
were reworked so the building makes sense to a player ([Outside and windows](#outside-and-windows-917), #917).

The map is `game/world/smallmap/smallmap_greybox.tscn`, written by `tools/world/build_smallmap_greybox.py` and
`tools/world/build_smallmap_dress.py` (run the first from the repository root; a rerun leaves the scene unchanged). It
is shipped (#792): the picker's second card, "The back rooms", builds it. The greybox is the collision, the walking
mesh, the sockets and the shell materials (#631, #633); the dressing puts the kit's modelled pieces, lamps, machines
and the backdrop on those sockets ([Dressed](#dressed-792) below).

![The greybox from above: the ground floor, and the upper floor with the ring's lap in yellow](smallmap-plan.png)

## The layout

A depot of 1958 facing the drive-in across its yard: the hall is one storey at the front (south), its flat roof a
terrace; the rewind room behind it and the upper floor over both are the back. The yard is one level all round.
Metres, x east, z south.

| Room | Where (inside the walls) | What it is |
| --- | --- | --- |
| Start room | 16 x 14.5 m | the loading hall: a counter of 5 x 3.5 m on four pillars to run round, 2 windows (south, facing the drive-in's screen, and east), the players' start south of the counter facing the south window |
| Side room | 22 x 7.5 m, along the hall's north side and 6 m past it to the west | the rewind room: a row of four pillars joined by film racks to run round, a window on its north wall at the east end and a breach in the west end onto the shed |
| Upstairs | over the side room (22 x 7.6 m) and over the hall's north strip (16 x 4.5 m) | two halves joined by an opening with no door; 2 windows, both over the hall (south onto the terrace, west onto the gallery the dead climb to by the outside stair) |

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

The counter is solid to 1.5 m and the racks to 1.2 m, so a loop round them is a loop, and they leave the view over
them open. The body climbs 1.25 m from a standing start (the jump is 1.1 m), so a 1.2 m counter was climbed, and its
middle, 1.75 m from every edge, is out of every zombie's reach (a centre stays 0.5 m off the counter, a swing is 1.4 m):
a roost with nothing able to answer (#847). It stands above that now, and `test_smallmap_counter.gd` runs the body at it.
A rack is no roost: its top is 0.2 m from an edge, so the dead strike a player on it.

## Measured against the formula

`SmallMapMeasure` (`game/tests/world/smallmap/`) measures the scene; `test_smallmap_formula.gd` fails a row out of
its tolerance, and `smallmap_report.gd` prints this table:

```text
godot --headless --path game -s res://tests/world/smallmap/smallmap_report.gd
```

| # | Target | Measured | Tolerance | Holds |
| ---: | --- | --- | --- | --- |
| 1 | Total floor inside, all links open | 578.3 m² | 540 to 660 m² | yes |
| 2 | Floors | 2 | exactly 2 | yes |
| 3 | Rooms (upstairs in two halves joined by an opening) | 3 | exactly 3 | yes |
| 4 | Start room floor | 200.4 m² | 188 to 230 m² | yes |
| 5 | Side room floor | 150.2 m² | 138 to 168 m² | yes |
| 6 | Upstairs floor, the largest (halves 64 and 153 m²) | 216.7 m² | 197 to 241 m² | yes |
| 7 | Side room width (22 x 7.5 m, 2.93 widths long) | 7.5 m | 6 to 8 m | yes |
| 8 | Loop round the start room's counter and pillars | 29.0 m | 25 to 36 m | yes |
| 9 | Ceiling, floor to ceiling in every room | 3.20 m | 3 to 3.6 m | yes |
| 10 | Longest sight line indoors at eye height | 23.0 m | 16 to 24 m | yes |
| 11 | Paid links, each joining two rooms | 3 | exactly 3 | yes |
| 12 | One ring, closed only by the third link | yes | exact | yes |
| 13 | The ring's lap | 68.4 m | 48 to 72 m | yes |
| 14 | Loop round the side room's rack row | 31.2 m | 25 to 36 m | yes |
| 15 | Windows start / side (one a breach) / upstairs (over the hall), the maintainer's rule (#917), the side room's south-west window dropped (#994) | 2 / 2 / 2 | exact | yes |
| 16 | Directions to watch start / side / upstairs | 3 / 3 / 2 | exact | yes |
| 17 | Players' start (the middle of the eight places) to the nearest window | 4.4 m | 4 to 7 m | yes |
| 18 | A window's spawn outside it, on the yard (in by its own window, its room only) | 7.0 to 14.8 m | 5 to 15 m | yes |
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
- **Windows and spawns** (rows 15 to 18): the sockets in `Windows/` by the room they open into; with the links shut
  and the windows open, each spawn's way to the floor 1.5 m inside its own window comes in by that window (not round to
  another, #824), and it walks into its own room and no other (the yard's walls give each room's windows ground of
  their own, so the dead never go round outside from one room to another, and nor does a bot's way).
- **Ceilings and sight lines** (rows 9, 10): rays from about 870 standing points (every room's edge every 0.5 m and
  inside every metre) at eye height (1.55 m), against walls, frames and the windows' blockers; and up from the floor.
- **The camera** (rows 27, 28): the width across each probe at four heights, and the shoulder camera swept through
  each probe both ways, both shoulders, level, up and down (`CameraProbe`, the player's tuning).

The measures are checked on shapes whose answer is known (`test_smallmap_measure.gd`: a 10 x 10 m room, a 1.4 m gap,
a corridor that squeezes the shoulder camera, a line through a wall).

## Walking it

`test_smallmap_walk.gd` walks three real player bodies (`PlayerSimulation`) from goal to goal along the zombies' mesh
for 90 s and runs a body and a jump at every window from inside. `test_smallmap_escape_sweep.gd` runs the real body
at everything beside the walls (counters, cabinets, machines, the window sills): it stands it on every top of 1.25 m or
less within 6 m of a wall or a closed link's slab, and on the floor beside every taller top, sprints and jumps at what
is ahead, three hops deep, for each of the eight sets of links, and fails on a standing place outside the building
(the yards, the hall's roof), in a room the links do not open yet, or 2 m and more over its floor (#848). The long run
is the move soak:

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
rooms it leads to (`metadata/opens`): the side room's three for the door, the upstairs' two for the first stair, both
for the stair between the side room and the upstairs. The hall's two are open from the start.

A link's card speaks in the map's own words, not the lot's: `MapWords` (`smallmap_tuning.tres`, `words`) names each link
("Side room door", "Hall stairs", "Side room stairs"), says what it opens ("Opens the side room"), and calls a breach a
boarded window. The card, the marker over the link and the feed's line all read it (`NightHudBinding.door_name`); the
lot has no `MapWords` and keeps the HUD's defaults. `test_hud_link_words.gd` fails when a link has no words or a card of
the map names the lot (#697).

### The windows

The six entries (five windows and the breach) are `Barricade`s of five boards each (`Windows/Window_<id>/Boards`, the
rules' `BarricadeTuning.ids`), with the kit's 1.5 m boards (so a mended board swings about 0.75 m,
`Barricade.board_half`, not the fence breaches' 2.05). The dead rise on the yard 7 to 15 m from a window, walk to its
boards and tear them off one by one (1.2 s a board, as on the lot), then come in; an upper window's dead climb the
outside stair first and walk along the gallery or the terrace to it ([Outside and windows](#outside-and-windows-917)). A
player puts a board back for points, as at the lot's fence; the players-only blocker in the opening keeps everyone in
whatever the boards do (the sill is 0.9 m, the body climbs 1.25 m, `CameraProbe.BODY_REACH`).
`test_smallmap_windows.gd` runs a night of 24 at once and fails unless every one is torn and walked through, to the
room it opens into and the height it is at; it also fails a window without floor inside it or ground or a deck outside
it at its own height, and an upper window whose dead do not rise on the yard and walk up to it.

### The shop (formula rows 22 to 25)

| Where | What | Price | Ratio to P |
| --- | --- | ---: | ---: |
| Hall, west wall | Revolver (no longer the start weapon, #898: the House Pistol is; it hits three times as hard) | 270 | 0.6 |
| Side room, middle and north walls | Pump shotgun, Tommy gun | 540 each | 1.2 |
| Upstairs, two walls | Flare gun | 630 | 1.4 |
| | Pump shotgun (a second wall of it) | 540 | 1.2 |
| Upstairs, the cabinet (over the side room) | Hunting rifle | 675 | 1.5 |
| Side room, north wall: the box (our crane) | a random gun you lack | 425 | 0.94 |
| An ammunition locker in each room and one more upstairs | rounds for the weapon in hand | the shared table's | |

The six new firearms (#793) are the box's alone on this map: a wall sells only the weaker guns (the maintainer's rule,
issue 858). Prices climb room by room as the formula asks, each within 10% of its ratio (`test_smallmap_economy.gd`).
Five weapons make six places, so the shotgun hangs on two walls (same price, different rooms): the wall of a weapon
already carried sells its rounds. The box has **one place and never moves**: its `leave_chances` are empty, so no play
breaks it down; it needs no link (the walls around it are the side room's). The prizes are the lot's (the shotgun
heaviest). At most **24 dead stand at once**, whatever the round and the party (`alive_cap`, on a desktop and in the
browser).

**The six places are all there are** (#858, #910): a wall sells only the weaker guns ([the wall
tier](weapons.md#the-wall-tier)), so the pump 870, the MP5 and the M4A1 get no place on this map; they come only from
the box, with the other guns above the tier. **No wall sells a melee weapon** (#910): the crowbar's hall wall and the
bat's and the axe's upstairs walls (three of the first nine places) are gone, plaques and markers with them, and their
prices left the tuning; they were not given to another gun, because every gun a wall may sell already has a wall
(the shotgun two) and a second Tommy gun or flare gun would put more firepower on sale in a change meant to take
some out. The hall keeps the revolver, so the formula's wall count of 2 / 2 / 4 and a cabinet is now 1 / 2 / 2 and a
cabinet. `test_wall_tier.gd` fails on a seventh wall that sells one, or any melee weapon.

### What the map leaves out

Nacht has no power, and neither has this map: no generator, breaker post or fuel can (the tank never drains, there are
no circuits, and the lamps hang on the `battery` circuit that is always lit so the dead keep their lit pace under
them). It does not leave out the machines: Nacht has no perks and no upgrade, but **every map has the soda fountain,
the perks, the re-cut bench and the prize crane** (the maintainer, 2026-11-03, #859; row 25 of the formula). Issue 792
brought the lot's own (the six tonics and the re-cut bench) at the shared table's prices, so the overlay does not drop
the tonic and upgrade kinds ([Machines](#machines)), and `test_map_machines.gd` fails a map of the picker's list that
lacks one.

### Floors for the dead

The dead were flat before this map: a zombie kept the height it spawned at, struck at the flat distance and weighed
players by it. On a map that declares a storey (`metadata/storey`) `ZombieSim` now follows the walking mesh up and
down its stairs (its path points less the baker's 0.35 m lift), weighs a player on another floor by three metres of
walking a metre of height, and swings only at a target within half a storey in height and with no wall between them (a
ray at 1.3 m, over the racks; on a stair beside a wall the dead had struck through it). The ray looks
at walls only (`WorldProbe.static_callable`): it used to end on the player's own body, so the dead began a swing at
0.9 m and not at their 1.4 m reach and landed 40% of them where the lot's land 73% (#764; the numbers are on the
research page). A press reaches only the doors, spots and boards on the player's floor. The lot (storey 0) is
untouched; `test_zombie_storeys.gd` holds both.

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
box, then the machines: the hearty tonic, the re-cut, the swift rescue and
quick load tonics). The numbers are in the overlay, not in the bots, and the lot's are unchanged.

The overlay also turns on **`bot_team_links`**: a link a bot can pay for, in a calm with no dead within `bot_clear_from`,
is bought by the nearest bot that is free (a claim by distance, like a body's), outside the one-errand turn and the
door's 40 s rotation, so the busy and the far cover instead of waiting. A link set in a stair has a stand at its foot and
one a flight up; a door's stand is chosen by walking cost (8 m a metre of height), so a bot on the ground floor takes the
foot, not the flat-nearer stand it would reach only by going round the whole map. The lot leaves the flag off.

The overlay's **`bot_saves_for`** names the shotgun (and the re-cut and the hearty tonic, as the profiles do): while
the shotgun is out of reach nothing after it on the list is bought. And once a bot that holds only its start gun can
pay for a gun, nothing after that gun is offered either, the team link rule included, so the first gun comes before
the second and third stairs (#910: a solo bot that paid for both stairs first met round 3 with the revolver and went
down on one of four seeds).

### Proof

`tests/captures/smallmap_bot_night.tscn` plays a night of hosted bots to a round and prints the numbers (`--bots`,
`--rounds`, `--seed`, `--open=all` to sell the links first, `--trace`); the numbers and what they showed are
[the research page](../research/maps/small-map-play.md). In seven long nights (one bot, four bots, and four with every
link sold first) **round 10 was reached in all seven and cleared in three** (before the dead's swing check stopped
meeting the player's body it was five: #764); the first link was bought in round 1, the first stair by round 2, all
twelve windows (the layout before #917) were torn, and the most dead at once was 20. `test_smallmap_bot_night.gd`
plays a short night of one and of four in the tests; `test_smallmap_economy.gd`, `_links.gd`, `_buys.gd` and
`_windows.gd` pin rows 20 to 26 and every link, buy and window; the shoulder-camera captures are on the pull request.

## Outside and windows (#917)

The maintainer, playing round 12: the ground outside the upper windows was the same flat land as outside the ground
floor (a bank raised to the upper floor's height behind the building, and the hall's roof walked by the dead), the
ground floor should look out on the drive-in, the upper windows should be reached by the dead walking up outside stairs
onto a patio, one window a wall downstairs, no window above a stairwell, each perk in its own alcove. So the map was
laid out again to read as a building a person believes; the inside rooms, the loops and the ring did not move. The
proposal, the plans and the before and after captures are on the pull request.

**The outside is one place.** The ground is one level (0 m) all round; no bank. The backdrop is turned half a circle,
so the drive-in (its lit screen, the cars, the marquee) is south of the building, straight out of the hall's south
window the players spawn facing; the yard's gate and the road to the drive-in are on that side, and the sky's glow over
the screen (`screen_glow_direction`) points south. The yard is walled into three, as a depot's would be: the **front
yard** (the hall's windows), the **alley** along the hall's west side with the outside stair (the upper windows), and the
**back yard** round the north and west (the side room's windows and the shed behind the breach, its back door gone, so
its dead come in from the yard through it). The walls keep each room's dead on ground of their own: one open yard gave
the walking mesh a way out of one room's window and in by another's, which a bot took to reach the upper floor and then
stopped at the boards.

**The way up.** The hall is one storey; its flat roof is a **terrace** with a 1.1 m railing. A **gallery** (a deck on
posts, 2.5 m wide) runs along the outside of the hall's west wall at the upper floor's height, and one **outside stair**
climbs to it from the alley at the hall's south-west corner. The two upper windows open onto the gallery or the
terrace; their dead rise in the alley by the stair's foot and climb it, in view of the windows.

| Window | Room, wall | Outside it | Why the dead come from there |
| --- | --- | --- | --- |
| `start_1` | hall, south | the front yard, the gate and the drive-in's screen | the drive-in's side, straight across the yard |
| `start_4` | hall, east | the east yard and the pole line | round the building's east side |
| `side_2` | side room, north | the back yard and its trees | from the dark behind the depot |
| `side_breach` | side room, west | the shed, open to the yard | through the shed and the broken wall |
| `upper_a1` | upstairs over the hall, west | the gallery | up the alley's outside stair and along the gallery |
| `upper_a2` | upstairs over the hall, south | the terrace, and past its railing the yard and the screen | up the stair and across the terrace |

Removed: the hall's second south window and two of its three east ones, the side room's second south window, the
window over the side stair's well (`upper_b1` was there, #824) and the north upper window (now over a 3.4 m drop). The
upper floor's windows are both in the half over the hall: a window of the other half on the same deck would join the
two halves outside by a shorter way than the opening between them, and the night's walking mesh (the dead's, which the
bots walk too) would send a bot out of one window and in by the other, to stop at the boards (the first build had one,
and a bot never reached the rifle cabinet or the Third Holster). The
hall's west wall has no window: it is the shop wall inside and the outside stair outside.

**The side room's south-west window, dropped (#994).** The side room had a third entry, `side_1`, in its south wall
west of the hall, 2.8 m from the breach round the corner and 3.2 m from the Swift Rescue alcove beside it. A press
reaches 2.5 m from a window and 1.5 m from a shop spot, and two use zones keep 0.5 m of floor between them
([use reach](../research/use-reach.md#spacing-and-the-press-908)): the window needed 4.5 m to the alcove's spot and
5.5 m to the breach, and the room's west end (6 m wide, with the side stair's foot in its north-west corner) has room
for neither. Two openings in one corner were also one direction for the dead, not two. So the side room has one entry
at each end: the breach at the west, `side_2` at the north-east; the alcove stays. The breach moved 0.5 m south (its
middle at z -2.0) to keep the side stair's zone clear, still facing the shed's open back door.

**Each perk in its own alcove.** The five coolers stood in pairs on three walls. Each now stands at the back of a bay
2.4 m wide and 1.3 m deep out of an outside wall, open full height to the room, its spot at the bay's mouth, and no two
on one wall; the bays read from outside as bays of the building (a bay of two floors on the north wall, solid below
the upper ones).

## Dressed (#792)

`build_smallmap_dress.py` is called by the greybox builder after every box is written, so the scene stays one file from
one script. What each socket wears, and what moved to make it fit:

| Socket | Wears | What moved |
| --- | --- | --- |
| Windows (6) | the kit's window module (`wall_window_zombie`, `_upper` upstairs); boards in the module's own slots on the room side | the wall's gap runs to the module's 2.8 m top (a `Lintel` body fills it); the sill, jambs and blocker are collision only |
| The breach | a kit post each side of the gap, a beam across its top, walked-over rubble, and a 0.9 m sill of the wall's stone: it is a window like the others (#915), its boards in the same 0.9 to 2.2 m opening | the gap is the windows' 1.5 m, and the dead climb over the sill (`ZombieGate.sill`) |
| Door (hall to side room), upstairs opening | the kit's wide opening (`wall_opening_wide`), its own hidden jambs and lintel | the wall's gap is the module's 3 m wide; the clear opening is the 2.0 x 2.4 m it was |
| The door's leaf, the stairs' blockers | `door_purchase` stretched to 2 m, `debris_blocker` stretched to the 2 m flight; each with a `DoorGlow` of the far room's lamp | the slab stays (hidden): the walking mesh and `LotDoors` are as they were |
| The two flights | the kit's `stair_straight` stretched to 2.0 x 5.1 x 3.4 m over the greybox's hidden ramp (rails off, the flight has a wall each side) | none: the ramp is what is walked on |
| Pillars, racks | the kit's pillar to 2.8 m with a block band above it; two shelf racks a bay, squat as their 1.2 m collision so the view over them stays open | the boxes are hidden collision now |
| Lamps | `PendantLight` (`hang` 0.4 m: the kit's lamp hangs from 2.8 m, the ceiling is 3.2 m): one real light each (the `powered_light` group), a halo, a pool and a cone of haze | the 8 omni lamps at 2.9 m, range 8, are these lights at 2.45 m, range 5.5 |
| Extra light | decor pendants (no light slot) over the box and each shop wall, wall lanterns at the three links, moon shafts in two windows, chalk messages in four places | none |
| Cabinet | the kit's `tall_cabinet` with the plaque on end in its recess | the cabinet's box is the fixture's |
| Clutter | filing cabinets, chairs, tipped tables, a rubble cone, walked-over rubble, helmets, radios and lanterns (`Dressing`) | solid pieces stand against walls and in corners; the saved walking meshes are baked again |
| Outside | the backdrop (`backdrop.tscn`); the yard is the backdrop's 62 x 54 m, frosted ground, its boundary a wire fence seen through (the boxes that stop the dead are hidden), turned so the drive-in is south (#917) | the yard grew from 50 x 56 m; the haze is 0.035 (the lot's 0.013 barely shows in a 6 m room) |

Not done: the kit's pitched roof (`roof_bay`) and a broken bay's top light. The roof can be seen from nowhere a player
stands (the ceilings are flat slabs under it and the windows look out sideways), so it would cost triangles for no
picture; a hole in a ceiling with moon through it is an art issue of its own.

### Machines

The lot's machines (every map has them all, with the box as the crane), one to a place that has the room for it
(each is its `ShopProps` instance, a hidden block that holds its place in the walking mesh and a `ShopSpots`
marker 0.7 to 1.1 m in front of it):

| Where | Machine | Item and price |
| --- | --- | --- |
| Hall, west wall between the two plaques | soda fountain | hearty health tonic, 1000 |
| Side room, its north wall's alcove | Quick Load cooler | 2500 |
| Side room, its south-west alcove (under the gallery) | Swift Rescue cooler | 1500 |
| Upstairs, over the side room: the middle wall | re-cut bench | 1500 |
| Upstairs, the north wall's two alcoves | Double Shot (over Quick Load's) and Third Holster (west of the stairwell) coolers | 3000 each |
| Upstairs, the east wall's alcove | Reload Shock cooler | 2000 |

Each cooler stands alone at the back of its own alcove (#917); the dearest are upstairs, as the weapons' prices climb.
The perk coolers are drawn at 0.85 so their emblem (3.55 m at full size) clears the 3.2 m ceiling. The prices are the
shared table's (one source); the bots shop at the soda fountain, the re-cut bench and the first two coolers (the map's
`bot_shopping` list names them after the last link, #811); the Third Holster, Double Shot and Reload Shock coolers are a
person's.

## Sockets for the kit and for the night

| Node | What it is |
| --- | --- |
| `Start`, `Side`, `UpperA`, `UpperB` | a room each, with `room`, `rect` (x, z, width, depth) and `floor` metadata; walls, floors, pillars, counter, racks and stairs under it |
| `Windows/Window_<id>` | a window or the breach: on the wall's centre line at floor height, +Z into the room; `barricade_id`, `room`, `kind` (`window` or `breach`), `gap` (the wall's gap the walking mesh sees: 1.5 m wide so the dead's way, 0.5 m a side less, stays inside the 1.2 m opening, 2.2 m tall, the breach's too). Its frame, sill and the players-only blocker (layer 2, as the boards) are StaticBody3D children the bake never reads. Its `Boards` child is the `Barricade` (five `window_board` slots, `board_half` 0.75; `sill`, `thickness`, `gap_half` and `clear_half` for the dead's climb) |
| `ZombieSpawns/Spawn_<id>` | where the dead of each window rise, on the yard: 7 m outside a ground window, in the alley by the outside stair's foot for an upper one, outside the shed's open door for the breach; `barricade_id` and `room` |
| `Doors` (`LotDoors`) | `Door_Side`, `Stairs_Start`, `Stairs_Side`: `shop_id` (`door_side`, `door_stairs_start`, `door_stairs_side`), `requires` (none), `cost` (read from the map's tuning when the scene is written), `opens` (the rooms whose dead may rise once it is open); one slab each and a stand on each side |
| `ShopSpots`, `ShopProps` | the markers a player buys from (`kind` `wall`, `crane` or `ammo`, `shop_id`, `room`; the cabinet also `cabinet`, the box `crane_spot` 0) and their plaques, signs, crates and cabinet: none of it is CSG, so the walking mesh does not read it, but for the four ammunition lockers (`StaticBody3D`s in the group `navmesh_obstacle`, `NavmeshBaker.OBSTACLE_GROUP`: baked in as boxes, so the dead and the bots walk round them, #1340) |
| `PlayerSpawns` (fifteen places, one for each body of a full night: the first eight in two rows south of the counter, 1.3 to 2 m apart, the other seven in the start room round them, 1.8 m or more from each other), `CameraProbes`, `Measure` | the players' start; the camera's narrow places; the ring's and loops' markers and each room's middle |
| `Ceilings`, `Roof`, `Outside` | the slabs (the terrace is `Ceilings/Terrace`), the roof, the alcoves' bays, and outside the yard, its walls (`Alley*`, `YardWallE`), the shed, the outside stair (`OutStair*`) and the gallery (`Gallery*`): #638 dresses `Outside` |

The zombies' meshes for the eight sets are saved in `game/world/smallmap/smallmap_navmeshes.res` (`LotNavmeshes`);
bake them again after the geometry changes (and after a body joins or leaves the group `navmesh_obstacle`):

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
