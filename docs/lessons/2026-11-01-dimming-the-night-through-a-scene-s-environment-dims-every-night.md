# Dimming the night through a scene's Environment dims every night after it

2026-11-01

- **Symptom:** with the light written to the lot's `Environment` directly, a test that darkened one lot to round 14 and
  built a second read the dark numbers in the new one (and a later round-1 test read them too): 3 failures.
- **Cause:** the `Environment` is a sub-resource of `drive_in_greybox.tscn`; every instance of a PackedScene shares its
  sub-resources, so an edit through one copy changes them all.
- **Fix:** `NightLight` duplicates the environment (`WorldEnvironment.environment = environment.duplicate()`) before it
  writes to it, and a test builds a second lot after round 14.
- **Documented:** [Night environment](../research/night-environment.md#the-night-closes-in-with-the-round).
