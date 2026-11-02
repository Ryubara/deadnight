# A test wait never saw the value its own lambda assigned

2026-11-02

- **Symptom:** the real-socket lobby test waited for the backend to say "round 3" with
  `await _until(func(): in_progress = await ...; return in_progress.round == 3)`, and read an empty dictionary after the
  wait had succeeded (`Invalid access to property or key 'full' on a base object of type 'Dictionary'`).
- **Cause:** a GDScript lambda captures a local variable by value. The assignment inside the lambda changed the lambda's
  copy, and the test's variable stayed `{}`. A condition that is itself `await`ed also needs the wait helper to
  `await condition.call()`: without it the helper compared a coroutine to false and returned at once.
- **Fix:** hand the value out through a one-element array (`var read := [{}]`, `read[0] = ...`), and write the wait as
  `while not await condition.call()`, which also takes plain conditions.
- **Documented:** `game/tests/net/test_lobby_online.gd` (the helper and the holder).
