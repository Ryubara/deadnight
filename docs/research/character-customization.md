# Character customization

What building the wardrobe taught us. The design is in [Customization](../design/customization.md).

## Findings

- **The parts model rests in a T-pose with bone axes that do not follow the limbs.** `UpperArm.R` has Y pointing up in
  the rest pose while the arm runs sideways, so a ring cannot assume "bone Y is the arm". The armband takes the
  direction to the next bone (`LowerArm.R`) in the bone's own space and turns the torus (whose axis is Y) onto it; a
  test checks the two agree. The armature is at scale 1 and in metres here (the older kit Soldier file is scaled by
  100).
- **Without a clip the model stands in its T-pose.** The assembler plays `Idle` (looping) so a preview and a lot of
  players look alive; a `BoneAttachment3D` under the skeleton then follows the arm.
- **`SoldierLook` paints one material per character**: it copies the atlas and fills the channel swatches, so tests read
  the colour back from the material's image at the swatch cell instead of reading material properties.
- **A 3D preview inside a menu** is a `SubViewportContainer` with a `SubViewport` that has `own_world_3d` and
  `transparent_bg`, and a `WorldEnvironment` whose background is `BG_CLEAR_COLOR`. A warm `SpotLight3D` and a cold
  `OmniLight3D` behind read well on the dark menu sky and run in the Compatibility renderer. `look_at` needs the node
  in the tree: use `look_at_from_position` while building.
- **Fifteen rows do not fit a screen.** Nine part slots, five colour channels and the preset are scrolled in a
  `ScrollContainer` with `follow_focus` on, and the focus neighbours are linked by hand: left to the engine, "down"
  from a selector once jumped to a footer button on the other side.
- **Parsing a damaged save without an engine error:** `JSON.parse_string` logs an `ERROR` for bad text, so a damaged
  settings file would turn the smoke run red; `JSON.new().parse(text)` returns an error code instead.
- **Godot rewrites `project.godot` when it imports** (it reorders the sections). Restore it before committing.

## Testing a menu with GdUnit4

- A click only lands if the control is inside the window and nothing is over it. In a headless run the test runner has
  its own full-window `Stage` control over the scene, so a screen added as a child of the test never gets mouse input:
  put it on a `CanvasLayer` (layer 100) and set `get_window().size` to the design size first.
- Keyboard and gamepad events (press, then release, a frame apart) go straight into the viewport with
  `get_viewport().push_input(event)`; the built-in `ui_left`, `ui_right` and `ui_accept` follow. Through
  `Input.parse_input_event` the same d-pad presses passed alone but were swallowed after other suites had run (the
  singleton tracks held buttons across suites), so tests should not depend on its state.
- Any menu suite should first wait out `UIRouter.busy`: a transition left running by another suite swallows input.
- GdUnit4 frees 3D nodes with the dummy renderer and logs `Parameter "material" is null` for each freed mesh; the tests
  still pass and the line is not from our code.

## Numbers

| Thing | Value |
| --- | --- |
| A look on the wire | 15 bytes (version, 9 parts, 5 colours); a join costs 16 up and 18 per player down |
| Presets | 8, all free options, all distinct |
| Four identical looks | four distinct main colours after `LookResolver` |
