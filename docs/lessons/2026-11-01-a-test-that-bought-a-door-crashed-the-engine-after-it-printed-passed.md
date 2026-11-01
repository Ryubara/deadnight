# A test that bought a door crashed the engine after it printed PASSED

2026-11-01

- **Symptom:** a GdUnit4 suite whose autopilot bought the concession passed every case, then the run ended with
  `Segmentation fault` (shell status 139); a wait for the lamps failed one tick early in the same suite (#206).
- **Cause:** the door starts a navigation bake on a worker thread, and the test freed the night and quit under it (the
  same fault as the autopilot capture's, `docs/research/zombies.md`). The lamps failed early because a command's events
  reach the client a tick after the server applies it: the loop that waits on the rules does not wait for the client.
- **Fix:** `NightFixture.settle_bake` before `queue_free` in a test that buys a door; after a wait on the rules, run two
  more ticks before asserting on what the client draws.
- **Documented:** [zombies research](../research/zombies.md).
