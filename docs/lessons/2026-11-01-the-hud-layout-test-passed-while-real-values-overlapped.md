# The HUD layout test passed while real values overlapped

2026-11-01

- **Symptom:** the HUD's layout test was green, yet a four-player night with long names, round 123, a big score and the
  Marquee typeface overlapped three parts at 1536 x 864 (#141).
- **Cause:** the test fed short names, two-digit rounds and the engine's fallback font, so the parts never met their
  limits; parts grew with their text instead of keeping a width.
- **Fix:** the test also runs the longest content the game allows in three typefaces; each part has a width and its text
  shrinks or ends in an ellipsis (`HudStyle.set_fitted`).
- **Documented:** [HUD research](../research/hud.md), [HUD design](../design/hud.md#scale).
