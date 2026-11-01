# An 11 s freeze at Play was blamed on a bake that takes half a second

2026-11-01

- **Symptom:** in Chrome, pressing Play froze the page in one 9 to 12 s frame; the issue (#335) said the navigation
  bake did it, because the web export has no worker threads.
- **Cause:** the bake takes 0.5 s in the browser. The long frame is the first draw of the 3D scene (shaders compile at
  the first draw call); and the night waited 600 frames (10 s) for a map iteration id that never reaches 2 there.
- **Fix:** time the stages with `Time.get_ticks_msec` prints in a web export before choosing a fix; wait for what you
  need (a path across the field), not a counter; ship the baked meshes anyway (no half-second stalls at Play or a door).
- **Documented:** [the zombies](../research/zombies.md#what-the-long-frame-was).
