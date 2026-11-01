# The lot

The drive-in map: seven areas, what opens in what order for how many points, where the dead can be kited, where the
light falls. The greybox that proves it is `game/world/drive_in_greybox.tscn`, at true scale (the player capsule is
0.35 m by 1.8 m; see the [style bible](style.md#scale)).

The layout is our own. The genre's map-flow principles were studied for understanding only: a first area that is
safe to learn in, doors that show what they will open before they are bought, every purchased area adding a loop,
and no area whose only way on is back through the last.

![The lot, top-down, evenly lit](map-plan.png)

North is up, the screen at the top. The numbers are the opening order; the red slabs are the purchase doors, with
their cost.

## Areas and opening order

The round economy is not written yet (`rounds.md` is another engineer's page). These costs rest on assumptions, and
every cost is one number on its door (`metadata/cost`), so changing them is a one-line edit.

**Assumed economy:** a hit pays 10, a kill 60; round N brings the team about 6 + 3N dead, so a team earns about 630
points in round 1 and 100 more in each next round (cumulative: 1.5k by round 2, 5.3k by round 5, 15.8k by round 10).
Doors should take about half of everything earned; the rest buys weapons, fuel and tonics.

| Plan | Area | Opens | Cost | Needs | Cumulative door spend (round it fits) |
| --- | --- | --- | --- | --- | --- |
| 1 | Screen field | start | free | - | 0 |
| 2 | Concession stand, then the midway behind it | round 2 | 750 | field | 750 (round 2) |
| 5 | Generator yard | round 4 | 1000 | concession | 1,750 (round 4) |
| 4 | Projection booth | round 5 | 1250 | concession | 3,000 (round 5-6) |
| 6 | Back lot | round 7 | 1750 | concession | 4,750 (round 7-8) |
| 7 | The road | round 10 | 2500 | concession | 7,250 (round 9-10) |

Where this departs from the [overview](index.md): the generator yard opens before the booth and the back lot, not
with them. Light is the first pillar, and the generator's starter tank has to be refuelled (fuel is bought at the
concession) before it runs dry, which this plan puts around round 4. The overview's table should follow.

`Plan` is the number on the plan above; the table is in opening order.

Rules the greybox is built to:

- A door opens an area; areas open outward. Zombies spawn only in open areas, and always in the field.
- A doorway between two open areas is a link and needs no purchase. The midway's links to the yard and back lot are
  plain gaps in the greybox; they only matter once both sides are open.
- Every purchased area adds at least one loop, so buying a door always buys somewhere to run.

## Choke points

| Where | Width | What it does |
| --- | --- | --- |
| Concession front door | 3 m | the first door; the dead queue on the field side |
| Yard gate, back lot gate, road gate | 4 m | one pack wide; a good place to hold, a bad place to stand |
| Concession rear exits | 1.8 m | single file; the stand empties into the midway slowly |
| Midway links to the yard and back lot | 4.5 m | the joints of the two long loops |
| Gaps between cars | about 1.4 m | a player fits (0.7 m wide), a pack does not; the rows are a funnel, not a wall |
| Booth ramp | 1.6 m | one at a time; a roost with no second way down |

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
- **Behind the car rows**: cars are 1.65 m tall, about eye height (1.7 m): a standing player sees over them, a pack
  hides its legs. Crouching breaks the line.
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

`game/world/drive_in_greybox.tscn`: CSG boxes, one flat colour per area, no scripts. Metres, Y up, x east, z south;
the screen is at z = -48 and the road at z = 52 to 64.

| Node | Holds |
| --- | --- |
| `Field`, `Concession`, `Midway`, `ProjectionBooth`, `GeneratorYard`, `BackLot`, `Road` | an area: ground, walls, props, `Lamps`, `ZombieSpawns`, a hidden `Label` |
| `Field/PlayerSpawns` | four markers on the apron below the screen |
| `Doors` | the five purchase slabs; `metadata/cost` is the price. Hide or delete it to walk everywhere |
| `Lighting` | the night environment and the moon |

`game/world/drive_in/` holds the parts (`car.tscn`, `lamp_post.tscn`) and the capture rig. The scene is written by
`tools/world/build_greybox.py` (run it from the repository root and commit what it writes), so a layout change is a
change to a coordinate there, not hand edits to a 350-node scene. `game/tests/world/` checks the areas, the door
costs, and that a player-sized capsule passes every doorway and is stopped by every door.

To capture: `capture_rig.tscn` takes `-- --view=top|night_top|start|concession|concession_in|booth|yard|backlot|plaza`.

## Not yet decided

- The ramps: drive-in rows sit on shallow berms so rear cars see over front ones. The greybox is flat; berms are
  dressing, and a 0.3 m step needs the player controller's step height first.
- How zombies path: link doors and breaches need a navigation mesh, and "spawn only in open areas" needs the rules
  code.
- What the road is for: the end of the night, an escape, or just the last door.
- Solo scaling of the door costs, which belongs in the round economy.
