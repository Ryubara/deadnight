# Greybox and captures

What building the drive-in greybox ([the lot](../design/map.md)) taught us, for the next scene built the same way.

## Lights on a big floor (Compatibility)

The Compatibility renderer lights each mesh with at most 8 omni and 8 spot lights (the project setting
`rendering/limits/opengl/max_lights_per_object`); lights past the cap are dropped for that mesh. One 120 m floor under
25 lamps is one mesh, so most of its lamps would not light it. The greybox tiles every floor into slabs of at most
24 m, so no slab sees more than a handful. Shadows are off: they are among the web build's most expensive features.

## Switching lights with the generator

How the lot's lamps follow the rules is in [the lot](../design/map.md#which-lamps-hang-on-which-circuit); what building
it taught:

- A scene instanced many times shares its sub-resources: the lamp post's bulb material is one resource for every post,
  so setting its emission darkens them all. `LampPost` duplicates the material in `_ready`, one per post.
- A light is `visible = false` only when its level is zero; a flicker moves `light_energy` and never hides it, so the
  count of lights that touch a mesh (the cap above) does not change on every flicker step. (A choice to keep the web
  build's shaders steady, not a measurement.)
- The flicker is a function of the frame's tick and the lamp's number (a golden-ratio sequence), not of `Time` or a
  random draw, so Movie Maker and a test see the same lights. The night's link delivers a tick late: a test that
  watches the lights waits a few ticks after changing the tank.
- Whether ground is lit is asked of the rules' `GeneratorState`, never of a `Light3D`, so a headless server that draws
  nothing gives the same answer as a client.
- `metadata/circuit = "name"` in a `.tscn` is a plain String; read it with `StringName(...)` and look up the tree for
  the first node that has it.
- A fresh git worktree has no `addons/gdUnit4` (it is ignored): copy it from the main checkout before running tests.

### The breaker posts

Where they stand and how they work is in [the lot](../design/map.md#the-breaker-posts); what building them taught:

- **Anything solid near a car-row gap fails the camera test.** The first post for the field's circuit stood at (8, -45),
  inside the first car row, and `test_the_arm_keeps_its_full_length_in_corridors` failed on `CarGap_R1c`: the arm runs
  2.8 m back from a probe toward the screen and the post was in it. The post moved to the avenue, away from every probe.
- **A post is a `StaticBody3D`, not CSG**, so it does not need the navigation bake's care; the dead path round it. Its
  lamp is an emissive mesh with its own material (shared sub-resources would light every post together) and is no
  `powered_light`, so it never lights ground for the dead.
- **The prompt's winner is the first match**: door, then breach, then post. A post stands more than `use_reach` from
  every slab of every door (a test checks it), so the order never decides between two things a player stands at.
- **The bot's `use` is an edge, so it needs the circuit it sees**: frames carry `circuits`, and the bot only presses
  when the post is thrown the wrong way; the server also refuses a second throw within `switch_interval`.

### The fuel cans

Where they stand and what they sell is in [the lot](../design/map.md#the-fuel-cans); what building them taught:

- **The prompt's card has room for about 22 letters on its detail line**; `ADDS 25 UNITS TO THE TANK` came out as
  `ADDS 25 UNITS TO THE TA...` in the capture. Say it shorter (`+25 UNITS OF FUEL`) and look at the frame.
- **The price is the rules'**, asked through `ShopItem.fuel_offer`, so the card, the bot and the purchase read one
  number: a part fill's price is a share of the can's, and a full tank offers nothing instead of a price.
- **A bought door's new mesh is live a few physics frames after the bake ends.** A bot that must walk through the
  new doorway in a test waits for `settle_bake` and then a few physics frames; `night.tick()` alone does not step
  the navigation server, and the path ends at the wall.
- **The stand in the yard stands outside the cage**, so the camera does not have to push through the 2 m opening
  past a crate; its 2 m reach does not reach a player on the cage's far side.

## CSG

- A scene of plain `CSGBox3D` roots (no combiners, no subtraction) builds fast: 350 nodes load in well under a
  second, and each box makes its own collision shape with `use_collision`.
- The collision shape is built on the node's first frame and the physics server has it one physics tick later. A test
  that casts a shape must `await get_tree().physics_frame` three times after adding the scene.
- Doorways and windows are cut by building the wall as pieces around the gap. Two gaps that overlap (a door and a
  window above it) must be two stacked walls, not two gaps in one: the first attempt left a window in the wrong place
  and a block in the doorway, and only a capture showed it.

## Captures

- `--write-movie` writes frames at the project's viewport size (1920 x 1080 here), whatever `--resolution` says. The
  first two frames are not settled; the fourth is. It also writes a `.wav`; ignore it.
- A top-down plan is an orthographic `Camera3D` with `size` set to the vertical extent in metres, looking down with
  `up = -Z` so north stays up. A `Label3D` lies flat when its basis columns are x, -z (up), y (forward) and
  `no_depth_test` is on; with the opposite sign it reads mirrored.
- **Capture without a window**: `--no-window --write-movie <abs>/clip.avi --fixed-fps 30` renders normally, steals no
  focus, and an `.avi` (MJPEG) is a third the size of the PNG frames; `ffmpeg -crf 29` makes the mp4. But a real mouse
  still reaches the game: the pointer of the person using the machine turned a `Night` camera by up to 65 degrees
  between two runs of the same script. A capture that drives the real player sets `player.local_input = false` after
  `Night.start` (mouse look off; the input actions still drive the controls) and gets the same clip every time.
- A capture that needs the dead without a round: give the night a tuning with `rounds.intro_seconds` very large and
  `ZombieSim.spawn` the dead by hand (`tests/captures/speed_chase.gd`); rules events applied outside the server
  (`rules.apply(set_circuit)`) never reach the client, so pass them to `night.state.apply_events` or the lamps stay lit.
- One rig scene and a user argument (`-- --view=top`) give every view from one command, so a layout change is
  re-captured by rerunning the same list.
- **A capture exits with code 0.** A tour that saved every frame and then exited with 139 (0xC0000005, #667) had set
  `MainMenu.board_factory` (a static variable) to a lambda of its own script and quit without clearing it; the engine frees
  the tour's script before the game's statics and quitting released a dead lambda. Clear every hook a capture sets
  (`= Callable()`) before `quit()`. `tests/core/test_capture_quit.gd` runs a reduced script in a child Godot for the exit
  code and checks every capture and tour script for a lambda set on a class and never cleared. The page for the engine
  side is the kit's `docs/godot/exit-code-139.md`.

## Testing a baked navigation mesh headless

Used by `game/tests/world/lot_navigation.gd`; it proves which areas of the lot a body reaches with a given set of doors.

- **The dummy renderer has no mesh data.** Under `--headless` the CSG visual meshes are empty, so
  `NavigationServer3D.parse_source_geometry_data` gives an empty mesh (and a warning about reading meshes from the
  GPU). Feed the faces yourself: `csg.bake_collision_shape().get_faces()` into
  `NavigationMeshSourceGeometryData3D.add_faces(faces, csg.global_transform)`, for every root CSG shape.
- **`agent_radius` is rounded up to whole cells** (a warning says so). 0.35 m needs a 0.05 m cell to be exact; the
  bake of the 124 m by 116 m lot then takes about 1.5 s, a test of nine door sets about 20 s. Set the map's cell size
  and cell height to the mesh's, or the polygons do not merge.
- **A new region takes a few physics ticks.** The map iterates every other tick or so and takes a new region in after
  about two iterations; querying before then gives an empty path and an error ("before first map synchronization").
  Wait on `NavigationServer3D.map_get_iteration_id(map)` rising by two, not on a fixed frame count.
- **Give each bake its own world.** Regions of earlier cases stay in a shared map and merge into the next case's
  answers. A `SubViewport` with `own_world_3d = true` has its own physics space and navigation map; freeing it
  frees both.
- `map_get_path(...)` to an unreachable target ends at the nearest reachable point, so "can reach" is "the path ends
  within a metre of the target", and "cannot" is "it ends more than two metres away".

## Sweeping the shoulder camera

`game/world/drive_in/camera_probe.gd` is the player's camera rig as a function (pivot 1.55 m, arm 2.8 m with a 0.25 m
sphere, shoulder 0.75 m after the sweep). Those numbers are read from `player_tuning_default.tres`, not copied, so
a tuning change moves the sweep. Read them through `CameraProbe.tuning()`: GDScript folds `CONST_RESOURCE.property`
into the script when it compiles, so a value changed afterwards (by a test) is not seen. What it found:

- The spring arm only collides along the arm. The shoulder offset comes after, so in a 1.4 m gap between cars the
  camera ends up inside the car's glass (at 1.55 m the cabin, 0.95 to 1.65 m, is what it hits, not the 1.0 m body).
  A passage needs 2 x (0.75 + 0.1) = 1.7 m for a centred player; the lot uses 1.8 m and more.
- **A concave (trimesh) body does not report a shape whose centre is already inside it.** CSG collision is a concave
  mesh: an overlap query with a small sphere placed inside a car box returns nothing, so "is the camera inside a wall"
  cannot be an overlap test. Sweep a sphere from a known-clear point (the arm's end) to the camera instead
  (`cast_motion`): it hits the face from outside. A negative control (a 1.4 m gap that must fail) caught this.
- Stand the sample point on the ground (a ray down from above) before sweeping: a probe at a fixed height floats in
  the ramp or sits under it, and the arm then hits the ramp itself.
- The booth's landing was at the foot of the ramp instead of the top (the ramp climbs to the south); the arm hit it at
  98 cm from the pivot. Moved to the top and widened to meet the upper floor.
