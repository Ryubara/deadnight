# A test that only named the warm-up manifest failed its shard on the leak gate

2026-11-04

- **Symptom:** `godot (2)` of #1100 exited 1 with no test FAILED: the log ended with `894 ObjectDB instances were
  leaked at exit` and 399 `Resource still in use` lines (the arrival's bank among 300 scripts and banks). Locally the
  same shard printed the same lines and exited 0, so only CI's last line (`! grep -E "leaked at exit|still in use"
  tests.log`) failed.
- **Cause:** `test_arrival_cutscene.gd` called `WarmupManifest.sound_paths()`. Naming that script loads
  `PlayerAnimation` and the scripts under it, and a test with no night leaves them in use at exit (a probe of one
  test that reads only `PlayerAnimation.HOLD_CLASSES` leaks the same 172; `test_night_warmup.gd` does not, it runs a
  night). I had seen the `ERROR: ... still in use at exit` lines in my own logs of that file and filed them as "the
  usual exit leaks".
- **Fix:** the test reads the manifest's source for `SoundCatalog.ids_for_night()` instead of calling it. Shard 2 run
  whole with CI's command and the gate grep: 0 lines.
- **Check next time:** run the shard's command and CI's gate (`grep -c -E "leaked at exit|still in use"` on the log
  is 0) before pushing a new test; an `ERROR` line in a log is never "usual" until it is the same on main. Bisect with a
  prefix of the test file, then one line at a time.
- **Documented:** [the arrival](../research/arrival.md#what-went-wrong-on-the-way).
