# A new machine in the greybox generator left the lot's saved navigation meshes stale

2026-11-03

- **Symptom:** Deadnight #687: after five machines and their hidden blocks went into `tools/world/build_greybox.py`, the
  world suite printed `no saved navigation mesh for the lot as it stands: baking one` and `test_bot_navigation` failed on
  the first area.
- **Cause:** the nine meshes the night loads are baked from the CSG boxes ahead of time
  (`game/world/drive_in/lot_navmeshes.res`) and found by a fingerprint of the lot; any block added to the scene changes
  the fingerprint, so the saved meshes no longer match and the night bakes one on the main thread (a half-second frame
  in a browser).
- **Fix:** after the generator writes the scene, run `godot --headless --path game -s
  res://tools/world/bake_lot_navmeshes.gd` and commit the resource with the scene (the run prints an `Identifier not
  found: UIRouter` compile error on the way and still saves nine meshes). Two branches that both change the lot conflict
  on that binary resource: bake again after the merge. A pull request that changes the generator or the scene has
  `lot_navmeshes.res` in its diff.
- **Documented:** [zombies](../research/zombies.md) (the meshes are baked ahead of time); the kit's
  [Navigation in tests](https://ryubara.github.io/gdstudio/engines/godot/navigation-in-tests/) covers what a baked
  mesh closes.
