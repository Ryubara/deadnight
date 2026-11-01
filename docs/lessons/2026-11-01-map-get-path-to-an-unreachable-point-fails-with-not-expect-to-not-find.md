# Map_get_path to an unreachable point fails with "not expect to not find the most reachable polygons"

2026-11-01

- **Symptom:** On a finely baked mesh (0.05 m cells for the whole 124 m by 116 m lot) a path query to a point inside a
  closed-off area printed `ERROR: It's not expect to not find the most reachable polygons` for some targets and
  answered a path that stopped far from the nearest reachable point; a coarse mesh (0.25 m) never did.
- **Cause:** `map_get_path` searches at most `path_search_max_polygons` (4096 by default). A query that has to explore
  the whole connected mesh to learn the target is unreachable runs out of polygons first.
- **Fix:** Ask with `NavigationServer3D.query_path` and a `NavigationPathQueryParameters3D` whose
  `path_search_max_polygons` is larger than the mesh (a million is plenty); read `NavigationPathQueryResult3D.path`.
  Zero errors afterwards.
- **Documented:** Deadnight `game/tests/world/lot_navigation.gd`.
