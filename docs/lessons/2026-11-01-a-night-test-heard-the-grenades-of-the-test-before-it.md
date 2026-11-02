# A night test heard the grenades of the test before it

2026-11-01

- **Symptom:** a night suite failed now and then with events that never happened in its own night (a
  `grenade_bounced` before the round began, a second `throw_started`), and with the player standing on a box 4 to 11 m
  up in later tests; the failing test changed from run to run.
- **Cause:** a `Night` added to the suite is not gone when the test ends. It stays in the tree until the next frame,
  keeps ticking from `_physics_process` and flying its grenades, and its `event_received` lambda was still appending to
  the suite's `_heard`. Its player body also still stood at the spawn, so the next night's player rose onto it.
- **Fix:** connect a named method and disconnect it in `after_test`; a suite that needs a clean spawn builds one night
  in `before()` for all its tests, or frees the night and waits two physics frames.
- **Documented:** [Grenades](../research/grenades.md#polish-357).
