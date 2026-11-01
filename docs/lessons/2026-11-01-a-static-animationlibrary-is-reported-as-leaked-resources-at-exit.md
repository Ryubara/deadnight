# A static AnimationLibrary is reported as leaked resources at exit

2026-11-01

- **Symptom:** A headless run ended with `ERROR: N resources still in use at exit` and `ObjectDB instances were
  leaked`, naming the animation clips of a shared library, although every zombie was freed.
- **Cause:** The library was built once and kept in a `static var` so every model's `AnimationPlayer` could share it
  (the rig-sharing recipe). A static outlives the scene tree, so its clips are still referenced when the engine shuts
  down.
- **Fix:** Give the owner a `release()` that sets the static to `null` and call it when the last user goes
  (`ZombieRig.release`, called from `ZombieHorde`'s exit); a test that builds the library calls it in its teardown.
- **Documented:** Deadnight `docs/research/zombies.md` (animation), kit `docs/godot/rig-sharing.md`.
