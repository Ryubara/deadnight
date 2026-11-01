# Lessons

Problems we hit and how we solved them, newest first. Five lines each: date, symptom, cause, fix, where it is
documented.

## 2026-11-01: the HUD's input tracker never saw a touch, and the layer's own look would have ended touch mode

- **Symptom:** the prompt card kept its keycap on a phone though the touch controls were up (#283).
- **Cause:** `TouchControls` sits after the HUD in the tree, so its `_input` runs first and marks every touch handled;
  `Hud._input`, which feeds `UIInputMode`, never got one. And the look it sends is `InputEventMouseMotion`, which the
  tracker read as a mouse being picked up.
- **Fix:** the layer calls `UIInputMode.track` on each touch itself and sets `UIInputMode.touch` when it comes up; mouse
  motion never ends touch mode, a real mouse click (not the engine's emulated copy) does.
- **Documented:** [touch controls](design/touch-controls.md#first-run-and-key-hints).

## 2026-11-01: a bot fired a magazine into a car the camera could see past

- **Symptom:** the autopilot emptied a magazine into a car cabin five metres away and killed nothing, though its line of
  sight to the zombie was clear (#158).
- **Cause:** in third person a shot leaves the barrel, which sits beside and below the camera; a corner can block the
  barrel and not the camera ray, and the bot only checked the camera's.
- **Fix:** the bot fires only when the line to the target is open from the eye **and** from the barrel
  (`Autopilot._clear`).
- **Documented:** [the autopilot](design/slice.md#the-autopilot).

## 2026-11-01: `Engine.time_scale` made a faster headless bot play a different night

- **Symptom:** an autopilot run at `Engine.time_scale = 10` started round 1 after 1 s of ticks instead of 12 s (#158).
- **Cause:** `time_scale` scales the delta each `_physics_process` receives, so the "fixed" step grows and the rules
  see a different night than the one at normal speed.
- **Fix:** leave `time_scale` at 1 and run several fixed ticks in each physics frame (`Night.ticks_per_frame`), each
  with the constant step: about 1,500 ticks a second, the same night.
- **Documented:** [the autopilot](design/slice.md#the-autopilot).

## 2026-11-01: a `Callable` from a temporary object went invalid and the bot's sight said "clear"

- **Symptom:** the bot's line-of-sight check answered "clear" for every shot, so it fired through walls (#158).
- **Cause:** `WorldProbe.new(space).callable()` holds the `RefCounted` by id, not by reference; the temporary object was
  freed at once and `Callable.is_valid()` was false (the check treated an invalid callable as open).
- **Fix:** keep the object in a member (`Night._sight`) and hand out `_sight.callable()`.
- **Documented:** [the autopilot](design/slice.md#the-autopilot).

## 2026-11-01: catalog overrides were silently ignored by `Dictionary.merged`

- **Symptom:** sounds played with their group's defaults: a UI press at the wrong pitch, `dry_fire` carrying 50 m
  instead of 20 (#135).
- **Cause:** `base.merged(overrides)` keeps the base's value when both have the key; only `merged(overrides, true)`
  overwrites. Overrides of keys the base lacked worked, which hid it.
- **Fix:** every override goes through one helper (`SoundCatalog._with`), and a test fails on any other `.merged(` in
  the catalog's source and on every override that does not take effect.
- **Documented:** [audio research](research/audio.md).

## 2026-11-01: an onset detector found nothing on a mix with a bed under it

- **Symptom:** the audio analysis of a night capture found one onset, so no sound could be checked against its event.
- **Cause:** the ambient bed never goes below the detector's absolute floor, so the level never "rises through" it.
- **Fix:** compare the short-term level with its own median over two seconds and call a rise of 9 dB an onset;
  `tools/audio/analyze.py capture --expect seconds:name` then checks every logged sound within a tolerance.
- **Documented:** [audio research](research/audio.md).

## 2026-11-01: the bot stopped at a doorway it had just bought

- **Symptom:** a night test bought the concession for the autopilot and the bot stood outside the stand for a minute,
  its path ending at the wall; the same bot reached a breaker post outside the stand without trouble (#247).
- **Cause:** the new navigation mesh is baked on a worker thread and the server takes it a few physics frames later;
  `night.tick()` does not step the server, and waiting for the bake to end is not waiting for the map.
- **Fix:** after `NightFixture.settle_bake`, await a few `physics_frame`s before sending the bot somewhere through the door.
- **Documented:** [greybox and captures](research/greybox-and-captures.md#the-fuel-cans).

## 2026-11-01: a test that bought a door crashed the engine after it printed PASSED

- **Symptom:** a GdUnit4 suite whose autopilot bought the concession passed every case, then the run ended with
  `Segmentation fault` (shell status 139); a wait for the lamps failed one tick early in the same suite (#206).
- **Cause:** the door starts a navigation bake on a worker thread, and the test freed the night and quit under it (the
  same fault as the autopilot capture's, `docs/research/zombies.md`). The lamps failed early because a command's events
  reach the client a tick after the server applies it: the loop that waits on the rules does not wait for the client.
- **Fix:** `NightFixture.settle_bake` before `queue_free` in a test that buys a door; after a wait on the rules, run two
  more ticks before asserting on what the client draws.
- **Documented:** [zombies research](research/zombies.md).

## 2026-11-01: GameRules leaked at exit through lambdas that capture self

- **Symptom:** every run that built `GameRules` ended with `ERROR: N resources still in use at exit` and
  `ObjectDB instances were leaked`, and agents learned to skip the line (#159).
- **Cause:** `GameRules` connected lambdas that use `self` to its own generator's signals. Such a lambda holds the
  `RefCounted` strongly, so the rules, the generator and the lambdas kept each other alive. A method `Callable` or
  `bind` stores only the object id, so rules and servers that connect methods to each other's signals are no cycle.
  A second, separate cause: a run that quits in the same moment a sound plays leaves that voice queued in the audio
  server, reported as leaked `AudioStreamOggVorbis`.
- **Fix:** connect methods (`_emit.bind(&"fuel_low")`, `_on_circuit_changed`), and remove the disconnect loops that
  worked around it; the night harness stops the audio and waits a moment before it quits. `test_rules_lifetime`
  fails on a cycle, and the CI `godot` job plays a night and fails on any leak line.
- **Documented:** [weapon firing research](research/weapon-firing.md).

## 2026-11-01: the HUD layout test passed while real values overlapped

- **Symptom:** the HUD's layout test was green, yet a four-player night with long names, round 123, a big score and the
  Marquee typeface overlapped three parts at 1536 x 864 (#141).
- **Cause:** the test fed short names, two-digit rounds and the engine's fallback font, so the parts never met their
  limits; parts grew with their text instead of keeping a width.
- **Fix:** the test also runs the longest content the game allows in three typefaces; each part has a width and its text
  shrinks or ends in an ellipsis (`HudStyle.set_fitted`).
- **Documented:** [HUD research](research/hud.md), [HUD design](design/hud.md#scale).

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

## 2026-11-01: a card that shrinks and ellipsizes still cut a prompt in half

- **Symptom:** the locker prompt read `20 ROUNDS FOR YOUR RES...`; the layout suites were green.
- **Cause:** the prompt's lines shrank to a 20-unit floor then ended in an ellipsis, and the tests only fed short,
  hand-picked prompts and accepted an ellipsis in the worst case.
- **Fix:** the card wraps its lines and grows upward (`HudStyle.set_wrapped`), and a suite walks every prompt the night
  can make through the real binding at desktop and phone-landscape canvases, failing on any cut line.
- **Documented:** [HUD research](research/hud.md).
