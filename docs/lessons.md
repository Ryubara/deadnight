# Lessons

Problems we hit and how we solved them, newest first. Five lines each: date, symptom, cause, fix, where it is
documented.

## 2026-11-01: a navigation region or link reaches path queries after a few iterations, and the id is no sign of it

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

## 2026-11-01: a static AnimationLibrary is reported as leaked resources at exit

- **Symptom:** A headless run ended with `ERROR: N resources still in use at exit` and `ObjectDB instances were
  leaked`, naming the animation clips of a shared library, although every zombie was freed.
- **Cause:** The library was built once and kept in a `static var` so every model's `AnimationPlayer` could share it
  (the rig-sharing recipe). A static outlives the scene tree, so its clips are still referenced when the engine shuts
  down.
- **Fix:** Give the owner a `release()` that sets the static to `null` and call it when the last user goes
  (`ZombieRig.release`, called from `ZombieHorde`'s exit); a test that builds the library calls it in its teardown.
- **Documented:** Deadnight `docs/research/zombies.md` (animation), kit `docs/godot/rig-sharing.md`.

## 2026-11-01: map_get_path to an unreachable point fails with "not expect to not find the most reachable polygons"

- **Symptom:** On a finely baked mesh (0.05 m cells for the whole 124 m by 116 m lot) a path query to a point inside a
  closed-off area printed `ERROR: It's not expect to not find the most reachable polygons` for some targets and
  answered a path that stopped far from the nearest reachable point; a coarse mesh (0.25 m) never did.
- **Cause:** `map_get_path` searches at most `path_search_max_polygons` (4096 by default). A query that has to explore
  the whole connected mesh to learn the target is unreachable runs out of polygons first.
- **Fix:** Ask with `NavigationServer3D.query_path` and a `NavigationPathQueryParameters3D` whose
  `path_search_max_polygons` is larger than the mesh (a million is plenty); read `NavigationPathQueryResult3D.path`.
  Zero errors afterwards.
- **Documented:** Deadnight `game/tests/world/lot_navigation.gd`.

## 2026-11-01: a NavigationLink across a door slab leaves agents walking back and forth on it

- **Symptom:** Zombies reached the link in front of an opened door and then stood there, moving a few centimetres to
  and fro for as long as the run lasted, although the link was enabled and `map_get_path` crossed it.
- **Cause:** A mesh baked with the slab present has a band without mesh round it (the slab plus the agent radius each
  side, 1.3 m). A link only spans the band; an agent inside the band is off the mesh, so each repath snaps it to the
  nearer edge and the new path starts there, back at the link's start. At 3 m/s and a 0.25 s repath the agent covers
  0.75 m, less than the band's far half.
- **Fix:** Do not bridge a baked wall with a link for agents that repath often. Rebake the mesh when the door opens
  (`bake_from_source_geometry_data_async`, a worker thread, about a second for the lot) and swap it into the region;
  or keep the path across a link and do not repath while an agent is on it.
- **Documented:** Deadnight `docs/research/zombies.md#doors`.

## 2026-11-01: a client could not connect to a server that was listening

- **Symptom:** `ERROR: Invalid ID received from server` on the client; the server printed nothing and showed no peers.
- **Cause:** port 9080 was already taken by another WebSocket server (the Godot editor's MCP bridge). Windows let the
  game server bind the same port, so connections went to the other listener, which is not our server.
- **Fix:** the spike listens on 8910. Before picking a port, check it: `netstat -ano | grep :<port>`.
- **Documented:** [Multiplayer research](research/multiplayer.md#local-setup).

## 2026-11-01: the server image failed to import the project

- **Symptom:** `docker build` printed `Could not create project data directory (res://.godot)`, and the container then
  failed with parse errors on every script that uses a `class_name`.
- **Cause:** `WORKDIR /app` makes a root-owned folder; the non-root user could not create `.godot/` (the import cache
  and the global class list) inside it.
- **Fix:** create `/app` and `chown` it to the game user before the `COPY` and the build-time `--import`.
- **Documented:** `spikes/net/Dockerfile`, [Multiplayer research](research/multiplayer.md#server-image).

## 2026-11-01: a handshake packet was rejected for being one byte short

- **Symptom:** the client connected and received snapshots, yet never became a player (id stayed 0).
- **Cause:** the decoder's minimum-length check for WELCOME counted 9 bytes; the packet is 8 (type, version, id, rate,
  4-byte tick). A malformed-packet guard silently dropped every valid welcome.
- **Fix:** derive each minimum length from the layout comment in `protocol.gd`, and print a counter for dropped packets
  while developing. A guard that fails closed hides its own bug.
- **Documented:** [Multiplayer research](research/multiplayer.md#protocol).
