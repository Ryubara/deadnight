# The grenade key did nothing in the night and nobody had noticed

2026-11-01

- **Symptom:** the maintainer could not throw grenades; the HUD said `GRENADES x3`, the key, pad and touch button were
  bound, and every grenade test passed.
- **Cause:** #131 wired the grenade code into the test range only; `NightServer` never made a `GrenadeServer`, and the
  issue that would have done it was never opened (the slice page listed it as "next"). Each link was tested alone and
  nothing pressed the key in a night. It was not one of the day's input merges: there was nothing to break.
- **Fix:** the night server throws for every player; `test_night_grenades.gd` presses the real key and follows the
  grenade to a dead zombie; `test_input_matrix.gd` presses every action on every device and fails on a new unrowed one.
- **Documented:** [Input tests](../research/input-tests.md), [Grenades](../research/grenades.md#in-the-night-351).
