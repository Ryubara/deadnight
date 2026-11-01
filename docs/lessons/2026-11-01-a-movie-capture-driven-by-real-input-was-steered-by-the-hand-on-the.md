# A movie capture driven by real input was steered by the hand on the mouse

2026-11-01

- **Symptom:** the second run of a scripted Movie Maker capture wandered in curves and aimed on its own, while the
  first run was exact (#349).
- **Cause:** the script pressed input actions, and the machine's real mouse and keys reach the same `Input`, so
  whoever was using the computer during the render steered the player.
- **Fix:** feed the player `PlayerCommand`s with `local_input = false` (`tests/player/capture_omni.gd`): the same path
  the server and a replay use, deaf to the hardware, so the run is the same every time.
- **Documented:** [character controller](../research/character-controller.md).
