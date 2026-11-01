# Greybox and captures

What building the drive-in greybox ([the lot](../design/map.md)) taught us, for the next scene built the same way.

## Lights on a big floor (Compatibility)

The Compatibility renderer lights each mesh with at most 8 omni and 8 spot lights (the project setting
`rendering/limits/opengl/max_lights_per_object`); lights past the cap are dropped for that mesh. One 120 m floor under
25 lamps is one mesh, so most of its lamps would not light it. The greybox tiles every floor into slabs of at most
24 m, so no slab sees more than a handful. Shadows are off: they are among the web build's most expensive features.

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
- One rig scene and a user argument (`-- --view=top`) give every view from one command, so a layout change is
  re-captured by rerunning the same list.
