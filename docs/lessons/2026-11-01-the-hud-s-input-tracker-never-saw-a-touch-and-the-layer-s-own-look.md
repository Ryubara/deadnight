# The HUD's input tracker never saw a touch, and the layer's own look would have ended touch mode

2026-11-01

- **Symptom:** the prompt card kept its keycap on a phone though the touch controls were up (#283).
- **Cause:** `TouchControls` sits after the HUD in the tree, so its `_input` runs first and marks every touch handled;
  `Hud._input`, which feeds `UIInputMode`, never got one. And the look it sends is `InputEventMouseMotion`, which the
  tracker read as a mouse being picked up.
- **Fix:** the layer calls `UIInputMode.track` on each touch itself and sets `UIInputMode.touch` when it comes up; mouse
  motion never ends touch mode, a real mouse click (not the engine's emulated copy) does.
- **Documented:** [touch controls](../design/touch-controls.md#first-run-and-key-hints).
