# Catalog overrides were silently ignored by `Dictionary.merged`

2026-11-01

- **Symptom:** sounds played with their group's defaults: a UI press at the wrong pitch, `dry_fire` carrying 50 m
  instead of 20 (#135).
- **Cause:** `base.merged(overrides)` keeps the base's value when both have the key; only `merged(overrides, true)`
  overwrites. Overrides of keys the base lacked worked, which hid it.
- **Fix:** every override goes through one helper (`SoundCatalog._with`), and a test fails on any other `.merged(` in
  the catalog's source and on every override that does not take effect.
- **Documented:** [audio research](../research/audio.md).
