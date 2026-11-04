# Two pinning tests in other folders failed for a new light and a new sound field

2026-11-04

- **Symptom:** after the helicopter drop (#1057) the game passed but `tests/world/test_lot_light_cap.gd` (a light made
  at run time) and `tests/tuning/test_tuning_defaults.gd` (3 tests: a new `SoundDef.on_demand` export, a new
  sound group, 3 new sounds) failed; the arrival's own suites were green.
- **Cause:** both suites read the project for what exists and pin it: every `Light3D.new(` must be listed in
  `LIGHT_SCRIPTS`, every exported property and sound must be in `tests/tuning/default_values.gd` and `sound_defaults.json`.
  I ran the new suites and a few whole folders, not the folders that pin a kind of thing I had added.
- **Fix:** a `LIGHT_SCRIPTS` row for the cutscene's lamp; `on_demand` defaulting to false in `DefaultValues.sounds()`, the
  `arrival` group limit and 3 rows in `sound_defaults.json`, and the count 212 to 215. A test that frees a show it
  already `queue_free`d twice (a `material` null error in the dummy renderer) now frees it at once with `free()`.
- **Check next time:** a new light, sound, export or tuning field is followed by `tests/world` and `tests/tuning` run
  whole, and the headless log is read for `ERROR` lines, not only the summary line.
- **Documented:** [the arrival](../research/arrival.md#what-went-wrong-on-the-way).
