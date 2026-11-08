# A render-layer rule in a scene generator skipped the boxes that another helper made

2026-11-03

- **Symptom:** Deadnight #841 (a light layer per room): after the generator wrote render layers on the stand's and the
  booth's boxes, the leak check still listed the second map's ceiling slabs (`StartSlabS`, `StartSlabE`): a lamp lit them
  through a wall although the rule named them.
- **Cause:** the rule was hooked into the generator's `box()`; the slabs of the second map come from `wood_box()`, which
  writes its node by hand. A search for who writes `CSGBox3D` nodes (`grep -n "CSGBox3D" tools/world/*.py`) before
  hooking a rule would have shown two writers.
- **Fix:** `wood_box()` asks the same `render_layers` rule. The check that found it (`GlowBleed.light_leaks` after
  regenerating) is the proof, not the diff of the scene (the diff looked complete: it had `layers` lines). Count the
  lines a rule wrote against the boxes it should touch, and run the check that reads the scene after every
  regeneration.
- **Documented:** the kit's
  [Compatibility lighting](https://ryubara.github.io/gdstudio/engines/godot/compat-lighting/#lamps-in-a-game-what-looks-like-light-and-what-is-light)
  (a light layer per room); `tools/world/build_greybox.py`.
