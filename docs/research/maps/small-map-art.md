# Small map: art and kit

What the maintainer's 15 reference images of Nacht der Untoten (Call of Duty: World at War, 2008, and its later
re-releases) teach about the look and the production of a small, tight survival map, and the modular kit our own
second map needs (issue #623). The design numbers (area, rooms, entries, loops, prices) are the sister page's work,
[the small-map formula](https://github.com/Ryubara/deadnight/issues/622) (`docs/research/maps/small-map-formula.md`).
This page covers the look and the assets.

The images are visual reference only. They stay in the workspace's `refs/deadnight/nacht-der-untoten/`, are never
committed, and nothing in them is traced, extracted or copied: no layout, no texture, no lettering, no model. We take
the mood and the production lessons and build them in Deadnight's own style ([style bible](../../design/style.md)):
chunky chamfered shapes, flat palette swatches, a cool night with warm pools of light.

**The maintainer's decision (2026-11-02):** the floorplan is our own, never a copy. Its scale and close-quarters feel
match Nacht closely: tight rooms, low ceilings, narrow doorways and stairs. The look fits Deadnight seamlessly. The
kit below is therefore sized to the reference's doors, windows, stairs and ceilings ([Scale](#scale)), and the
blockout renders put it beside our own Soldier, zombie and drive-in props ([Blockout](#blockout)).

## The images, one by one

Three generations of the map appear in the set, and they differ in look. The original (2008) is grey and blue with
little colour. A later re-release looks much the same with a newer HUD. The remaster is warmer, denser and darker.
Where they disagree, the original's readability is the one to follow: it has fewer, bigger shapes, which is our
style anyway. HUD elements (points, tally marks, a weapon name) are ignored throughout.

| Image | What it shows | What we take | What we leave |
| --- | --- | --- | --- |
| `above map` | A top-down view of the whole map at night: a roofless two-storey building, the yard round it with fences and wire, bare trees, utility poles, a burning wreck at one end, frosted ground | The whole map is one building and a fenced yard you never enter. The building is a cluster of narrow rectangles, one main room each. Warm light shows only in a few rooms and at the fire. The yard is a backdrop seen through windows | The building's outline and the wreck (a crashed aircraft) |
| `floorplan` (downstairs) | A community diagram of the ground floor: a long narrow room, a squarer room with a grid of pillars, a curved stair, numbered wall buys | Rooms are narrow (one long axis), pillars stand in a regular grid in the big room, and the stairs sit at the joint between two rooms | The plan itself. Room sizes and topology are the formula page's |
| `floorplan_upstairs` | The same for the upper floor: two rooms over the lower ones, a straight stair and a winding stair, a dead-end side room, numbered buys | The upper floor is smaller than the ground floor and reached by two stairs. Each upper room has windows on its outer walls only | The plan, the buy placement |
| `spawn point view` | The starting room, looking out: a row of tall barred openings between square pillars under a low, rough ceiling, the fenced yard and fog beyond. Moonlight throws the bars' shadows across the tiled floor | The first room looks out onto where the danger comes from. The ceiling is low and close (about 1.3 m over the eye). The light comes in sideways through the openings, and the floor pattern of light and bars is what makes the room read | The barred-window design as drawn. Ours are our own pieces |
| `corner behind spawn point view` | The pillared room: square pillars with round-headed arches between them, heavy beams, a sandbag pile, a metal rack, scattered bricks and planks on a dirt-covered floor. Warm, dusty light, a zombie crossing a lit doorway at the back | Rhythm. One pillar and arch module repeated makes the whole room. The far doorway is lit, so a body crossing it reads as a silhouette. Clutter hugs the walls and the middle stays open | The sepia grade of the re-release |
| `door_1` | The remaster's first purchase door: a dark plank door scrawled with a chalk plea, rubble, sandbags and filing cabinets round it. Warm light from an arch on the left. The red frame and arrow are a video's annotation, not the game | A purchase door is a plain slab in a frame, and what marks it is writing and light, not ornament. Rubble drifts against the walls, never in the doorway | The writing, and the colour. Our purchase doors are the lot's Yellow ([style bible](../../design/style.md#lot-surfaces)) |
| `downstairs_facing_dead_end` | A ground-floor room with square pillars, a broken wall and a rubble heap on the left, the stair beyond, a small lantern on a pillar. Fog fills the room | A broken wall says "ruin" more than any texture: a ragged hole and a cone of rubble below it. A lantern on a pillar marks a place to stop | The textures of the stone |
| `downstairs_facing_stairs` | The remaster's stair hall: a curved stair with a thin rail rising past a wall lit by a moonlight shaft that carries a chalk message, rubble all over the steps, pillars and arches beyond | Light on the wall over a stair pulls the eye up it. Writing is placed where the light lands. A thin rail against a heavy stair reads well | The message's words, the curved stair's form |
| `stairs_door` | Looking up a straight timber-and-stone stair blocked by a tipped table and chair: the purchase that opens the upper floor. A pendant lamp hangs under the landing, a pipe rail runs beside the stair | A purchase can be a pile of furniture rather than a door: the way on is visibly blocked by things a player could clear. The stair is about as wide as two people abreast, with risers of a normal house stair | The specific pile |
| `stairs_door_from_spawn_area` | The same stair from the start, in warm light: the blocked flight rises past rubble and broken planks, lit from above, with a chalk message on the wall over it | Warm light spilling down a blocked stair from the room above advertises the next area before it is bought. The light comes from behind the blocker | The message |
| `looking outside from upstairs sitting behind sandbags next to stairs` | From behind a sandbag line on the upper floor, out over the yard: plank fences topped with wire, a lamp post, bare trees, a huge pale moon and dense ground fog. A zombie crosses the yard | The upper floor's outer openings are firing positions marked by sandbags. The outside is a flat, pale, foggy backdrop with silhouettes (trees, poles, wire) against a bright sky | The moon's size (ours sits in our own sky shader) |
| `mysterybox left corner as soon as open first door that says 'help'` | The random weapon chest in a room corner: a long wooden chest on cinder blocks, a single enamel pendant lamp right over it throwing a cone of light, a coil of rope and a helmet on the floor, blue-grey walls | The single best guide to the box is the one lamp right over it. Its cone is the brightest thing in the room, and the chest's dark wood sits in it against a cooler wall | The chest. Ours is the [prize crane](../mystery-box.md), which keeps its own look |
| `outside_map` | The remaster's yard at the edge of the map: a pond, a sunken tank-like wreck, burning debris, birches and a radio mast in the fog, a stair down from the building | Outside the walls, layered silhouettes in fog with one or two warm fires give depth with little geometry | The wreck and the mast as designed |
| `sniper_locker to buy` | A tall carved wooden cabinet that sells a long gun, standing against a pillar. Behind it, a row of pendant lamps leads into the next room, and filing cabinets stand to the right | A wall buy can be a piece of furniture, and a row of lamps can lead the eye to the next room like runway lights | The cabinet's carving |
| `upstairs_corner` | The remaster's upper room: a broken ceiling open to the sky, a ragged hole in a curved wall looking onto the stair, a wide mullioned window onto snowy trees, broken glass and planks on a reddish floor | Holes in walls and ceilings that look onto other playable spaces make a small map feel bigger and let players read where the dead are. The sky through a broken roof gives a cool top light | The remaster's density of small debris |

## Architecture vocabulary

What each piece tells the player, in the reference and in ours:

| Piece | In the reference | What it tells the player | Ours |
| --- | --- | --- | --- |
| Heavy masonry wall | rough grey concrete and brick, thick | "Solid: nothing comes through here" | cinder block, the lot's `blocks` pattern on a Concrete tint |
| Broken wall | a ragged hole, rubble cone below | "This was a fight", and when it opens onto another room, "you can see through but not pass" | a 2 m module with a chunky hole of 4-6 big facets, a separate rubble cone |
| Boarded window | sill at waist height, boards nailed across | "They come in here: hold it, mend it" | the zombie window module with the [barricade](../../design/map.md#the-fences-breaches)'s boards, short |
| Barred opening | tall, floor to near ceiling | "You can see out, nothing comes in" | a 2 m barred opening for the start room |
| Purchase door | dark planks in a frame, chalk on it | "Pay to open" | a plank door in Yellow, the lot's purchase colour, with a cream price plate |
| Debris blocker | furniture piled on a stair | "Pay to clear: what is beyond is lit" | a rubble and furniture pile that fills a 1.4 x 2.4 m opening |
| Stair | straight or curved, a thin pipe rail | "Up is somewhere else: a holdout" | a straight flight and an L flight with a landing, 1.4 m wide |
| Pillar and arch | a regular grid of square pillars | "A room you can circle": the pillars are what you run round | a 0.5 m pillar with cap and plinth, a segmental arch module |
| Sandbag line | waist-high at upper openings | "Stand here and shoot out" | 1 m and 2 m sandbag lines, 0.9 m tall |
| Crates, tables, cabinets, racks | against walls | Nothing to do, but they hide corners and narrow the edges | crates and pallets from the props, and new table, chair, filing cabinet and shelf rack |
| Wall buy | a chalk outline, or a cabinet | "A gun for sale here" | the lot's amber plaque, or a tall cabinet for a long gun |
| Random weapon box | a chest under one lamp | "The gamble" | the prize crane, under its own light |
| Pendant lamp | enamel shade, bare bulb | "Something is here" | the pendant lamp, the main guide |
| Chalk writing | white scrawl on lit walls | Story and direction | our own short messages in a Chalk swatch, placed where the light lands |
| Yard fence, wire, poles, bare trees | outside, in fog | "There is no leaving" | the props' fences, new barbed wire, poles and bare trees as a backdrop |

## Palette translation

The reference's colour structure is the one Deadnight's lot already has: a cool, blue-grey night with a few warm
pools. The detail of the reference (grime, cracks, stains in every texture) does not translate: we say "old and
broken" with shape (chamfers, broken edges, rubble) and with the lot's two-to-four-tone patterns, never with dirt
textures.

| The reference's colour | Its role | Deadnight swatch or tint |
| --- | --- | --- |
| Grey-brown weathered concrete and brick | the shell | Concrete `#9a968c` on the lot's `blocks` pattern (the booth's cool `#9a9ca6` for colder rooms) |
| Pale, crumbling plaster on the upper floor | upper rooms | **Plaster `#b3a588`** (new) on a new `plaster` pattern |
| Grey stone floor tiles | ground floor | the lot's `concrete` pattern, the booth floor's tint `#8f8c84` |
| Dark timber: stairs, floorboards, frames | stairs, upper floor | Wood `#95703d` treads, DarkWood `#6b4f2c` stringers and frames, the `planks` pattern at `#7d6446` |
| Dark plank doors | purchase doors | **Yellow `#d1ab46`**: on the lot the purchase doors are Yellow and nothing else is, and the small map keeps that rule |
| Pale burlap sandbags | cover | **Sandbag `#a88d62`** (new) |
| White chalk writing | messages | **Chalk `#ece6d2`** (new) |
| Rust on rails and cabinets | metal | **Rust `#7d4b2f`** (new), Grey `#818491` |
| Soot and charred wood | burned edges, fire-damaged walls | **Soot `#2f2c2a`** (new) |
| Green military crates | ammunition | the lot's locker: Green `#496321` with a Yellow band |
| Polished wooden cabinet | a wall weapon's furniture | DarkWood, with the amber plaque |
| Red smears | threat accents | SignRed `#b8322e`, sparingly. Blood is the hit effect's work (#618) |
| Moonlit, frosted ground and blue-white fog | outside | the lot's `gravel` pattern on a cool pale tint (about `#7f8794`), fog `#16224a`, moon `#9db4e8` |
| Orange firelight and tungsten bulbs | warm accents | sodium `#ffb866` (the lot's lamps), bulb `#ffd9a0`, Amber `#e8a33a` |

The five new swatches go into the five cells the drive-in palette leaves empty (cells 20-24 of its 5 x 5 grid), so
the kit's atlas is the drive-in atlas plus five colours. Every drive-in prop's UVs stay valid on it, and a drive-in
prop can stand in the small map without a second texture. The list lives in `tools/blender/smallmap_kit.py`.

## Lighting and atmosphere

Light does the reference's wayfinding. The rooms are dark, and every lit thing is either a danger (a window) or a
purchase (a door, a buy, the box).

| How the reference guides | Seen in | Ours, in the Compatibility renderer |
| --- | --- | --- |
| **One lamp right over the box**, a cone of light the brightest thing in its room | the box image | the crane's own lamp (exists) plus a pendant lamp prop over each crane spot, with a cone of additive haze (`beam.gdshader`, as the projector's) and a pool quad (`glow.gdshader`) |
| **Lamps over every buy**, a row of lamps leading into the next room | the cabinet image | a pendant lamp over each wall buy and locker. In a corridor, a row of 2-3 lamps with glow quads only (no light slot) |
| **Warm light from the unopened room** spilling over a blocker or under a door | both stair images | a warm `GlowPane`-style quad behind each purchase door or blocker, on the far room's circuit, plus a strip under the door. The next area is advertised before it is bought |
| **Cool moonlight through windows and bars**, bar shadows on the floor | the start-room view | a cool additive shaft quad in each window and a floor quad textured with the bars' shadow. The moon light casts no shadows (Compatibility, see [night environment](../night-environment.md)) |
| **Moonlight landing on a wall over a stair**, with writing in it | the stair hall | a cool shaft quad on the wall and a chalk message placed in it |
| **Haze inside the rooms** | most interiors | the map's own `Environment`: the lot's fog (density 0.013) barely shows in a 6 m room (about 8 %). A small map can take about 0.035 (about 19 % at 6 m, 30 % at 10 m) and the round's darkening still multiplies it. Glow, SSAO and volumetric fog stay off |
| **Fires outside** | the overview, the yard | a barrel or wreck fire: an omni light plus flame and halo quads, seen through windows |
| **Darkness is blue, never black** | all | the lot's ambient `#4d5c8c` at 0.24: the shadow side of the player and the dead still reads |

Budget rules from the lot that bind here ([lamps and glow](../night-environment.md#lamps-and-glow-issue-244)):
at most 8 lights reach a mesh, 6 so a fight has room. Tight rooms help: walls, floors and ceilings are cut per room,
so a room's mesh is reached by its own one or two lamps and a neighbour's spill. Most "lights" are quads.

## Scale

Measured against a 1.8 m player (the reference's player is close to ours) with the eye at about 1.5-1.6 m.
In a level first-person view the horizon line is the eye's height, so the height of a thing on the far wall is
(its pixels above the floor line) / (the eye's pixels above the floor line) x 1.55 m. These are estimates of
plus or minus 10 to 15 %: the images are screenshots, not plans. The stair count and the floorplans' tread marks
cross-check the storey height.

| Element | Reference (estimated) | From | Kit target | The lot today |
| --- | --- | --- | --- | --- |
| Purchase doorway, clear | 1.2-1.4 m wide, 2.2-2.4 m tall | `door_1` (the door is 0.54 as wide as tall), the plans' door gaps | **1.4 x 2.4 m** in a 2 m wall module | 3 m wide, 2.6 m slab |
| Wide opening between rooms | about 2 m wide, arched | the pillared room | **2.0 x 2.4 m** in a 3 m module, flat or segmental arch | 4-4.5 m gates and links |
| Zombie window, opening | 1.0-1.3 m wide, 1.0-1.3 m tall | `upstairs_corner`, the sandbag view | **1.2 x 1.3 m** | the fence breaches, 4 m wide |
| Zombie window, sill | 0.8-1.0 m (waist) | the same | **0.9 m** (top at 2.2 m) | at the ground |
| Barred opening | 2.4-2.6 m between pillars, 2.6-2.8 m tall | `spawn point view` | **2.0 x 2.4 m** in a 2 m module | - |
| Ceiling, clear | 2.8-3.0 m, rough slab | the start room (about 1.3 m over the eye), the pillared room | **2.8 m** | - |
| Under a beam | 2.4-2.6 m | the pillared room | **2.4 m** (0.4 m beam) | - |
| Floor to floor | about 3.2 m | about 16 risers on the stairs | **3.0 m** (2.8 clear and a 0.2 m slab) | the booth's floor, 3.75 m up a ramp |
| Stair width | 1.2-1.4 m | `stairs_door`, the stair hall | **1.4 m** | the booth ramp, 2.0 m |
| Riser and tread | about 0.2 and 0.3 m | `stairs_door` | **0.2 and 0.3 m**: 15 risers, 33.7 degrees | a 25 degree ramp |
| Pillar | 0.5-0.6 m square | the pillared room, the dead-end room | **0.5 m** with a 0.62 m cap | - |
| Sandbag line | 0.8-1.0 m tall | the sandbag view | **0.9 m**, 0.6 m deep | - |
| Pendant lamp | shade 0.4-0.5 m across, rim about 2.2 m up | the box, the cabinet | shade **0.6 m**, rim **2.15 m** | the lot's lamps are posts |
| Tall cabinet (a wall buy) | about 1.1 m wide, 2.3 m tall | the cabinet image | **1.0 x 0.5 x 2.2 m** | the amber plaque, 1.7 x 0.9 m |
| Box | about 1.5 m long, top about 0.8 m | the box image | the crane (exists) | the crane |

![Openings against a 1.8 m player: the reference dashed, the kit solid, the lot grey](kit-scale.png)

What the tight sizes mean for our game, checked against the code:

- **The shoulder camera fits a 1.4 m doorway.** The lens is swept sideways to the shoulder as well as back
  (`CameraPlacement`, issue #76): beside a jamb it slides in behind the player instead of through the wall. The
  lot's 1.8 m minimum passage ([widths and the camera](../../design/map.md#widths-and-the-camera)) was written for
  open ground, where the arm runs its full length. Indoors the arm is shortened by the walls, and the greybox's
  camera probes (as the lot's `CameraProbes`) must pass at every doorway and on the stair.
- **A 2.8 m ceiling shortens the arm when the player looks down.** With the pivot at 1.6 m, an arm of 2.3 m and a
  0.25 m lens margin, the arm starts to shorten past about 24 degrees down (about 14 degrees under a 2.4 m beam).
  That is the close, low feel the maintainer wants, and the spring arm handles it. The probes should include a look
  down under a beam.
- **Two of the dead fit a 1.4 m doorway only shoulder to shoulder** (each is 0.7 m wide). Whether a doorway is a
  single-file choke is the formula's choice. The lot's rule that "nothing is single file" was for the lot.
- **Nobody leaves through a window.** A player jumps 1.1 m, so a 0.9 m sill is easy to clear once the boards are
  torn. Each window needs a player-only blocker in its opening that is always there, as the breaches' aprons are
  closed on the lot. The dead pass it, players do not.
- **Stairs walk on a hidden ramp.** A 0.2 m riser is under the player's 0.3 m `step_height`, but stepping up fifteen
  times bobs the view. The flight's collision is one ramp at 33.7 degrees (under the default 45 degree floor
  limit), and the treads are only drawn, as the booth ramp's collision is.

## Grid and conventions

- **Grid**: snap to 0.5 m. Wall modules are 1, 2 and 3 m wide, 2.8 m tall, 0.3 m thick on the ground floor (block)
  and 0.2 m on the upper floor (timber and plaster). A storey is 3.0 m.
- **Origin**: the middle of the footprint, on the floor, the room side facing Blender -Y (Godot +Z), as the drive-in
  props do. A 2 m module's ends land on the grid when its middle does.
- **Flat surfaces are not modelled.** Plain walls, floors and ceilings stay CSG boxes with the lot shader and a
  pattern (`blocks`, `concrete`, `planks`, and a new `plaster`), split per room for the light cap. What is modelled
  is everything with a shape: openings, frames, pillars, stairs, broken pieces and props.
- **Chamfers**: 60 mm on wall pieces and frames (the lot's buildings use 80 mm, and a 2.8 m room is closer to the
  camera), 30 mm on props of 1-3 m, none under 0.1 m.
- **Budgets**: the style bible's classes. A wall module is a 1-3 m prop (1.5k), a stair or roof piece a large prop
  (5k). The blockout's pieces are 68-1,056 triangles.
- **Atlas**: one material on the kit atlas (the drive-in cells plus five), roughness 0.415, metallic 0, imported
  lossless with no mipmaps and Detect 3D off (`palette_import.py`).
- **Files**: `game/assets/smallmap/<name>.gltf` + `.bin`, a fixture scene each in `game/world/smallmap/fixtures/`
  with hidden CSG collision (what navigation and the camera tests read), as `game/world/drive_in/fixtures/`.

## Blockout

`tools/blender/build_kit_blockout.py` (pinned Blender, headless; the command is at its top) builds six pieces at the
kit targets: the narrow doorway with its purchase door, the zombie window with five boards, a pillar and beam, a
straight stair, a sandbag line and a pendant lamp. It renders them beside the game's Soldier (1.8 m), a zombie
(1.63 m in its Idle) and three of the game's own props, and then assembles them as a room corner at night. Nothing
goes into the game: the pieces are the follow-up issues' to build properly. The palette, the sizes and the builder
are in `tools/blender/smallmap_kit.py` for those builds to share. With `--gltf` it also writes each piece as
glTF, which the light cards' capture room is built from (`tools/web_smoke/smallmap_lights.py` copies them into its
copy of the project).

![The kit pieces on the 0.5 m grid beside the Soldier, a zombie, the ticket booth, a trash can and a crate](kit-blockout-sheet.png)

![The pieces as a room at night, from the shoulder camera: the warm pool under the lamp, cool moonlight through the boards, light under the purchase door](kit-blockout-room.png)

What the blockout showed:

| Piece | Tris | Size (m) | Reads as Deadnight? |
| --- | ---: | --- | --- |
| Narrow doorway and purchase door | 572 | 2.0 x 0.38 x 2.8 | yes. Beside the ticket booth the chamfered block frame and the Yellow planks speak the same language. The door is a head taller than the Soldier |
| Zombie window, boarded | 572 | 2.0 x 0.42 x 2.8 | yes. Five boards fill 1.3 m. The boards are the lot's Wood, shorter than the breach's |
| Pillar and beam | 176 | 4.0 x 0.62 x 2.8 | yes, but plain. The cap and plinth carry it. Leave it this simple |
| Straight stair | 952 | 1.4 x 4.64 x 3.91 (rail included) | yes. Open risers read lighter than a solid flight. The rail goes on the open side only |
| Sandbag line | 1,056 | 2.0 x 0.63 x 0.91 | yes. The kit's Sack Trench was 3.6-7.2k for the same job |
| Pendant lamp | 68 | 0.57 x 0.6 x 0.7 | yes. At this size it carries the warm pool from 2.15 m |

In the room render the chibi Soldier fills the doorway's width almost exactly, and the 2.8 m ceiling sits about a
head and a half over his helmet: the room is close without being cramped, which is the reference's feel at our
proportions. The palette holds at night: the Yellow door stays the warmest thing on the wall, and the zombie's green
reads against both the plaster and the block.

## Stairs, rails and blockers (group 2)

`tools/blender/build_kit_stairs.py` (pinned Blender, headless; the command is at its top) builds parts 19-23 into
`game/assets/smallmap/` and writes each fixture scene in `game/world/smallmap/fixtures/` from the same numbers, so the
collision always matches the model. Timber treads (Wood) on DarkWood stringers and risers, Grey pipe rails with Rust
shoes and elbows, one material on the kit atlas.

| Piece | Tris | Budget | Origin, and what the fixture holds |
| --- | ---: | ---: | --- |
| `stair_straight` | 1,308 | 5,000 | middle of the 1.4 x 4.5 footprint, foot at +Z (Godot), top at -Z 3.0 m up; `KitStair` shows the rail on `rail_left` (default) or `rail_right` and turns its blocker on with it |
| `stair_l_left`, `stair_l_right` | 1,612 | 5,000 | middle of the 3.5 x 3.5 footprint; the lower flight's foot at +Z, the upper flight turns to -X (left) or +X (right); the rail and a newel post on the inside of the turn, the outside against two walls |
| `rail_flat`, `rail_sloped` | 128 | 1,500 | 2 m along X; posts at +-0.5 m, so joined runs keep a post every metre; the sloped one rises 1.33 m to +X at the stairs' slope, its origin on the nosing line |
| `landing_edge` | 208 | 1,500 | the last 0.3 m of an upper floor (its top at the origin, the floor at +Z, the drop at -Z), a rail on it |
| `debris_blocker` | 1,300 | 1,500 | the wall's plane through the origin, the room at +Z; nodes `Part1_Planks` to `Part6_Rubble` in the order they come away, each with its origin at its own middle; one 1.4 x 2.4 x 1.0 blocker |

- **Each flight walks on one ramp**, a hidden CSG box whose top runs through the middle of every tread (R/2 + u R/T),
  from half a tread before the first riser to the top level half a tread past the last, then a flat strip. A landing's
  box starts where its ramp ends and the upper ramp starts half a tread into the landing, so no seam is a ledge.
  `test_smallmap_stairs.gd` walks the real player body up and down every stair, at a run, a sprint and across the L's
  corner: no step-up and no tick off the floor. Where a slope meets the flat, the capsule's round foot settles by at
  most 8 mm in one tick (a riser is 200 mm). The same flight with its treads as collision steps fifteen times.
- **The ramp is 33.7 degrees**, under the body's 45 degree floor limit and the zombies' 45 degree bake slope.
- **Rails are player-only** (collision layer 2, the boards' layer): a player cannot walk off an open side, a shot and
  the shoulder camera pass the pipes, and the walking mesh goes round them.
- **The space under a flight is open.** The level closes it (a wall, a cupboard) where the dead or a player could
  wedge into the low end.
- **A right-handed L is its own model**, never a mirrored instance: Godot's physics does not take negative scale.

![The stairs, rails, edge and debris blocker on the 0.5 m grid beside the Soldier, the trash can, a crate and the ticket booth](kit-stairs-sheet.png)

![In Godot under the lot's night: the room, the blocker in a doorway, and the player walking up and back down the straight stair](kit-stairs-room.png)

## Modular kit parts list

Coverage: **Exists** (in the game now), **Material** (a CSG box with a lot pattern, maybe a new pattern or tint),
**Model** (to build in Blender), **Godot** (a scene or shader job, no modelling). Effort for one agent: S is up to
2 hours, M half a day, L a day or more. The group is the follow-up issue that builds it.

| # | Piece | Size on the grid (m) | Covered by | Coverage | Effort | Group |
| ---: | --- | --- | --- | --- | --- | --- |
| 1 | Plain wall, ground floor | 1 / 2 / 3 x 0.3 x 2.8 | CSG + `blocks`, material `smallmap_wall_ground` (Concrete) | Exists | S | 1 |
| 2 | Plain wall, upper floor | 1 / 2 / 3 x 0.2 x 2.8 | CSG + the new `plaster` pattern, material `smallmap_wall_upper` (Plaster) | Exists | S | 1 |
| 3 | Narrow doorway with frame | 2.0 x 0.38 x 2.8, clear 1.4 x 2.4 (488 tris); `_upper` 0.2 m in Plaster | `wall_door_narrow` | Exists | S | 1 |
| 4 | Purchase door leaf | 1.35 x 0.13 x 2.36, Yellow (388 tris) | `door_purchase` | Exists | S | 1 |
| 5 | Wide opening | 3.0 x 0.36 x 2.8, clear 2.0 x 2.4 (224 tris) | `wall_opening_wide` | Exists | S | 1 |
| 6 | Arched opening (segmental, 8 facets) | 2.0 x 0.36 x 2.8, 1.4 wide, springing 2.0, crown 2.4 (616 tris) | `wall_arch` | Exists | S | 1 |
| 7 | Zombie window with frame | 2.0 x 0.44 x 2.8, clear 1.2 x 1.3, sill 0.9 (624 tris); `_upper` | `wall_window_zombie`, a player-only blocker and five board markers | Exists | S | 1 |
| 8 | Window boards | 1.5 x 0.06 x 0.19 (112 tris), five a window | `window_board` (+ `.obj` for the barricade's pooled copies) | Exists | S | 1 |
| 9 | Glazed window (not an entry), mullions | 2.0 x 0.44 x 2.8, 1.6 x 1.4, sill 0.9 (772 tris); `_upper` | `wall_window_glazed` | Exists | S | 1 |
| 10 | Barred opening | 2.0 x 0.3 x 2.8, bars 2.0 x 2.4 (360 tris) | `wall_barred` | Exists | S | 1 |
| 11 | Broken wall (ragged hole, top) | 2.0 x 0.3 x 2.8, a six-facet hole and a top down to 2.22 (304 tris); `_upper` | `wall_broken` | Exists | M | 1 |
| 12 | Pillar with cap and plinth | 0.64 x 0.64 x 2.8, shaft 0.5 (220 tris) | `pillar` | Exists | S | 1 |
| 13 | Beam | 0.36 x 0.4 x 2 / 4 / 6, soffit at 2.4 (108 tris each) | `beam_2`, `beam_4`, `beam_6` | Exists | S | 1 |
| 14 | Corner and end trims | corner 0.46 x 0.46 x 2.8 (352 tris), end 0.36 x 0.42 x 2.8 (132 tris) | `trim_corner`, `trim_end` | Exists | S | 1 |
| 15 | Ground floor | any, 0.2 slab | CSG + `concrete`, material `smallmap_floor_ground` | Exists | S | 1 |
| 16 | Upper floor | any, 0.2 slab | CSG + `planks`, material `smallmap_floor_upper` | Exists | S | 1 |
| 17 | Broken floor edge, joists showing | 2.0 x 2.1 x 0.21 (992 tris) | `floor_edge_broken` | Exists | M | 1 |
| 18 | Ceiling underside | any | CSG + `plaster`, material `smallmap_ceiling` (or `smallmap_floor_ground`) | Exists | S | 1 |
| 19 | Straight stair, one storey | 1.4 x 4.5 x 3.0 | `stair_straight`, 1,308 tris (a rail each side, the open one shown) | Exists | M | 2 |
| 20 | L stair with landing | 3.5 x 3.5 x 3.0, landing 1.4 x 1.4 at 1.6 | `stair_l_left`, `stair_l_right`, 1,612 tris each | Exists | M | 2 |
| 21 | Pipe rail, flat and sloped | 2 m runs, 1.0 tall, posts at +-0.5 | `rail_flat`, `rail_sloped`, 128 tris each | Exists | S | 2 |
| 22 | Landing or balcony edge | 2 x 0.3 x 0.2 with a 1.0 rail | `landing_edge`, 208 tris | Exists | S | 2 |
| 23 | Debris blocker (purchase) | fills 1.4 x 2.4, 1.0 deep (drawn 1.74 x 1.27 x 2.53) | `debris_blocker`, 1,300 tris in six parts | Exists | M | 2 |
| 24 | Sandbag line | 1 and 2 x 0.6 x 0.9 | blockout; replaces the kit's Sack Trench | Model | S | 3 |
| 25 | Table, and tipped over | 1.6 x 0.8 x 0.78 | - | Model | S | 3 |
| 26 | Chair | 0.45 x 0.45 x 0.9 | - | Model | S | 3 |
| 27 | Filing cabinet | 0.5 x 0.6 x 1.3 | - | Model | S | 3 |
| 28 | Shelf rack, X-braced | 1.2 x 0.45 x 2.0 | - | Model | S | 3 |
| 29 | Tall cabinet (a long gun's wall buy) | 1.0 x 0.5 x 2.2 | - | Model | S | 3 |
| 30 | Rubble: chunks and a cone | 0.2-0.6 chunks, 1.5 cone | the props' `debris` in part | Model | S | 3 |
| 31 | Period clutter: radio set, lantern, helmet | under 0.5 | - | Model | S | 3 |
| 32 | Crates, boxes, pallets | as built | props `crate`, `boxes`, `box`, `pallet`, `pallet_broken` | Exists | - | - |
| 33 | Barrels, gas cans, tanks | as built | props `barrel`, `gas_can`, `gas_tank` | Exists | - | - |
| 34 | Papers on the floor | as built | props `papers`, `papers_b`, `papers_c` | Exists | - | - |
| 35 | Shop spots: plaque, locker, crane, re-cut bench, fountain | as built | the lot's builders and `game/world/machines/` | Exists | - | - |
| 36 | Pendant lamp | 0.6 x 0.6 x 0.66, rim at 2.15, 396 tris | `pendant_lamp.gltf`, `fixtures/pendant_lamp.tscn`, lit: `lights/pendant_light.tscn` | Exists | - | 4 |
| 37 | Wall lantern | 0.25 x 0.2 x 0.4, foot at 1.8, 416 tris | `wall_lantern.gltf`, `fixtures/wall_lantern.tscn`, lit: `lights/lantern_light.tscn` | Exists | - | 4 |
| 38 | Lamp cone and pool | cone 0.27 to 1.3 m over 2.14 m, pool 3.6 m | `KitLamp` (`beam.gdshader`, `glow.gdshader`) | Exists | - | 4 |
| 39 | Moon shaft and bar-shadow quads | any opening | `MoonShaft` (`glow.gdshader`'s card, bars and rails: no texture) | Exists | - | 4 |
| 40 | Light under and behind a purchase door | the doorway, spill 1.6 m | `DoorGlow`, on the far room's circuit | Exists | - | 4 |
| 41 | Chalk messages | 0.3-3 wide, six lines | `ChalkMessage`, `chalk_messages.png` (`build_chalk_messages.py`) | Exists | - | 4 |
| 42 | Bare tree, three variants | 4-8 tall | the props' trees have leaves | Model | M | 5 |
| 43 | Utility pole and wire | 0.3 x 0.3 x 7, crossbar | `street_light` in part | Model | S | 5 |
| 44 | Barbed wire coil and fence post | 2 m runs | - | Model | S | 5 |
| 45 | Plank and metal fences | as built | props `fence`, `fence_long` | Exists | - | - |
| 46 | Roof: pitched, broken, rafters | 2 m bays | - | Model | L | 5 |
| 47 | A set-piece wreck | the design's choice | `broken_car` and `wreck.tscn` cover a car | Exists (a new one is L) | - | 5 |
| 48 | Frosted ground outside | any | CSG + `gravel`, a cool pale tint | Material | S | 5 |

**48 parts: 32 to model in Blender, 6 materials on CSG, 4 Godot jobs, 6 already in the game.** Nine of the 32 have a
blockout already. Group 4 (36-41) is in the game: [Lamps and light cards](#lamps-and-light-cards).

| Group | Parts | Effort |
| --- | --- | --- |
| 1. Walls, openings, floors | 1-18 (13 models, 5 materials, the `plaster` pattern) | about 2 days |
| 2. Stairs, rails, blockers | 19-23 (5 models) | about 1.5 days |
| 3. Cover and clutter | 24-31 (8 models) | about 1.5 days |
| 4. Lamps and light cards | 36-41 (2 models, 4 Godot jobs) | about 1 day |
| 5. Outside and roof | 42-48 (4 models, a tint; 45 and 47 exist) | about 2 days |

The groups share only `smallmap_kit.py` (the palette and the sizes) and the atlas, so five agents can work at once.
Each builds its own script, writes its own files, and adds a fixture scene per piece. Group 4's light cards need
group 1's doorway and window to sit in, but can be built against the blockout's sizes.

## Group 1 as built: walls, openings, floors

`tools/blender/build_smallmap_walls.py` (issue #633) builds parts 3-14 and 17 (twenty files: the openings also come
in an `_upper` variant, 0.2 m thick in Plaster, for the upper floor) into `game/assets/smallmap/`, and writes a
fixture scene per piece into `game/world/smallmap/fixtures/`. `tools/world/build_lot_textures.py` adds the
`plaster` pattern and the five shell materials (`smallmap_wall_ground`, `smallmap_wall_upper`,
`smallmap_floor_ground`, `smallmap_floor_upper`, `smallmap_ceiling`). Every piece is 108-992 triangles against its
1.5k (or 5k) budget; the build fails over it, and `tests/world/test_smallmap_kit_walls.gd` checks the counts Godot
draws, the openings' clear sizes and the window blockers.

How the pieces are made, so the other groups match:

- **A wall is one cast piece.** The face is an outline with holes (`Kit.plate`: Blender's `triangle_fill` fills it,
  the face is pushed through the wall) and only its sharp edges get the 60 mm chamfer, so there are no seams where
  boxes would meet. Frames, sills, lintels, voussoirs and bars are boxes on top, DarkWood frames proud by 40 mm.
- **Clear openings stay exact.** The masonry hole is the clear size plus a 50 mm lining on each side, so a 1.4 x 2.4
  m doorway is 1.4 x 2.4 m between the linings.
- **Collision.** Hidden CSG boxes (layer 1) for the wall; the navigation bakes them. What players must not pass but
  the dead or shots may: the zombie window's opening is a `PlayerBlocker` StaticBody3D on the boards' layer (the
  navigation reads only CSG, so the dead's way stays open); the bars and the broken hole are CSG on the boards'
  layer (players and the walking mesh stop, shots pass). The window fixture carries five `BoardSlot` markers for
  `window_board.tscn`, a board in `board.tscn`'s shape that a `Barricade` takes as it is.
- **The palette** is `game/assets/smallmap/smallmap_palette.png` for every group (the build writes it). Its swatches
  are the sRGB values in `smallmap_kit.py`: the first build stored them as linear and every piece came out
  far too dark ([lesson](https://github.com/Ryubara/gdstudio/blob/main/docs/lessons/2026-11-02-a-palette-written-as-linear-came-out-dark.md)).

![The kit's walls and openings beside the Soldier, a zombie and the drive-in props on the 0.5 m grid](kit-walls-sheet.jpg)

![A room built from the fixtures in Godot under the lot's night: the boarded zombie window, the purchase door, the arch, the broken wall, bars between pillars](kit-walls-room.jpg)

## Lamps and light cards

Group 4 (issue #636). Everything lit in a room is a lamp model, at most one or two real lights, and additive cards on the
lot's own shaders. `game/world/smallmap/`: `fixtures/` the two models with hidden CSG collision, `lights/` the four
cards, each a scene with its settings in the inspector. `game/tests/captures/smallmap_lights.tscn` puts them in a room
and a corridor built from the blockout's pieces (below); `tests/world/test_smallmap_lights.gd` holds the rules.

| Piece | What it is | Tris (budget) | Size (m) |
| --- | --- | ---: | --- |
| Pendant lamp | ceiling rose, cord, socket, a 12-sided enamel shade (Green outside, Cream inside, a DarkGrey rolled rim) and a pear bulb that shows under the rim | 396 (600) | 0.6 x 0.6 x 0.66, hung from 2.8, rim at 2.15 |
| Wall lantern | back plate, arm, Rust hood and foot, a cage of four posts, two rings and two front bars round an upright bulb | 416 (600) | 0.25 x 0.2 x 0.4, its foot at 1.8, its back on the wall |

`tools/blender/build_smallmap_lights.py` builds both on the kit atlas (`smallmap_palette.png`) and renders the contact
sheet. **The bulb is a swatch, not a material**: it sits on Popcorn, which no other face of the lamps uses, and
`KitLamp` lights that cell with an emission texture of the atlas's layout (the drive-in's `ModelGlow` manner), with a
little of the shade's Cream inside. A lamp stays one mesh, one material, one draw.

| Card | Scene and class | Made of | Follows |
| --- | --- | --- | --- |
| Lamp: halo, floor pool, cone of haze, wall wash | `pendant_light.tscn`, `lantern_light.tscn` (`KitLamp`) | `glow.gdshader` discs, a 16-sided open cone on `beam.gdshader` | its own `Light` (`own_light`), or another lamp of its circuit, or steady |
| Moon shaft | `moon_shaft.tscn` (`MoonShaft`) | a faint card in the opening, two sheets of haze along the moon, and the opening projected along the moon onto the floor (or onto a wall `land_wall` ahead) in 12 rows, cut by `bars` and `rails` | the moon (it dims with `NightLight`'s rounds) |
| Light of the far room | `door_glow.tscn` (`DoorGlow`) | a card filling the opening behind the door, brightest low (seen through the planks' cracks and over a blocker), and a spill on the near floor from under the door; `opened` drops the spill | a lamp of the far room's circuit, with `GlowPane`'s tremble |
| Chalk message | `chalk_message.tscn` (`ChalkMessage`) | a card on the wall with a row of `chalk_messages.png` as a mask, Chalk `#ece6d2`, additive: it shows as much as the light it is given | the light it stands in (the moon, a lamp) |

- **No new GL program.** `glow.gdshader` gained a `card` mode (soft rectangle, fade along V), `bars` and `rails` (the
  shadows of bars and boards, drawn in the shader: no stripe texture) and a `mask`; `beam.gdshader` a `near_fade`.
  Defaults leave the lot's picture as it was, and a material's program is its shader's file, so every card is a key
  the lot's warm-up already draws. The test plays the warm-up of a night and finds nothing of the lamps or cards
  missing from its ledger ([first-use hitches](../first-use-hitches.md)).
- **No light slot.** The cards are unshaded (the cap counts none of them). The capture room has three real lights
  (the crane's own lamp, the buy's pendant, the corridor's lantern); the box's pendant follows the crane's lamp and the
  corridor's three pendants follow the lantern. Every lit mesh is reached by at most 3 (the corridor's floor, ceiling and
  south wall: the room's lamps reach through the wall, as nothing casts a shadow), under the 6 a fight needs.
- **The moon indoors.** With no shadows, the lot's moon (0.36) lights every floor under a roof evenly, which lifts the
  dark and lowers the shafts' contrast. The capture keeps 0.1 (`INDOOR_MOON`; `--lot_moon` shows the lot's) and lets
  the shafts carry the moonlight; the greybox's environment (#631) should do the same.
- **Players walk under the lamps.** From inside a cone the haze faced the camera all round and washed the screen, so
  `beam.gdshader`'s `near_fade` fades haze nearer than 2 m.
- Tuned against the captures: halo 1.2, pool 0.45 (3.6 m), haze 0.3, shade glow 0.12; shaft 0.18, patch 0.3, opening
  0.12; door 1.0 behind, 0.9 spill; chalk 0.5. The bar shadow is 0.3 of a gap for bars, 0.7 for boards.

What the cards cost, from the shoulder camera at 1280 x 720 (`smallmap_lights.tscn --frames=600 --unpaced`; the web
build through `tools/web_smoke/smallmap_lights.py`, Chrome on an RTX 5080, ANGLE on Direct3D 11, unpaced, three runs
interleaved, medians of the runs; a shared machine):

| Where | Without the cards: mean / p50 / p95 | With them | GL programs linked while measured |
| --- | --- | --- | --- |
| Web, room, build 1 | 2.30 / 1.80 / 4.40 ms | 2.42 / 1.90 / 4.20 ms | 0 and 0 (87 in all, the same with and without) |
| Web, corridor, build 1 | 1.97 / 1.80 / 3.40 ms | 1.96 / 1.80 / 3.70 ms | 0 and 0 (60 in all, the same) |
| Web, room, build 2 (palette fixed) | 2.65 / 2.00 / 5.50 ms | 2.62 / 2.30 / 5.00 ms | 0 and 0 (87 in all) |
| Web, corridor, build 2 | 2.33 / 1.80 / 4.50 ms | 2.23 / 2.00 / 4.30 ms | 0 and 0 (60 in all) |
| Desktop, room (2 runs) | p50 0.61 and 0.74 ms | p50 0.76 and 0.79 ms | - |
| Desktop, corridor (2 runs) | p50 0.55 and 0.56 ms | p50 0.57 and 0.58 ms | - |

At most 0.1 to 0.3 ms at the median in the room, inside the spread between two builds of the same scene (eleven
cards and three cones in view, the haze overdrawing the crane's glass), and nothing measurable in the corridor. On a
weak GPU the part to watch is the overdraw of the cones and the floor patches; the lot's pools are 15 m, these are 2 to
4 m. The lot's own frames are unchanged pixel for pixel (the night look tour's first six
spots, with the new shaders and the old).

## Sources

- The maintainer's 15 images, `<workspace>/refs/deadnight/nacht-der-untoten/` (not committed). The floorplans are
  community diagrams, the rest are screenshots of the original (2008), a later re-release and the remaster.
- Deadnight's [style bible](../../design/style.md), [the lot](../../design/map.md),
  [night environment](../night-environment.md), the player and camera tuning
  (`game/gameplay/player/player_tuning.gd`, `camera_placement.gd`).
- The design formula: [#622](https://github.com/Ryubara/deadnight/issues/622).
