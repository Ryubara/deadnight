# GameRules leaked at exit through lambdas that capture self

2026-11-01

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
- **Documented:** [weapon firing research](../research/weapon-firing.md).
