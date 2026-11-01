# A card that shrinks and ellipsizes still cut a prompt in half

2026-11-01

- **Symptom:** the locker prompt read `20 ROUNDS FOR YOUR RES...`; the layout suites were green.
- **Cause:** the prompt's lines shrank to a 20-unit floor then ended in an ellipsis, and the tests only fed short,
  hand-picked prompts and accepted an ellipsis in the worst case.
- **Fix:** the card wraps its lines and grows upward (`HudStyle.set_wrapped`), and a suite walks every prompt the night
  can make through the real binding at desktop and phone-landscape canvases, failing on any cut line.
- **Documented:** [HUD research](../research/hud.md).
