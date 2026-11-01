# Character customization

What building the wardrobe taught us. The design is in [Customization](../design/customization.md).

## Findings

- **The kit Soldier's material names do not say what they cover.** `Black` is the hood, mask, eyes, belt and boots (so it
  is the hair channel), `Character_Main` is the vest and the helmet shell, `Grey` is the helmet band and the pads, `Skin`
  is every bare patch including the head and face. Tinting is per material name on the body, head and pad meshes only;
  the weapons share `Grey` and are left alone. Surfaces get their own copies of the material
  (`set_surface_override_material`), never a change to the shared one, or every character on screen changes colour.
- **The armature is scaled by 100.** `CharacterArmature` has scale 100 and the bones are in Z-up units, so anything
  parented to a `BoneAttachment3D` is sized in hundredths of a metre (an armband of radius 0.0015). The bone's Y axis
  runs down the limb, so a torus parented there rings the arm.
- **A bare head is two hidden surfaces.** The helmet is the `Character_Main` and `Grey` surfaces of the `Head` mesh; an
  invisible override material on those two leaves the face, eyes and hood.
- **A 3D preview inside a menu** is a `SubViewportContainer` with a `SubViewport` that has `own_world_3d` and
  `transparent_bg`, and a `WorldEnvironment` whose background is `BG_CLEAR_COLOR`. A warm `SpotLight3D` and a cold
  `OmniLight3D` behind read well on the dark menu sky and run in the Compatibility renderer. `look_at` needs the node
  in the tree: use `look_at_from_position` while building.
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
