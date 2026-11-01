# A navigation region or link reaches path queries after a few iterations, and the id is no sign of it

2026-11-01

- **Symptom:** `map_get_path` returned `[]` and `map_get_closest_point` returned `(0, 0, 0)` for a few physics frames
  after a baked `NavigationRegion3D` joined (headless and windowed); a query before the map's first sync printed
  `ERROR: navigation map query failed because it was made before first map synchronization`. Waiting for
  `map_get_iteration_id` to rise by 2 worked until `NavigationLink3D` nodes were in the scene: they bump the id too,
  the wait ended early and every later query came back empty.
- **Cause:** The server applies a region over the map's next iterations, and any change (a region, a link, a cell
  size) is an iteration, so the id counts changes, not readiness.
- **Fix:** Wait for an answer: `await physics_frame` until `map_get_closest_point` on one of the mesh's own vertices
  lands within half a metre (after `map_get_iteration_id(map) > 0`), or until a path across open ground is not empty;
  then a few frames more for links. Take the map from `get_world_3d().navigation_map`.
- **Documented:** Deadnight `docs/research/zombies.md`, `game/tests/world/lot_navigation.gd`.
