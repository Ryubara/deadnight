# A left-handed mirror of the buttons alone lands Fire on the HUD's points card

2026-11-01

- **Symptom:** mirroring only the buttons would draw the Fire arc over the points and health cards and the stick's
  ring over the ammo card (#284; seen in the layout numbers before building it).
- **Cause:** the buttons were placed to miss the cards in the right corner; the cards are in fixed corners, so flipping
  only the buttons dropped them on the cards.
- **Fix:** the HUD's corner columns flip with the layout (`Hud.mirrored`); the layout test runs both hands against the
  HUD in the same state.
- **Documented:** [touch controls](../design/touch-controls.md#left-handed-layout).
