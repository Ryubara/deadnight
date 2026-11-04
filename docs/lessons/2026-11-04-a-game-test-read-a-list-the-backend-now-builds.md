# A game test read a list the backend now builds

2026-11-04

- **Symptom:** `godot (8)` failed on #1108 in `test_the_backend_lists_the_maps_the_game_can_play` with "Cannot call
  method 'get_string' on a null value". The pull request had run the game suites it touched, not this one.
- **Cause:** the test reads `spikes/backend/src/settings.ts` as text and looks for a literal `PLAYABLE_MAPS = [...]`.
  #1108 made that constant `Object.keys(MAP_UNLOCK_LEVELS)`, so the search found nothing. A change to a backend file
  broke a game test in another folder, and its comment now said a backend test held the same fact.
- **Fix:** the test reads the keys of `MAP_UNLOCK_LEVELS`. Before changing the form of a constant, search the other
  side of the repository for its name: `git grep PLAYABLE_MAPS` found this test at once.
- **Documented:** [Platform backend](../research/platform-backend.md).
